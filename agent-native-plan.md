# Agent-Native Architecture Plan for Lil' Doc

This plan describes how to adopt agent-native architectural ideas in Lil' Doc: a ~270-line macOS plain text editor built with SwiftUI, zero dependencies, file-based documents.

The goal is not to bolt AI features onto an editor. It's to restructure the app so that an agent (Claude Code, an MCP client, a script) can do everything the UI can do, through the same code paths, with the file system as the shared interface.

## Principles applied to this app

Not all seven agent-native ideas apply equally to a 270-line text editor. Here's what fits and what doesn't.

**Strong fit:**

- **Parity (UI ↔ tools)**: The core operations—read text, write text, search text, get word count—should be callable both from the UI and from an external tool, through the same logic. Today they're tangled into the view layer.
- **Granular primitives**: The app's operations are already small. But they need to be extractable: read a document's text, replace a range, find matches, count words. These become the building blocks for both the UI and agent tooling.
- **Files as interface**: The app already reads and writes plain text files. This is the natural coordination point. An agent writes to a file; the app picks it up. No IPC protocol needed for basic operations.
- **Layered permissions**: An agent should be able to read freely, but writing should require either user approval or explicit opt-in. The phased rollout below implements this.

**Moderate fit:**

- **Features as prompts**: Some "features" (e.g., summarize document, suggest a title, reformat paragraph) could be defined as prompt templates rather than code. This makes sense as a later phase once the primitive layer exists.
- **Discovery flywheel**: As agents use the primitives, patterns emerge (common searches, frequent edits) that inform what to build next. This is a practice, not a feature.

**Weak fit (skip for now):**

- **Emergent capability**: With only a handful of primitives, combinatorial explosion isn't the design challenge. This matters more for apps with dozens of operations.


## Phase 0: Extract LilDocKit

**What**: Pull pure logic out of ContentView.swift into a separate Swift package that builds and tests on Linux.

**Why**: This is the prerequisite for everything else. Today, word counting and cursor logic live inside SwiftUI views. You can't call them from a CLI tool, a test, or an MCP server. Extraction creates the primitive layer that both UI and agents consume.

**What moves into LilDocKit:**

```
LilDocKit/
  Sources/LilDocKit/
    TextAnalysis.swift      # Word count, character count, line count
    TextSearch.swift         # Find matches (word-boundary, case-insensitive)
    TextOperations.swift     # Replace range, insert at position
  Tests/LilDocKitTests/
    TextAnalysisTests.swift
    TextSearchTests.swift
    TextOperationsTests.swift
```

**Concrete extractions:**

1. **Word count** — currently a computed property on ContentView (lines 17-23). Extract to:
   ```swift
   // LilDocKit/TextAnalysis.swift
   public struct TextAnalysis {
       public static func wordCount(_ text: String) -> Int
       public static func characterCount(_ text: String) -> Int
       public static func lineCount(_ text: String) -> Int
   }
   ```

2. **Search** — the app previously had word-boundary search in `applyHighlighting`. The current version delegates to the native Find bar, but the agent needs programmatic search. Extract/recreate:
   ```swift
   // LilDocKit/TextSearch.swift
   public struct TextSearch {
       public struct Match {
           public let range: Range<String.Index>
           public let text: String
       }
       public static func findMatches(in text: String, query: String) -> [Match]
   }
   ```

3. **Text operations** — replace, insert, delete by range:
   ```swift
   // LilDocKit/TextOperations.swift
   public struct TextOperations {
       public static func replace(in text: String, range: Range<String.Index>, with replacement: String) -> String
       public static func insert(into text: String, at position: String.Index, content: String) -> String
   }
   ```

**What stays in the app target**: Everything that touches pixels—`NSViewRepresentable`, SwiftUI views, `FileDocument`, the `@main` entry point, `configureAppearance`, the Coordinator. The app imports LilDocKit and calls into it.

**How ContentView changes:**

