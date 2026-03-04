import Foundation

/// Shared file read/write helpers used by both lildoc-cli and lildoc-mcp.
public enum FileIO {
    public static func read(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    public static func write(_ path: String, _ content: String) throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
