# On-Device Agent Plan: Apple Foundation Models in Lil' Doc

This plan describes how to make Lil' Doc's document editor agent-capable using Apple's on-device foundation model (Foundation Models framework, macOS 26). The editor exposes its operations as Swift `Tool` conformances. The on-device model calls these tools to perform editing tasks the user describes in natural language.

This is a different architecture from the MCP/CLI plan. The agent lives _inside_ the app, not outside it. The user talks to the model through a text field in the editor. The model calls tools that operate on the current document. The tools are Swift functions backed by the same logic the UI uses.


## Design constraints from the framework

These shape every decision in this plan:

**4,096-token context window.** Input + output + tool schemas + tool results all share this budget. Tools must return concise results. We cannot dump entire documents into the prompt. Instructions must be terse.

**No sequential tool chaining within a turn.** The model calls tools, gets all results back, then generates its final response. It cannot call a tool, read the result, then call another tool. This means tools must be self-contained operations, not pipeline stages. "Search then replace" must be a single `replaceInDocument` tool, not a search tool followed by a replace tool.

**Parallel tool calls are supported.** The model can call multiple tools simultaneously in one turn. So "count TODOs and count FIXMEs" works as two parallel `countPattern` calls.

**~3B parameter model.** Good at structured output, tool selection, and following instructions. Not good at complex multi-step reasoning. The tools should do the heavy lifting; the model should decide _which_ tool to call and _with what arguments_.

**On-device only.** No network. No cost. No data leaves the device. Works offline. But requires Apple Silicon and macOS 26+.


## Architecture overview

```
┌─────────────────────────────────────────────┐
│  LilDocApp                                  │
│  ┌───────────────────────────────────────┐  │
│  │  ContentView                          │  │
│  │  ┌─────────────┐  ┌───────────────┐   │  │
│  │  │ PlainText   │  │ AgentField    │   │  │
│  │  │ Editor      │  │ (user input)  │   │  │
│  │  └──────┬──────┘  └───────┬───────┘   │  │
│  │         │                 │            │  │
│  │         ▼                 ▼            │  │
│  │  ┌─────────────────────────────────┐  │  │
│  │  │  DocumentAgent (@Observable)    │  │  │
│  │  │  - LanguageModelSession         │  │  │
│  │  │  - tools: [any Tool]            │  │  │
│  │  │  - instructions: Instructions   │  │  │
│  │  └──────────────┬──────────────────┘  │  │
│  └─────────────────┼────────────────────-┘  │
│                    │                         │
│           ┌───────-┼────────┐                │
│           ▼        ▼        ▼                │
│  ┌────────────┐ ┌──────┐ ┌──────────────┐   │
│  │ Read/      │ │Search│ │ Transform    │   │
│  │ Inspect    │ │Tools │ │ Tools        │   │
│  │ Tools      │ │      │ │              │   │
│  └─────┬──────┘ └──┬───┘ └──────┬───────┘   │
│        │           │            │            │
│        ▼           ▼            ▼            │
│  ┌─────────────────────────────────────┐     │
│  │  LilDocKit (pure Foundation logic)  │     │
│  └─────────────────────────────────────┘     │
└─────────────────────────────────────────────┘
```

Three layers:
1. **LilDocKit** — pure functions, no UI, no framework dependency. Testable on Linux.
2. **Tools** — Swift structs conforming to `Tool`, wrapping LilDocKit. Each tool holds a reference to the document binding so it can read and mutate the editor's text.
3. **DocumentAgent** — an `@Observable` class that owns the `LanguageModelSession`, the tool set, and the instructions. Wired into the SwiftUI view hierarchy.


## Phase 0: Extract LilDocKit

Same as the MCP/CLI plan. Pull pure logic out of the view layer. This phase is identical regardless of which agent interface we build on top.

```
LilDocKit/
  Sources/LilDocKit/
    TextAnalysis.swift      # wordCount, characterCount, lineCount
    TextSearch.swift         # findMatches(in:query:) -> [Match]
    TextOperations.swift     # replace, insert, wrapMatches, prependLine, appendLine
  Tests/LilDocKitTests/
    ...
```

