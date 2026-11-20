import CoreGraphics
import Testing
@testable import Core

@Suite("ElementSearch")
struct ElementSearchTests {
    private func element(_ id: Int, x: CGFloat, y: CGFloat = 0, _ text: String) -> HintElement {
        HintElement(id: id, frame: CGRect(x: x, y: y, width: 40, height: 20), role: "AXButton", text: text)
    }

    /// In reading order: Open (2), Close Tab (3), Save As (1).
    private var toolbar: [HintElement] {
        [element(1, x: 200, "Save As"), element(2, x: 0, "Open"), element(3, x: 100, "Close Tab")]
    }

    private func search(_ elements: [HintElement], pressing keys: String) -> ElementSearch {
        var search = ElementSearch(elements: elements)
        for key in keys { _ = search.press(String(key)) }
        return search
    }

    @Test func everyLabelHasTwoLettersInReadingOrder() {
        let search = ElementSearch(elements: toolbar)
        #expect(search.label(of: 2) == "aa")
        #expect(search.label(of: 3) == "sa")
        #expect(search.label(of: 1) == "da")
    }

    @Test func twoLettersPickAnElement() {
        var search = ElementSearch(elements: toolbar)
        #expect(search.press("s") == .updated)
        #expect(search.typed == "s")
        #expect(search.press("a") == .picked(toolbar[2]))
        #expect(search.typed == "")
    }

    @Test func oneLetterIsNotEnough() {
        var search = ElementSearch(elements: toolbar)
        #expect(search.press("d") == .updated)
        #expect(search.matches.count == 3)
    }

    @Test func aWrongSecondLetterCancelsTheFirst() {
        var search = ElementSearch(elements: toolbar)
        _ = search.press("s")
        #expect(search.press("z") == .updated)
        #expect(search.typed == "")
        #expect(search.press("a") == .updated)
        #expect(search.typed == "a")
    }

    @Test func aLetterThatIsNoLabelDoesNothingUntilASearchStarts() {
        var search = ElementSearch(elements: toolbar)
        #expect(search.press("z") == .ignored)
        #expect(search.query == "")
    }

