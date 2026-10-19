import Foundation

public enum Rewrap {
    /// Collapse all runs of whitespace (including newlines) to single spaces.
    public static func normalise(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// Greedy word wrap. The first line is prefixed with `firstPrefix`, the
    /// rest with `restPrefix` (vim-style hanging indent). A word longer than
    /// the available width (e.g. a URL) goes on its own line unbroken.
    public static func wrap(_ text: String, firstPrefix: String, restPrefix: String, width: Int) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        if words.isEmpty { return [firstPrefix.trimmingTrailingSpaces()] }
        var out: [String] = []
        var current = firstPrefix
        var currentHasWord = false
        for w in words {
            let candidate = currentHasWord ? current + " " + w : current + w
            if candidate.count <= width || !currentHasWord {
                current = candidate
                currentHasWord = true
            } else {
                out.append(current)
                current = restPrefix + w
                currentHasWord = true
            }
        }
        out.append(current)
        return out
    }
}

extension String {
    func trimmingTrailingSpaces() -> String {
        var s = Substring(self)
        while s.last == " " { s = s.dropLast() }
        return String(s)
    }
}