**Key addition for this plan**: `TextOperations` needs richer operations than the MCP plan because the on-device model can't chain tools. Each operation must be self-contained.

```swift
public struct TextOperations {
    /// Replace first or all occurrences of `search` with `replacement`.
    public static func replace(
        in text: String, search: String, with replacement: String, all: Bool
    ) -> (result: String, count: Int)

    /// Insert `content` before or after the line at `lineNumber` (1-indexed).
    public static func insertLine(
        in text: String, content: String, at lineNumber: Int, position: LinePosition
    ) -> String

    /// Wrap every occurrence of `search` with `prefix` and `suffix`.
    public static func wrapMatches(
        in text: String, search: String, prefix: String, suffix: String
    ) -> (result: String, count: Int)

    /// Add a prefix to every line matching `pattern`, or all lines if nil.
    public static func prefixLines(
        in text: String, prefix: String, matching pattern: String?
    ) -> String

    /// Wrap the entire text or a line range in `prefix` and `suffix`.
    public static func wrapRange(
        in text: String, lineRange: ClosedRange<Int>?, prefix: String, suffix: String
    ) -> String

    public enum LinePosition { case before, after }
}
```

**Verification**: `swift test` passes. App still works identically.


## Phase 1: Define tools

Each tool is a struct conforming to `Tool`. Tools hold a reference to the document text (via a closure or binding) so they can read and mutate it.

### Document access pattern

Tools need access to the current document. Since `Tool.call` is `async` and tools may be called from a non-main-actor context, we use a thread-safe wrapper:

```swift
/// Provides tools with read/write access to the document text.
@MainActor
final class DocumentAccess: Observable {
    var text: String  // bound to the document

    func read() -> String { text }
    func write(_ newText: String) { text = newText }
    func readLines(_ range: ClosedRange<Int>) -> String { ... }
}
```

Tools receive a `DocumentAccess` instance at initialization.

### Tool catalog

**Inspection tools** (read-only, cheap, safe to call freely):

```swift
struct GetDocumentInfoTool: Tool {
    let name = "getDocumentInfo"
    let description = "Get document statistics: word count, line count, and character count."
    let doc: DocumentAccess

    @Generable struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let text = await doc.read()
        let words = TextAnalysis.wordCount(text)
        let lines = TextAnalysis.lineCount(text)
        let chars = TextAnalysis.characterCount(text)
        return "Words: \(words), Lines: \(lines), Characters: \(chars)"
    }
}

struct ReadLinesTool: Tool {
    let name = "readLines"
    let description = "Read specific lines from the document by line number range. Use this to inspect parts of the document without reading the whole thing."
    let doc: DocumentAccess

    @Generable struct Arguments {
        @Guide(description: "First line number to read (1-indexed)")
        var from: Int
        @Guide(description: "Last line number to read (1-indexed)")
        var to: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await doc.readLines(arguments.from...arguments.to)
    }
}

struct FindInDocumentTool: Tool {
    let name = "findInDocument"
    let description = "Search the document for a word or phrase. Returns matching lines with line numbers."
    let doc: DocumentAccess

    @Generable struct Arguments {
        @Guide(description: "The text to search for")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let text = await doc.read()
        let matches = TextSearch.findMatches(in: text, query: arguments.query)
        if matches.isEmpty { return "No matches found." }
        // Return concise results to conserve tokens
        return matches.prefix(10).map { "Line \($0.line): \($0.context)" }.joined(separator: "\n")
    }
}

struct CountPatternTool: Tool {
    let name = "countPattern"
    let description = "Count how many times a word or phrase appears in the document."
    let doc: DocumentAccess

    @Generable struct Arguments {
        @Guide(description: "The text pattern to count")
        var pattern: String
    }

    func call(arguments: Arguments) async throws -> String {
        let text = await doc.read()
        let matches = TextSearch.findMatches(in: text, query: arguments.pattern)
        return "\(arguments.pattern): \(matches.count) occurrences"
    }
}
```

**Mutation tools** (modify the document):

