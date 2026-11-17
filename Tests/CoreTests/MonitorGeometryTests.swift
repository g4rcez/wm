import CoreGraphics
import Testing
@testable import Core

struct MonitorGeometryTests {
    // Laptop on the left, a larger monitor on its right, a small one above the laptop.
    private let monitors = [
        MonitorFrame(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
        MonitorFrame(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440)),
        MonitorFrame(id: 3, frame: CGRect(x: 0, y: -600, width: 1024, height: 600)),
    ]

    @Test func adjacentMonitorInEachDirection() {
        #expect(MonitorGeometry.adjacent(to: 1, .right, in: monitors) == 2)
        #expect(MonitorGeometry.adjacent(to: 1, .up, in: monitors) == 3)
        #expect(MonitorGeometry.adjacent(to: 3, .down, in: monitors) == 1)
    }

    @Test func leftOfTheTwoMonitorsPicksTheNearerOne() {
        #expect(MonitorGeometry.adjacent(to: 2, .left, in: monitors) == 1)
    }

    @Test func aMonitorAboveIsNotToTheLeft() {
        #expect(MonitorGeometry.adjacent(to: 2, .up, in: monitors) == nil)
        #expect(MonitorGeometry.adjacent(to: 3, .right, in: monitors) == nil)
    }

    @Test func noMonitorBeyondTheEdge() {
        #expect(MonitorGeometry.adjacent(to: 1, .left, in: monitors) == nil)
        #expect(MonitorGeometry.adjacent(to: 2, .right, in: monitors) == nil)
    }

    @Test func cycleGoesLeftToRightAndWraps() {
        #expect(MonitorGeometry.cycle(from: 3, step: 1, in: monitors) == 1)
        #expect(MonitorGeometry.cycle(from: 2, step: 1, in: monitors) == 3)
        #expect(MonitorGeometry.cycle(from: 3, step: -1, in: monitors) == 2)
    }

    @Test func cycleNeedsMoreThanOneMonitor() {
        #expect(MonitorGeometry.cycle(from: 1, step: 1, in: [monitors[0]]) == nil)
    }

    @Test func pointBelongsToTheMonitorThatContainsIt() {
        #expect(MonitorGeometry.monitor(containing: CGPoint(x: 2000, y: 700), in: monitors) == 2)
        #expect(MonitorGeometry.monitor(containing: CGPoint(x: 500, y: -100), in: monitors) == 3)
        #expect(MonitorGeometry.monitor(containing: CGPoint(x: -50, y: 10), in: monitors) == nil)
    }

    @Test func hiddenCornerOfOneMonitor() {
        #expect(MonitorGeometry.hiddenCorner(of: [CGRect(x: 0, y: 0, width: 1512, height: 982)]) == CGPoint(x: 1511, y: 981))
    }

    @Test func hiddenCornerOfTwoMonitorsIsTheOuterBottomRight() {
        let frames = monitors.map(\.frame)
        #expect(MonitorGeometry.hiddenCorner(of: frames) == CGPoint(x: 4071, y: 1439))
    }

    private let area = CGRect(x: 0, y: 25, width: 1920, height: 1055)

    @Test func aWindowMostlyOutsideComesBackInsideTheArea() {
        let frame = CGRect(x: 1900, y: 100, width: 400, height: 300)
        #expect(MonitorGeometry.rescued(frame, in: area) == CGRect(x: 1520, y: 100, width: 400, height: 300))
    }

    @Test func aWindowThatIsHalfInsideStaysWhereItIs() {
        #expect(MonitorGeometry.rescued(CGRect(x: 1720, y: 100, width: 400, height: 300), in: area) == nil)
        #expect(MonitorGeometry.rescued(CGRect(x: 100, y: 100, width: 400, height: 300), in: area) == nil)
    }

    @Test func aWindowLargerThanTheAreaIsCutDownToIt() {
        let frame = CGRect(x: 5000, y: 5000, width: 3000, height: 2000)
        #expect(MonitorGeometry.rescued(frame, in: area) == CGRect(x: 0, y: 25, width: 1920, height: 1055))
    }

    @Test func clampedMovesAWindowTheShortestWayInside() {
        #expect(MonitorGeometry.clamped(CGRect(x: -50, y: 2000, width: 400, height: 300), in: area) == CGRect(x: 0, y: 780, width: 400, height: 300))
    }

    @Test func aWindowKeepsItsSizeAndItsRelativePlaceOnAnotherMonitor() {
        let old = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let new = CGRect(x: 1000, y: 0, width: 2000, height: 1600)
        #expect(MonitorGeometry.translated(CGRect(x: 100, y: 100, width: 400, height: 300), from: old, to: new) == CGRect(x: 1200, y: 200, width: 400, height: 300))
    }

    @Test func aWindowIsCutDownToASmallerMonitor() {
        let old = CGRect(x: 0, y: 0, width: 2000, height: 1600)
        let new = CGRect(x: 2000, y: 0, width: 1000, height: 800)
        #expect(MonitorGeometry.translated(CGRect(x: 0, y: 0, width: 1500, height: 1000), from: old, to: new) == CGRect(x: 2000, y: 0, width: 1000, height: 800))
    }

    // MARK: mouse drags

    @Test func aDragTakesTheEdgesOnTheSideOfThePointer() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let topLeft = MonitorGeometry.nearestEdges(of: frame, to: CGPoint(x: 150, y: 120))
        #expect(topLeft.horizontal == .left)
        #expect(topLeft.vertical == .up)
        let bottomRight = MonitorGeometry.nearestEdges(of: frame, to: CGPoint(x: 450, y: 380))
        #expect(bottomRight.horizontal == .right)
        #expect(bottomRight.vertical == .down)
    }

    @Test func draggingTheRightAndBottomEdgesGrowsTheWindow() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let grown = MonitorGeometry.resized(frame, edges: (.right, .down), by: CGPoint(x: 50, y: 20), minimum: CGSize(width: 120, height: 80))
        #expect(grown == CGRect(x: 100, y: 100, width: 450, height: 320))
    }

    @Test func draggingTheLeftAndTopEdgesKeepsTheOppositeEdgesInPlace() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let grown = MonitorGeometry.resized(frame, edges: (.left, .up), by: CGPoint(x: -50, y: -20), minimum: CGSize(width: 120, height: 80))
        #expect(grown == CGRect(x: 50, y: 80, width: 450, height: 320))
    }

    @Test func aWindowStopsShrinkingAtTheMinimumSize() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let small = MonitorGeometry.resized(frame, edges: (.left, .down), by: CGPoint(x: 900, y: -900), minimum: CGSize(width: 120, height: 80))
        #expect(small == CGRect(x: 380, y: 100, width: 120, height: 80))
    }
}
