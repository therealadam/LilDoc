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