```swift
struct ReplaceInDocumentTool: Tool {
    let name = "replaceInDocument"
    let description = "Find and replace text in the document. Can replace the first match or all matches."
    let doc: DocumentAccess

    @Generable struct Arguments {
        @Guide(description: "The text to find")
        var search: String
        @Guide(description: "The replacement text")
        var replacement: String
        @Guide(description: "Replace all occurrences (true) or just the first (false)")
        var all: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        let text = await doc.read()
        let (result, count) = TextOperations.replace(
            in: text, search: arguments.search,
            with: arguments.replacement, all: arguments.all
        )
        await doc.write(result)
        return "Replaced \(count) occurrence(s)."
    }
}

struct InsertLineTool: Tool {
    let name = "insertLine"
    let description = "Insert a new line of text before or after a specific line number in the document."
    let doc: DocumentAccess

    @Generable
    enum Position: String, CaseIterable {
        case before
        case after
    }

    @Generable struct Arguments {
        @Guide(description: "The text to insert")
        var text: String
        @Guide(description: "The line number to insert relative to (1-indexed)")
        var lineNumber: Int
        @Guide(description: "Insert before or after the specified line")
        var position: Position
    }

    func call(arguments: Arguments) async throws -> String {
        let text = await doc.read()
        let pos: TextOperations.LinePosition = arguments.position == .before ? .before : .after
        let result = TextOperations.insertLine(
            in: text, content: arguments.text,
            at: arguments.lineNumber, position: pos
        )
        await doc.write(result)
        return "Inserted line \(arguments.position.rawValue) line \(arguments.lineNumber)."
    }
}

struct WrapMatchesTool: Tool {
    let name = "wrapMatches"
    let description = "Find every occurrence of a word or phrase and wrap each one with a prefix and suffix. Example: wrap 'TODO' with '**' and '**' to make every TODO bold in Markdown."
    let doc: DocumentAccess

    @Generable struct Arguments {
        @Guide(description: "The text to search for")
        var search: String
        @Guide(description: "Text to insert before each match")
        var prefix: String
        @Guide(description: "Text to insert after each match")
        var suffix: String
    }

    func call(arguments: Arguments) async throws -> String {
        let text = await doc.read()
        let (result, count) = TextOperations.wrapMatches(
            in: text, search: arguments.search,
            prefix: arguments.prefix, suffix: arguments.suffix
        )
        await doc.write(result)
        return "Wrapped \(count) occurrence(s) of '\(arguments.search)'."
    }
}

struct PrependToDocumentTool: Tool {
    let name = "prependToDocument"
    let description = "Add text to the very beginning of the document."
    let doc: DocumentAccess

    @Generable struct Arguments {
        @Guide(description: "The text to prepend")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        let text = await doc.read()
        await doc.write(arguments.text + text)
        return "Prepended text to document."
    }
}

struct AppendToDocumentTool: Tool {
    let name = "appendToDocument"
    let description = "Add text to the very end of the document."
    let doc: DocumentAccess

    @Generable struct Arguments {
        @Guide(description: "The text to append")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        let text = await doc.read()
        await doc.write(text + arguments.text)
        return "Appended text to document."
    }
}

struct PrefixLinesTool: Tool {
    let name = "prefixLines"
    let description = "Add a prefix to every line in the document, or only to lines containing a specific word or phrase. Useful for adding bullet points, numbering, or markers."
    let doc: DocumentAccess

    @Generable struct Arguments {
        @Guide(description: "The prefix to add to each line (e.g. '- ' for bullets)")
        var prefix: String
        @Guide(description: "Only prefix lines containing this text. Leave empty to prefix all lines.")
        var matching: String
    }

    func call(arguments: Arguments) async throws -> String {
        let text = await doc.read()
        let pattern = arguments.matching.isEmpty ? nil : arguments.matching
        let result = TextOperations.prefixLines(in: text, prefix: arguments.prefix, matching: pattern)
        await doc.write(result)
        return "Added prefix to matching lines."
    }
}
```

### Why these tools and not others

Each tool maps to a self-contained operation because the model cannot chain calls. The tool set is designed around what a text editor actually does:

