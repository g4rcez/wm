import Common
import Testing

struct OverviewTests {
    @Test func listsMonitorsWorkspacesAndWindowsInColumns() {
        let text = renderOverview(
            monitors: [OverviewMonitor(id: 1, name: "Built-in Retina Display", workspace: "1")],
            workspaces: [
                OverviewWorkspace(name: "1", layout: "tiling", monitor: 1, windows: [
                    OverviewWindow(id: 3042, app: "Finder", title: "Downloads", focused: true),
                    OverviewWindow(id: 3017, app: "Podman Desktop", title: "Podman Desktop"),
                    OverviewWindow(id: 31, app: "Rex Beta", title: "zsh", floating: true),
                ]),
                OverviewWorkspace(name: "5", layout: "scrolling", monitor: nil, windows: [
                    OverviewWindow(id: 3026, app: "Finder", title: "Documents", strip: "vertical"),
                ]),
            ]
        )

        #expect(text == """
        monitor 1  Built-in Retina Display  shows workspace 1

        workspace 1  tiling  [visible, monitor 1]
          * 3042  Finder          Downloads
            3017  Podman Desktop  Podman Desktop
            31    Rex Beta        zsh  (floating)
        workspace 5  scrolling
            3026  Finder          Documents  [vertical]

        """)
    }

    @Test func marksMaximizedAndMinimizedWindowsAndSkipsEmptyTitles() {
        let text = renderOverview(monitors: [], workspaces: [
            OverviewWorkspace(name: "2", layout: "scrolling", monitor: 2, windows: [
                OverviewWindow(id: 7, app: "Notes", title: "", maximized: true),
                OverviewWindow(id: 8, app: "Mail", title: "Inbox", minimized: true),
            ]),
        ])

        #expect(text == """
        workspace 2  scrolling  [visible, monitor 2]
            7  Notes  (maximized)
            8  Mail   Inbox  (minimized)

        """)
    }

    @Test func aVisibleWorkspaceWithoutWindowsStillHasItsHeader() {
        let text = renderOverview(
            monitors: [
                OverviewMonitor(id: 1, name: "Left", workspace: "1"),
                OverviewMonitor(id: 2, name: "Right", workspace: "2"),
            ],
            workspaces: [OverviewWorkspace(name: "2", layout: "tiling", monitor: 2, windows: [])]
        )

        #expect(text == """
        monitor 1  Left  shows workspace 1
        monitor 2  Right  shows workspace 2

        workspace 2  tiling  [visible, monitor 2]

        """)
    }

    @Test func nothingToShowIsEmpty() {
        #expect(renderOverview(monitors: [], workspaces: []) == "")
    }
}
