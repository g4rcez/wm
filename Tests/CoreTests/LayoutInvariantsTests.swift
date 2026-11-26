import Testing
@testable import Core

struct LayoutInvariantsTests {
    private let tiled = LayoutInvariants.Window(workspace: "1", tiled: true)

    @Test func agreeingBookkeepingHasNoProblem() {
        let problems = LayoutInvariants.problems(
            windows: [1: tiled, 2: tiled, 3: .init(workspace: "1", tiled: false)],
            workspaces: ["1": .init(engine: [1, 2], fullscreen: 2), "2": .init(engine: [])])
        #expect(problems.isEmpty)
    }

    @Test func aWindowInTheLayoutOfAnotherWorkspace() {
        let problems = LayoutInvariants.problems(
            windows: [1: .init(workspace: "2", tiled: true)], workspaces: ["1": .init(engine: [1]), "2": .init(engine: [])])
        #expect(problems == [
            "window 1 is in the layout of workspace 1, but on workspace 2",
            "window 1 tiles on workspace 2, but its layout does not hold it",
        ])
    }

    @Test func aFloatingOrUnknownOrDoubledWindowInALayout() {
        let problems = LayoutInvariants.problems(
            windows: [1: .init(workspace: "1", tiled: false)], workspaces: ["1": .init(engine: [1, 7, 7])])
        #expect(problems.contains("window 1 is in the layout of workspace 1, but does not tile"))
        #expect(problems.contains("the layout of workspace 1 holds window 7, which wm does not know"))
        #expect(problems.contains("window 7 is twice in the layout of workspace 1"))
    }

    @Test func aPlaceholderOfARestoreIsFine() {
        let placeholder = Placeholder.id(for: 42)
        #expect(LayoutInvariants.problems(windows: [:], workspaces: ["1": .init(engine: [placeholder])]).isEmpty)
    }

    @Test func aFullscreenWindowOfAnotherWorkspace() {
        let problems = LayoutInvariants.problems(
            windows: [1: tiled, 5: .init(workspace: "2", tiled: false)], workspaces: ["1": .init(engine: [1], fullscreen: 5)])
        #expect(problems == ["workspace 1 has window 5 in fullscreen or maximized, but it is not on it"])
    }
}
