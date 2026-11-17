import CoreGraphics
import Testing
@testable import Core

struct OverviewLayoutTests {
    private let screen = CGSize(width: 1000, height: 500)

    private func row(_ frames: [WindowID: CGRect], viewports: [CGRect] = [], size: CGSize = CGSize(width: 1000, height: 500), origin: CGPoint = .zero) -> OverviewRowInput {
        OverviewRowInput(frames: frames, viewports: viewports, screen: size, origin: origin)
    }

    @Test func aSlotIsTheScreenOfItsWorkspaceScaledAndCentered() {
        let geometry = OverviewLayout.compute([row([:])], screen: screen, zoom: 0.5, gap: 40)
        #expect(geometry.slots[0].frame == CGRect(x: 250, y: 125, width: 500, height: 250))
    }

    @Test func theSlotsFollowEachOtherDownTheWorldWithAGap() {
        let geometry = OverviewLayout.compute([row([:]), row([:]), row([:])], screen: screen, zoom: 0.5, gap: 40)
        #expect(geometry.slots.map(\.frame.minY) == [125, 415, 705])
    }

    @Test func eachSlotCanBePutInTheMiddleOfTheScreen() {
        let geometry = OverviewLayout.compute([row([:]), row([:]), row([:])], screen: screen, zoom: 0.5, gap: 40)
        #expect(geometry.centers == [0, 290, 580])
        #expect(geometry.scrollRange == 0...580)
    }

    @Test func theWorldHasRoomToCenterTheLastSlot() {
        let geometry = OverviewLayout.compute([row([:]), row([:])], screen: screen, zoom: 0.5, gap: 40)
        // The last slot ends at 665; half of the screen minus half a slot (125) stays below it.
        #expect(geometry.worldHeight == 790)
    }

    @Test func aScrollIsKeptInsideTheRange() {
        let geometry = OverviewLayout.compute([row([:]), row([:])], screen: screen, zoom: 0.5, gap: 40)
        #expect(geometry.clampedScroll(-30) == 0)
        #expect(geometry.clampedScroll(100) == 100)
        #expect(geometry.clampedScroll(900) == 290)
    }

    @Test func aTileIsMovedAndScaledIntoItsSlot() {
        let geometry = OverviewLayout.compute([row([1: CGRect(x: 100, y: 100, width: 400, height: 300)])], screen: screen, zoom: 0.5, gap: 40)
        #expect(geometry.cards[1] == CGRect(x: 300, y: 175, width: 200, height: 150))
    }

    @Test func aColumnOutsideTheScreenSticksOutOfTheSlot() {
        let geometry = OverviewLayout.compute(
            [row([1: CGRect(x: 1000, y: 0, width: 500, height: 500)], viewports: [CGRect(x: 0, y: 0, width: 1000, height: 500)])],
            screen: screen, zoom: 0.5, gap: 40)
        #expect(geometry.cards[1] == CGRect(x: 750, y: 125, width: 250, height: 250))
        #expect(geometry.slots[0].viewports == [CGRect(x: 250, y: 125, width: 500, height: 250)])
    }

    @Test func aStripThatIsScrolledKeepsItsOffsetFromTheScreen() {
        // The screen starts at x = 600 of the strip: a column at x = 600 is at the left edge of the slot.
        let geometry = OverviewLayout.compute(
            [row([1: CGRect(x: 600, y: 0, width: 500, height: 500)], origin: CGPoint(x: 600, y: 0))], screen: screen, zoom: 0.5, gap: 40)
        #expect(geometry.cards[1] == CGRect(x: 250, y: 125, width: 250, height: 250))
    }

    @Test func aMonitorWithAnotherSizeGetsASlotOfItsOwnShape() {
        let geometry = OverviewLayout.compute([row([:], size: CGSize(width: 600, height: 800))], screen: screen, zoom: 0.5, gap: 40)
        #expect(geometry.slots[0].frame == CGRect(x: 350, y: 50, width: 300, height: 400))
    }

    @Test func theSmallestCardUnderAPointWins() {
        let geometry = OverviewLayout.compute(
            [row([1: CGRect(x: 0, y: 0, width: 1000, height: 500), 2: CGRect(x: 200, y: 100, width: 200, height: 100)])],
            screen: screen, zoom: 0.5, gap: 40)
        #expect(geometry.card(at: CGPoint(x: 400, y: 200)) == 2)
        #expect(geometry.card(at: CGPoint(x: 700, y: 300)) == 1)
        #expect(geometry.card(at: CGPoint(x: 10, y: 10)) == nil)
    }

