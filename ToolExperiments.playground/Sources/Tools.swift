import Foundation
import FoundationModels

public struct CountPatternTool: Tool {
    public let name = "countPattern"
    public let description = "Count how many times a word or phrase appears in the text."
    public let text: String

    @Generable
    public struct Arguments {
        @Guide(description: "The word or phrase to count")
        public var pattern: String
    }

    public init(text: String) { self.text = text }

    public func call(arguments: Arguments) async throws -> String {
        let count = text.components(separatedBy: arguments.pattern).count - 1
        return "\(arguments.pattern): \(count) occurrences"
    }
}

public struct GetInfoTool: Tool {
    public let name = "getInfo"
    public let description = "Get document statistics: word count, line count, character count."
    public let text: String

    @Generable
    public struct Arguments {}

    public init(text: String) { self.text = text }

    public func call(arguments: Arguments) async throws -> String {
        let words = text.split(whereSeparator: \.isWhitespace).count
        let lines = text.components(separatedBy: .newlines).count
        let chars = text.count
        return "Words: \(words), Lines: \(lines), Characters: \(chars)"
    }
}

public struct FindTool: Tool {
    public let name = "findInDocument"
    public let description = "Search the text for a word or phrase. Returns matching lines with line numbers."
    public let text: String

    @Generable
    public struct Arguments {
        @Guide(description: "The text to search for")
        public var query: String
    }

    public init(text: String) { self.text = text }

    public func call(arguments: Arguments) async throws -> String {
        let lines = text.components(separatedBy: .newlines)
        var results: [String] = []
        for (i, line) in lines.enumerated() {
            if line.localizedCaseInsensitiveContains(arguments.query) {
                results.append("Line \(i + 1): \(line)")
            }
        }
        if results.isEmpty { return "No matches found." }
        return results.prefix(10).joined(separator: "\n")
    }
}
