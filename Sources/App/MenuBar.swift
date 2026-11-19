import AppKit
import Core
import Platform

/// Menu bar item: current workspace, config errors, reload and quit.
@MainActor
final class MenuBar: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let errorItem = NSMenuItem()
    private let workspaceItem = NSMenuItem()
    private let reload: () -> Void
    private let setup: () -> Void
    private let shortcuts: () -> Void
    private let tile: (String) -> Void
    /// The tile templates to list, as the config gives them for the layout in focus.
    private let templates: () -> [SplitTemplate]
    private let configFolder: URL
    /// The pieces of the icon: `T:1 2 5`, with the workspace in focus on a background.
    private var shown: [StatusSegment]?
    private var shownLayout: LayoutKind?
    private var pendingShown = false
    /// The active binding mode, or `nil` in `main`.
    private var modeShown: String?

    init(configFolder: URL, reload: @escaping () -> Void, setup: @escaping () -> Void, shortcuts: @escaping () -> Void, templates: @escaping () -> [SplitTemplate], tile: @escaping (String) -> Void) {
        self.reload = reload
        self.setup = setup
        self.shortcuts = shortcuts
        self.templates = templates
        self.tile = tile
        self.configFolder = configFolder
        super.init()
        let menu = NSMenu()
        workspaceItem.isEnabled = false
        menu.addItem(workspaceItem)
        errorItem.isHidden = true
        errorItem.isEnabled = false
        menu.addItem(errorItem)
        menu.addItem(.separator())
        let tileMenu = NSMenu()
        tileMenu.delegate = self
        let tileItem = NSMenuItem(title: "Tile Windows", action: nil, keyEquivalent: "")
        tileItem.submenu = tileMenu
        menu.addItem(tileItem)
        menu.addItem(.separator())
        let reloadItem = NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)
        let setupItem = NSMenuItem(title: "Setup…", action: #selector(openSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
        let shortcutsItem = NSMenuItem(title: "Shortcuts…", action: #selector(openShortcuts), keyEquivalent: "")
        shortcutsItem.target = self
        menu.addItem(shortcutsItem)
        let folderItem = NSMenuItem(title: "Open Config Folder", action: #selector(openFolder), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(folderItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit wm", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        item.button?.title = "▦"
    }

    /// `false` when macOS keeps the item off the menu bar (the app is not allowed in System Settings > Menu Bar, or
    /// the bar has no room). The window server knows what is really on screen, so ask it: a shown status item
    /// is an on-screen window of this process at the status window level.
    var isVisible: Bool {
        let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        return windows.contains {
            ($0[kCGWindowOwnerPID as String] as? Int) == me && ($0[kCGWindowLayer as String] as? Int) == statusLevel
        }
    }

    var details: String {
        guard let window = item.button?.window else { return "no window" }
        return "frame=\(window.frame) shownByWindowServer=\(isVisible)"
    }

    /// What the icon shows, by priority: "..." while a key sequence waits, the binding mode, the workspaces (`T:1 2 5`). All are
    /// template images, so macOS tints them for light and dark menu bars.
    private func refreshIcon() {
        guard let button = item.button else { return }
        if pendingShown {
            button.title = ""
            button.image = WorkspaceIcon.image(for: "...")
        } else if let modeShown {
            button.title = ""
            button.image = WorkspaceIcon.modeImage(for: modeShown)
        } else if let shown, !shown.isEmpty {
            button.title = ""
            button.image = WorkspaceIcon.strip(shown)
            button.setAccessibilityLabel("wm: " + shown.map(\.text).joined())
        } else {
            button.image = nil
            button.title = "▦"
        }
    }

    /// Shows `label` in the icon (`T:1 2 5`, see `StatusLabel`). `name` and `layout` are for the first line of the menu.
    func setWorkspace(_ name: String, layout: LayoutKind? = nil, label: [StatusSegment]) {
        workspaceItem.title = name.isEmpty ? "wm" : "Workspace \(name)" + (layout.map { " · \($0.rawValue)" } ?? "")
        shownLayout = layout
        guard shown != label else { return }
        shown = label
        refreshIcon()
    }

    /// Shows "..." in the icon while a key sequence waits for its next key.
    func setPending(_ waiting: Bool) {
        guard waiting != pendingShown else { return }
        pendingShown = waiting
        refreshIcon()
    }

    /// Shows the name of a binding mode in an outlined square. `nil` (the `main` mode) shows the workspace again.
    func setMode(_ name: String?) {
        guard name != modeShown else { return }
        modeShown = name
        refreshIcon()
    }

    func setError(_ message: String?) {
        errorItem.isHidden = message == nil
        errorItem.title = message.map { "⚠ " + String($0.prefix(80)) } ?? ""
        item.button?.toolTip = message
    }

    /// The tile submenu is filled each time it opens, so it follows the config and the layout in focus.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for template in TemplateGlyph.entries(templates()) {
            let entry = NSMenuItem(title: template?.title ?? "Back to the chain", action: #selector(applyTile(_:)), keyEquivalent: "")
            entry.target = self
            entry.image = TemplateGlyph.image(for: template)
            entry.representedObject = TemplateGlyph.label(template)
            menu.addItem(entry)
        }
    }

    @objc private func applyTile(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { tile(name) }
    }

    @objc private func reloadConfig() { reload() }
    @objc private func openSetup() { setup() }
    @objc private func openShortcuts() { shortcuts() }
    @objc private func openFolder() { NSWorkspace.shared.open(configFolder) }
}
