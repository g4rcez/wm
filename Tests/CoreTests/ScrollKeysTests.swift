import CoreGraphics
import Testing
@testable import Core

@Suite("ScrollKeys")
struct ScrollKeysTests {
    @Test func vimKeysScrollOneStep() {
        var keys = ScrollKeys()
        #expect(keys.press("h") == .by(dx: -60, dy: 0))
        #expect(keys.press("l") == .by(dx: 60, dy: 0))
        #expect(keys.press("j") == .by(dx: 0, dy: 60))
        #expect(keys.press("k") == .by(dx: 0, dy: -60))
    }

    @Test func shiftDashesFiveSteps() {
        var keys = ScrollKeys()
        #expect(keys.press("j", shift: true) == .by(dx: 0, dy: 300))
        #expect(keys.press("h", shift: true) == .by(dx: -300, dy: 0))
    }

    @Test func dAndUScrollHalfAPage() {
        var keys = ScrollKeys()
        #expect(keys.press("d") == .halfPage(1))
        #expect(keys.press("u") == .halfPage(-1))
    }

    @Test func twoGsGoToTheTopAndShiftGToTheBottom() {
        var keys = ScrollKeys()
        #expect(keys.press("g") == .pending)
        #expect(keys.press("g") == .top)
        #expect(keys.press("g", shift: true) == .bottom)
    }

    @Test func aKeyBetweenTheGsStartsOver() {
        var keys = ScrollKeys()
        #expect(keys.press("g") == .pending)
        #expect(keys.press("j") == .by(dx: 0, dy: 60))
        #expect(keys.press("g") == .pending)
    }

    @Test func areasChangeWithTabArrowsControlKeysAndDigits() {
        var keys = ScrollKeys()
        #expect(keys.press("tab") == .nextArea)
        #expect(keys.press("tab", shift: true) == .previousArea)
        #expect(keys.press("down") == .nextArea)
        #expect(keys.press("up") == .previousArea)
        #expect(keys.press("n", control: true) == .nextArea)
        #expect(keys.press("p", control: true) == .previousArea)
        #expect(keys.press("3") == .area(3))
    }

    @Test func escapeExitsAndOtherKeysAreLeftToTheCaller() {
        var keys = ScrollKeys()
        #expect(keys.press("esc") == .exit)
        #expect(keys.press("x") == .ignored)
        #expect(keys.press("j", control: true) == .ignored)
        #expect(keys.press("enter") == .ignored)
    }
}

@Suite("ScrollAreas")
struct ScrollAreasTests {
    private let window = CGRect(x: 0, y: 0, width: 800, height: 600)

    @Test func areasAreNumberedInReadingOrderAndTheLargestStartsActive() {
        let sidebar = CGRect(x: 0, y: 0, width: 200, height: 600)
        let content = CGRect(x: 200, y: 0, width: 600, height: 400)
        let footer = CGRect(x: 200, y: 400, width: 600, height: 100)
        let areas = ScrollAreas(frames: [footer, content, sidebar], fallback: window)
        #expect(areas.frames == [sidebar, content, footer])
        #expect(areas.active == 1)
        #expect(areas.current == content)
    }

    @Test func withoutAreasTheWindowIsTheOnlyOne() {
        let areas = ScrollAreas(frames: [], fallback: window)
        #expect(areas.frames == [window])
        #expect(areas.active == 0)
    }

    @Test func stepWrapsAndSelectIgnoresANumberWithNoArea() {
        var areas = ScrollAreas(
            frames: [CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 0, y: 20, width: 10, height: 10)], fallback: window)
        #expect(areas.active == 0)
        areas.step(-1)
        #expect(areas.active == 1)
        areas.step(1)
        #expect(areas.active == 0)
        areas.select(5)
        #expect(areas.active == 0)
        areas.select(1)
        #expect(areas.active == 1)
    }

    @Test func aWebViewOnTheFrameOfItsScrollAreaIsOneArea() {
        let area = CGRect(x: 0, y: 0, width: 400, height: 300)
        let webView = CGRect(x: 0, y: 1, width: 400, height: 299)
        #expect(ScrollAreas(frames: [area, webView], fallback: window).frames == [area])
    }

    @Test func atMostTenAreasAreKept() {
        let frames = (0..<12).map { CGRect(x: 0, y: CGFloat($0) * 10, width: 10, height: 10) }
        #expect(ScrollAreas(frames: frames, fallback: window).frames.count == 10)
    }
}
