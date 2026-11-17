import Testing
@testable import Scripting

struct BindTrackerTests {
    private let a = BindAction.command("a")
    private let b = BindAction.command("b")
    private let c = BindAction.command("c")

    @Test func aPlainBindRunsOnEveryEventOfAHeldKey() {
        var tracker = BindTracker()
        let lookup = BindLookup(press: a)
        #expect(tracker.keyDown(keyCode: 4, isRepeat: false, lookup: lookup) == (true, [.run(a)]))
        #expect(tracker.keyDown(keyCode: 4, isRepeat: true, lookup: lookup) == (true, [.run(a)]))
        #expect(tracker.keyUp(keyCode: 4) == (false, []))
    }

    @Test func aHoldBindRunsOnRepeatsAndThePressBindOnlyWhenTheKeyGoesDown() {
        var tracker = BindTracker()
        let lookup = BindLookup(press: a, hold: b)
        #expect(tracker.keyDown(keyCode: 4, isRepeat: false, lookup: lookup) == (true, [.run(a)]))
        #expect(tracker.keyDown(keyCode: 4, isRepeat: true, lookup: lookup) == (true, [.run(b)]))
        #expect(tracker.keyDown(keyCode: 4, isRepeat: true, lookup: lookup) == (true, [.run(b)]))
    }

    @Test func aHoldBindStillWinsOverANoRepeatPressBind() {
        var tracker = BindTracker()
        let lookup = BindLookup(press: a, hold: b, noRepeat: true)
        #expect(tracker.keyDown(keyCode: 4, isRepeat: true, lookup: lookup) == (true, [.run(b)]))
    }

    @Test func aHoldBindWorksWithAReleaseBind() {
        var tracker = BindTracker()
        let lookup = BindLookup(press: a, release: c, hold: b)
        #expect(tracker.keyDown(keyCode: 4, isRepeat: false, lookup: lookup) == (true, [.run(a)]))
        #expect(tracker.keyDown(keyCode: 4, isRepeat: true, lookup: lookup) == (true, [.run(b)]))
        #expect(tracker.keyUp(keyCode: 4) == (true, [.run(c)]))
    }

    @Test func aBindThatDoesNotRepeatRunsOncePerPress() {
        var tracker = BindTracker()
        let lookup = BindLookup(press: a, noRepeat: true)
        #expect(tracker.keyDown(keyCode: 4, isRepeat: false, lookup: lookup) == (true, [.run(a)]))
        #expect(tracker.keyDown(keyCode: 4, isRepeat: true, lookup: lookup) == (true, []))
    }

    @Test func aKeyWithNoBindPassesThrough() {
        var tracker = BindTracker()
        #expect(tracker.keyDown(keyCode: 4, isRepeat: false, lookup: BindLookup()) == (false, []))
        #expect(tracker.keyUp(keyCode: 4) == (false, []))
    }

    @Test func aReleaseBindRunsWhenTheKeyComesUp() {
        var tracker = BindTracker()
        let lookup = BindLookup(release: b)
        #expect(tracker.keyDown(keyCode: 4, isRepeat: false, lookup: lookup) == (true, []))
        #expect(tracker.keyDown(keyCode: 4, isRepeat: true, lookup: lookup) == (true, []))
        #expect(tracker.keyUp(keyCode: 4) == (true, [.run(b)]))
        // The key is free again: a second release does nothing.
        #expect(tracker.keyUp(keyCode: 4) == (false, []))
    }

    @Test func aPressAndAReleaseBindOnOneChordBothRun() {
        var tracker = BindTracker()
        let lookup = BindLookup(press: a, release: b)
        #expect(tracker.keyDown(keyCode: 4, isRepeat: false, lookup: lookup) == (true, [.run(a)]))
        #expect(tracker.keyUp(keyCode: 4) == (true, [.run(b)]))
    }

    @Test func aShortPressRunsThePressBindWhenTheKeyComesUp() {
        var tracker = BindTracker()
        let lookup = BindLookup(press: a, longPress: c)
        #expect(tracker.keyDown(keyCode: 4, isRepeat: false, lookup: lookup) == (true, [.startLongPress(keyCode: 4)]))
        #expect(tracker.keyUp(keyCode: 4) == (true, [.cancelLongPress(keyCode: 4), .run(a)]))
    }

    @Test func aLongPressRunsTheLongBindAndNotThePressBind() {
        var tracker = BindTracker()
        let lookup = BindLookup(press: a, longPress: c)
        _ = tracker.keyDown(keyCode: 4, isRepeat: false, lookup: lookup)
        #expect(tracker.keyDown(keyCode: 4, isRepeat: true, lookup: lookup) == (true, []))
        #expect(tracker.longPressElapsed(keyCode: 4) == [.run(c)])
        // It runs once, and letting go afterwards runs nothing more.
        #expect(tracker.longPressElapsed(keyCode: 4) == [])
        #expect(tracker.keyUp(keyCode: 4) == (true, [.cancelLongPress(keyCode: 4)]))
    }

    @Test func aLongPressBindAloneDoesNothingOnAShortPress() {
        var tracker = BindTracker()
        let lookup = BindLookup(longPress: c)
        _ = tracker.keyDown(keyCode: 4, isRepeat: false, lookup: lookup)
        #expect(tracker.keyUp(keyCode: 4) == (true, [.cancelLongPress(keyCode: 4)]))
    }

    @Test func aTimerForAKeyThatIsNotHeldDoesNothing() {
        var tracker = BindTracker()
        #expect(tracker.longPressElapsed(keyCode: 9) == [])
    }
}
