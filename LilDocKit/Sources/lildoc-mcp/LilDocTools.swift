import Foundation
import MCP
import LilDocKit

// MARK: - Tool definitions and dispatch

enum LilDocTools {
    // MARK: Tool names — single source of truth referenced by both schema and dispatch
    enum ToolName {
        static let read    = "lildoc.read"
        static let search  = "lildoc.search"
        static let analyze = "lildoc.analyze"
        static let replace = "lildoc.replace"
        static let insert  = "lildoc.insert"
        static let append  = "lildoc.append"
    }

    static let all: [Tool] = [readTool, searchTool, analyzeTool, replaceTool, insertTool, appendTool]

    // MARK: Tool schemas

    static let readTool = Tool(
        name: ToolName.read,
        description: "Read the contents of a text file. Optionally restrict to a line range.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string"), "description": .string("Absolute or relative path to the file.")]),
                "startLine": .object(["type": .string("integer"), "description": .string("First line to read (1-indexed, optional).")]),
                "endLine": .object(["type": .string("integer"), "description": .string("Last line to read (1-indexed, optional).")])
            ]),
            "required": .array([.string("path")])
        ])
    )

    static let searchTool = Tool(
        name: ToolName.search,
        description: "Search for a word or phrase in a text file. Returns matching lines with line numbers.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string"), "description": .string("Path to the file.")]),
                "query": .object(["type": .string("string"), "description": .string("Text to search for (case-insensitive).")])
            ]),
            "required": .array([.string("path"), .string("query")])
        ])
    )

    static let analyzeTool = Tool(
        name: ToolName.analyze,
        description: "Return word count, character count, and line count for a text file.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string"), "description": .string("Path to the file.")])
            ]),
            "required": .array([.string("path")])
        ])
    )

    static let replaceTool = Tool(
        name: ToolName.replace,
        description: """
            Replace text in a file. Without confirm:true, returns a diff (dry-run). \
            With confirm:true, applies the change.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string"), "description": .string("Path to the file.")]),
                "search": .object(["type": .string("string"), "description": .string("Text to replace.")]),
                "replacement": .object(["type": .string("string"), "description": .string("Replacement text.")]),
                "all": .object(["type": .string("boolean"), "description": .string("Replace all occurrences (default: false = first only).")]),
                "confirm": .object(["type": .string("boolean"), "description": .string("Set true to apply. Omit for dry-run.")])
            ]),
            "required": .array([.string("path"), .string("search"), .string("replacement")])
        ])
    )

    static let insertTool = Tool(
        name: ToolName.insert,
        description: """
            Insert a line into a file at a given line number. \
            Without confirm:true, returns a diff (dry-run). With confirm:true, applies the change.
            """,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string"), "description": .string("Path to the file.")]),
                "content": .object(["type": .string("string"), "description": .string("Text to insert.")]),
                "atLine": .object(["type": .string("integer"), "description": .string("Line number to insert at (1-indexed).")]),
                "position": .object(["type": .string("string"), "description": .string("\"before\" (default) or \"after\" the given line.")]),
                "confirm": .object(["type": .string("boolean"), "description": .string("Set true to apply. Omit for dry-run.")])
            ]),
            "required": .array([.string("path"), .string("content"), .string("atLine")])
        ])
    )

    static let appendTool = Tool(
        name: ToolName.append,
        description: "Append content to the end of a file.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string"), "description": .string("Path to the file.")]),
                "content": .object(["type": .string("string"), "description": .string("Text to append.")])
            ]),
            "required": .array([.string("path"), .string("content")])
        ])
    )

    // MARK: Dispatch

    static func handle(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let args = params.arguments ?? [:]
        switch params.name {
        case ToolName.read:    return try handleRead(args)
        case ToolName.search:  return try handleSearch(args)
        case ToolName.analyze: return try handleAnalyze(args)
        case ToolName.replace: return try handleReplace(args)
        case ToolName.insert:  return try handleInsert(args)
        case ToolName.append:  return try handleAppend(args)
        default:
            throw LilDocError.unknown("Unknown tool: \(params.name)")
        }
    }

    // MARK: Handlers

    private static func handleRead(_ args: [String: Value]) throws -> CallTool.Result {
        let path = try requireString(args, key: "path")
        let text = try FileIO.read(path)
        if let start = intArg(args, key: "startLine"), let end = intArg(args, key: "endLine") {
            let slice = TextOperations.readLines(in: text, from: start, to: end)
            if slice.isEmpty { return .init(content: [.text(text: "(empty range)", annotations: nil, _meta: nil)]) }
            return .init(content: [.text(text: slice, annotations: nil, _meta: nil)])
        }
        return .init(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    private static func handleSearch(_ args: [String: Value]) throws -> CallTool.Result {
        let path  = try requireString(args, key: "path")
        let query = try requireString(args, key: "query")
        let text  = try FileIO.read(path)
        let matches = TextSearch.findMatches(in: text, query: query)
        if matches.isEmpty { return .init(content: [.text(text: "No matches found.", annotations: nil, _meta: nil)]) }
        let lines = matches.map { "Line \($0.line), col \($0.column): \($0.context)" }.joined(separator: "\n")
        return .init(content: [.text(text: lines, annotations: nil, _meta: nil)])
    }

    private static func handleAnalyze(_ args: [String: Value]) throws -> CallTool.Result {
        let path = try requireString(args, key: "path")
        let text = try FileIO.read(path)
        let result = """
            {
              "words": \(TextAnalysis.wordCount(text)),
              "characters": \(TextAnalysis.characterCount(text)),
              "lines": \(TextAnalysis.lineCount(text))
            }
            """
        return .init(content: [.text(text: result, annotations: nil, _meta: nil)])
    }

    private static func handleReplace(_ args: [String: Value]) throws -> CallTool.Result {
        let path        = try requireString(args, key: "path")
        let search      = try requireString(args, key: "search")
        let replacement = try requireString(args, key: "replacement")
        let all         = boolArg(args, key: "all") ?? false
        let confirm     = boolArg(args, key: "confirm") ?? false

        let original = try FileIO.read(path)
        let (modified, count) = TextOperations.replace(in: original, search: search, with: replacement, all: all)

        if count == 0 {
            return .init(content: [.text(text: "No matches found for \"\(search)\".", annotations: nil, _meta: nil)], isError: true)
        }
        if confirm {
            try FileIO.write(path, modified)
            return .init(content: [.text(text: "Replaced \(count) occurrence(s).", annotations: nil, _meta: nil)])
        } else {
            let diff = TextOperations.unifiedDiff(original: original, modified: modified, path: path)
            return .init(content: [.text(text: "Dry run — \(count) occurrence(s) would be replaced.\n\n\(diff)", annotations: nil, _meta: nil)])
        }
    }

    private static func handleInsert(_ args: [String: Value]) throws -> CallTool.Result {
        let path    = try requireString(args, key: "path")
        let content = try requireString(args, key: "content")
        let atLine  = try requireInt(args, key: "atLine")
        let posStr  = stringArg(args, key: "position") ?? "before"
        let confirm = boolArg(args, key: "confirm") ?? false
        let position: TextOperations.LinePosition = posStr == "after" ? .after : .before

        let original = try FileIO.read(path)
        let modified = TextOperations.insertLine(in: original, content: content, at: atLine, position: position)

        if confirm {
            try FileIO.write(path, modified)
            return .init(content: [.text(text: "Inserted line at \(atLine).", annotations: nil, _meta: nil)])
        } else {
            let diff = TextOperations.unifiedDiff(original: original, modified: modified, path: path)
            return .init(content: [.text(text: "Dry run — line would be inserted at \(atLine).\n\n\(diff)", annotations: nil, _meta: nil)])
        }
    }

    private static func handleAppend(_ args: [String: Value]) throws -> CallTool.Result {
        let path    = try requireString(args, key: "path")
        let content = try requireString(args, key: "content")
        let original = try FileIO.read(path)
        let modified = TextOperations.append(content, to: original)
        try FileIO.write(path, modified)
        return .init(content: [.text(text: "Content appended.", annotations: nil, _meta: nil)])
    }
}

// MARK: - Argument helpers

private func requireString(_ args: [String: Value], key: String) throws -> String {
    guard let v = args[key], case .string(let s) = v else {
        throw LilDocError.missingParam(key)
    }
    return s
}

private func requireInt(_ args: [String: Value], key: String) throws -> Int {
    guard let v = args[key] else { throw LilDocError.missingParam(key) }
    if case .int(let i) = v { return i }
    if case .double(let d) = v { return Int(d) }
    throw LilDocError.badParam(key, "expected integer")
}

private func stringArg(_ args: [String: Value], key: String) -> String? {
    guard case .string(let s) = args[key] else { return nil }
    return s
}

private func intArg(_ args: [String: Value], key: String) -> Int? {
    guard let v = args[key] else { return nil }
    if case .int(let i) = v { return i }
    if case .double(let d) = v { return Int(d) }
    return nil
}

private func boolArg(_ args: [String: Value], key: String) -> Bool? {
    guard let v = args[key] else { return nil }
    if case .bool(let b) = v { return b }
    return nil
}

// MARK: - Errors

enum LilDocError: Error, LocalizedError {
    case missingParam(String)
    case badParam(String, String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .missingParam(let k): return "Missing required parameter: \(k)"
        case .badParam(let k, let m): return "Bad parameter \"\(k)\": \(m)"
        case .unknown(let m): return m
        }
    }
}
