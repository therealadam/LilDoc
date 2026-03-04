import Foundation

public struct TextSearch {
    public struct Match: Sendable {
        /// 1-indexed line number.
        public let line: Int
        /// 1-indexed column of the match start.
        public let column: Int
        /// The matched substring.
        public let text: String
        /// The full line containing the match.
        public let context: String

        public init(line: Int, column: Int, text: String, context: String) {
            self.line = line
            self.column = column
            self.text = text
            self.context = context
        }
    }

    /// Find all occurrences of `query` in `text` (case-insensitive).
    /// Returns one Match per occurrence, with the line and column where it starts.
    public static func findMatches(in text: String, query: String) -> [Match] {
        guard !query.isEmpty else { return [] }
        var matches: [Match] = []
        let lines = text.components(separatedBy: "\n")
        for (lineIndex, line) in lines.enumerated() {
            var searchRange = line.startIndex..<line.endIndex
            while let range = line.range(of: query, options: .caseInsensitive, range: searchRange) {
                let column = line.distance(from: line.startIndex, to: range.lowerBound) + 1
                matches.append(Match(
                    line: lineIndex + 1,
                    column: column,
                    text: String(line[range]),
                    context: line
                ))
                searchRange = range.upperBound..<line.endIndex
            }
        }
        return matches
    }
}
