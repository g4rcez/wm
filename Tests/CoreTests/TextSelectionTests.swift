import CoreGraphics
import Testing
@testable import Core

@Suite("TextSelection")
struct TextSelectionTests {
    private func word(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 40) -> TextWord {
        TextWord(text, frame: CGRect(x: x, y: y, width: width, height: 20))
    }

    /// Two lines: "Save As" and "Open File".
    private var page: TextPage {
        TextPage(words: [word("Save", x: 0, y: 0), word("As", x: 50, y: 0, width: 20), word("Open", x: 0, y: 30), word("File", x: 50, y: 30)])
    }

    private func selection(_ query: String) -> TextSelection { TextSelection(page.matches(query)[0]) }

    @Test func itStartsOnTheMatch() {
        #expect(selection("save as").text(in: page) == "Save As")
    }

    @Test func aMoveWithoutExtendTakesTheSelectionToTheCursor() {
        var selection = selection("pe")
        selection.move(.right, in: page)
        #expect(selection.head == TextPosition(word: 2, offset: 3))
        #expect(selection.anchor == TextPosition(word: 2, offset: 3))
        #expect(selection.text(in: page) == "n")
    }

    @Test func rightGoesToTheNextWordAndStopsAtTheEndOfTheLine() {
        var selection = selection("open")
        selection.move(.right, in: page)
        #expect(selection.head == TextPosition(word: 3, offset: 0))
        selection.move(.right, in: page)
        selection.move(.right, in: page)
        selection.move(.right, in: page)
        selection.move(.right, in: page)
        #expect(selection.head == TextPosition(word: 3, offset: 3))
    }

    @Test func leftGoesToThePreviousWordAndStopsAtTheStartOfTheLine() {
        var selection = selection("f")
        selection.move(.left, in: page)
        #expect(selection.head == TextPosition(word: 2, offset: 3))
        selection.move(.lineStart, in: page)
        selection.move(.left, in: page)
        #expect(selection.head == TextPosition(word: 2, offset: 0))
    }

    @Test func theWordMovesCrossTheLines() {
        var selection = selection("as")
        selection.move(.nextWord, in: page)
        #expect(selection.head == TextPosition(word: 2, offset: 0))
        selection.move(.wordEnd, in: page)
        #expect(selection.head == TextPosition(word: 2, offset: 3))
        selection.move(.wordEnd, in: page)
        #expect(selection.head == TextPosition(word: 3, offset: 3))
        selection.move(.previousWord, in: page)
        #expect(selection.head == TextPosition(word: 3, offset: 0))
        selection.move(.previousWord, in: page)
        #expect(selection.head == TextPosition(word: 2, offset: 0))
    }

    @Test func downAndUpGoToTheCharacterThatIsNearest() {
        var selection = selection("as")
        selection.move(.down, in: page)
        #expect(selection.head == TextPosition(word: 3, offset: 1))
        selection.move(.up, in: page)
        #expect(selection.head == TextPosition(word: 1, offset: 1))
        selection.move(.up, in: page)
        #expect(selection.head == TextPosition(word: 1, offset: 1))
    }

    @Test func theLineMovesGoToTheEnds() {
        var selection = selection("as")
        selection.move(.lineStart, in: page)
        #expect(selection.head == TextPosition(word: 0, offset: 0))
        selection.move(.lineEnd, in: page)
        #expect(selection.head == TextPosition(word: 1, offset: 1))
    }

    @Test func extendKeepsTheAnchor() {
        var selection = selection("as")
        selection.toggleExtend()
        selection.move(.down, in: page)
        #expect(selection.anchor == TextPosition(word: 1, offset: 0))
        #expect(selection.text(in: page) == "As\nOpen Fi")
        #expect(selection.rects(in: page) == [CGRect(x: 50, y: 0, width: 20, height: 20), CGRect(x: 0, y: 30, width: 70, height: 20)])
    }

    @Test func extendOffTakesTheSelectionToTheCursor() {
        var selection = selection("save as")
        selection.toggleExtend()
        selection.toggleExtend()
        #expect(selection.text(in: page) == "s")
    }

    @Test func theFirstLabelSelectsTheMatchAndTheNextOnesExtendToTheirs() {
        var selection = selection("save")
        selection.jump(to: page.matches("file")[0])
        #expect(selection.extend)
        #expect(selection.text(in: page) == "File")
        selection.jump(to: page.matches("as")[0])
        #expect(selection.head == TextPosition(word: 1, offset: 0))
        #expect(selection.text(in: page) == "As\nOpen File")
    }

    @Test func aLabelAfterTheSelectionExtendsItToTheEndOfTheMatch() {
        var selection = selection("save")
        selection.toggleExtend()
        selection.jump(to: page.matches("open")[0])
        #expect(selection.head == TextPosition(word: 2, offset: 3))
        #expect(selection.text(in: page) == "Save As\nOpen")
    }

    @Test func theClickGoesToTheFirstWordOfTheSelection() {
        var selection = selection("as")
        selection.toggleExtend()
        selection.move(.down, in: page)
        #expect(selection.clickPoint(in: page) == CGPoint(x: 60, y: 10))
    }

    @Test func expandTakesTheWholeWordThenGrowsWordByWord() {
        var selection = selection("pe")
        selection.expand(in: page)
        #expect(selection.text(in: page) == "Open")
        #expect(selection.extend)
        selection.expand(in: page)
        #expect(selection.text(in: page) == "Open File")
        selection.expand(in: page)
        #expect(selection.text(in: page) == "Open File")
    }

    @Test func expandOfAWholeWordAddsTheNextOne() {
        var selection = selection("as")
        selection.expand(in: page)
        #expect(selection.text(in: page) == "As\nOpen")
    }

    @Test func expandGrowsTowardTheCursorWhenItIsBeforeTheAnchor() {
        var selection = selection("le")
        selection.toggleExtend()
        selection.move(.left, in: page)
        selection.move(.left, in: page)
        selection.expand(in: page)
        #expect(selection.text(in: page) == "File")
        #expect(selection.head == TextPosition(word: 3, offset: 0))
        selection.expand(in: page)
        #expect(selection.text(in: page) == "Open File")
    }
}
