import CoreGraphics
import Testing
@testable import Core

// The restore after a reboot: the saved layout is rebuilt under placeholder ids, and each real window takes the place of one.
struct RebootRestoreTests {
    private let context = LayoutContext(viewport: CGRect(x: 0, y: 0, width: 1000, height: 600), gaps: Gaps())

    private func placeholders(_ ids: [WindowID]) -> [WindowID: WindowID] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, Placeholder.id(for: $0)) })
    }

    @Test func aScrollingLayoutKeepsItsSizesAndStacksWhenTheWindowsGetNewIds() {
        var original = ScrollingEngine(settings: Settings())
        original.insert(10, after: nil)
        original.insert(11, after: 10)
        original.insert(12, after: 11)
        _ = original.perform(.columnWidth(.fraction(0.8)), focused: 10, in: context)
        _ = original.perform(.stack(.left), focused: 12, in: context)
        let before = original.frames(in: context, focused: 10)

        var restored = makeEngine(restoring: original.state, settings: Settings())
        restored.relabel(placeholders([10, 11, 12]))
        // The apps open in another order, with new ids.
        restored.relabel([Placeholder.id(for: 12): 300])
        restored.relabel([Placeholder.id(for: 10): 100])
        restored.relabel([Placeholder.id(for: 11): 200])
        let after = restored.frames(in: context, focused: 100)

        #expect(after[100] == before[10])
        #expect(after[200] == before[11])
        #expect(after[300] == before[12])
    }

    @Test func aTilingLayoutKeepsItsSplitsWhenTheWindowsGetNewIds() {
        var original = DwindleEngine(settings: Settings())
        original.insert(1, after: nil)
        original.insert(2, after: 1)
        original.insert(3, after: 2)
        _ = original.perform(.splitRatio(0.7, relative: false), focused: 1, in: context)
        let before = original.frames(in: context, focused: 1)

        var restored = makeEngine(restoring: original.state, settings: Settings())
        restored.relabel(placeholders([1, 2, 3]))
        restored.relabel([Placeholder.id(for: 1): 51, Placeholder.id(for: 2): 52, Placeholder.id(for: 3): 53])
        let after = restored.frames(in: context, focused: 51)

        #expect(after[51] == before[1])
        #expect(after[52] == before[2])
        #expect(after[53] == before[3])
    }

    @Test func aWindowThatNeverComesBackLeavesAndTheOthersCloseTheGap() {
        var original = ScrollingEngine(settings: Settings())
        original.insert(10, after: nil)
        original.insert(11, after: 10)
        original.insert(12, after: 11)

        var restored = makeEngine(restoring: original.state, settings: Settings())
        restored.relabel(placeholders([10, 11, 12]))
        restored.relabel([Placeholder.id(for: 10): 100, Placeholder.id(for: 12): 300])
        // The app of the middle window never opens: its place is given up.
        for id in restored.windows where Placeholder.isPlaceholder(id) { restored.remove(id) }

        #expect(restored.windows == [100, 300])
        let frames = restored.frames(in: context, focused: 100)
        #expect(frames[100] == CGRect(x: 0, y: 0, width: 500, height: 600))
        #expect(frames[300] == CGRect(x: 500, y: 0, width: 500, height: 600))
    }
}