```swift
// Before (in ContentView)
private var wordCount: Int {
    let trimmed = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return 0 }
    return trimmed.components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .count
}

// After
private var wordCount: Int {
    TextAnalysis.wordCount(document.text)
}
```

**Verification**: `swift build` and `swift test` pass on the LilDocKit package. The app builds and behaves identically. Word count shows the same numbers. Find bar still works.

**Design constraint**: LilDocKit depends only on Foundation. No AppKit, no SwiftUI, no Combine.


## Phase 1: CLI tool (read-only agent interface)

**What**: A small command-line tool, `lildoc-cli`, that uses LilDocKit to inspect plain text files.

**Why**: This is the simplest possible agent interface. Claude Code (or any tool) can shell out to `lildoc-cli` to read and analyze documents without touching the running app. Files are the interface. The CLI reads what the app writes; the app reads what the CLI writes.

**Structure:**

```
LilDocKit/
  Sources/
    LilDocKit/          # (from Phase 0)
    lildoc-cli/
      main.swift        # CLI entry point
      Commands/
        ReadCommand.swift
        SearchCommand.swift
        AnalyzeCommand.swift
```

**Commands:**

```
lildoc-cli read <file>
  Outputs the file contents to stdout. Trivial, but establishes the pattern.

lildoc-cli search <file> <query>
  Finds word-boundary matches using TextSearch.findMatches.
  Outputs matches as JSON: [{"line": 5, "column": 12, "text": "the match"}]

lildoc-cli analyze <file>
  Outputs analysis as JSON: {"words": 342, "characters": 1847, "lines": 28}

lildoc-cli read <file> --range <start>:<end>
  Outputs a substring by character offset.
```

**Output format**: JSON by default. This is what agents parse well. Add `--plain` flag for human-readable output.

**No dependency on ArgumentParser** unless you want it. A simple `CommandLine.arguments` switch is fine for four commands.

**Parity check**: Every read-only operation available in the UI is now available via CLI:
| UI action | CLI equivalent |
|---|---|
| Open and read a file | `lildoc-cli read <file>` |
| See word count in status bar | `lildoc-cli analyze <file>` |
| Cmd+F search | `lildoc-cli search <file> <query>` |

**Verification**: Run the CLI against a sample text file. JSON output parses correctly. Search results match what the app's Find bar finds.


## Phase 2: Write operations (with guardrails)

**What**: Add write commands to the CLI, gated behind explicit flags.

**Why**: An agent that can only read is limited. But an agent that silently mutates your documents is dangerous. This phase adds writes with friction.

**New commands:**

```
lildoc-cli replace <file> <search> <replacement> --confirm
  Replaces the first match. Prints the diff to stderr, writes only if --confirm is present.
  Without --confirm, it's a dry run.

lildoc-cli replace-all <file> <search> <replacement> --confirm
  Replaces all matches. Same dry-run behavior.

lildoc-cli insert <file> --at <offset> --text <content> --confirm
  Inserts text at a character offset.

lildoc-cli append <file> --text <content>
  Appends to end of file. No --confirm needed (append is low-risk).
```

**The `--confirm` pattern**: Every destructive operation defaults to dry-run. Without `--confirm`, the CLI prints what it would do (as a unified diff) and exits with code 1. This is the "layered permissions" principle in practice. An agent can propose changes; a human (or a wrapper script) decides whether to apply them.

**Parity check update:**
| UI action | CLI equivalent |
|---|---|
| Type in the editor | `lildoc-cli insert` / `lildoc-cli replace` |
| Cmd+Z undo | Not supported (agents should use version control instead) |
| Save | Implicit in write commands (they write to the file) |

**File watching (optional, defer if complex)**: The macOS app already responds to file changes on disk via `FileDocument`. If the CLI writes to a file that's open in the app, the app should notice. Test whether this works out of the box with `FileDocument`'s built-in file coordination. If it does, you get live agent-to-app feedback for free.

**Verification**: `lildoc-cli replace test.txt "old" "new"` shows a diff. `lildoc-cli replace test.txt "old" "new" --confirm` modifies the file. The app picks up the change if the file is open.


