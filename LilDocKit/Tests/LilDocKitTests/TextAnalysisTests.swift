import XCTest
@testable import LilDocKit

final class TextAnalysisTests: XCTestCase {
    func testWordCount_empty() {
        XCTAssertEqual(TextAnalysis.wordCount(""), 0)
    }

    func testWordCount_whitespaceOnly() {
        XCTAssertEqual(TextAnalysis.wordCount("   \n  "), 0)
    }

    func testWordCount_singleWord() {
        XCTAssertEqual(TextAnalysis.wordCount("hello"), 1)
    }

    func testWordCount_multipleWords() {
        XCTAssertEqual(TextAnalysis.wordCount("hello world foo"), 3)
    }

    func testWordCount_leadingTrailingWhitespace() {
        XCTAssertEqual(TextAnalysis.wordCount("  hello world  "), 2)
    }

    func testWordCount_newlines() {
        XCTAssertEqual(TextAnalysis.wordCount("one\ntwo\nthree"), 3)
    }

    func testCharacterCount() {
        XCTAssertEqual(TextAnalysis.characterCount("hello"), 5)
        XCTAssertEqual(TextAnalysis.characterCount(""), 0)
    }

    func testLineCount_empty() {
        XCTAssertEqual(TextAnalysis.lineCount(""), 0)
    }

    func testLineCount_singleLine() {
        XCTAssertEqual(TextAnalysis.lineCount("hello"), 1)
    }

    func testLineCount_multipleLines() {
        XCTAssertEqual(TextAnalysis.lineCount("one\ntwo\nthree"), 3)
    }

    func testLineCount_trailingNewline() {
        // "one\ntwo\n" should count as 2 lines, not 3
        XCTAssertEqual(TextAnalysis.lineCount("one\ntwo\n"), 2)
    }
}
