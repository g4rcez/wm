import CoreGraphics
import Testing
@testable import Core

struct SnapTests {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func halvesAndQuartersFillTheirPartOfTheArea() {
        #expect(snapFrame(.left, step: 0, in: area) == CGRect(x: 0, y: 0, width: 500, height: 800))
        #expect(snapFrame(.right, step: 0, in: area) == CGRect(x: 500, y: 0, width: 500, height: 800))
        #expect(snapFrame(.top, step: 0, in: area) == CGRect(x: 0, y: 0, width: 1000, height: 400))
        #expect(snapFrame(.bottom, step: 0, in: area) == CGRect(x: 0, y: 400, width: 1000, height: 400))
        #expect(snapFrame(.topLeft, step: 0, in: area) == CGRect(x: 0, y: 0, width: 500, height: 400))
        #expect(snapFrame(.bottomRight, step: 0, in: area) == CGRect(x: 500, y: 400, width: 500, height: 400))
        #expect(snapFrame(.center, step: 0, in: area) == CGRect(x: 200, y: 160, width: 600, height: 480))
    }

    @Test func theSameSideCyclesThroughThirdsAndTwoThirds() {
        #expect(snapFrame(.left, step: 1, in: CGRect(x: 0, y: 0, width: 900, height: 600)) == CGRect(x: 0, y: 0, width: 300, height: 600))
        #expect(snapFrame(.right, step: 2, in: CGRect(x: 0, y: 0, width: 900, height: 600)) == CGRect(x: 300, y: 0, width: 600, height: 600))
        #expect(snapFrame(.left, step: 3, in: area) == snapFrame(.left, step: 0, in: area))
    }

    @Test func theAreaCanStartAnywhere() {
        let offset = CGRect(x: 100, y: 50, width: 1000, height: 800)
        #expect(snapFrame(.right, step: 0, in: offset) == CGRect(x: 600, y: 50, width: 500, height: 800))
        #expect(snapFrame(.bottomLeft, step: 0, in: offset) == CGRect(x: 100, y: 450, width: 500, height: 400))
    }

    @Test func aWindowAtAStepGoesOnToTheNextOne() {
        #expect(nextSnapStep(current: CGRect(x: 0, y: 0, width: 500, height: 800), place: .left, in: area) == 1)
        #expect(nextSnapStep(current: CGRect(x: 2, y: 1, width: 498, height: 800), place: .left, in: area) == 1)
        #expect(nextSnapStep(current: CGRect(x: 0, y: 0, width: 1000.0 * 2 / 3, height: 800), place: .left, in: area) == 0)
    }

    @Test func aWindowSomewhereElseStartsAtTheFirstStep() {
        #expect(nextSnapStep(current: CGRect(x: 120, y: 90, width: 640, height: 420), place: .left, in: area) == 0)
        #expect(nextSnapStep(current: CGRect(x: 0, y: 0, width: 500, height: 400), place: .topLeft, in: area) == 0)
    }
}
