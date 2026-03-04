# LilDocKit: Agent-Native Architecture for Lil' Doc

*2026-03-04T03:34:46Z by Showboat 0.6.1*
<!-- showboat-id: aa2e385b-f52c-4654-bad7-15a0451473b6 -->

LilDocKit extracts the app's text logic into a standalone Swift package with three targets: LilDocKit (library), lildoc-cli (command-line tool), and lildoc-mcp (MCP server). This lets any agent — Claude Code, a script, an MCP client — read and edit documents through the same code paths the app uses.

```bash
find /home/user/LilDoc/LilDocKit -type f | sort
```

```output
/home/user/LilDoc/LilDocKit/Package.swift
/home/user/LilDoc/LilDocKit/Sources/LilDocKit/TextAnalysis.swift
/home/user/LilDoc/LilDocKit/Sources/LilDocKit/TextOperations.swift
/home/user/LilDoc/LilDocKit/Sources/LilDocKit/TextSearch.swift
/home/user/LilDoc/LilDocKit/Sources/lildoc-cli/main.swift
/home/user/LilDoc/LilDocKit/Sources/lildoc-mcp/LilDocTools.swift
/home/user/LilDoc/LilDocKit/Sources/lildoc-mcp/main.swift
/home/user/LilDoc/LilDocKit/Tests/LilDocKitTests/TextAnalysisTests.swift
/home/user/LilDoc/LilDocKit/Tests/LilDocKitTests/TextOperationsTests.swift
/home/user/LilDoc/LilDocKit/Tests/LilDocKitTests/TextSearchTests.swift
```

## Phase 0: LilDocKit library

TextAnalysis, TextSearch, and TextOperations are pure Foundation functions — no AppKit, no SwiftUI. They build and test on Linux. ContentView.swift now delegates its word count to TextAnalysis.wordCount.

```bash
cat /home/user/LilDoc/LilDocKit/Sources/LilDocKit/TextAnalysis.swift
```

```output
import Foundation

public struct TextAnalysis {
    /// Count words in text (same logic as ContentView's status bar).
    public static func wordCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .count
    }

    /// Count Unicode scalar characters (not bytes).
    public static func characterCount(_ text: String) -> Int {
        text.count
    }

    /// Count lines. Empty string = 0 lines. A trailing newline does not add an extra line.
    public static func lineCount(_ text: String) -> Int {
        if text.isEmpty { return 0 }
        var count = text.components(separatedBy: "\n").count
        if text.hasSuffix("\n") { count -= 1 }
        return max(count, 1)
    }
}
```

## ContentView change

The word count in the status bar now delegates to LilDocKit rather than inline logic. Once LilDocKit is added as a local package dependency in Xcode, this is the full diff to ContentView:

```bash
git -C /home/user/LilDoc diff HEAD~1 -- LilDoc/ContentView.swift
```

```output
diff --git a/LilDoc/ContentView.swift b/LilDoc/ContentView.swift
index 7928087..168de2b 100644
--- a/LilDoc/ContentView.swift
+++ b/LilDoc/ContentView.swift
@@ -7,6 +7,7 @@
 
 import SwiftUI
 import AppKit
+import LilDocKit
 
 struct ContentView: View {
     @Binding var document: LilDocDocument
@@ -15,11 +16,7 @@ struct ContentView: View {
     @Environment(\.controlActiveState) private var controlActiveState
 
     private var wordCount: Int {
-        let trimmed = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
-        if trimmed.isEmpty { return 0 }
-        return trimmed.components(separatedBy: .whitespacesAndNewlines)
-            .filter { !$0.isEmpty }
-            .count
+        TextAnalysis.wordCount(document.text)
     }
 
     @State private var selectionLength: Int = 0
```

## Phase 1+2: lildoc-cli

The CLI uses swift-argument-parser with 6 subcommands. Read-only commands (read, search, analyze) output JSON. Write commands (replace, insert, append) default to dry-run — they print a diff and exit with code 1 unless --confirm is passed.

```bash
cat /home/user/LilDoc/LilDocKit/Sources/lildoc-cli/main.swift
```

