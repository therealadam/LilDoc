# ToolExperiments.playground Walkthrough

*2026-03-02T01:42:42Z by Showboat 0.6.0*
<!-- showboat-id: c4d52afe-b14e-4492-9376-3537f128d788 -->

This playground is a prototype for on-device AI tool calling using Apple's Foundation Models framework. It defines three tools that operate on an in-memory text document, wires them into a `LanguageModelSession`, and asks the model a question — proving that a local LLM on Apple Silicon can call structured tools and reason about text.

The code lives in three files:

```bash
ls ToolExperiments.playground/Contents.swift ToolExperiments.playground/Sources/*.swift
```

```output
ToolExperiments.playground/Contents.swift
ToolExperiments.playground/Sources/SampleText.swift
ToolExperiments.playground/Sources/Tools.swift
```

## SampleText.swift — Test Data

The playground needs a document to operate on. Rather than reading from disk (which Xcode playgrounds make awkward), `SampleText` is an enum with static string properties containing realistic sample documents. The main one is `meetingNotes` — a fake meeting transcript with TODOs, FIXMEs, and action items that give the tools something interesting to find and count.

```bash
cat ToolExperiments.playground/Sources/SampleText.swift
```

```output
import Foundation

/// Sample documents for testing tools without reading real files.
public enum SampleText {
    public static let meetingNotes = """
    # Q1 Planning Meeting

    TODO: Finalize budget by Friday
    TODO: Send hiring plan to VP

    We discussed the product roadmap for Q1. The main priorities are:
    1. Ship the new onboarding flow
    2. Fix the search performance regression
    3. FIXME: The analytics dashboard still shows stale data

    Action items:
    - Alice: draft the onboarding spec
    - Bob: profile the search queries
    - NOTE: We need to revisit the pricing model in February

    HACK: The export feature uses a hardcoded path for now.
    """

    public static let shortNote = """
    Pick up milk.
    Call the dentist.
    Finish the report.
    """
}
```

## Tools.swift — Three Tool Conformances

This is the heart of the experiment. Each tool conforms to Foundation Models' `Tool` protocol, which requires:

- A `name` and `description` (the LLM reads these to decide when to call each tool)
- An `Arguments` struct marked `@Generable` (the LLM generates these as structured output)
- A `call(arguments:)` method that does the actual work

All three tools take a `text: String` at init time — the document they operate on. They're pure functions over that string; no side effects, no state mutation.

### GetInfoTool

The simplest tool. Takes no arguments, returns word/line/character counts.

```bash
sed -n '23,39p' ToolExperiments.playground/Sources/Tools.swift
```

```output
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
```

Note the empty `Arguments` struct — the model doesn't need to provide any input, it just calls the tool. The `@Generable` macro is still required even when there are no fields.

### FindTool

A simple grep-like search. The model provides a query string, and the tool returns matching lines with line numbers (capped at 10 results).

```bash
sed -n '41,65p' ToolExperiments.playground/Sources/Tools.swift
```

```output
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
```

Here the `@Guide(description:)` macro annotates the `query` argument — this description is what the LLM reads to understand what value to generate. `localizedCaseInsensitiveContains` makes the search forgiving.

### CountPatternTool

Counts occurrences of a word or phrase using a split-and-subtract trick.

```bash
sed -n '4,21p' ToolExperiments.playground/Sources/Tools.swift
```

```output
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
```

The counting trick: split the text by the pattern, then subtract 1 from the number of segments. "a-b-a" split by "-" gives 3 segments, so 2 occurrences. Simple and correct for non-overlapping matches.

## Contents.swift — The Entry Point

This is where it all comes together. The playground's top-level code creates a model session, registers the three tools, and sends a natural language question.

```bash
cat ToolExperiments.playground/Contents.swift
```

```output
import Foundation
import FoundationModels

// MARK: - Verify Foundation Models availability

let model = SystemLanguageModel.default
print("Model availability: \(model.availability)")

// MARK: - Test through the model

let text = SampleText.meetingNotes

let session = LanguageModelSession(
    tools: [
        GetInfoTool(text: text),
        FindTool(text: text),
        CountPatternTool(text: text),
    ],
    instructions: "You are a text editing assistant. Use the provided tools to answer questions about the document. Be concise."
)

let r1 = try await session.respond(to: "How many TODOs are in this document?")
print("Q1:", r1.content)
```

The flow:

1. Check that the on-device model is available (`SystemLanguageModel.default`)
2. Grab the sample meeting notes as the target document
3. Create a `LanguageModelSession` with all three tools and a system instruction
4. Ask "How many TODOs are in this document?" — the model should recognize it needs to call `countPattern` with `"TODO"` and report the result

The model decides which tool to call based on the tool names, descriptions, and the `@Guide` annotations on their arguments. The developer never explicitly dispatches a tool — the LLM reasons about which one fits the question and generates the structured `Arguments` value.

This is the core proof-of-concept for LilDoc's on-device agent plan: if a local model can call tools over a text document in a playground, it can do the same thing inside the app.
