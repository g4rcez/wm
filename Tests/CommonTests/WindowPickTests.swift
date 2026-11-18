import Common
import Testing

struct WindowPickTests {
    @Test func managedWindowShowsStateSelectorsAndRule() {
        let text = renderPick(PickedWindow(
            id: 3042, pid: 512, bundleID: "com.apple.Safari", appName: "Safari", title: "GitHub",
            role: "AXWindow", subrole: "AXStandardWindow", frame: PickedFrame(x: 100, y: 40, width: 1200, height: 800),
            managed: true, workspace: "2", state: ["floating", "mark:mail"]))

        #expect(text == """
        id         3042
        app        Safari (com.apple.Safari)
        pid        512
        title      GitHub
        role       AXWindow / AXStandardWindow
        managed    yes
        workspace  2
        state      floating, mark:mail
        frame      100,40 1200x800
        window     --window 3042 · --window app:com.apple.Safari · --window pid:512
        rule       { app = "com.apple.Safari", title = "^GitHub$" }

        """)
    }

    @Test func unmanagedWindowHasNoWorkspaceStateOrSelectors() {
        let text = renderPick(PickedWindow(
            id: 77, pid: 90, bundleID: "com.example.Tool", appName: "Tool", title: "",
            role: "AXWindow", subrole: "AXDialog", frame: PickedFrame(x: 0, y: 0, width: 300, height: 200),
            managed: false, workspace: nil, state: []))

        #expect(text == """
        id         77
        app        Tool (com.example.Tool)
        pid        90
        title      -
        role       AXWindow / AXDialog
        managed    no
        frame      0,0 300x200
        rule       { app = "com.example.Tool" }

        """)
    }

    @Test func ruleEscapesRegexCharactersAndLuaQuotes() {
        let text = renderPick(PickedWindow(
            id: 1, pid: 2, bundleID: "a.b", appName: "B", title: "say \"hi\" (1)",
            role: "AXWindow", subrole: "AXStandardWindow", frame: PickedFrame(x: 0, y: 0, width: 1, height: 1),
            managed: false, workspace: nil, state: []))

        #expect(text.contains(#"rule       { app = "a.b", title = "^say \"hi\" \\(1\\)$" }"#))
    }
}