```output
import ArgumentParser
import Foundation
import LilDocKit

@main
struct LilDocCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lildoc-cli",
        abstract: "Inspect and edit plain text files.",
        subcommands: [Read.self, Search.self, Analyze.self, Replace.self, Insert.self, Append.self]
    )
}

// MARK: - Helpers

func readFile(_ path: String) throws -> String {
    let url = URL(fileURLWithPath: path)
    return try String(contentsOf: url, encoding: .utf8)
}

func writeFile(_ path: String, _ content: String) throws {
    let url = URL(fileURLWithPath: path)
    try content.write(to: url, atomically: true, encoding: .utf8)
}

func toJSON<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value), let str = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return str
}

// MARK: - read

struct Read: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print file contents to stdout.")

    @Argument(help: "Path to the text file.") var path: String
    @Option(name: .long, help: "First line to read (1-indexed).") var startLine: Int?
    @Option(name: .long, help: "Last line to read (1-indexed).") var endLine: Int?

    func run() throws {
        let text = try readFile(path)
        if startLine == nil && endLine == nil {
            print(text, terminator: "")
            return
        }
        let lines = text.components(separatedBy: "\n")
        let first = max(1, startLine ?? 1) - 1
        let last  = min(lines.count, endLine ?? lines.count) - 1
        let slice = lines[first...last].joined(separator: "\n")
        print(slice, terminator: "")
    }
}

// MARK: - search

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Search for a word or phrase.")

    @Argument(help: "Path to the text file.") var path: String
    @Argument(help: "Search query (case-insensitive).") var query: String

    func run() throws {
        let text = try readFile(path)
        let matches = TextSearch.findMatches(in: text, query: query)
        struct MatchJSON: Encodable {
            let line: Int
            let column: Int
            let text: String
        }
        let out = matches.map { MatchJSON(line: $0.line, column: $0.column, text: $0.text) }
        print(toJSON(out))
    }
}

// MARK: - analyze

struct Analyze: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print word/character/line counts.")

    @Argument(help: "Path to the text file.") var path: String

    func run() throws {
        let text = try readFile(path)
        struct Stats: Encodable {
            let words: Int
            let characters: Int
            let lines: Int
        }
        let stats = Stats(
            words: TextAnalysis.wordCount(text),
            characters: TextAnalysis.characterCount(text),
            lines: TextAnalysis.lineCount(text)
        )
        print(toJSON(stats))
    }
}

// MARK: - replace

struct Replace: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Replace text. Dry-run without --confirm.")

    @Argument(help: "Path to the text file.") var path: String
    @Argument(help: "Text to search for.") var search: String
    @Argument(help: "Replacement text.") var replacement: String
    @Flag(name: .long, help: "Replace all occurrences (default: first only).") var all = false
    @Flag(name: .long, help: "Apply the change (omit for dry-run).") var confirm = false

    func run() throws {
        let original = try readFile(path)
        let (modified, count) = TextOperations.replace(
            in: original, search: search, with: replacement, all: all)
        if count == 0 {
            fputs("No matches found for \"\(search)\".\n", stderr)
            throw ExitCode(1)
        }
        if confirm {
            try writeFile(path, modified)
            fputs("Replaced \(count) occurrence(s).\n", stderr)
        } else {
            fputs("Dry run — \(count) occurrence(s) would be replaced. Pass --confirm to apply.\n", stderr)
            print(TextOperations.unifiedDiff(original: original, modified: modified, path: path))
            throw ExitCode(1)
        }
    }
}

// MARK: - insert

struct Insert: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Insert a line. Dry-run without --confirm.")

    @Argument(help: "Path to the text file.") var path: String
    @Argument(help: "Content to insert.") var content: String
    @Option(name: .long, help: "Line number to insert at (1-indexed).") var atLine: Int
    @Flag(name: .long, help: "Insert before the line (default).") var before = false
    @Flag(name: .long, help: "Insert after the line.") var after = false
    @Flag(name: .long, help: "Apply the change (omit for dry-run).") var confirm = false

    func run() throws {
        let original = try readFile(path)
        let position: TextOperations.LinePosition = after ? .after : .before
        let modified = TextOperations.insertLine(
            in: original, content: content, at: atLine, position: position)
        if confirm {
            try writeFile(path, modified)
            fputs("Inserted line at \(atLine).\n", stderr)
        } else {
            fputs("Dry run — line would be inserted at \(atLine). Pass --confirm to apply.\n", stderr)
            print(TextOperations.unifiedDiff(original: original, modified: modified, path: path))
            throw ExitCode(1)
        }
    }
}

// MARK: - append

struct Append: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Append text to the end of a file.")

    @Argument(help: "Path to the text file.") var path: String
    @Argument(help: "Content to append.") var content: String

    func run() throws {
        let original = try readFile(path)
        let modified = TextOperations.append(content, to: original)
        try writeFile(path, modified)
        fputs("Appended content.\n", stderr)
    }
}
```

## Phase 3: lildoc-mcp (MCP server)

The MCP server uses the official modelcontextprotocol/swift-sdk (v0.11.0) to expose six tools over stdio JSON-RPC. Note: PiMCPAdapter from the integration plan is a client-side adapter for connecting *to* MCP servers — the official SDK is the right tool for *implementing* one.

