import Testing
@testable import Scripting

struct GestureDefaultsTests {
    @Test func fourFingersGoThroughTheWorkspacesAndOpenAndCloseTheOverview() {
        let defaults = Gesture.defaults(fingers: 4)
        #expect(defaults.map(\.fingers) == [4, 4, 4, 4])
        #expect(defaults.map(\.direction) == [.left, .right, .up, .down])
        #expect(defaults.map(\.action) == [
            .command("workspace next"), .command("workspace prev"), .command("overview open"), .command("overview close"),
        ])
        #expect(defaults.allSatisfy { $0.modifiers == [] && $0.isBuiltIn })
    }

    @Test func theTitleBarHasSixBuiltInGestures() {
        let defaults = Gesture.titleBarDefaults
        #expect(defaults.map(\.direction) == [.left, .right, .up, .down, .pinchIn, .pinchOut])
        #expect(defaults.map(\.action) == [
            .command("window swipe left"), .command("window swipe right"), .command("window swipe up"),
            .command("window swipe down"), .command("window close"), .command("window fullscreen"),
        ])
        #expect(defaults.allSatisfy { $0.zone == .titleBar && $0.modifiers == [] && $0.isBuiltIn })
        #expect(defaults.map(\.label) == [
            "title_bar-scroll left", "title_bar-scroll right", "title_bar-scroll up", "title_bar-scroll down",
            "title_bar pinch-in", "title_bar pinch-out",
        ])
    }

    @Test func aTitleBarGestureOfTheUserReplacesOnlyTheBuiltInOneOfTheSameDirection() {
        let mine = Gesture(zone: .titleBar, direction: .pinchIn, action: .command("window minimize"))
        let elsewhere = Gesture(modifiers: .option, direction: .left, action: .command("workspace prev"))
        #expect(Gesture.missingTitleBarDefaults([mine, elsewhere]).map(\.direction) == [.left, .right, .up, .down, .pinchOut])
    }

    @Test func threeFingersUseTheSameSwipes() {
        #expect(Gesture.defaults(fingers: 3).map(\.fingers) == [3, 3, 3, 3])
    }

    @Test func aGestureOfTheUserReplacesTheBuiltInOneForTheSameSwipe() {
        let mine = Gesture(fingers: 4, direction: .up, action: .command("layout balance"))
        let missing = Gesture.missingDefaults([mine], fingers: 4)
        #expect(missing.map(\.direction) == [.left, .right, .down])
    }

    @Test func aGestureWithOtherFingersOrModifiersReplacesNothing() {
        let threeFingers = Gesture(fingers: 3, direction: .up, action: .command("overview"))
        let withAlt = Gesture(modifiers: .option, fingers: 4, direction: .up, action: .command("overview"))
        #expect(Gesture.missingDefaults([threeFingers, withAlt], fingers: 4).count == 4)
    }

    @Test func theSidewaysBuiltInSwipesStepAsideOnAScrollingWorkspace() {
        let mine = Gesture(fingers: 4, direction: .left, action: .command("focus left"))
        let all = [mine] + Gesture.defaults(fingers: 4).filter { $0.direction != .left }
        let kept = Gesture.effective(all, scrollsStrip: true)
        #expect(kept.map(\.direction) == [.left, .up, .down])
        #expect(kept.map(\.isBuiltIn) == [false, true, true])
    }

    @Test func everyBuiltInSwipeStaysOnAWorkspaceThatDoesNotScroll() {
        #expect(Gesture.effective(Gesture.defaults(fingers: 4), scrollsStrip: false).count == 4)
    }

    @Test func aSidewaysSwipeOnAScrollingWorkspaceIsLeftToTheStrip() {
        var tracker = GestureTracker()
        let gestures = Gesture.effective(Gesture.defaults(fingers: 4), scrollsStrip: true)
        #expect(tracker.scroll(dx: -400, dy: 0, modifiers: [], phase: .began, time: 0, gestures: gestures, fingers: 4) == .ignored)
    }

    @Test func aSidewaysSwipeOnATilingWorkspaceGoesToTheNextWorkspace() {
        var tracker = GestureTracker()
        let gestures = Gesture.effective(Gesture.defaults(fingers: 4), scrollsStrip: false)
        #expect(tracker.scroll(dx: -400, dy: 0, modifiers: [], phase: .began, time: 0, gestures: gestures, fingers: 4) == .fire(.command("workspace next")))
    }

    @Test func aSwipeWithAnotherNumberOfFingersIsNotTouched() {
        var tracker = GestureTracker()
        let gestures = Gesture.defaults(fingers: 4)
        #expect(tracker.scroll(dx: -400, dy: 0, modifiers: [], phase: .began, time: 0, gestures: gestures, fingers: 3) == .ignored)
    }

    @Test func aGestureIsLabelledForTheBindList() {
        #expect(Gesture(fingers: 4, direction: .up, action: .command("overview")).label == "4-finger up")
        #expect(Gesture(modifiers: .option, direction: .left, action: .command("overview")).label == "alt-scroll left")
    }
}
