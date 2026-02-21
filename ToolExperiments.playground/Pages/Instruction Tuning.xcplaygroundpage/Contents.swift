//: # Instruction Tuning
//: Experiment with how instruction wording affects tool selection, response verbosity,
//: and context window consumption. Each section isolates one variable.

import FoundationModels

// MARK: - Shared tools for all experiments

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

let text = SampleText.meetingNotes

func makeTools() -> [any Tool] {
    [GetInfoTool(text: text), FindInDocumentTool(text: text), CountPatternTool(text: text)]
}

// MARK: - Experiment 1: Vague vs specific instructions
//
// Does the model pick the right tool without explicit guidance?

print("=== Vague instructions ===")
let vagueSession = LanguageModelSession(
    tools: makeTools(),
    instructions: Instructions { "Help the user with their document." }
)
let vague1 = try await vagueSession.respond(to: "Are there any TODOs?")
print("Q: Are there any TODOs?")
print("A:", vague1.content)

print("\n=== Specific instructions ===")
let specificSession = LanguageModelSession(
    tools: makeTools(),
    instructions: Instructions {
        "You are a text editing assistant for a plain text document."
        "Use getInfo for questions about document size (words, lines, characters)."
        "Use findInDocument for questions about what the document contains."
        "Use countPattern for questions about how many times something appears."
        "Be concise. Do not reproduce large amounts of text."
    }
)
let specific1 = try await specificSession.respond(to: "Are there any TODOs?")
print("Q: Are there any TODOs?")
print("A:", specific1.content)

// MARK: - Experiment 2: Response verbosity
//
// Can you force the model to be terse?

print("\n=== Verbose response ===")
let verboseSession = LanguageModelSession(
    tools: makeTools(),
    instructions: Instructions { "You are a helpful assistant. Be thorough." }
)
let verbose1 = try await verboseSession.respond(to: "How long is this document?")
print("A:", verbose1.content)

print("\n=== Terse response ===")
let terseSession = LanguageModelSession(
    tools: makeTools(),
    instructions: Instructions {
        "You are a text editing assistant."
        "Reply in one sentence."
        "Do not echo tool output. Summarize it."
    }
)
let terse1 = try await terseSession.respond(to: "How long is this document?")
print("A:", terse1.content)

// MARK: - Experiment 3: Context window budget
//
// Send multiple turns and watch for exceededContextWindowSize.
// This tells you how many turns your instructions + tool schemas allow.

print("\n=== Context window stress test ===")
let budgetSession = LanguageModelSession(
    tools: makeTools(),
    instructions: Instructions {
        "You are a text editing assistant."
        "Be concise."
    }
)

let questions = [
    "How many words are in this document?",
    "How many TODOs are there?",
    "Find lines mentioning Alice",
    "How many FIXMEs?",
    "Find lines mentioning Bob",
    "How many characters?",
    "Find the action items",
    "How many HACKs?",
]

for (i, question) in questions.enumerated() {
    do {
        let response = try await budgetSession.respond(to: question)
        print("Turn \(i + 1): \(response.content)")
    } catch {
        print("Turn \(i + 1): Context full — \(error)")
        break
    }
}
