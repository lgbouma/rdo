import Foundation
import Combine
import AuthenticationServices
import PhoneListCore

public enum SyncStatus: Equatable {
    case notLinked
    case idle(lastSync: Date?)
    case syncing
    case dirty            // local edits not yet uploaded
    case conflict
    case error(String)

    public var label: String {
        switch self {
        case .notLinked: return "Not linked"
        case .idle(let d):
            guard let d else { return "Synced" }
            let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
            return "Synced \(f.localizedString(for: d, relativeTo: Date()))"
        case .syncing: return "Syncing…"
        case .dirty: return "Unsaved changes"
        case .conflict: return "Conflict"
        case .error(let s): return s
        }
    }
}

/// Local state: the working document, the base it was derived from (what
/// Dropbox had when we last synced) and that base's rev.
struct PersistedState: Codable {
    var text: String
    var baseLines: [String]
    var rev: String?
    var lastSync: Date?
}

@MainActor
public final class Store: ObservableObject {
    @Published public private(set) var document: Document
    @Published public private(set) var status: SyncStatus = .notLinked
    @Published public private(set) var isLinked = false
    @Published public var conflict: Conflict?
    @Published public var path: String {
        didSet { UserDefaults.standard.set(path, forKey: "dropboxPath") }
    }

    public struct Conflict: Identifiable {
        public let id = UUID()
        public let remoteText: String
        public let remoteRev: String
    }

    private var baseLines: [String]
    private var rev: String?
    private var lastSync: Date?
    private var tokens: DropboxTokens? {
        didSet {
            if let tokens, let data = try? JSONEncoder().encode(tokens) {
                Keychain.save(data, account: "dropbox")
            } else {
                Keychain.delete(account: "dropbox")
            }
            isLinked = tokens != nil
        }
    }
    private var pushTask: Task<Void, Never>?
    private let client: DropboxClient?
    private var authSession: ASWebAuthenticationSession?
    private var pkce: PKCE?

