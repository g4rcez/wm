import CoreGraphics
import Testing
@testable import Core

@Suite("TextPage")
struct TextPageTests {
    private func word(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 40, window: Int = 0) -> TextWord {
        TextWord(text, frame: CGRect(x: x, y: y, width: width, height: 20), window: window)
    }

    /// Two lines: "Save As" and "Open File".
    private var page: TextPage {
        TextPage(words: [
            word("File", x: 50, y: 30), word("Open", x: 0, y: 30), word("As", x: 50, y: 2, width: 20), word("Save", x: 0, y: 0),
        ])
    }

    @Test func wordsAreInLinesInReadingOrder() {
        #expect(page.words.map(\.text) == ["Save", "As", "Open", "File"])
        #expect(page.lines == [0..<2, 2..<4])
    }

    @Test func aWordBehindAWindowInFrontIsNotOnThePage() {
        let windows = [CGRect(x: 0, y: 0, width: 100, height: 100), CGRect(x: 0, y: 0, width: 400, height: 400)]
        let page = TextPage(
            words: [word("front", x: 10, y: 10, window: 0), word("hidden", x: 20, y: 50, window: 1), word("seen", x: 200, y: 50, window: 1)],
            windows: windows)
        #expect(page.words.map(\.text) == ["front", "seen"])
    }

    @Test func aMatchCanGoOverTwoWords() {
        let matches = page.matches("save as")
        #expect(matches.count == 1)
        #expect(matches[0].start == TextPosition(word: 0, offset: 0))
        #expect(matches[0].end == TextPosition(word: 1, offset: 1))
        #expect(matches[0].frame == CGRect(x: 0, y: 0, width: 70, height: 22))
    }

    @Test func aMatchInsideAWordHasThePartOfItsFrame() {
        let matches = page.matches("pe")
        #expect(matches.count == 1)
        #expect(matches[0].start == TextPosition(word: 2, offset: 1))
        #expect(matches[0].end == TextPosition(word: 2, offset: 2))
        #expect(matches[0].frame == CGRect(x: 10, y: 30, width: 20, height: 20))
    }

    @Test func caseAndAccentsDoNotCount() {
        let matches = TextPage(words: [word("Não", x: 0, y: 0)]).matches("NAO")
        #expect(matches.count == 1)
        #expect(matches[0].end == TextPosition(word: 0, offset: 2))
    }

    @Test func aTextThatIsNotOnThePageHasNoMatch() {
        #expect(page.matches("print").isEmpty)
    }

    @Test func anEmptyTextMatchesEveryWord() {
        let matches = page.matches("")
        #expect(matches.count == 4)
        #expect(matches[3].start == TextPosition(word: 3, offset: 0))
        #expect(matches[3].end == TextPosition(word: 3, offset: 3))
    }

    @Test func noLabelStartsWithAMotionKey() {
        let labels = page.labels(for: page.matches(""))
        #expect(labels == [0: "aa", 1: "sa", 2: "da", 3: "fa"])
        let many = TextPage(words: [
            word("a", x: 0, y: 0), word("b", x: 50, y: 0), word("c", x: 100, y: 0), word("d", x: 150, y: 0), word("e", x: 200, y: 0),
            word("f", x: 250, y: 0),
        ])
        #expect(many.labels(for: many.matches(""))[5] == "qa")
    }

    @Test func theTextOfARangeKeepsTheLines() {
        #expect(page.text(from: TextPosition(word: 0, offset: 2), to: TextPosition(word: 2, offset: 1)) == "ve As\nOp")
        #expect(page.text(from: TextPosition(word: 2, offset: 1), to: TextPosition(word: 0, offset: 2)) == "ve As\nOp")
    }

    @Test func aWindowWithFewWordsNeedsTheOCR() {
        #expect(TextPage.needsOCR(wordCount: 7))
        #expect(!TextPage.needsOCR(wordCount: 8))
    }

    @Test func aVisionBoxBecomesAScreenFrame() {
        let box = TextPage.screenRect(normalized: CGRect(x: 0.5, y: 0.75, width: 0.25, height: 0.25), in: CGRect(x: 100, y: 0, width: 800, height: 400))
        #expect(box == CGRect(x: 500, y: 0, width: 200, height: 100))
    }

    @Test func aVisionBoxOnADisplayToTheLeftKeepsItsNegativeOrigin() {
        let box = TextPage.screenRect(normalized: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), in: CGRect(x: -1920, y: -200, width: 1920, height: 1080))
        #expect(box == CGRect(x: -1920, y: 340, width: 960, height: 540))
    }
}
