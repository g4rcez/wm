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

    @Test func nativeDesktopNamesHavePrefixOnlyWithSeveralDisplays() {
        #expect(NativeWorkspaceName.desktops(displayNumber: 1, displayCount: 1, desktopCount: 3) == ["1", "2", "3"])
        #expect(NativeWorkspaceName.desktops(displayNumber: 2, displayCount: 2, desktopCount: 2) == ["2.1", "2.2"])
    }

    @Test func virtualRowNames() {
        #expect(NativeWorkspaceName.row(of: "2", 1) == "2")
        #expect(NativeWorkspaceName.row(of: "2", 3) == "2/3")
        #expect(NativeWorkspaceName.row(of: "2.1", 2) == "2.1/2")
    }

    @Test func desktopAndRowAreRecoveredFromAName() {
        #expect(NativeWorkspaceName.desktop(of: "2/3") == "2")
        #expect(NativeWorkspaceName.rowNumber(of: "2/3") == 3)
        #expect(NativeWorkspaceName.desktop(of: "2.1") == "2.1")
        #expect(NativeWorkspaceName.rowNumber(of: "2.1") == 1)
    }
}
