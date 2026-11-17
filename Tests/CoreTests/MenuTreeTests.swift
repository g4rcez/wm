import Testing
@testable import Core

struct MenuTreeTests {
    private let bar = MenuNode(title: "", children: [
        MenuNode(title: "File", children: [
            MenuNode(title: "New", shortcut: "⌘N", token: 0),
            MenuNode(title: "Open Recent", children: [
                MenuNode(title: "Notes.txt", token: 1),
                MenuNode(title: "Old.txt", enabled: false, token: 2),
            ]),
            MenuNode(title: "Close", enabled: false, token: 3),
        ]),
        MenuNode(title: "Window", children: [MenuNode(title: "Minimize", shortcut: "⌘M", token: 4)]),
    ])

    @Test func everyEnabledItemHasItsPathFromTheMenuBar() {
        #expect(bar.flattened() == [
            MenuNode.Entry(path: "File > New", token: 0, shortcut: "⌘N"),
            MenuNode.Entry(path: "File > Open Recent > Notes.txt", token: 1, shortcut: nil),
            MenuNode.Entry(path: "Window > Minimize", token: 4, shortcut: "⌘M"),
        ])
    }

    @Test func aDisabledMenuHidesItsItems() {
        let tree = MenuNode(title: "", children: [MenuNode(title: "Edit", enabled: false, children: [MenuNode(title: "Cut", token: 0)])])
        #expect(tree.flattened() == [])
    }

    @Test func aShortcutShowsItsModifiersInTheUsualOrder() {
        #expect(menuShortcut(key: "s", modifiers: 0) == "⌘S")
        #expect(menuShortcut(key: "s", modifiers: 1) == "⇧⌘S")
        #expect(menuShortcut(key: "t", modifiers: 7) == "⌃⌥⇧⌘T")
        #expect(menuShortcut(key: "f", modifiers: 8) == "F")
    }
}
