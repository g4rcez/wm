import CoreGraphics
import Testing
@testable import Core

/// Two strips: a horizontal strip of four columns (ids 1...4) and a vertical strip of two rows (ids 5, 6) at its right.
private let twoStrips = LayoutOverview(
    frames: [
        1: CGRect(x: 0, y: 0, width: 400, height: 600),
        2: CGRect(x: 400, y: 0, width: 400, height: 600),
        3: CGRect(x: 800, y: 0, width: 400, height: 600),
        4: CGRect(x: 1200, y: 0, width: 400, height: 600),
        5: CGRect(x: 1600, y: 0, width: 400, height: 300),
        6: CGRect(x: 1600, y: 300, width: 400, height: 300),
    ],
    viewports: [CGRect(x: 0, y: 0, width: 1000, height: 600)]
)

private func model(mru: [WindowID], floating: [WindowID: CGRect] = [:]) -> SwitcherModel {
    SwitcherModel(overview: twoStrips, floating: floating, mru: mru, focused: mru.first)
}

@Suite("SwitcherModel")
struct SwitcherModelTests {
    @Test func startsAtThePreviousWindow() {
        #expect(model(mru: [3, 1, 2, 4, 5, 6]).selected == 1)
    }

    @Test func startsAtTheOnlyWindow() {
        let one = LayoutOverview(frames: [7: CGRect(x: 0, y: 0, width: 10, height: 10)], viewports: [])
        let model = SwitcherModel(overview: one, floating: [:], mru: [7], focused: 7)
        #expect(model.order == [7])
        #expect(model.selected == 7)
    }

    @Test func hasNoSelectionWhenEmpty() {
        var model = SwitcherModel(overview: LayoutOverview(frames: [:], viewports: []), floating: [:], mru: [1], focused: nil)
        #expect(model.order.isEmpty)
        #expect(model.selected == nil)
        model.step(1)
        model.move(.left)
        #expect(model.selected == nil)
    }

    @Test func historyComesFirstThenFrameOrder() {
        // 99 is not on screen. Windows 1, 2, 4, 5 are not in the history: top-left first.
        let model = model(mru: [3, 99, 6, 3])
        #expect(model.order == [3, 6, 1, 2, 4, 5])
        #expect(model.selected == 6)
    }

    @Test func floatingWindowsComeLast() {
        let floating: [WindowID: CGRect] = [8: CGRect(x: 0, y: 700, width: 400, height: 100)]
        #expect(model(mru: [2], floating: floating).order == [2, 1, 3, 4, 5, 6, 8])
        #expect(model(mru: [8, 2], floating: floating).order == [8, 2, 1, 3, 4, 5, 6])
    }

    @Test func stepWrapsInBothDirections() {
        var model = model(mru: [3, 6, 1, 2, 4, 5])
        #expect(model.selected == 6)
        model.step(-1)
        #expect(model.selected == 3)
        model.step(-1)
        #expect(model.selected == 5)
        model.step(1)
        #expect(model.selected == 3)
        model.step(1)
        model.step(1)
        model.step(1)
        model.step(1)
        model.step(1)
        #expect(model.selected == 5)
        model.step(1)
        #expect(model.selected == 3)
    }

    @Test func arrowsHopBetweenTheStrips() {
        var model = model(mru: [4, 4])
        model.select(4)
        model.move(.right)
        #expect(model.selected == 5)
        model.move(.down)
        #expect(model.selected == 6)
        model.move(.left)
        #expect(model.selected == 4)
        model.select(6)
        model.move(.right)
        #expect(model.selected == 1)
    }

    @Test func floatingWindowTakesPartInMoves() {
        var model = model(mru: [1], floating: [8: CGRect(x: 0, y: 700, width: 400, height: 100)])
        model.select(1)
        model.move(.down)
        #expect(model.selected == 8)
        model.move(.up)
        #expect(model.selected == 1)
        #expect(model.frames[8] == CGRect(x: 0, y: 700, width: 400, height: 100))
        #expect(model.frames.count == 7)
    }