| User intent | Tool | Why self-contained |
|---|---|---|
| "How long is this?" | `getDocumentInfo` | Single read, no follow-up needed |
| "Show me lines 10-20" | `readLines` | Returns a slice without reading everything |
| "Find all TODOs" | `findInDocument` | Returns matches with context |
| "How many TODOs?" | `countPattern` | Just a count, minimal tokens |
| "Change foo to bar everywhere" | `replaceInDocument` | Search + replace in one call |
| "Add a header above line 5" | `insertLine` | Positional insert, no search needed |
| "Bold every TODO" | `wrapMatches` | Search + wrap in one call |
| "Add a title at the top" | `prependToDocument` | Simple, no position needed |
| "Add a footer" | `appendToDocument` | Simple, no position needed |
| "Bullet-point every line" | `prefixLines` | Batch line transform |

**Tools intentionally omitted:**
- **Undo**: The model shouldn't undo. The user presses Cmd+Z. If tool mutations go through the `NSTextView` undo manager (see Phase 3), undo works naturally.
- **Delete line**: Use `replaceInDocument` with an empty replacement, or build it if the pattern comes up.
- **Regex search**: The 3B model struggles with regex construction. Keep searches literal.


## Phase 2: DocumentAgent and session management

```swift
import FoundationModels
import Observation

@Observable
@MainActor
final class DocumentAgent {
    private(set) var lastResponse: String?
    private(set) var isProcessing = false
    var error: Error?

    private let doc: DocumentAccess
    private var session: LanguageModelSession

    init(doc: DocumentAccess) {
        self.doc = doc

        let tools: [any Tool] = [
            GetDocumentInfoTool(doc: doc),
            ReadLinesTool(doc: doc),
            FindInDocumentTool(doc: doc),
            CountPatternTool(doc: doc),
            ReplaceInDocumentTool(doc: doc),
            InsertLineTool(doc: doc),
            WrapMatchesTool(doc: doc),
            PrependToDocumentTool(doc: doc),
            AppendToDocumentTool(doc: doc),
            PrefixLinesTool(doc: doc),
        ]

        let instructions = Instructions {
            "You are a text editing assistant for a plain text document."
            "Use the provided tools to inspect and modify the document."
            "Be concise in your responses."
            "When the user asks you to change the document, make the change and confirm what you did."
            "When the user asks a question about the document, use tools to find the answer."
            "Do not reproduce large amounts of document text in your response — refer to line numbers instead."
        }

        self.session = LanguageModelSession(
            tools: tools,
            instructions: instructions
        )
    }

    func send(_ userMessage: String) async {
        isProcessing = true
        error = nil
        defer { isProcessing = false }

        do {
            let response = try await session.respond(to: userMessage)
            lastResponse = response.content
        } catch let err as LanguageModelSession.GenerationError
            where err == .exceededContextWindowSize {
            // Context full — start fresh session, preserve tool state
            resetSession()
            do {
                let response = try await session.respond(to: userMessage)
                lastResponse = response.content
            } catch {
                self.error = error
            }
        } catch {
            self.error = error
        }
    }

    func prewarm() {
        session.prewarm()
    }

    private func resetSession() {
        // Re-create session with same tools and instructions but empty transcript.
        // DocumentAccess is shared, so the new session still operates on the same document.
        self = DocumentAgent(doc: doc) // or re-initialize session directly
    }
}
```

### Context window budget

With 4,096 tokens total, here's a rough budget:

| Component | Estimated tokens |
|---|---|
| Instructions | ~100 |
| Tool schemas (10 tools) | ~400-600 |
| User message | ~50-100 |
| Tool call arguments | ~30-50 per call |
| Tool results | ~50-200 per call |
| Model response | ~100-300 |
| **Remaining for history** | **~2,500-3,000** |

This means ~5-10 conversational turns before the context fills up. When it does, `DocumentAgent.send` catches the error and resets. The document state is always live in `DocumentAccess`, so nothing is lost.

**Token conservation strategies:**
- `getDocumentInfo` returns one line, not the whole document.
- `readLines` reads a slice, not everything.
- `findInDocument` caps results at 10 matches.
- Instructions are 6 short sentences.
- Tool descriptions are one sentence each.


## Phase 3: UI integration

### The agent field

Add a text field to ContentView where the user types natural-language commands. This is the agent's input.

