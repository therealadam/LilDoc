# PiSwift Integration Plan for Lil' Doc

This plan evaluates PiSwift (https://github.com/xibbon/PiSwift) as a component of LilDoc's agent-native architecture and recommends how to integrate it alongside the existing MCP/CLI and on-device agent plans.

The short version: use **PiMCPAdapter only**, in the `lildoc-mcp` executable target only. The app binary stays dependency-free. The on-device agent plan is unchanged and does not use PiSwift.

## Module Assessment

PiSwift has eight modules. Most are not a fit for LilDoc.

**PiMCPAdapter — adopt (lildoc-mcp target only)**

Ready-made MCP stdio transport with JSON-RPC. This is the direct answer to Phase 3 of the agent-native plan's "evaluate Swift MCP SDK or roll stdio transport." `McpServer` handles the JSON-RPC loop; you register tools instead of writing a dispatcher. The only dependency it adds is `swift-argument-parser`, scoped to the executable target.

**PiSwiftAI — skip**

Abstracts Anthropic, OpenAI, Gemini, Bedrock, Azure behind one interface. Pulls in `OpenAI` and `SwiftAnthropic` packages. Requires API keys. Conflicts directly with the design brief's "Zero external dependencies. System frameworks only." of no value for on-device privacy use cases.

**PiSwiftAgent — skip**

Single/Parallel/Chain agent execution. Depends on PiSwiftAI, which pulls cloud dependencies. Targets cloud providers, not Apple Foundation Models. LilDoc's in-app agent layer is `LanguageModelSession` — already async, already working in the playground. There is nothing complex enough here to need abstracting.

**PiExtensionSDK — skip (premature)**

User-editable Swift extensions in `~/.pi/agents/`. Assumes a richer UI than LilDoc's single text window. The design brief explicitly opposes panels and toolbars. The Phase 5 "features as prompts" concept in the agent-native plan maps to this, but LilDoc's version is simpler: plain Markdown templates in `prompts/`, not user-installable Swift extensions.

**PiSwiftCodingAgent — skip**

Specialized coding workflows. Out of scope for a text editor.

## Architecture: Hard Dependency Boundary

The key structural decision is where PiSwift's dependency lives:

```
LilDoc.app  (no external deps — system frameworks only)
  ContentView → AgentField (#available macOS 26 guard)
  DocumentAgent → LanguageModelSession + Tool conformances
  DocumentAccess → NSTextView undo manager
       │
       ▼ imports
LilDocKit/Sources/LilDocKit/   (Foundation only, no external deps)
  TextAnalysis.swift
  TextSearch.swift
  TextOperations.swift
       │
       ├── LilDocKit/Sources/lildoc-cli/  (LilDocKit, optional ArgumentParser)
       │
       └── LilDocKit/Sources/lildoc-mcp/ (LilDocKit + PiMCPAdapter ← only here)
```

PiSwift is a dependency of `lildoc-mcp` only. The `LilDocKit` library target and the app target have no knowledge of PiSwift. If PiMCPAdapter's API changes, only `main.swift` and `LilDocMcpServer.swift` need to update — not LilDocKit and not the app.

## How PiSwift Fits the Existing Plans

### Agent-Native / MCP Plan — Phase 3 replacement

The agent-native plan says for Phase 3: "Evaluate Swift MCP SDK or roll stdio transport." PiMCPAdapter resolves this. The six tools defined in that plan (`lildoc.read`, `lildoc.search`, `lildoc.analyze`, `lildoc.replace`, `lildoc.insert`, `lildoc.append`) become PiMCPAdapter tool registrations backed by LilDocKit functions. The `--confirm` / dry-run pattern is implemented inside each tool's handler, not by PiMCPAdapter itself.

The CLI tool (Phases 1–2) is unaffected. It stays a standalone executable using either `CommandLine.arguments` or `swift-argument-parser` (since that package is pulled in by `lildoc-mcp` anyway, sharing the dependency is free once Phase 3 is done).

### On-Device Plan — unchanged

The on-device plan does not use PiSwift at all. The `LanguageModelSession` + `Tool` conformances from the playground are the correct approach. Foundation Models' `Tool` protocol uses `@Generable`, a macro that requires Apple's Swift compiler and the macOS 26 SDK — it cannot be compiled on Linux and cannot be bridged to PiSwiftAI's cloud backends. These tool structs must stay in the app target.

### Why not share tool definitions between layers?

There is no code sharing between the Foundation Models tools (app target, `@Generable`) and the MCP tools (`lildoc-mcp`, JSON-RPC). They serve different interfaces with different argument shapes and return types. The duplication is intentional and correct.

## Tool Protocol Comparison

For reference, the structural difference between Foundation Models tools and PiSwift's AgentTool concept:

| Foundation Models `Tool` | PiSwift AgentTool | Notes |
|---|---|---|
| `struct GetInfoTool: Tool` | Tool registration with name + description + handler | Same structure, different protocol |
| `@Generable struct Arguments` | Codable JSON for arguments | Foundation Models uses macro-generated structured output; PiSwift uses JSON decoding |
| `call(arguments:) async throws -> String` | Handler closure returning String | Identical return type and async pattern |
| `@Guide(description:)` on arguments | JSON Schema field descriptions | Foundation Models uses macros; PiSwift uses JSON Schema annotations |

The Foundation Models tools in the playground (`GetInfoTool`, `FindTool`, `CountPatternTool`) are the prototypes for the app-layer tools in the on-device plan. They do not transfer to the MCP layer.

## Phased Implementation

Phases 0–2 and 4–5 are identical to the agent-native and on-device plans. Only Phase 3 changes.

### Phase 0: Extract LilDocKit (prerequisite, unchanged)

Pull pure logic out of `ContentView.swift` into a new Swift package.

- `LilDocKit/Sources/LilDocKit/TextAnalysis.swift` — `wordCount`, `characterCount`, `lineCount`
- `LilDocKit/Sources/LilDocKit/TextSearch.swift` — `findMatches(in:query:) -> [Match]` with line numbers
- `LilDocKit/Sources/LilDocKit/TextOperations.swift` — `replace`, `insertLine`, `wrapMatches`, `prefixLines`, `append`

Use the richer `TextOperations` from the on-device plan (self-contained operations rather than index-returning variants) since they serve both layers.

Verification: `swift test` passes on LilDocKit. App builds and status bar word count is unchanged.

### Phase 1: CLI Tool — read-only (no PiSwift)

Add `lildoc-cli` executable target with `read`, `search`, `analyze` subcommands. JSON output. No external deps at this stage.

Verification: `lildoc-cli analyze sample.txt` output matches the app's status bar count.

### Phase 2: CLI Write Commands (no PiSwift)

Add `replace`, `replace-all`, `insert`, `append` with `--confirm` / dry-run pattern. Add `swift-argument-parser` as a dependency of `lildoc-cli` if four+ commands with flags justify it.

Verification: dry-run shows unified diff; `--confirm` modifies file; app reflects change via file coordination.

### Phase 3: MCP Server with PiMCPAdapter

Add `lildoc-mcp` executable target to `LilDocKit/Package.swift`:

```swift
.executableTarget(
    name: "lildoc-mcp",
    dependencies: [
        "LilDocKit",
        .product(name: "PiMCPAdapter", package: "PiSwift"),
    ]
)
```

Implement `LilDocMcpServer.swift` using `McpServer`. Register the six tools from the agent-native plan. Each handler calls LilDocKit functions. The `confirm` parameter (diff vs. write) is handled in the handler.

Update `conductor.json` (currently empty) with MCP registration:

```json
{
  "mcpServers": {
    "lildoc": {
      "command": "swift",
      "args": ["run", "--package-path", "LilDocKit", "lildoc-mcp"]
    }
  }
}
```

**Risk:** Pin PiSwift to an exact version. Sub-1.0 Swift packages can have breaking API changes on minor bumps. If PiMCPAdapter's API changes, only `main.swift` and `LilDocMcpServer.swift` need updating.

Verification: `lildoc.analyze` result matches `lildoc-cli analyze`. `lildoc.replace` with `confirm: false` returns a diff; with `confirm: true` writes the file.

### Phase 4: On-Device Agent in App (no PiSwift — deferred)

Implement per the on-device plan. Gate with `#available(macOS 26, *)`. The playground tools (`GetInfoTool`, `FindTool`, `CountPatternTool`) are prototypes for the ten production tool structs in `DocumentTools.swift`.

This phase is independent of PiSwift and can proceed in parallel with or after Phase 3.

### Phase 5: Context.md Convention and Prompt Templates (no code)

Store 2–3 Markdown prompt templates in `prompts/` at the project root. Document the `Context.md` convention in `humans.md`. The templates are compatible with PiSwift's Markdown agent definition format (YAML frontmatter) and can be reformatted if that ecosystem becomes standard.

## Tradeoffs

| Dimension | On-Device (Apple FM) | MCP Layer (PiMCPAdapter) |
|---|---|---|
| External dependencies | None | `swift-argument-parser` via PiMCPAdapter |
| API cost | Free (on-device) | None for server; agent client pays |
| macOS version | macOS 26+, Apple Silicon | macOS 15+ |
| Privacy | Data stays on device | Data goes to external MCP client |
| Complexity in app target | DocumentAgent + tools | None |
| Complexity in package | None | lildoc-mcp target + PiMCPAdapter dep |
| Reversibility | High | High (isolated to lildoc-mcp target) |

## End-to-End Verification

1. `swift build --package-path LilDocKit` builds all three targets
2. `swift test --package-path LilDocKit` passes all TextAnalysis, TextSearch, TextOperations tests
3. `lildoc-cli analyze <file>` output matches app status bar word count
4. Claude Code discovers `lildoc` MCP server via `conductor.json` and calls `lildoc.analyze`
5. On Apple Silicon + macOS 26: Cmd+Shift+A opens agent field; natural language queries work
6. On Intel / macOS 15: app opens normally, no agent field, no errors
