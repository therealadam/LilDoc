//: # Composed Features
//: Multiple tools working together to implement higher-level editing features.
//: Each experiment uses a fresh session to avoid filling the context window.

import FoundationModels

// MARK: - Full tool set (mirrors the on-device-agent-plan.md catalog)

struct GetInfoTool: Tool {
    let name = "getInfo"
    let description = "Get document statistics: word count, line count, and character count."
    let text: String
    @Generable struct Arguments {}
    func call(arguments: Arguments) async throws -> String {
        let words = text.split(whereSeparator: \.isWhitespace).count
        let lines = text.components(separatedBy: .newlines).count
        return "Words: \(words), Lines: \(lines), Characters: \(text.count)"
    }
}

struct CountPatternTool: Tool {
    let name = "countPattern"
    let description = "Count how many times a word or phrase appears in the document."
    let text: String
    @Generable struct Arguments {
        @Guide(description: "The word or phrase to count")
        var pattern: String
    }
    func call(arguments: Arguments) async throws -> String {
        let count = text.components(separatedBy: arguments.pattern).count - 1
        return "\(arguments.pattern): \(count) occurrences"
    }
}

struct FindInDocumentTool: Tool {
    let name = "findInDocument"
    let description = "Search the document for a word or phrase. Returns matching lines with line numbers."
    let text: String
    @Generable struct Arguments {
        @Guide(description: "The word or phrase to search for")
        var query: String
    }
    func call(arguments: Arguments) async throws -> String {
        let lines = text.components(separatedBy: .newlines)
        let results = lines.enumerated()
            .filter { $0.element.localizedCaseInsensitiveContains(arguments.query) }
            .prefix(10)
            .map { "Line \($0.offset + 1): \($0.element)" }
        return results.isEmpty ? "No matches found." : results.joined(separator: "\n")
    }
}

struct ReplaceInDocumentTool: Tool {
    let name = "replaceInDocument"
    let description = "Find and replace text in the document. Can replace the first match or all matches."
    let doc: MutableText
    @Generable struct Arguments {
        @Guide(description: "The text to find")
        var search: String
        @Guide(description: "The replacement text")
        var replacement: String
        @Guide(description: "Replace all occurrences (true) or just the first (false)")
        var all: Bool
    }
    func call(arguments: Arguments) async throws -> String {
        if arguments.all {
            let count = doc.content.components(separatedBy: arguments.search).count - 1
            doc.content = doc.content.replacingOccurrences(of: arguments.search, with: arguments.replacement)
            return "Replaced \(count) occurrence(s) of '\(arguments.search)'."
        }
        if let range = doc.content.range(of: arguments.search, options: .caseInsensitive) {
            doc.content = doc.content.replacingCharacters(in: range, with: arguments.replacement)
            return "Replaced 1 occurrence of '\(arguments.search)'."
        }
        return "No match found for '\(arguments.search)'."
    }
}

struct PrefixLinesTool: Tool {
    let name = "prefixLines"
    let description = "Add a prefix to every line in the document, or only lines containing a specific word. Useful for adding bullet points or markers."
    let doc: MutableText
    @Generable struct Arguments {
        @Guide(description: "The prefix to add to each matching line (e.g. '- ' for bullets)")
        var prefix: String
        @Guide(description: "Only prefix lines containing this text. Leave empty to prefix all lines.")
        var matching: String
    }
    func call(arguments: Arguments) async throws -> String {
        let lines = doc.content.components(separatedBy: .newlines)
        let pattern = arguments.matching.isEmpty ? nil : arguments.matching
        let result = lines.map { line -> String in
            if let pattern {
                return line.localizedCaseInsensitiveContains(pattern) ? arguments.prefix + line : line
            }
            return line.isEmpty ? line : arguments.prefix + line
        }
        doc.content = result.joined(separator: "\n")
        return "Added prefix '\(arguments.prefix)' to matching lines."
    }
}

// MARK: - Feature: Count all markers
//
// Sends one prompt; the model calls countPattern in parallel for each marker.

print("=== Count Markers ===")
let markerText = SampleText.meetingNotes
let markerSession = LanguageModelSession(
    tools: [CountPatternTool(text: markerText)],
    instructions: Instructions {
        "You are a text editing assistant."
        "Use the countPattern tool to count occurrences."
        "Report all counts clearly."
    }
)
let markers = try await markerSession.respond(
    to: "Count how many times each of these appears: TODO, FIXME, HACK, NOTE"
)
print(markers.content)

// MARK: - Feature: Make a bulleted list

print("\n=== Make List ===")
let listDoc = MutableText(SampleText.shortNote)
let listSession = LanguageModelSession(
    tools: [PrefixLinesTool(doc: listDoc)],
    instructions: Instructions {
        "You are a text editing assistant."
        "Use prefixLines to format the document."
    }
)
print("Before:", listDoc.content)
let listResult = try await listSession.respond(to: "Convert this into a Markdown bulleted list")
print("A:", listResult.content)
print("After:\n", listDoc.content)

// MARK: - Feature: Summarize document stats then find key content

print("\n=== Stats + Search ===")
let richText = SampleText.meetingNotes
let richSession = LanguageModelSession(
    tools: [
        GetInfoTool(text: richText),
        FindInDocumentTool(text: richText),
    ],
    instructions: Instructions {
        "You are a text editing assistant."
        "Use getInfo for size questions, findInDocument for content questions."
        "Be concise."
    }
)
let statsResult = try await richSession.respond(
    to: "How long is this document and what are the action items?"
)
print(statsResult.content)
