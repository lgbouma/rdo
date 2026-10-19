import Foundation
import CryptoKit

/// Minimal Dropbox API v2 client: PKCE OAuth, refresh, download, upload.
/// Uses only Foundation + CryptoKit so it compiles everywhere.
public struct DropboxTokens: Codable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool { Date() > expiresAt.addingTimeInterval(-60) }
}

public struct DropboxFile: Equatable {
    public var content: Data
    public var rev: String
    public var serverModified: String?
}

public enum DropboxError: Error, LocalizedError, Equatable {
    case notLinked
    case conflict           // upload rev did not match
    case notFound
    case http(Int, String)
    case badResponse(String)
    case missingAppKey

    public var errorDescription: String? {
        switch self {
        case .notLinked: return "Dropbox is not linked."
        case .conflict: return "The file changed on Dropbox since it was last downloaded."
        case .notFound: return "File not found on Dropbox."
        case .http(let code, let body): return "Dropbox HTTP \(code): \(body)"
        case .badResponse(let s): return "Unexpected Dropbox response: \(s)"
        case .missingAppKey: return "Dropbox app key is not set (see README)."
        }
    }
}

public struct PKCE {
    public let verifier: String
    public let challenge: String

    public init() {
        var bytes = [UInt8](repeating: 0, count: 48)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        verifier = Data(bytes).base64URLEncoded()
        challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public final class DropboxClient {
    public let appKey: String
    public let redirectURI: String
    private let session: URLSession

    public init(appKey: String, redirectURI: String, session: URLSession = .shared) {
        self.appKey = appKey
        self.redirectURI = redirectURI
        self.session = session
    }

    // MARK: OAuth

    public func authorizationURL(pkce: PKCE) -> URL {
        var c = URLComponents(string: "https://www.dropbox.com/oauth2/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: appKey),
            .init(name: "response_type", value: "code"),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "token_access_type", value: "offline"),
        ]
        return c.url!
    }

    public func exchangeCode(_ code: String, pkce: PKCE) async throws -> DropboxTokens {
        try await tokenRequest([
            "code": code,
            "grant_type": "authorization_code",
            "code_verifier": pkce.verifier,
            "client_id": appKey,
            "redirect_uri": redirectURI,
        ], refreshToken: nil)
    }

    public func refresh(_ tokens: DropboxTokens) async throws -> DropboxTokens {
        guard let rt = tokens.refreshToken else { throw DropboxError.notLinked }
        return try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": rt,
            "client_id": appKey,
        ], refreshToken: rt)
    }

    private func tokenRequest(_ form: [String: String], refreshToken: String?) async throws -> DropboxTokens {
        var req = URLRequest(url: URL(string: "https://api.dropboxapi.com/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\($0.value.formEncoded())" }.joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp, data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            throw DropboxError.badResponse(String(decoding: data, as: UTF8.self))
        }
        let expires = (json["expires_in"] as? Double) ?? 14400
        return DropboxTokens(accessToken: access,
                             refreshToken: (json["refresh_token"] as? String) ?? refreshToken,
                             expiresAt: Date().addingTimeInterval(expires))
    }

    // MARK: Files

    public func download(path: String, accessToken: String) async throws -> DropboxFile {
        var req = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/download")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.apiArg(["path": path]), forHTTPHeaderField: "Dropbox-API-Arg")
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp, data)
        guard let http = resp as? HTTPURLResponse,
              let result = http.value(forHTTPHeaderField: "Dropbox-API-Result"),
              let json = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any],
              let rev = json["rev"] as? String else {
            throw DropboxError.badResponse("missing Dropbox-API-Result")
        }
        return DropboxFile(content: data, rev: rev, serverModified: json["server_modified"] as? String)
    }

    /// Upload with `mode=update` against `rev`. Throws `.conflict` if the
    /// file on Dropbox no longer has that rev. Pass `rev == nil` to overwrite.
    public func upload(path: String, content: Data, rev: String?, accessToken: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        var arg: [String: Any] = ["path": path, "autorename": false, "mute": true]
        if let rev { arg["mode"] = [".tag": "update", "update": rev] } else { arg["mode"] = "overwrite" }
        req.setValue(Self.apiArg(arg), forHTTPHeaderField: "Dropbox-API-Arg")
        req.httpBody = content
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp, data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newRev = json["rev"] as? String else {
            throw DropboxError.badResponse(String(decoding: data, as: UTF8.self))
        }
        return newRev
    }

    // MARK: helpers

    static func apiArg(_ dict: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        // Header must be ASCII; escape non-ASCII as \uXXXX.
        return String(decoding: data, as: UTF8.self).unicodeScalars.map { s -> String in
            s.isASCII ? String(s) : String(format: "\\u%04x", s.value)
        }.joined()
    }

    static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { throw DropboxError.badResponse("no HTTP response") }
        guard !(200..<300).contains(http.statusCode) else { return }
        let body = String(decoding: data, as: UTF8.self)
        if http.statusCode == 409 {
            if body.contains("conflict") { throw DropboxError.conflict }
            if body.contains("not_found") { throw DropboxError.notFound }
        }
        throw DropboxError.http(http.statusCode, body)
    }
}

extension String {
    func formEncoded() -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
