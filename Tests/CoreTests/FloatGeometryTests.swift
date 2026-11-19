import CoreGraphics
import Testing
@testable import Core

struct FloatGeometryTests {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
    private let frame = CGRect(x: 100, y: 100, width: 400, height: 300)

    @Test func aMoveGoesTheGivenNumberOfPoints() {
        #expect(FloatGeometry.moved(frame, .right, by: 40, in: area) == CGRect(x: 140, y: 100, width: 400, height: 300))
        #expect(FloatGeometry.moved(frame, .up, by: 40, in: area) == CGRect(x: 100, y: 60, width: 400, height: 300))
    }

    @Test func aMoveStopsAtTheEdgeOfTheArea() {
        #expect(FloatGeometry.moved(frame, .left, by: 500, in: area) == CGRect(x: 0, y: 100, width: 400, height: 300))
        #expect(FloatGeometry.moved(frame, .down, by: 500, in: area) == CGRect(x: 100, y: 300, width: 400, height: 300))
        #expect(FloatGeometry.moved(frame, .right, by: 900, in: area) == CGRect(x: 600, y: 100, width: 400, height: 300))
    }

    @Test func aWideWindowSitsAtTheStartOfTheArea() {
        let wide = CGRect(x: 50, y: 0, width: 1200, height: 300)
        #expect(FloatGeometry.moved(wide, .right, by: 40, in: area) == CGRect(x: 0, y: 0, width: 1200, height: 300))
    }

    @Test func aResizeKeepsTheTopLeftCorner() {
        #expect(FloatGeometry.resized(frame, .width, by: 50, in: area) == CGRect(x: 100, y: 100, width: 450, height: 300))
        #expect(FloatGeometry.resized(frame, .height, by: -50, in: area) == CGRect(x: 100, y: 100, width: 400, height: 250))
    }

    @Test func smartResizesBothAroundTheCentre() {
        #expect(FloatGeometry.resized(frame, .smart, by: 50, in: area) == CGRect(x: 75, y: 75, width: 450, height: 350))
    }

    @Test func aFractionSetsTheWidthOrTheHeightOfTheArea() {
        #expect(FloatGeometry.sized(frame, .width, fraction: 0.5, in: area) == CGRect(x: 100, y: 100, width: 500, height: 300))
        #expect(FloatGeometry.sized(frame, .height, fraction: 1, in: area) == CGRect(x: 100, y: 0, width: 400, height: 600))
    }

    @Test func cyclingGoesToTheNextFractionAndWrapsAround() {
        #expect(FloatGeometry.nextFraction(of: frame, .width, in: area) == 1.0 / 2)  // 40% is past a third
        #expect(FloatGeometry.nextFraction(of: CGRect(x: 0, y: 0, width: 1000, height: 300), .width, in: area) == 1.0 / 3)
    }

    @Test func aResizeThatWouldLeaveTheAreaPushesTheWindowBack() {
        let low = CGRect(x: 800, y: 400, width: 200, height: 200)
        #expect(FloatGeometry.resized(low, .width, by: 100, in: area) == CGRect(x: 700, y: 400, width: 300, height: 200))
    }

    @Test func aResizeStaysBetweenTheMinimumAndTheArea() {
        #expect(FloatGeometry.resized(frame, .width, by: -1000, in: area).width == 100)
        #expect(FloatGeometry.resized(frame, .height, by: 5000, in: area) == CGRect(x: 100, y: 0, width: 400, height: 600))
    }

    @Test func centeringKeepsTheSize() {
        #expect(FloatGeometry.centered(frame, in: area) == CGRect(x: 300, y: 150, width: 400, height: 300))
    }

    @Test func centeringWorksOnAMonitorThatDoesNotStartAtZero() {
        let right = CGRect(x: 1000, y: 0, width: 1000, height: 600)
        #expect(FloatGeometry.centered(frame, in: right) == CGRect(x: 1300, y: 150, width: 400, height: 300))
    }
}