## Phase 3: MCP server

**What**: Wrap the LilDocKit primitives as an MCP (Model Context Protocol) server so Claude Code and other MCP clients can call them as tools.

**Why**: The CLI works, but MCP is the native protocol for agent-tool communication. An MCP server lets Claude Code discover and call Lil' Doc operations without shelling out. It also enables richer interaction: the agent gets structured responses, tool descriptions, and can compose operations.

**Implementation approach**: Use the [Swift MCP SDK](https://github.com/modelcontextprotocol/swift-sdk) (if mature enough) or implement the JSON-RPC stdio transport directly. MCP-over-stdio is simple: read JSON-RPC from stdin, write JSON-RPC to stdout.

**Tools to expose:**

```
lildoc.read
  params: { path: string, range?: { start: number, end: number } }
  returns: { text: string }

lildoc.search
  params: { path: string, query: string }
  returns: { matches: [{ line: number, column: number, text: string }] }

lildoc.analyze
  params: { path: string }
  returns: { words: number, characters: number, lines: number }

lildoc.replace
  params: { path: string, search: string, replacement: string, all?: boolean, confirm?: boolean }
  returns: { diff: string, applied: boolean }

lildoc.insert
  params: { path: string, offset: number, text: string, confirm?: boolean }
  returns: { diff: string, applied: boolean }

lildoc.append
  params: { path: string, text: string }
  returns: { success: boolean }
```

**Same guardrails**: The `confirm` parameter works the same as the CLI flag. Default is dry-run. The MCP client (Claude Code) can present the diff to the user and re-call with `confirm: true`.

**Registration**: Add an `mcp.json` or instructions in `humans.md` so Claude Code can discover the server:
```json
{
  "mcpServers": {
    "lildoc": {
      "command": "swift",
      "args": ["run", "--package-path", "/path/to/LilDocKit", "lildoc-mcp"]
    }
  }
}
```

**Parity is now complete**: Every operation the UI supports, the MCP server supports, through the same LilDocKit code paths.


## Phase 4: Context.md — working memory as a file

**What**: Establish a convention where a `Context.md` file in the same directory as a document serves as working memory for agents.

**Why**: An agent working on a document needs scratch space: what it's found so far, what it plans to do, notes about structure. Rather than inventing a database or state protocol, use a file. The user can read it. The agent can read and write it. The app could optionally display it.

**Format:**

```markdown
# Context: my-document.txt

## Summary
Brief description of the document's content and structure.

## Recent operations
- Searched for "deadline" — 3 matches found (lines 12, 45, 89)
- Word count: 1,247

## Notes
- Document appears to be meeting notes from Q1 planning
- Key topics: budget, hiring, product roadmap
```

**Convention, not enforcement**: The agent creates `Context.md` alongside the document it's working on. The app doesn't need to know about it initially. Later, you could show a sidebar or overlay with context info, but that's optional.

**Agent instructions**: Add to `humans.md` or a prompt template:
> When working on a document, maintain a `Context.md` file alongside it. Update it with your findings, analysis, and planned operations. Read it at the start of each session to restore context.

**This is "features as prompts"**: The Context.md convention isn't implemented in code. It's a behavior defined by instructions. If you later want structured context (e.g., always include word count, always include last search), you define that in the prompt, not in the app.


## Phase 5: Prompt templates (features as prompts)

**What**: Define a small set of prompt templates that combine Lil' Doc primitives into useful workflows.

**Why**: Once agents can read, search, write, and maintain context, you can define "features" as instructions rather than code. A summarize feature is a prompt that reads the document and writes a summary to Context.md. A cleanup feature is a prompt that searches for patterns and proposes replacements.

**Templates (stored in a `prompts/` directory):**

```
prompts/
  summarize.md      # Read the document, write a summary to Context.md
  find-todos.md     # Search for TODO/FIXME patterns, list them
  word-frequency.md # Analyze word usage, report repetition
  proofread.md      # Read the document, suggest corrections via replace dry-runs
```

**Example — `prompts/summarize.md`:**

```markdown
# Summarize Document

Read the document at {{path}} using lildoc.read.
Analyze it using lildoc.analyze to get basic statistics.
Write a summary to Context.md (alongside the document) using lildoc.append.

Include:
- A 2-3 sentence summary of the content
- Word count and line count
- Key topics or themes you notice
```

**These are not code**: They're Markdown files containing instructions. An agent (Claude Code) reads them and follows them, using the MCP tools from Phase 3. The "feature" exists entirely as a prompt + primitive tools.

**Adding a new feature**: Write a new `.md` file in `prompts/`. No code changes. No build. This is the lightest possible feature development.


## UI ↔ Agent parity map (complete)

After all phases, here is the full mapping:

| What the user does in the UI | What the agent does via tools | Shared code path |
|---|---|---|
| Opens a file, reads text | `lildoc.read` / `lildoc-cli read` | `FileDocument` / direct file I/O |
| Sees word count in status bar | `lildoc.analyze` / `lildoc-cli analyze` | `TextAnalysis.wordCount` |
| Cmd+F search | `lildoc.search` / `lildoc-cli search` | `TextSearch.findMatches` |
| Types in the editor | `lildoc.replace` / `lildoc.insert` | `TextOperations.*` |
| Saves the document | Write commands flush to disk | File system |
| Reviews a change before applying | N/A (direct in UI) | `--confirm` / dry-run pattern |
| — | Maintains working memory | Context.md convention |
| — | Runs composite workflows | Prompt templates |

The last two rows are agent-only capabilities. That's fine — parity means the agent can do everything the UI can, not that the UI must do everything the agent can. Agents have their own strengths (batch operations, analysis, persistence across sessions).


## Implementation sequence

```
Phase 0: LilDocKit extraction
  ├── Create Swift package structure
  ├── Extract TextAnalysis (word count)
  ├── Write TextSearch (find matches)
  ├── Write TextOperations (replace, insert)
  ├── Tests for all of the above
  ├── Wire app to use LilDocKit
  └── Verify app behavior unchanged

Phase 1: CLI (read-only)
  ├── Create lildoc-cli executable target
  ├── Implement read, search, analyze commands
  ├── JSON output format
  └── Test against sample files

Phase 2: CLI (write operations)
  ├── Add replace, insert, append commands
  ├── Implement --confirm / dry-run pattern
  ├── Diff output for proposed changes
  └── Test file-watching with the app

Phase 3: MCP server
  ├── Evaluate Swift MCP SDK or roll stdio transport
  ├── Expose all primitives as MCP tools
  ├── Same confirm/dry-run guardrails
  ├── Registration config for Claude Code
  └── Test end-to-end with Claude Code

Phase 4: Context.md convention
  ├── Document the convention in humans.md
  ├── Create example Context.md
  └── (Optional) Show context in app sidebar

Phase 5: Prompt templates
  ├── Write 2-3 starter templates
  ├── Document how to add new ones
  └── Test with Claude Code
```

Each phase is independently useful. You can stop after Phase 0 and have a better-structured app with tests. You can stop after Phase 1 and have a CLI that agents can shell out to. Each subsequent phase adds capability without requiring the next.


## What this plan does not do

- **Add AI features to the editor UI** (e.g., inline suggestions, chat sidebar). The app stays minimal. Agent interaction happens through tools and files, not through the app's interface.
- **Add dependencies** beyond what's necessary. LilDocKit is pure Foundation. The CLI uses only standard library argument parsing unless you opt into ArgumentParser. The MCP server is the only place where an external dependency (Swift MCP SDK) might be warranted.
- **Change the user experience of the editor**. It still opens files, you type, you search, you save. The agent-native architecture lives alongside the app, not inside it.
- **Over-abstract for hypothetical futures**. Each primitive does one thing. If a new operation is needed, add it then.