    @Test func aSearchHidesTheLabelsUntilItsFirstLetter() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        #expect(search.labels.isEmpty)
        #expect(search.matches.count == 3)
    }

    @Test func theSearchIgnoresCase() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        for key in "SAVE" { _ = search.press(String(key)) }
        #expect(search.matches.map(\.id) == [1])
    }

    @Test func theLettersOfAWordCanHaveOthersBetweenThem() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        for key in "svs" { _ = search.press(String(key)) }
        #expect(search.matches.map(\.id) == [1])
    }

    @Test func theLettersOfAWordMustComeInOrder() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        for key in "tc" { _ = search.press(String(key)) }
        #expect(search.matches.isEmpty)
    }

    @Test func wordsMatchInAnyOrder() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        for key in "tab clo" { _ = search.press(String(key)) }
        #expect(search.matches.map(\.id) == [3])
    }

    @Test func everyWordMustMatch() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        for key in "as sa" { _ = search.press(String(key)) }
        #expect(search.matches.map(\.id) == [1])
        _ = search.press(" ")
        for key in "zz" { _ = search.press(String(key)) }
        #expect(search.matches.isEmpty)
    }

    @Test func aSpaceEndsTheWordAndHidesTheLabelsUntilTheNextLetter() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        _ = search.press("o")
        #expect(!search.labels.isEmpty)
        _ = search.press(" ")
        #expect(search.labels.isEmpty)
        #expect(search.matches.map(\.id) == [2, 3])
    }

    @Test func aWordDoesNotStartWithASpaceAndASpaceIsNotRepeated() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        #expect(search.press(" ") == .ignored)
        _ = search.press("o")
        _ = search.press(" ")
        #expect(search.press(" ") == .ignored)
        #expect(search.query == "o ")
    }

    @Test func matchesGetLabelsAgainInReadingOrder() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        _ = search.press("o")
        // "Open" and "Close Tab" have an o. The letters after it are p e n and s e t a b, so no label starts with them.
        #expect(search.matches.map(\.id) == [2, 3])
        #expect(search.label(of: 2) == "da")
        #expect(search.label(of: 3) == "fa")
    }

    @Test func aLetterThatCouldContinueTheWordIsSearchAndNeverALabelStart() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        _ = search.press("o")
        #expect(search.press("p") == .updated)
        #expect(search.query == "op")
        #expect(search.matches.map(\.id) == [2])
    }

    @Test func aLabelPicksInsideASearch() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        _ = search.press("o")
        _ = search.press("d")
        #expect(search.press("a") == .picked(toolbar[1]))
    }

    @Test func whenEveryLetterCouldContinueTheWordNoMatchHasALabel() {
        let every = "xabcdefghijklmnopqrstuvwxyz"
        var search = ElementSearch(elements: [element(1, x: 0, every), element(2, x: 100, every)])
        search.beginSearch()
        _ = search.press("x")
        #expect(search.matches.count == 2)
        #expect(search.labels.isEmpty)
    }

    @Test func backspaceTakesBackALabelLetterThenTextThenTheSearch() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        _ = search.press("o")
        _ = search.press("d")
        search.backspace()
        #expect(search.typed == "")
        #expect(search.query == "o")
        search.backspace()
        #expect(search.query == "")
        #expect(search.searching)
        search.backspace()
        #expect(!search.searching)
        #expect(search.label(of: 2) == "aa")
    }

    @Test func moreElementsThanOneLetterEachNeedTheSecondLetterToTellThemApart() {
        let many = (0..<30).map { element($0, x: CGFloat($0) * 50, "item") }
        let search = ElementSearch(elements: many)
        #expect(search.label(of: 0) == "aa")
        #expect(search.label(of: 1) == "sa")
        #expect(search.label(of: 26) == "as")
        #expect(Set(search.labels.values).count == 30)
    }

    @Test func theLabelsUseOnlyTheLettersThatWereGiven() {
        let many = (0..<10).map { element($0, x: CGFloat($0) * 50, "item") }
        let search = ElementSearch(elements: many, letters: Array("asdf"))
        #expect(search.label(of: 0) == "aa")
        #expect(search.label(of: 1) == "sa")
        #expect(search.label(of: 4) == "as")
        #expect(search.labels.values.allSatisfy { $0.allSatisfy { "asdf".contains($0) } })
        #expect(Set(search.labels.values).count == 10)
    }

    @Test func everyLabelHasTwoLettersSoOnlyTheFirstSixHundredSeventySixElementsHaveOne() {
        let many = (0..<677).map { element($0, x: CGFloat($0) * 3, "item") }
        let labels = ElementSearch(elements: many).labels
        #expect(labels.count == 676)
        #expect(labels.values.allSatisfy { $0.count == 2 })
    }

    @Test func stepWalksTheMatchesAndWraps() {
        var search = ElementSearch(elements: toolbar)
        search.step(1)
        #expect(search.focused == 2)
        search.step(1)
        search.step(1)
        #expect(search.focused == 1)
        search.step(1)
        #expect(search.focused == 2)
        search.step(-1)
        #expect(search.focused == 1)
    }

    @Test func focusHighlightsAMatchWithoutPickingIt() {
        var search = ElementSearch(elements: toolbar)
        search.focus(3)
        #expect(search.focused == 3)
        #expect(search.target?.id == 3)
    }

    @Test func anElementThatIsNotAMatchCannotBeFocused() {
        var search = ElementSearch(elements: toolbar)
        search.beginSearch()
        _ = search.press("o")
        search.focus(1)
        #expect(search.focused == nil)
    }

    @Test func theFocusIsLostWhenTheSearchDropsThatElement() {
        var search = ElementSearch(elements: toolbar)
        search.step(1)
        search.beginSearch()
        for key in "save" { _ = search.press(String(key)) }
        #expect(search.focused == nil)
        #expect(search.target?.id == 1)
    }

    @Test func withSeveralMatchesAndNoFocusThereIsNoTarget() {
        #expect(ElementSearch(elements: toolbar).target == nil)
    }

    @Test func anElementOnTheFrameOfAnotherOneIsDropped() {
        let row = HintElement(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 20), role: "AXRow", text: "Inbox")
        let same = HintElement(id: 2, frame: CGRect(x: 1, y: 1, width: 101, height: 19), role: "AXButton", text: "Inbox")
        let other = HintElement(id: 3, frame: CGRect(x: 0, y: 30, width: 100, height: 20), role: "AXButton", text: "Sent")
        #expect(ElementSearch(elements: [row, same, other]).elements.map(\.id) == [1, 3])
    }

    @Test func noElementsMeansNoMatchesAndNoTarget() {
        var search = ElementSearch(elements: [])
        search.step(1)
        #expect(search.matches.isEmpty)
        #expect(search.target == nil)
    }

    @Test func keptLabelsStayWhileTheTextPicksATarget() {
        var search = ElementSearch(elements: toolbar, keepsLabels: true)
        search.beginSearch()
        for key in "save" { _ = search.press(String(key)) }
        #expect(search.label(of: 2) == "aa")
        #expect(search.label(of: 3) == "sa")
        #expect(search.label(of: 1) == "da")
        #expect(search.target?.id == 1)
    }

    @Test func keptLabelsPickByLabel() {
        var search = ElementSearch(elements: toolbar, keepsLabels: true)
        search.beginSearch()
        for key in "sa" { _ = search.press(String(key)) }
        #expect(search.target?.id == 3)
    }
}
