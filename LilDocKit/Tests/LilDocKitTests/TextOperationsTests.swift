import XCTest
@testable import LilDocKit

final class TextOperationsTests: XCTestCase {
    // MARK: - replace

    func testReplaceFirst() {
        let (result, count) = TextOperations.replace(in: "aaa", search: "a", with: "b", all: false)
        XCTAssertEqual(result, "baa")
        XCTAssertEqual(count, 1)
    }

    func testReplaceAll() {
        let (result, count) = TextOperations.replace(in: "aaa", search: "a", with: "b", all: true)
        XCTAssertEqual(result, "bbb")
        XCTAssertEqual(count, 3)
    }

    func testReplaceNoMatch() {
        let (result, count) = TextOperations.replace(in: "hello", search: "xyz", with: "zzz", all: false)
        XCTAssertEqual(result, "hello")
        XCTAssertEqual(count, 0)
    }

    func testReplaceEmptySearch() {
        let (result, count) = TextOperations.replace(in: "hello", search: "", with: "x", all: false)
        XCTAssertEqual(result, "hello")
        XCTAssertEqual(count, 0)
    }

    // MARK: - insertLine

    func testInsertBefore() {
        let result = TextOperations.insertLine(in: "a\nb\nc", content: "X", at: 2, position: .before)
        XCTAssertEqual(result, "a\nX\nb\nc")
    }

    func testInsertAfter() {
        let result = TextOperations.insertLine(in: "a\nb\nc", content: "X", at: 2, position: .after)
        XCTAssertEqual(result, "a\nb\nX\nc")
    }

    func testInsertAtFirstLine() {
        let result = TextOperations.insertLine(in: "a\nb", content: "X", at: 1, position: .before)
        XCTAssertEqual(result, "X\na\nb")
    }

    // MARK: - wrapMatches

    func testWrapMatches() {
        let (result, count) = TextOperations.wrapMatches(in: "hello world", search: "world", prefix: "**", suffix: "**")
        XCTAssertEqual(result, "hello **world**")
        XCTAssertEqual(count, 1)
    }

    func testWrapMatchesCaseInsensitive() {
        let (result, _) = TextOperations.wrapMatches(in: "Hello World", search: "hello", prefix: "[", suffix: "]")
        XCTAssertEqual(result, "[Hello] World")
    }

    // MARK: - prefixLines

    func testPrefixAllLines() {
        let result = TextOperations.prefixLines(in: "a\nb\nc", prefix: "> ", matching: nil)
        XCTAssertEqual(result, "> a\n> b\n> c")
    }

    func testPrefixMatchingLines() {
        let result = TextOperations.prefixLines(in: "TODO: fix this\ndone\nTODO: also this", prefix: "- ", matching: "TODO")
        XCTAssertEqual(result, "- TODO: fix this\ndone\n- TODO: also this")
    }

    // MARK: - append

    func testAppendToText() {
        let result = TextOperations.append("world", to: "hello")
        XCTAssertEqual(result, "hello\nworld")
    }

    func testAppendToTextWithTrailingNewline() {
        let result = TextOperations.append("world", to: "hello\n")
        XCTAssertEqual(result, "hello\nworld")
    }

    func testAppendToEmpty() {
        let result = TextOperations.append("hello", to: "")
        XCTAssertEqual(result, "hello")
    }

    // MARK: - unifiedDiff

    func testNoChanges() {
        let diff = TextOperations.unifiedDiff(original: "same", modified: "same", path: "f.txt")
        XCTAssertEqual(diff, "(no changes)")
    }

    func testDiffShowsChanges() {
        let diff = TextOperations.unifiedDiff(original: "old", modified: "new", path: "f.txt")
        XCTAssertTrue(diff.contains("---"))
        XCTAssertTrue(diff.contains("+++"))
        XCTAssertTrue(diff.contains("-old"))
        XCTAssertTrue(diff.contains("+new"))
    }
}