    public static let appKey: String = {
        (Bundle.main.object(forInfoDictionaryKey: "DropboxAppKey") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }()
    public static var hasAppKey: Bool { !appKey.isEmpty && !appKey.hasPrefix("$(") && appKey != "your_app_key_here" }
    public static var redirectScheme: String { "db-\(appKey)" }
    public static var redirectURI: String { "\(redirectScheme)://oauth" }

    public var isDirty: Bool { document.lineTexts != baseLines }

    /// Dropbox paths must start with "/".
    private var apiPath: String {
        let p = path.trimmingCharacters(in: .whitespaces)
        return p.hasPrefix("/") ? p : "/" + p
    }

    public init() {
        path = UserDefaults.standard.string(forKey: "dropboxPath") ?? "/research_TODO.txt"
        client = Self.hasAppKey ? DropboxClient(appKey: Self.appKey, redirectURI: Self.redirectURI) : nil
        var saved = Self.loadState()
        #if DEBUG
        // UI-test hook: seed the document from the environment instead of disk.
        if let seed = ProcessInfo.processInfo.environment["PHONELIST_SEED_TEXT"] {
            saved = PersistedState(text: seed, baseLines: Document(text: seed).lineTexts, rev: nil, lastSync: nil)
        }
        #endif
        let doc = Document(text: saved?.text ?? Self.starterText)
        document = doc
        // With no saved state the starter text counts as clean.
        baseLines = saved?.baseLines ?? doc.lineTexts
        rev = saved?.rev
        lastSync = saved?.lastSync
        if let data = Keychain.load(account: "dropbox"),
           let t = try? JSONDecoder().decode(DropboxTokens.self, from: data) {
            tokens = t
            isLinked = true
        }
        status = tokens == nil ? .notLinked : (isDirty ? .dirty : .idle(lastSync: lastSync))
    }

    // MARK: - Editing

    /// Apply a line-level edit, persist, and schedule an upload.
    public func edit(_ body: (inout Document) -> Void) {
        var d = document
        body(&d)
        guard d != document else { return }
        document = d
        persist()
        if tokens != nil { status = .dirty }
        schedulePush()
    }

    private func schedulePush(after seconds: Double = 1.5) {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    // MARK: - Sync

    public func pull() async {
        guard let client, let token = await validToken() else { return }
        status = .syncing
        do {
            let file = try await client.download(path: apiPath, accessToken: token)
            let remoteText = String(decoding: file.content, as: UTF8.self)
            try integrate(remoteText: remoteText, remoteRev: file.rev)
            if isDirty { await push() } else { status = .idle(lastSync: lastSync) }
        } catch DropboxError.notFound {
            status = .error("No file at \(apiPath)")
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Merge a freshly downloaded remote into the working document.
    private func integrate(remoteText: String, remoteRev: String) throws {
        let remote = Document(text: remoteText)
        // Never synced before (rev == nil): whatever is local is the starter
        // text or pre-link scribbles, so the remote simply wins.
        if !isDirty || rev == nil {
            // Preserve line ids where lines are unchanged, so UI state survives.
            document = reconcile(document, with: remote)
        } else if let merged = Merge.merge(base: baseLines, local: document.lineTexts, remote: remote.lineTexts) {
            let mergedDoc = Document(lines: merged.map { Line($0) }, trailingNewline: remote.trailingNewline)
            document = reconcile(document, with: mergedDoc)
        } else {
            conflict = Conflict(remoteText: remoteText, remoteRev: remoteRev)
            status = .conflict
            throw CancellationError()
        }
        baseLines = remote.lineTexts
        rev = remoteRev
        lastSync = Date()
        persist()
    }

    public func push() async {
        guard let client, isDirty, let token = await validToken() else {
            if tokens != nil, !isDirty { status = .idle(lastSync: lastSync) }
            return
        }
        status = .syncing
        let text = document.text
        do {
            let newRev = try await client.upload(path: apiPath, content: Data(text.utf8), rev: rev, accessToken: token)
            // Only mark clean if nothing changed while uploading.
            if document.text == text {
                baseLines = document.lineTexts
                rev = newRev
                lastSync = Date()
                persist()
                status = .idle(lastSync: lastSync)
            } else {
                rev = newRev
                baseLines = Document(text: text).lineTexts
                persist()
                schedulePush()
            }
        } catch DropboxError.conflict {
            // Someone else wrote first: pull merges and re-pushes.
            await pull()
        } catch {
            status = .error(error.localizedDescription)
            schedulePush(after: 30)
        }
    }

    public func resolveConflict(keepMine: Bool) async {
        guard let c = conflict else { return }
        conflict = nil
        if keepMine {
            // Overwrite Dropbox with the phone version.
            rev = c.remoteRev
            baseLines = Document(text: c.remoteText).lineTexts
            persist()
            await push()
        } else {
            let remote = Document(text: c.remoteText)
            document = remote
            baseLines = remote.lineTexts
            rev = c.remoteRev
            lastSync = Date()
            persist()
            status = .idle(lastSync: lastSync)
        }
    }

    /// Keep existing `Line` ids for lines whose text is unchanged in order.
    private func reconcile(_ old: Document, with new: Document) -> Document {
        let diff = new.lineTexts.difference(from: old.lineTexts)
        guard let lines = old.lines.applying(convert(diff)) else { return new }
        return Document(lines: lines, trailingNewline: new.trailingNewline)
    }

    private func convert(_ diff: CollectionDifference<String>) -> CollectionDifference<Line> {
        CollectionDifference<Line>(diff.map { change -> CollectionDifference<Line>.Change in
            switch change {
            case .insert(let o, let e, let a): return .insert(offset: o, element: Line(e), associatedWith: a)
            case .remove(let o, let e, let a): return .remove(offset: o, element: Line(e), associatedWith: a)
            }
        })!
    }

    // MARK: - Auth

    private func validToken() async -> String? {
        guard let client, var t = tokens else { status = .notLinked; return nil }
        if t.isExpired {
            do {
                t = try await client.refresh(t)
                tokens = t
            } catch {
                status = .error("Token refresh failed: \(error.localizedDescription)")
                return nil
            }
        }
        return t.accessToken
    }

    public func link(presentationAnchor: ASPresentationAnchor?) {
        guard let client else { status = .error(DropboxError.missingAppKey.localizedDescription); return }
        let pkce = PKCE()
        self.pkce = pkce
        let url = client.authorizationURL(pkce: pkce)
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.redirectScheme) { [weak self] cb, err in
            guard let self else { return }
            Task { @MainActor in
                guard let cb, err == nil,
                      let code = URLComponents(url: cb, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.status = .error(err?.localizedDescription ?? "Authorization cancelled")
                    return
                }
                do {
                    self.tokens = try await client.exchangeCode(code, pkce: pkce)
                    self.status = .idle(lastSync: nil)
                    await self.pull()
                } catch {
                    self.status = .error(error.localizedDescription)
                }
            }
        }
        let provider = AnchorProvider(anchor: presentationAnchor)
        session.presentationContextProvider = provider
        session.prefersEphemeralWebBrowserSession = false
        self.authSession = session
        self.anchorProvider = provider
        session.start()
    }
    private var anchorProvider: AnchorProvider?

    public func unlink() {
        tokens = nil
        status = .notLinked
    }

    // MARK: - Persistence

    private static var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhoneList", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    private static func loadState() -> PersistedState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    private func persist() {
        let state = PersistedState(text: document.text, baseLines: baseLines,
                                   rev: rev, lastSync: lastSync)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: Self.stateURL, options: .atomic)
        }
        #if DEBUG
        // UI-test hook: mirror the file text to a host path for assertions.
        if let dump = ProcessInfo.processInfo.environment["PHONELIST_DUMP_PATH"] {
            try? document.text.write(toFile: dump, atomically: true, encoding: .utf8)
        }
        #endif
    }

    static let starterText = """
    ==========================================
    Getting started

    * Open Settings (gear icon) and link Dropbox.
    * The file at /research_TODO.txt will replace this list.

    """
}

final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor?
    init(anchor: ASPresentationAnchor?) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
}

extension Store {
    /// Like `edit`, but returns a value from the mutation (e.g. a new node id).
    @discardableResult
    public func edit<T>(returning body: (inout Document) -> T) -> T {
        var result: T?
        edit { result = body(&$0) }
        return result!
    }
}
