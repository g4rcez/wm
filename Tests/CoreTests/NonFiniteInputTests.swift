import CoreGraphics
import Testing
@testable import Core

/// A NaN or an infinity must never reach a layout: it gets through every `min`/`max` clamp, then stays in the saved state
/// (which cannot be written as JSON) and in the animations (which never arrive).
struct NonFiniteInputTests {
    private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 800))
    private static let bad: [CGFloat] = [.nan, .infinity, -.infinity]

    private static func commands(_ value: CGFloat) -> [LayoutCommand] {
        [
            .resize(.width, value), .resize(.height, value), .resize(.smart, value),
            .resizeEdge(.left, value), .resizeEdge(.right, value), .resizeEdge(.up, value), .resizeEdge(.down, value),
            .resizeDirection(.right, value), .resizeDirection(.down, value), .scroll(value),
            .splitRatio(Double(value), relative: false), .splitRatio(Double(value), relative: true),
            .masterRatio(Double(value), relative: false), .masterRatio(Double(value), relative: true),
            .columnWidth(.fraction(Double(value))), .windowHeight(.fraction(Double(value))),
        ]
    }

    private func engines() -> [any LayoutEngine] {
        var list: [any LayoutEngine] = [
            DwindleEngine(settings: Settings()), ScrollingEngine(settings: Settings()), MasterEngine(settings: Settings()),
            MonocleEngine(settings: Settings()),
        ]
        for index in list.indices {
            for id: WindowID in 1...3 { list[index].insert(id, after: id == 1 ? nil : id - 1) }
            // A stack in the scrolling strip, so the cross-axis resizes have something to change.
            _ = list[index].perform(.stack(.left), focused: 3, in: context)
        }
        return list
    }

    @Test func aCommandWithANonFiniteNumberIsNotFinite() {
        for value in Self.bad {
            let refused = Self.commands(value).filter(\.isFinite)
            #expect(refused.isEmpty)
        }
        let finite = Self.commands(40).filter { !$0.isFinite }
        #expect(finite.isEmpty)
        #expect(LayoutCommand.balance.isFinite)
    }

    @Test func everyEngineRefusesNonFiniteNumbersAndKeepsFiniteFrames() {
        for var engine in engines() {
            let before = engine.frames(in: context, focused: 2)
            for value in Self.bad {
                for command in Self.commands(value) {
                    let changed = engine.perform(command, focused: 2, in: context)
                    #expect(!changed, "\(type(of: engine)) took \(command)")
                }
            }
            let after = engine.frames(in: context, focused: 2)
            #expect(after == before, "\(type(of: engine)) changed")
            let broken = after.values.filter { !$0.isFinite }
            #expect(broken.isEmpty)
        }
    }

    @Test func theAnimatorIgnoresANonFiniteTarget() {
        var animator = Animator()
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        animator.setTargets([1: frame])
        animator.setTargets([1: CGRect(x: CGFloat.nan, y: 0, width: CGFloat.nan, height: 100)])
        #expect(animator.frames[1] == nil || animator.frames[1]!.isFinite)
        #expect(animator.isSettled)
        let moved = animator.step(dt: 1.0 / 60)
        #expect(moved.isEmpty)
    }

    @Test func theAnimatorIgnoresANonFinitePlaceAndSeed() {
        var animator = Animator()
        let goal = CGRect(x: 100, y: 0, width: 100, height: 100)
        animator.seed(1, at: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100))
        animator.setTargets([1: goal])
        #expect(animator.frames[1] == goal)
        animator.place(1, at: CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100))
        #expect(animator.frames[1] == goal)
        animator.start(1, from: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100))
        #expect(animator.frames[1] == goal)
        #expect(animator.isSettled)
    }
}
