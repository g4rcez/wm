import CoreGraphics
import Testing
@testable import Core

struct AnimatorTests {
    private let start = CGRect(x: 0, y: 0, width: 100, height: 100)
    private let goal = CGRect(x: 100, y: 0, width: 100, height: 100)

    @Test func unseenWindowStartsAtItsTarget() {
        var animator = Animator()
        animator.setTargets([1: goal])

        #expect(animator.frames == [1: goal])
        #expect(animator.isSettled)
        #expect(animator.step(dt: 0.016).isEmpty)
    }

    @Test func movesAPartOfTheWayEachStep() {
        var animator = Animator(rate: 20)
        animator.setTargets([1: start])
        animator.setTargets([1: goal])

        // A spring starts at rest: after 1/60 s with rate 20 the window is 4.46 points into the 100 point move
        // (the offset is (-100 - 2000/60) * exp(-1/3) = -95.54).
        let moved = animator.step(dt: 1.0 / 60)

        #expect(moved[1]!.minX > 4.4 && moved[1]!.minX < 4.5)
        #expect(!animator.isSettled)
    }

    @Test func aLongMoveStartsSlowlyAtRate30() {
        var animator = Animator(rate: 30)
        animator.setTargets([1: CGRect(x: 0, y: 0, width: 100, height: 100)])
        animator.setTargets([1: CGRect(x: 600, y: 0, width: 100, height: 100)])

        // (-600 - 18000/60) * exp(-0.5) = -545.88, so 54.12 of the 600 points. The old curve covered 236 points.
        let moved = animator.step(dt: 1.0 / 60)

        #expect(moved[1]!.minX > 54 && moved[1]!.minX < 54.2)
    }

    @Test func widthAndHeightFollowTheSameCurve() {
        var animator = Animator(rate: 20)
        animator.setTargets([1: CGRect(x: 0, y: 0, width: 100, height: 100)])
        animator.setTargets([1: CGRect(x: 0, y: 0, width: 200, height: 300)])

        let moved = animator.step(dt: 1.0 / 60)

        #expect(moved[1]!.width > 104.4 && moved[1]!.width < 104.5)
        #expect(moved[1]!.height > 108.9 && moved[1]!.height < 109.0)
    }

    @Test func aNewTargetKeepsTheSpeed() {
        var animator = Animator(rate: 20)
        animator.setTargets([1: start])
        animator.setTargets([1: goal])
        _ = animator.step(dt: 1.0 / 60)

        // The window moves right at 477.7 points per second. A new target further right keeps that speed:
        // x = 200 + (-195.54 + (477.69 - 20 * 195.54) / 60) * exp(-1/3) = 18.89. From rest it would be 13.19.
        animator.setTargets([1: CGRect(x: 200, y: 0, width: 100, height: 100)])
        let moved = animator.step(dt: 1.0 / 60)

        #expect(moved[1]!.minX > 18.8 && moved[1]!.minX < 19.0)
    }

    @Test func aPlacedWindowStartsFromRestAgain() {
        var animator = Animator(rate: 20)
        animator.setTargets([1: start])
        animator.setTargets([1: goal])
        _ = animator.step(dt: 1.0 / 60)

        animator.place(1, at: start)
        let moved = animator.step(dt: 1.0 / 60)

        #expect(moved[1]!.minX > 4.4 && moved[1]!.minX < 4.5)
    }

    @Test func arrivesAndThenStopsReporting() {
        var animator = Animator(rate: 20)
        animator.setTargets([1: start])
        animator.setTargets([1: goal])

        for _ in 0..<200 { _ = animator.step(dt: 1.0 / 60) }

        #expect(animator.frames == [1: goal])
        #expect(animator.isSettled)
        #expect(animator.step(dt: 1.0 / 60).isEmpty)
    }

    @Test func aLongStallDoesNotJumpFurtherThanOneThirtiethOfASecond() {
        var animator = Animator(rate: 20)
        animator.setTargets([1: start])
        animator.setTargets([1: goal])

        let moved = animator.step(dt: 5)

        // The step is cut to 1/30 s: 100 + (-100 - 2000/30) * exp(-2/3) = 14.43.
        #expect(moved[1]!.minX > 14.4 && moved[1]!.minX < 14.5)
    }

    @Test func snappedWindowJumpsToItsTarget() {
        var animator = Animator()
        animator.setTargets([1: start])
        animator.setTargets([1: goal], snap: [1])

        #expect(animator.frames == [1: goal])
    }

    @Test func disabledAnimatorSnapsEverything() {
        var animator = Animator(enabled: false)
        animator.setTargets([1: start])
        animator.setTargets([1: goal])

        #expect(animator.frames == [1: goal])
    }

    @Test func removedWindowIsForgotten() {
        var animator = Animator()
        animator.setTargets([1: start, 2: goal])
        animator.setTargets([2: goal])

        #expect(animator.frames == [2: goal])
    }

    @Test func seededWindowAnimatesFromItsRealFrame() {
        var animator = Animator(rate: 20)
        animator.seed(1, at: start)
        animator.setTargets([1: goal])

        #expect(animator.frames == [1: start])
        #expect(!animator.isSettled)
    }

    @Test func placedWindowAnimatesFromWhereItReallyIs() {
        var animator = Animator(rate: 20)
        animator.setTargets([1: start])
        animator.place(1, at: goal)

        #expect(animator.frames == [1: goal])
        #expect(!animator.isSettled)
    }

    @Test func aWindowThatStartsFromAFrameMovesFromThere() {
        var animator = Animator(rate: 20)
        animator.setTargets([1: goal])
        animator.start(1, from: CGRect(x: 900, y: 0, width: 100, height: 100))

        #expect(animator.frames[1]?.minX == 900)
        let moved = animator.step(dt: 1.0 / 60)
        #expect(moved[1]!.minX < 900 && moved[1]!.minX > 100)
        #expect(!animator.isSettled)
    }

    @Test func aWindowWithItsOwnRateMovesAtThatRate() {
        var slow = Animator(rate: 20)
        slow.setTargets([1: goal])
        slow.start(1, from: start)
        var fast = Animator(rate: 20)
        fast.setTargets([1: goal])
        fast.start(1, from: start, rate: 60)

        let slowStep = slow.step(dt: 1.0 / 60)[1]!.minX
        let fastStep = fast.step(dt: 1.0 / 60)[1]!.minX
        #expect(fastStep > slowStep)
    }

    @Test func theOwnRateEndsWhenTheWindowArrives() {
        var animator = Animator(rate: 20)
        animator.setTargets([1: goal])
        animator.start(1, from: start, rate: 200)
        for _ in 0..<600 where !animator.isSettled { _ = animator.step(dt: 1.0 / 60) }
        #expect(animator.isSettled)

        // The next move of this window uses the rate of the animator again.
        animator.setTargets([1: start])
        let again = animator.step(dt: 1.0 / 60)[1]!.minX
        var reference = Animator(rate: 20)
        reference.setTargets([1: goal])
        reference.setTargets([1: start])
        #expect(abs(again - reference.step(dt: 1.0 / 60)[1]!.minX) < 1e-9)
    }

    @Test func startDoesNothingWhenAnimationsAreOff() {
        var animator = Animator(rate: 20, enabled: false)
        animator.setTargets([1: goal])
        animator.start(1, from: start)
        #expect(animator.frames == [1: goal])
    }
}
