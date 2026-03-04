import Foundation

public struct TextAnalysis {
    /// Count words in text (same logic as ContentView's status bar).
    public static func wordCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    /// Count Unicode scalar characters (not bytes).
    public static func characterCount(_ text: String) -> Int {
        text.count
    }

    /// Count lines. Empty string = 0 lines. A trailing newline does not add an extra line.
    public static func lineCount(_ text: String) -> Int {
        if text.isEmpty { return 0 }
        var count = text.components(separatedBy: "\n").count
        if text.hasSuffix("\n") { count -= 1 }
        return max(count, 1)
    }
}
