//: # Inspection Tools
//: Read-only tools for querying document content.
//: Run each section independently to verify tool logic before involving the model.

import FoundationModels

// MARK: - Availability check

let model = SystemLanguageModel.default
print("Model availability:", model.availability)

// MARK: - Tool definitions
// @Generable types must live on the playground page, not in Sources/.

struct GetInfoTool: Tool {
    let name = "getInfo"
    let description = "Get document statistics: word count, line count, and character count."

    let text: String

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let words = text.split(whereSeparator: \.isWhitespace).count
        let lines = text.components(separatedBy: .newlines).count
        let chars = text.count
        return "Words: \(words), Lines: \(lines), Characters: \(chars)"
    }
}

struct FindInDocumentTool: Tool {
    let name = "findInDocument"
    let description = "Search the document for a word or phrase. Returns matching lines with line numbers."

    let text: String

    @Generable
    struct Arguments {
        @Guide(description: "The word or phrase to search for")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
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

struct CountPatternTool: Tool {
    let name = "countPattern"
    let description = "Count how many times a word or phrase appears in the document."

    let text: String

    @Generable
    struct Arguments {
        @Guide(description: "The word or phrase to count")
        var pattern: String
    }

    func call(arguments: Arguments) async throws -> String {
        let components = text.components(separatedBy: arguments.pattern)
        let count = components.count - 1
        return "\(arguments.pattern): \(count) occurrences"
    }
}

// MARK: - Test tools by hand (no model involved)

let infoTool = GetInfoTool(text: SampleText.meetingNotes)
let infoResult = try await infoTool.call(arguments: .init())
print("Info:", infoResult)

let findTool = FindInDocumentTool(text: SampleText.meetingNotes)
let findResult = try await findTool.call(arguments: .init(query: "TODO"))
print("Find TODOs:\n\(findResult)")

let countTool = CountPatternTool(text: SampleText.meetingNotes)
let countResult = try await countTool.call(arguments: .init(pattern: "TODO"))
print("Count:", countResult)

// MARK: - Test through the model

let text = SampleText.meetingNotes

let session = LanguageModelSession(
    tools: [
        GetInfoTool(text: text),
        FindInDocumentTool(text: text),
        CountPatternTool(text: text),
    ],
    instructions: Instructions {
        "You are a text editing assistant for a plain text document."
        "Use getInfo for questions about document size (words, lines, characters)."
        "Use findInDocument for questions about what the document contains."
        "Use countPattern for questions about how many times something appears."
        "Be concise. Do not reproduce large amounts of text."
    }
)

let r1 = try await session.respond(to: "How long is this document?")
print("\nQ: How long is this document?")
print("A:", r1.content)

let r2 = try await session.respond(to: "How many TODOs are there?")
print("\nQ: How many TODOs are there?")
print("A:", r2.content)

let r3 = try await session.respond(to: "Find all the action items")
print("\nQ: Find all the action items")
print("A:", r3.content)

// MARK: - Inspect the transcript

print("\n--- Transcript ---")
for entry in session.transcript.entries {
    print(entry)
}