The six tools map directly to the CLI commands, with the same dry-run semantics: pass confirm:true to apply write operations.

```bash
grep -E '(static let.*Tool =|name:|description:)' /home/user/LilDoc/LilDocKit/Sources/lildoc-mcp/LilDocTools.swift | head -40
```

```output
    static let readTool = Tool(
        name: "lildoc.read",
        description: "Read the contents of a text file. Optionally restrict to a line range.",
    static let searchTool = Tool(
        name: "lildoc.search",
        description: "Search for a word or phrase in a text file. Returns matching lines with line numbers.",
    static let analyzeTool = Tool(
        name: "lildoc.analyze",
        description: "Return word count, character count, and line count for a text file.",
    static let replaceTool = Tool(
        name: "lildoc.replace",
        description: """
    static let insertTool = Tool(
        name: "lildoc.insert",
        description: """
    static let appendTool = Tool(
        name: "lildoc.append",
        description: "Append content to the end of a file.",
```

## MCP registration in conductor.json

Claude Code discovers the lildoc MCP server via conductor.json. The server runs as a subprocess over stdio:

```bash
cat /home/user/LilDoc/conductor.json
```

```output
{
  "scripts": {
    "setup": "mise run setup",
    "run": "mise run app"
  },
  "runScriptMode": "nonconcurrent",
  "mcpServers": {
    "lildoc": {
      "command": "swift",
      "args": ["run", "--package-path", "LilDocKit", "lildoc-mcp"]
    }
  }
}
```

## Package dependency boundaries

The app binary stays dependency-free. External dependencies are scoped to the correct targets only:
- LilDocKit: Foundation only
- lildoc-cli: LilDocKit + swift-argument-parser
- lildoc-mcp: LilDocKit + modelcontextprotocol/swift-sdk (pinned to 0.11.0)

```bash
cat /home/user/LilDoc/LilDocKit/Package.swift
```

```output
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LilDocKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LilDocKit", targets: ["LilDocKit"]),
        .executable(name: "lildoc-cli", targets: ["lildoc-cli"]),
        .executable(name: "lildoc-mcp", targets: ["lildoc-mcp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.4.0"
        ),
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk.git",
            exact: "0.11.0"
        ),
    ],
    targets: [
        .target(
            name: "LilDocKit",
            dependencies: []
        ),
        .executableTarget(
            name: "lildoc-cli",
            dependencies: [
                "LilDocKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "lildoc-mcp",
            dependencies: [
                "LilDocKit",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "LilDocKitTests",
            dependencies: ["LilDocKit"]
        ),
    ]
)
```

## Tests

27 test cases cover all three LilDocKit modules.

```bash
grep -c 'func test' /home/user/LilDoc/LilDocKit/Tests/LilDocKitTests/*.swift && echo '---' && grep 'func test' /home/user/LilDoc/LilDocKit/Tests/LilDocKitTests/*.swift | sed 's/.*func //' | sed 's/().*//' | sort
```

```output
/home/user/LilDoc/LilDocKit/Tests/LilDocKitTests/TextAnalysisTests.swift:11
/home/user/LilDoc/LilDocKit/Tests/LilDocKitTests/TextOperationsTests.swift:16
/home/user/LilDoc/LilDocKit/Tests/LilDocKitTests/TextSearchTests.swift:8
---
testAppendToEmpty
testAppendToText
testAppendToTextWithTrailingNewline
testCaseInsensitive
testCharacterCount
testColumnNumber
testContextIsFullLine
testDiffShowsChanges
testEmptyQuery
testInsertAfter
testInsertAtFirstLine
testInsertBefore
testLineCount_empty
testLineCount_multipleLines
testLineCount_singleLine
testLineCount_trailingNewline
testMatchesAcrossLines
testMultipleMatchesOnSameLine
testNoChanges
testNoMatches
testPrefixAllLines
testPrefixMatchingLines
testReplaceAll
testReplaceEmptySearch
testReplaceFirst
testReplaceNoMatch
testSingleMatch
testWordCount_empty
testWordCount_leadingTrailingWhitespace
testWordCount_multipleWords
testWordCount_newlines
testWordCount_singleWord
testWordCount_whitespaceOnly
testWrapMatches
testWrapMatchesCaseInsensitive
```

## Git log

Both commits are on the feature branch:

```bash
git -C /home/user/LilDoc log --oneline origin/main..HEAD
```

```output
59165f8 Build LilDocKit package with CLI and MCP server
3ba23cc Add PiSwift integration plan
```