    @Test func selectIgnoresUnknownWindows() {
        var model = model(mru: [3, 1])
        model.select(42)
        #expect(model.selected == 1)
        model.select(5)
        #expect(model.selected == 5)
    }

    @Test func viewportsComeFromTheOverview() {
        #expect(model(mru: [1]).viewports == [CGRect(x: 0, y: 0, width: 1000, height: 600)])
    }
}

@Suite("Miniature")
struct MiniatureTests {
    @Test func fitsAndCentresALongLayout() {
        let layout = CGRect(x: 0, y: 0, width: 2000, height: 500)
        let transform = Miniature.transform(fitting: [layout], into: CGRect(x: 100, y: 50, width: 800, height: 600), padding: 0, maxScale: 1)
        #expect(transform.a == 0.4)
        #expect(transform.d == 0.4)
        #expect(layout.applying(transform) == CGRect(x: 100, y: 250, width: 800, height: 200))
    }

    @Test func usesTheUnionOfAllRectangles() {
        let rects = [CGRect(x: 0, y: 0, width: 1000, height: 500), CGRect(x: 1000, y: 0, width: 1000, height: 500)]
        let transform = Miniature.transform(fitting: rects, into: CGRect(x: 0, y: 0, width: 900, height: 600), padding: 50, maxScale: 1)
        #expect(transform.a == 0.4)
        #expect(rects[0].applying(transform) == CGRect(x: 50, y: 200, width: 400, height: 200))
    }

    @Test func doesNotEnlargeBeyondMaxScale() {
        let layout = CGRect(x: 0, y: 0, width: 100, height: 50)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(layout.applying(Miniature.transform(fitting: [layout], into: bounds, padding: 0, maxScale: 1)) == CGRect(x: 350, y: 275, width: 100, height: 50))
        #expect(layout.applying(Miniature.transform(fitting: [layout], into: bounds, padding: 0, maxScale: 0.5)) == CGRect(x: 375, y: 287.5, width: 50, height: 25))
    }

    @Test func emptyInputGivesTheIdentity() {
        #expect(Miniature.transform(fitting: [], into: CGRect(x: 0, y: 0, width: 800, height: 600), padding: 10, maxScale: 1) == .identity)
    }

    @Test func rowsPutOneWorkspaceBelowTheOther() {
        let normal = LayoutOverview(
            frames: [1: CGRect(x: 0, y: 0, width: 500, height: 600), 2: CGRect(x: 500, y: 0, width: 500, height: 600)],
            viewports: [CGRect(x: 0, y: 0, width: 1000, height: 600)]
        )
        // A special workspace: its area starts at (100, 50).
        let special = LayoutOverview(
            frames: [3: CGRect(x: 100, y: 50, width: 400, height: 300)],
            viewports: [CGRect(x: 100, y: 50, width: 800, height: 500)]
        )

        let stacked = Miniature.rows([normal, special], spacing: 40)

        #expect(stacked.overview.frames == [
            1: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 600),
            3: CGRect(x: 0, y: 640, width: 400, height: 300),
        ])
        #expect(stacked.overview.viewports == [CGRect(x: 0, y: 0, width: 1000, height: 600), CGRect(x: 0, y: 640, width: 800, height: 500)])
        #expect(stacked.rows == [CGRect(x: 0, y: 0, width: 1000, height: 600), CGRect(x: 0, y: 640, width: 800, height: 500)])
    }

    @Test func aLongStripStaysInItsRow() {
        let strip = LayoutOverview(
            frames: [
                1: CGRect(x: -600, y: 0, width: 500, height: 600),
                2: CGRect(x: 0, y: 0, width: 500, height: 600),
                3: CGRect(x: 1100, y: 0, width: 500, height: 600),
            ],
            viewports: [CGRect(x: 0, y: 0, width: 1000, height: 600)]
        )
        let single = LayoutOverview(frames: [4: CGRect(x: 0, y: 0, width: 1000, height: 600)], viewports: [CGRect(x: 0, y: 0, width: 1000, height: 600)])

        let stacked = Miniature.rows([strip, single], spacing: 40)

        #expect(stacked.overview.frames[1] == CGRect(x: -600, y: 0, width: 500, height: 600))
        #expect(stacked.overview.frames[4] == CGRect(x: 0, y: 640, width: 1000, height: 600))
        #expect(stacked.rows == [CGRect(x: -600, y: 0, width: 2200, height: 600), CGRect(x: 0, y: 640, width: 1000, height: 600)])
    }

    @Test func rowsOfNothingAreEmpty() {
        let stacked = Miniature.rows([], spacing: 40)
        #expect(stacked.overview == LayoutOverview(frames: [:], viewports: []))
        #expect(stacked.rows == [])
    }
}

