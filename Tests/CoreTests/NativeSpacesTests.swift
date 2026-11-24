import Testing
@testable import Core

struct NativeSpacesTests {
    private func display(_ uuid: String, minX: Double, current: UInt64, _ spaces: [UInt64]) -> NativeDisplay {
        NativeDisplay(uuid: uuid, displayID: 1, minX: minX, current: current, spaces: spaces)
    }

    @Test func desktopsAreNumberedAcrossDisplaysFromTheLeftmost() {
        let binding = NativeSpaceBinding(displays: [
            display("right", minX: 1000, current: 30, [30, 31]),
            display("left", minX: 0, current: 10, [10, 11, 12]),
        ])
        #expect(binding.desktop(of: "1")?.space == 10)
        #expect(binding.desktop(of: "3")?.space == 12)
        #expect(binding.desktop(of: "4")?.space == 30)
        #expect(binding.desktop(of: "5")?.display == "right")
        #expect(binding.count == 5)
    }

    @Test func aWorkspaceBeyondTheDesktopsHasNone() {
        let binding = NativeSpaceBinding(displays: [display("a", minX: 0, current: 1, [1, 2])])
        #expect(binding.desktop(of: "3") == nil)
        #expect(binding.missing(["1", "3", "web"]) == ["3", "web"])
    }

    @Test func aRuleGivesItsDesktopToAName() {
        let binding = NativeSpaceBinding(displays: [display("a", minX: 0, current: 1, [1, 2, 3])], rules: ["web": 2])
        #expect(binding.desktop(of: "web")?.space == 2)
        #expect(binding.workspace(of: 2) == "web")
        #expect(binding.desktop(of: "2") == nil)
        #expect(binding.workspace(of: 1) == "1")
        #expect(binding.workspace(of: 3) == "3")
    }

    @Test func aRuleBeyondTheDesktopsIsMissing() {
        let binding = NativeSpaceBinding(displays: [display("a", minX: 0, current: 1, [1])], rules: ["mail": 4])
        #expect(binding.desktop(of: "mail") == nil)
        #expect(binding.missing(["mail"]) == ["mail"])
    }

    @Test func aSpaceThatIsNoDesktopIsNoWorkspace() {
        let binding = NativeSpaceBinding(displays: [display("a", minX: 0, current: 99, [1, 2])])
        #expect(binding.workspace(of: 99) == nil)
    }

    @Test func workspacesOfADisplayFollowTheDesktopOrder() {
        let binding = NativeSpaceBinding(
            displays: [display("a", minX: 0, current: 1, [1, 2]), display("b", minX: 5, current: 3, [3, 4])], rules: ["web": 4])
        #expect(binding.workspaces(on: "a") == ["1", "2"])
        #expect(binding.workspaces(on: "b") == ["3", "web"])
    }
}