```swift
struct ContentView: View {
    @Binding var document: LilDocDocument
    // ... existing state ...

    @State private var agentInput: String = ""
    @State private var agent: DocumentAgent?
    @State private var showAgentField = false

    private let model = SystemLanguageModel.default

    var body: some View {
        ZStack {
            PlainTextEditor(...)
                .background(...)

            VStack {
                // Agent response (top, fades out)
                if let response = agent?.lastResponse {
                    agentResponseOverlay(response)
                }

                Spacer()

                HStack {
                    // Agent field (bottom-left, toggled with keyboard shortcut)
                    if showAgentField {
                        agentField
                    }

                    Spacer()

                    // Existing word count (bottom-right)
                    statusText
                }
            }
        }
        .task { setupAgent() }
    }

    @ViewBuilder
    private var agentField: some View {
        HStack(spacing: 8) {
            TextField("Ask something...", text: $agentInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit { sendToAgent() }

            if agent?.isProcessing == true {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(.leading, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: 400)
    }

    private func setupAgent() {
        guard model.availability == .available else { return }
        let access = DocumentAccess(/* bound to document.text */)
        let agent = DocumentAgent(doc: access)
        agent.prewarm()
        self.agent = agent
    }

    private func sendToAgent() {
        let message = agentInput
        agentInput = ""
        Task { await agent?.send(message) }
    }
}
```

### Keyboard shortcut

Add a shortcut (e.g., Cmd+Shift+A or Cmd+J) to toggle the agent field, following the same pattern as the existing Find commands in `LilDocApp.swift`.

### Undo integration

When a tool mutates the document, the change should be undoable via Cmd+Z. To achieve this, `DocumentAccess.write` should apply changes through the `NSTextView`'s undo manager rather than replacing the string directly:

```swift
@MainActor
final class DocumentAccess {
    private weak var textView: NSTextView?

    func write(_ newText: String) {
        guard let textView else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        // This registers with the undo manager automatically
        textView.shouldChangeText(in: fullRange, replacementString: newText)
        textView.replaceCharacters(in: fullRange, with: newText)
        textView.didChangeText()
    }
}
```

Now Cmd+Z undoes agent edits the same way it undoes manual typing. The user doesn't need to know or care whether a human or agent made the change.


## Phase 4: Composed features via instructions

Once the tools exist, "features" are instructions you give the model. No code changes. No builds.

### Approach: per-request instruction injection

Instead of static instructions, prefix the user's message with task-specific instructions when the user invokes a named feature:

```swift
enum AgentFeature: String, CaseIterable {
    case countMarkers = "Count Markers"
    case numberLines = "Number Lines"
    case makeList = "Make List"
    case cleanup = "Clean Up"

    var prompt: String {
        switch self {
        case .countMarkers:
            return """
            Count occurrences of these markers in the document: TODO, FIXME, \
            HACK, NOTE, XXX. Use the countPattern tool for each one. Report the \
            counts.
            """
        case .numberLines:
            return """
            Add line numbers to every line in the document. Use the prefixLines \
            tool. The prefix for each line should be the line number followed by \
            a period and space.
            """
            // Note: this one requires a smarter approach since prefixLines adds
            // the same prefix to all lines. See "Limitations" below.
        case .makeList:
            return """
            Convert the document into a bulleted Markdown list. Use the \
            prefixLines tool with "- " as the prefix.
            """
        case .cleanup:
            return """
            Clean up the document: use replaceInDocument to remove trailing \
            whitespace, double blank lines, and fix inconsistent spacing.
            """
        }
    }
}
```

These features appear as a menu or a palette. Selecting one sends the `prompt` to `DocumentAgent.send`. The model reads the instructions, calls the appropriate tools, and reports back.

### Why this is powerful

Adding a new feature is adding a `case` with a `prompt` string. The tools already exist. The model figures out which ones to call and with what arguments. If the model gets it wrong, you refine the prompt — not the code.

### Limitations of the 3B model

Some composed features need capabilities the on-device model may struggle with:

- **Numbered line prefixes**: Each line needs a _different_ prefix (1., 2., 3...). The `prefixLines` tool adds the _same_ prefix to all lines. Options: (a) add a `numberLines` tool to LilDocKit, (b) have the model call `insertLine` repeatedly (but it can only call tools once per turn), or (c) accept this as a LilDocKit function, not a model-composed feature.
- **Complex multi-step edits**: "Move paragraph 3 to after paragraph 1" requires reading, deleting, and inserting — three sequential steps the model can't chain. Make this a dedicated tool if the pattern is common.
- **Large documents**: A 10,000-word document won't fit in the context. The model must use `readLines` and `findInDocument` to work with slices. The instructions should emphasize this.

**Rule of thumb**: If a feature requires sequential tool calls or reasoning over long text, make it a LilDocKit function exposed as a single tool. If it can be done with one or two parallel tool calls, let the model compose it.


## Tool → UI parity map

| What the user does in the UI | What the agent does via tools |
|---|---|
| Reads the document | `readLines`, `getDocumentInfo` |
| Cmd+F search | `findInDocument` |
| Types text | `replaceInDocument`, `insertLine` |
| Sees word count in status bar | `getDocumentInfo` |
| Cmd+Z undo | Works automatically (undo manager) |
| — | `wrapMatches` (no UI equivalent) |
| — | `prefixLines` (no UI equivalent) |
| — | `countPattern` (no UI equivalent) |
| — | `prependToDocument` / `appendToDocument` |

The last four rows are agent-only operations — batch transforms that would be tedious to do by hand. This is where the agent adds value beyond what the UI offers.


## Implementation sequence

```
Phase 0: LilDocKit extraction
  ├── Create Swift package
  ├── TextAnalysis: wordCount, lineCount, characterCount
  ├── TextSearch: findMatches with line numbers and context
  ├── TextOperations: replace, insertLine, wrapMatches, prefixLines
  ├── Tests for all of the above
  ├── Wire ContentView.wordCount to TextAnalysis.wordCount
  └── Verify app works identically

Phase 1: Tool definitions
  ├── DocumentAccess class (thread-safe document read/write)
  ├── Inspection tools: getDocumentInfo, readLines, findInDocument, countPattern
  ├── Mutation tools: replaceInDocument, insertLine, wrapMatches,
  │   prependToDocument, appendToDocument, prefixLines
  └── Unit tests for each tool (mock DocumentAccess)

Phase 2: DocumentAgent
  ├── LanguageModelSession setup with tools and instructions
  ├── send() with context-overflow recovery
  ├── Prewarm on app launch
  └── Test with hardcoded prompts

Phase 3: UI integration
  ├── Agent text field in ContentView (toggled with keyboard shortcut)
  ├── Response overlay (shows agent's reply, fades)
  ├── Undo integration via NSTextView undo manager
  ├── Availability check (graceful fallback on unsupported hardware)
  └── Keyboard shortcut registration in LilDocApp

Phase 4: Composed features
  ├── AgentFeature enum with prompt templates
  ├── Menu or palette UI for selecting features
  ├── Starter features: count markers, make list, clean up
  └── Iterate on prompts based on model behavior
```


## What this plan does not do

- **Add cloud AI.** Everything runs on-device. No API keys, no network, no cost.
- **Replace the editor.** The text field and editor are still the primary interface. The agent field is a secondary input.
- **Over-abstract.** Each tool is a flat struct. No tool registry pattern, no plugin system, no middleware. Add those if the tool count grows past ~15.
- **Support non-Apple-Silicon Macs.** Foundation Models requires Apple Silicon and macOS 26. On unsupported hardware, the agent field simply doesn't appear.
- **Add dependencies.** Foundation Models is a system framework. LilDocKit is pure Foundation. No third-party packages.


## Open questions for you

1. **Agent field location**: Bottom-left (shown above), or a popover/sheet triggered by a shortcut? The bottom-left keeps the single-window simplicity. A sheet gives more room for showing responses.
2. **Response display**: Inline overlay that fades, or a persistent panel? Short responses (confirmations) work as overlays. Longer responses (analysis) might need more space.
3. **macOS 26 minimum**: This plan requires macOS 26. Is that acceptable, or should the agent features be behind `#available` checks so the app still builds for earlier macOS?