@Suite("WindowHints")
struct WindowHintsTests {
    private func frames(_ count: Int) -> [WindowID: CGRect] {
        Dictionary(uniqueKeysWithValues: (0..<count).map { (WindowID($0 + 1), CGRect(x: CGFloat($0) * 10, y: 0, width: 10, height: 10)) })
    }

    @Test func labelsFollowReadingOrder() {
        let hints = WindowHints(frames: [
            1: CGRect(x: 100, y: 0, width: 10, height: 10),
            2: CGRect(x: 0, y: 0, width: 10, height: 10),
            3: CGRect(x: 0, y: 50, width: 10, height: 10),
        ])
        #expect(hints.labels == [2: "a", 1: "s", 3: "d"])
    }

    @Test func aLabelNeverUsesTheNavigationKeys() {
        let letters = Set(WindowHints(frames: frames(22)).labels.values)
        #expect(letters.count == 22)
        #expect(letters.isDisjoint(with: ["h", "j", "k", "l"]))
    }

    @Test func aSingleLetterFocusesItsWindow() {
        var hints = WindowHints(frames: frames(3))
        #expect(hints.press("s") == .focus(2))
    }

    @Test func moreWindowsThanLettersNeedTwoLetters() {
        var hints = WindowHints(frames: frames(23))
        #expect(hints.labels[1] == "aa")
        #expect(hints.labels[23] == "sa")
        #expect(hints.press("s") == .pending)
        #expect(hints.typed == "s")
        #expect(hints.press("a") == .focus(23))
        #expect(hints.typed == "")
    }

    @Test func aWrongSecondLetterStartsOver() {
        var hints = WindowHints(frames: frames(23))
        #expect(hints.press("s") == .pending)
        #expect(hints.press("m") == .pending)
        #expect(hints.typed == "")
    }

    @Test func otherKeysAreLeftToTheCaller() {
        var hints = WindowHints(frames: frames(3))
        #expect(hints.press("h") == .ignored)
        #expect(hints.press("enter") == .ignored)
        #expect(hints.press("1") == .ignored)
    }

    @Test func deleteLastRemovesTheTypedLetter() {
        var hints = WindowHints(frames: frames(23))
        _ = hints.press("s")
        hints.deleteLast()
        #expect(hints.typed == "")
    }

    @Test func aGridPutsTheTilesInRowsInTheOrderGiven() {
        let grid = Miniature.grid([7, 8, 9], tile: CGSize(width: 100, height: 60), columns: 2, spacing: 10)
        #expect(grid.frames == [
            7: CGRect(x: 0, y: 0, width: 100, height: 60),
            8: CGRect(x: 110, y: 0, width: 100, height: 60),
            9: CGRect(x: 0, y: 70, width: 100, height: 60),
        ])
        #expect(grid.viewports == [])
    }

    @Test func aGridSelectsTheSecondMostRecentWindowFirst() {
        let grid = Miniature.grid([7, 8, 9], tile: CGSize(width: 100, height: 60), columns: 3)
        let model = SwitcherModel(overview: grid, floating: [:], mru: [7, 8, 9], focused: 7)
        #expect(model.selected == 8)
        #expect(model.order == [7, 8, 9])
    }
}