    @Test func aPointBetweenTwoSlotsBelongsToTheNearerOne() {
        let geometry = OverviewLayout.compute([row([:]), row([:])], screen: screen, zoom: 0.5, gap: 40)
        // Slot 0 ends at 375 and slot 1 starts at 415: the gap is 375 to 415, and 395 is its middle.
        #expect(geometry.slotIndex(at: CGPoint(x: 500, y: 390)) == 0)
        #expect(geometry.slotIndex(at: CGPoint(x: 500, y: 400)) == 1)
        #expect(geometry.slotIndex(at: CGPoint(x: 500, y: 20)) == nil)
    }

    @Test func aCardKnowsItsSlot() {
        let geometry = OverviewLayout.compute(
            [row([1: CGRect(x: 0, y: 0, width: 100, height: 100)]), row([2: CGRect(x: 0, y: 0, width: 100, height: 100)])],
            screen: screen, zoom: 0.5, gap: 40)
        #expect(geometry.slotIndex(ofCard: 1) == 0)
        #expect(geometry.slotIndex(ofCard: 2) == 1)
        #expect(geometry.slotIndex(ofCard: 3) == nil)
    }

    @Test func noWorkspacesGiveAnEmptyGeometry() {
        let geometry = OverviewLayout.compute([], screen: screen, zoom: 0.5, gap: 40)
        #expect(geometry.slots.isEmpty)
        #expect(geometry.scrollRange == 0...0)
        #expect(geometry.worldHeight == 500)
    }

    // A strip of three columns, each as wide as the screen's half: 500 points in the strip, 250 in the slot.
    private func strip() -> OverviewGeometry {
        OverviewLayout.compute(
            [row(
                [1: CGRect(x: 0, y: 0, width: 500, height: 500), 2: CGRect(x: 1000, y: 0, width: 500, height: 500), 3: CGRect(x: 2000, y: 0, width: 500, height: 500)],
                viewports: [CGRect(x: 0, y: 0, width: 1000, height: 500)])],
            screen: screen, zoom: 0.5, gap: 40)
    }

    @Test func aCardInTheMiddleOfAWideStripMovesToTheMiddleOfTheScreen() {
        // Card 2 is at x 750...1000, so its middle is 875 and the screen's middle is 500.
        #expect(strip().panToCenter(2) == -375)
    }

    @Test func aCardAtTheEndOfAWideStripStopsWhereTheStripEndsOnTheScreen() {
        // The last card would need -875, but the strip may not end more than 24 points inside the screen: 1000 - 24 - 1500.
        #expect(strip().panToCenter(3) == -524)
        // The first card would need +125, but the strip may not start more than 24 points inside: 24 - 250.
        #expect(strip().panToCenter(1) == -226)
    }

    @Test func aLayoutThatFitsTheScreenIsNotPanned() {
        let geometry = OverviewLayout.compute([row([1: CGRect(x: 0, y: 0, width: 500, height: 500), 2: CGRect(x: 500, y: 0, width: 500, height: 500)])], screen: screen, zoom: 0.5, gap: 40)
        #expect(geometry.panToCenter(1) == 0)
    }

    @Test func panningMovesTheCardsAndTheViewportOfThatSlotOnly() {
        var geometry = OverviewLayout.compute(
            [row([1: CGRect(x: 0, y: 0, width: 100, height: 100)], viewports: [CGRect(x: 0, y: 0, width: 1000, height: 500)]), row([2: CGRect(x: 0, y: 0, width: 100, height: 100)])],
            screen: screen, zoom: 0.5, gap: 40)
        geometry.pan(slot: 0, by: -100)
        #expect(geometry.cards[1] == CGRect(x: 150, y: 125, width: 50, height: 50))
        #expect(geometry.slots[0].viewports == [CGRect(x: 150, y: 125, width: 500, height: 250)])
        #expect(geometry.cards[2] == CGRect(x: 250, y: 415, width: 50, height: 50))
    }

    @Test func aPannedCardNeedsNoMoreMove() {
        var geometry = strip()
        geometry.pan(slot: 0, by: geometry.panToCenter(2))
        #expect(geometry.panToCenter(2) == 0)
        #expect(geometry.cards[2]?.midX == 500)
    }
}
