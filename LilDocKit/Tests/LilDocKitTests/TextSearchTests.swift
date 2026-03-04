import XCTest
@testable import LilDocKit

final class TextSearchTests: XCTestCase {
    func testNoMatches() {
        let matches = TextSearch.findMatches(in: "hello world", query: "xyz")
        XCTAssertTrue(matches.isEmpty)
    }

    func testEmptyQuery() {
        let matches = TextSearch.findMatches(in: "hello world", query: "")
        XCTAssertTrue(matches.isEmpty)
    }

    func testSingleMatch() {
        let matches = TextSearch.findMatches(in: "hello world", query: "world")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].line, 1)
        XCTAssertEqual(matches[0].text, "world")
    }

    func testCaseInsensitive() {
        let matches = TextSearch.findMatches(in: "Hello World", query: "hello")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].text, "Hello")
    }

    func testMultipleMatchesOnSameLine() {
        let matches = TextSearch.findMatches(in: "the cat sat on the mat", query: "the")
        XCTAssertEqual(matches.count, 2)
    }

    func testMatchesAcrossLines() {
        let text = "line one\nline two\nline three"
        let matches = TextSearch.findMatches(in: text, query: "line")
        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(matches[0].line, 1)
        XCTAssertEqual(matches[1].line, 2)
        XCTAssertEqual(matches[2].line, 3)
    }

    func testColumnNumber() {
        // "hello world" — "world" starts at column 7
        let matches = TextSearch.findMatches(in: "hello world", query: "world")
        XCTAssertEqual(matches[0].column, 7)
    }

    func testContextIsFullLine() {
        let text = "first line\nsecond line"
        let matches = TextSearch.findMatches(in: text, query: "second")
        XCTAssertEqual(matches[0].context, "second line")
    }
}
