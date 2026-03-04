import Foundation

public struct TextOperations {
    public enum LinePosition: Sendable {
        case before, after
    }

    // MARK: - Replace

    /// Replace the first or all occurrences of `search` with `replacement`.
    /// Returns the modified text and the number of replacements made.
    public static func replace(
        in text: String, search: String, with replacement: String, all: Bool
    ) -> (result: String, count: Int) {
        guard !search.isEmpty else { return (text, 0) }
        if all {
            let count = text.components(separatedBy: search).count - 1
            let result = text.replacingOccurrences(of: search, with: replacement)
            return (result, count)
        } else {
            if let range = text.range(of: search) {
                let result = text.replacingCharacters(in: range, with: replacement)
                return (result, 1)
            }
            return (text, 0)
        }
    }

    // MARK: - Insert

    /// Insert `content` before or after the line at `lineNumber` (1-indexed).
    public static func insertLine(
        in text: String, content: String, at lineNumber: Int, position: LinePosition
    ) -> String {
        var lines = text.components(separatedBy: "\n")
        let idx: Int
        switch position {
        case .before: idx = max(0, min(lineNumber - 1, lines.count))
        case .after:  idx = max(0, min(lineNumber, lines.count))
        }
        lines.insert(content, at: idx)
        return lines.joined(separator: "\n")
    }

    // MARK: - Wrap

    /// Wrap every occurrence of `search` with `prefix` and `suffix` (case-insensitive).
    public static func wrapMatches(
        in text: String, search: String, prefix: String, suffix: String
    ) -> (result: String, count: Int) {
        guard !search.isEmpty else { return (text, 0) }
        var result = ""
        var remaining = text
        var count = 0
        while let range = remaining.range(of: search, options: .caseInsensitive) {
            result += remaining[remaining.startIndex..<range.lowerBound]
            result += prefix + String(remaining[range]) + suffix
            remaining = String(remaining[range.upperBound...])
            count += 1
        }
        result += remaining
        return (result, count)
    }

    // MARK: - Prefix lines

    /// Add `prefix` to every line, or only to lines containing `pattern`.
    public static func prefixLines(
        in text: String, prefix: String, matching pattern: String?
    ) -> String {
        let lines = text.components(separatedBy: "\n")
        return lines.map { line in
            guard let p = pattern else { return prefix + line }
            return line.contains(p) ? prefix + line : line
        }.joined(separator: "\n")
    }

    // MARK: - Append

    /// Append `content` to the end of `text`, ensuring a newline separator.
    public static func append(_ content: String, to text: String) -> String {
        if text.isEmpty { return content }
        let sep = text.hasSuffix("\n") ? "" : "\n"
        return text + sep + content
    }

    // MARK: - Diff

    /// Return a human-readable before/after summary for dry-run display.
    /// Not a true LCS diff, but sufficient for previewing single-operation changes.
    public static func unifiedDiff(original: String, modified: String, path: String) -> String {
        guard original != modified else { return "(no changes)" }
        let origLines = original.components(separatedBy: "\n")
        let modLines  = modified.components(separatedBy: "\n")

        var diff = "--- a/\(path)\n+++ b/\(path)\n"
        var i = 0, j = 0
        var hunkLines = ""
        var hunkOldStart = 1, hunkOldLen = 0, hunkNewStart = 1, hunkNewLen = 0
        var inHunk = false

        while i < origLines.count || j < modLines.count {
            let oldLine = i < origLines.count ? origLines[i] : nil
            let newLine = j < modLines.count ? modLines[j] : nil

            if oldLine == newLine {
                hunkLines += " \(oldLine!)\n"
                i += 1; j += 1
                hunkOldLen += 1; hunkNewLen += 1
                inHunk = true
            } else if let old = oldLine, newLine == nil {
                hunkLines += "-\(old)\n"
                i += 1; hunkOldLen += 1; inHunk = true
            } else if oldLine == nil, let new = newLine {
                hunkLines += "+\(new)\n"
                j += 1; hunkNewLen += 1; inHunk = true
            } else {
                hunkLines += "-\(oldLine!)\n"
                hunkLines += "+\(newLine!)\n"
                i += 1; j += 1
                hunkOldLen += 1; hunkNewLen += 1; inHunk = true
            }
        }

        if inHunk {
            diff += "@@ -\(hunkOldStart),\(hunkOldLen) +\(hunkNewStart),\(hunkNewLen) @@\n"
            diff += hunkLines
        }
        return diff
    }
}
