//: # Mutation Tools
//: Tools that modify document text.
//: MutableText (from Sources/) holds state so you can print before/after.

import FoundationModels

// MARK: - Tool definitions

struct ReplaceInDocumentTool: Tool {
    let name = "replaceInDocument"
    let description = "Find and replace text in the document. Can replace the first match or all matches."

    let doc: MutableText

    @Generable
    struct Arguments {
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
            doc.content = doc.content.replacingOccurrences(
                of: arguments.search,
                with: arguments.replacement
            )
            return "Replaced \(count) occurrence(s) of '\(arguments.search)'."
        } else {
            if let range = doc.content.range(of: arguments.search, options: .caseInsensitive) {
                doc.content = doc.content.replacingCharacters(in: range, with: arguments.replacement)
                return "Replaced 1 occurrence of '\(arguments.search)'."
            }
            return "No match found for '\(arguments.search)'."
        }
    }
}

struct WrapMatchesTool: Tool {
    let name = "wrapMatches"
    let description = "Find every occurrence of a word or phrase and wrap each one with a prefix and suffix. Example: wrap 'TODO' with '**' and '**' to bold every TODO in Markdown."

    let doc: MutableText

    @Generable
    struct Arguments {
        @Guide(description: "The text to search for")
        var search: String
        @Guide(description: "Text to insert before each match")
        var prefix: String
        @Guide(description: "Text to insert after each match")
        var suffix: String
    }

    func call(arguments: Arguments) async throws -> String {
        let wrapped = arguments.prefix + arguments.search + arguments.suffix
        let count = doc.content.components(separatedBy: arguments.search).count - 1
        doc.content = doc.content.replacingOccurrences(of: arguments.search, with: wrapped)
        return "Wrapped \(count) occurrence(s) of '\(arguments.search)'."
    }
}

struct AppendToDocumentTool: Tool {
    let name = "appendToDocument"
    let description = "Add text to the very end of the document."

    let doc: MutableText

    @Generable
    struct Arguments {
        @Guide(description: "The text to append")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        doc.content += arguments.text
        return "Appended text to document."
    }
}

struct PrependToDocumentTool: Tool {
    let name = "prependToDocument"
    let description = "Add text to the very beginning of the document."

    let doc: MutableText

    @Generable
    struct Arguments {
        @Guide(description: "The text to prepend")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        doc.content = arguments.text + doc.content
        return "Prepended text to document."
    }
}

// MARK: - Test tools by hand

var doc = MutableText(SampleText.meetingNotes)

let replaceTool = ReplaceInDocumentTool(doc: doc)
print("Before replace:", doc.content.components(separatedBy: "TODO").count - 1, "TODOs")
let replaceResult = try await replaceTool.call(arguments: .init(search: "TODO", replacement: "DONE", all: true))
print(replaceResult)
print("After replace:", doc.content.components(separatedBy: "DONE").count - 1, "DONEs")

doc = MutableText(SampleText.meetingNotes)
let wrapTool = WrapMatchesTool(doc: doc)
let wrapResult = try await wrapTool.call(arguments: .init(search: "TODO", prefix: "**", suffix: "**"))
print("\n", wrapResult)
print("Sample after wrap:", String(doc.content.prefix(200)))

// MARK: - Test through the model

doc = MutableText(SampleText.meetingNotes)

let session = LanguageModelSession(
    tools: [
        ReplaceInDocumentTool(doc: doc),
        WrapMatchesTool(doc: doc),
        AppendToDocumentTool(doc: doc),
        PrependToDocumentTool(doc: doc),
    ],
    instructions: Instructions {
        "You are a text editing assistant."
        "When asked to change the document, use the appropriate tool and confirm what you did."
        "Be concise."
    }
)

print("\n--- Model-driven mutations ---")
print("Before:", doc.content.prefix(100))

let r1 = try await session.respond(to: "Change every TODO to DONE")
print("\nQ: Change every TODO to DONE")
print("A:", r1.content)
print("Doc now:", doc.content.prefix(200))

let r2 = try await session.respond(to: "Add a footer: '---\\nEnd of notes.'")
print("\nQ: Add a footer")
print("A:", r2.content)
print("Doc end:", doc.content.suffix(50))
