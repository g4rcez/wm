import CoreGraphics
import Testing
@testable import Core

// Two windows exchange slots with `relabel([a: b, b: a])`, which is how `swap` and the mouse drop work.
struct SwapTests {
    @Test func tilingSlotsKeepTheirSize() {
        let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 600))
        var engine = DwindleEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        engine.insert(3, after: 2)

        engine.relabel([1: 3, 3: 1])

        #expect(engine.frames(in: context, focused: 1) == [
            3: CGRect(x: 0, y: 0, width: 500, height: 600),
            2: CGRect(x: 500, y: 0, width: 500, height: 300),
            1: CGRect(x: 500, y: 300, width: 500, height: 300),
        ])
    }

    @Test func scrollingColumnsKeepTheirWidth() {
        let context = LayoutContext(
            viewport: CGRect(x: 0, y: 0, width: 1000, height: 800), gaps: Gaps(), hiddenCorner: CGPoint(x: 4000, y: 3000))
        var engine = ScrollingEngine(settings: Settings())
        engine.insert(1, after: nil)
        engine.insert(2, after: 1)
        let narrowed = engine.perform(.columnWidth(.fraction(0.25)), focused: 2, in: context)
        #expect(narrowed)

        engine.relabel([1: 2, 2: 1])

        #expect(engine.windows == [2, 1])
        #expect(engine.frames(in: context, focused: 2) == [
            2: CGRect(x: 0, y: 0, width: 500, height: 800),
            1: CGRect(x: 500, y: 0, width: 250, height: 800),
        ])
    }
}
