import Testing

@testable import Scripting

struct SystemSwipesTests {
    private let counts = [(3, true), (3, false), (4, true), (4, false)]

    /// A trackpad with every swipe of macOS off, and `changes` on top.
    private func trackpad(_ changes: [String: Any] = [:]) -> [String: Any] {
        let off: [String: Any] = [
            "TrackpadThreeFingerHorizSwipeGesture": 0, "TrackpadThreeFingerVertSwipeGesture": 0,
            "TrackpadFourFingerHorizSwipeGesture": 0, "TrackpadFourFingerVertSwipeGesture": 0, "TrackpadThreeFingerDrag": 0,
        ]
        return off.merging(changes) { $1 }
    }

    private func taken(_ swipes: SystemSwipes) -> [String] {
        counts.filter { swipes.takes(fingers: $0.0, horizontal: $0.1) }.map { "\($0.0)\($0.1 ? "h" : "v")" }
    }

    @Test func aMacWithNoTrackpadSettingsHasTheDefaultsOfMacOS() {
        #expect(taken(SystemSwipes(trackpads: [], dock: [:])) == ["3h", "3v", "4h", "4v"])
        #expect(taken(SystemSwipes(trackpads: [[:], [:]], dock: [:])) == ["3h", "3v", "4h", "4v"])
    }

    @Test func aKeyThatADomainDoesNotHaveIsOn() {
        let swipes = SystemSwipes(trackpads: [["TrackpadFourFingerVertSwipeGesture": 0]], dock: [:])
        #expect(taken(swipes) == ["3h", "3v", "4h"])
    }

    @Test(arguments: [
        ("TrackpadThreeFingerHorizSwipeGesture", "3h"), ("TrackpadThreeFingerVertSwipeGesture", "3v"),
        ("TrackpadFourFingerHorizSwipeGesture", "4h"), ("TrackpadFourFingerVertSwipeGesture", "4v"),
    ])
    func eachKeyTakesItsFingersAndAxis(key: String, swipe: String) {
        #expect(taken(SystemSwipes(trackpads: [trackpad([key: 2])], dock: [:])) == [swipe])
    }

    @Test func nothingIsTakenWhenEveryKeyIsOff() {
        #expect(taken(SystemSwipes(trackpads: [trackpad(), trackpad()], dock: [:])) == [])
    }

    @Test func oneTrackpadIsEnoughToTakeASwipe() {
        let bluetooth = trackpad(["TrackpadFourFingerVertSwipeGesture": 2])
        #expect(taken(SystemSwipes(trackpads: [trackpad(), bluetooth], dock: [:])) == ["4v"])
        #expect(taken(SystemSwipes(trackpads: [[:], bluetooth], dock: [:])) == ["4v"])
    }

    @Test func threeFingerDragTakesThreeFingers() {
        let swipes = SystemSwipes(trackpads: [trackpad(["TrackpadThreeFingerDrag": true])], dock: [:])
        #expect(taken(swipes) == ["3h", "3v"])
    }

    @Test func upAndDownAreFreeWithNoMissionControlAndNoAppExpose() {
        let on = [trackpad(["TrackpadFourFingerVertSwipeGesture": 2])]
        let neither: [String: Any] = ["showMissionControlGestureEnabled": false, "showAppExposeGestureEnabled": false]
        #expect(taken(SystemSwipes(trackpads: on, dock: neither)) == [])
        #expect(taken(SystemSwipes(trackpads: on, dock: ["showMissionControlGestureEnabled": false])) == [])
        #expect(taken(SystemSwipes(trackpads: on, dock: ["showAppExposeGestureEnabled": false])) == ["4v"])
        let exposeOnly: [String: Any] = ["showMissionControlGestureEnabled": false, "showAppExposeGestureEnabled": true]
        #expect(taken(SystemSwipes(trackpads: on, dock: exposeOnly)) == ["4v"])
    }

    @Test func aGestureIsTakenByItsFingersAndAxisAlsoWithAModifier() {
        let swipes = SystemSwipes(trackpads: [trackpad(["TrackpadFourFingerVertSwipeGesture": 2])], dock: [:])
        let command = BindAction.command("palette")
        #expect(swipes.takes(Gesture(fingers: 4, direction: .up, action: command)))
        #expect(swipes.takes(Gesture(modifiers: .option, fingers: 4, direction: .down, action: command)))
        #expect(!swipes.takes(Gesture(fingers: 4, direction: .left, action: command)))
        #expect(!swipes.takes(Gesture(fingers: 3, direction: .up, action: command)))
    }

    @Test func aScrollGestureIsNeverTaken() {
        let swipes = SystemSwipes(trackpads: [], dock: [:])
        let command = BindAction.command("noop")
        #expect(!swipes.takes(Gesture(modifiers: .option, direction: .up, action: command)))
        #expect(!swipes.takes(Gesture(zone: .titleBar, direction: .up, action: command)))
    }
}
