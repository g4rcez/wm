import CoreGraphics
import Testing
@testable import Core

struct FloatDropTests {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
    private let size = CGSize(width: 300, height: 200)
    private let others: [WindowID: CGRect] = [2: CGRect(x: 400, y: 200, width: 200, height: 200)]

    private func target(_ x: CGFloat, _ y: CGFloat, edges: Bool = true, grouping: Bool = false) -> FloatDrop? {
        FloatDrop.target(pointer: CGPoint(x: x, y: y), dragged: 1, size: size, others: others, area: area, edges: edges, grouping: grouping)
    }

    @Test func theSidesOfTheScreenSnapAHalfTheTopFillsAndCornersAQuarter() {
        #expect(target(4, 300) == .frame(CGRect(x: 0, y: 0, width: 500, height: 600)))
        #expect(target(996, 300) == .frame(CGRect(x: 500, y: 0, width: 500, height: 600)))
        #expect(target(500, 4) == .frame(area))
        #expect(target(4, 10) == .frame(CGRect(x: 0, y: 0, width: 500, height: 300)))
        #expect(target(990, 595) == .frame(CGRect(x: 500, y: 300, width: 500, height: 300)))
    }

    @Test func withMacOSTilingTheEdgesAreLeftToIt() {
        #expect(target(4, 300, edges: false) == nil)
    }

    @Test func besideAnotherWindowItGoesAgainstThatSide() {
        // The right side of window 2: x 400 + 200.
        #expect(target(590, 300) == .frame(CGRect(x: 600, y: 200, width: 300, height: 200)))
        #expect(target(410, 300) == .frame(CGRect(x: 100, y: 200, width: 300, height: 200)))
    }

    @Test func theMiddleGroupsOnlyWithCmd() {
        #expect(target(500, 300) == nil)
        #expect(target(500, 300, grouping: true) == .group(2))
    }

    @Test func anywhereElseItStaysWhereItIsLetGo() {
        #expect(target(200, 300) == nil)
    }
}
