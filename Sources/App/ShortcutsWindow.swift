import AppKit
import Common
import Scripting

/// The Shortcuts window: a table of the `[[shortcut]]` entries of `shortcuts.toml`, with Add, Edit and Delete. Each change
/// is written to the file at once; the config watcher then reloads the daemon, as for any edit of the config folder.
///
/// The window never writes a file that it cannot read: when `shortcuts.toml` has an error, it shows the error and the
/// buttons that change the file stay off until the user fixes the file.
@MainActor
final class ShortcutsWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let configURL: URL
    /// Records the keys that the user presses (the key tap swallows them before the window could see them).
    private let input: InputRouter
    /// `false` while the key tap is off (Accessibility is missing): recording cannot work then, typing still does.
    private let tapRunning: () -> Bool
    private var fileURL: URL { shortcutsURL(for: configURL) }
    private var window: NSWindow?
    private var stack: NSStackView?
    private let table = NSTableView()
    private let banner = NSTextField(wrappingLabelWithString: "")
    private let addButton = NSButton(title: "Add…", target: nil, action: nil)
    private let editButton = NSButton(title: "Edit…", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let openButton = NSButton(title: "Open File", target: nil, action: nil)
    private var shortcuts: [Shortcut] = []
    private var overrides: [BindOverride] = []
    /// `false` when the file has an error: nothing may be written over it.
    private var writable = true

    private static let columns: [(id: String, title: String, width: CGFloat)] = [
        ("keys", "Keys", 150), ("action", "Action", 220), ("mode", "Mode", 80), ("description", "Description", 160), ("status", "Status", 130),
    ]

    init(configURL: URL, input: InputRouter, tapRunning: @escaping () -> Bool) {
        self.configURL = configURL
        self.input = input
        self.tapRunning = tapRunning
        super.init()
    }

    func show() {
        if window == nil { build() }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    /// The file may have changed outside the window (an editor, the daemon): read it again when the window comes back.
    func windowDidBecomeKey(_ notification: Notification) { refresh() }

    // MARK: - Build

    private func build() {
        let title = NSTextField(labelWithString: "Shortcuts")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        banner.textColor = .systemOrange
        banner.preferredMaxLayoutWidth = 740

        for (id, name, width) in Self.columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = name
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.target = self
        table.doubleAction = #selector(edit)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: 740).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 300).isActive = true

        for (button, action) in [(addButton, #selector(add)), (editButton, #selector(edit)), (deleteButton, #selector(remove)), (openButton, #selector(openFile))] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
        }
        let buttons = NSStackView(views: [addButton, editButton, deleteButton, NSView(), openButton])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalToConstant: 740).isActive = true

        let stack = NSStackView(views: [title, banner, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        self.stack = stack

        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "wm shortcuts"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = stack
        self.window = window
    }

    // MARK: - State

    private func refresh() {
        var note: String?
        overrides = []
        do {
            shortcuts = try readShortcuts(at: fileURL)
            writable = true
            switch checkConfig(at: configURL) {
            case .failure(let error):
                note = "init.lua does not load: \(error.message)"
            case .success(let summary):
                overrides = summary.overrides
                if !summary.shortcutsImported {
                    note = "init.lua does not call wm.shortcuts(): the shortcuts are saved, but none is bound. Add `wm.shortcuts()` to init.lua."
                }
            }
        } catch {
            shortcuts = []
            writable = false
            note = "\(error)\nThe window does not change this file until it is fixed (Open File)."
        }
        banner.stringValue = note.map { "⚠ " + $0 } ?? ""
        banner.isHidden = note == nil
        table.reloadData()
        updateButtons()
        if let stack, let window { window.setContentSize(stack.fittingSize) }
    }

    private func updateButtons() {
        let selected = shortcuts.indices.contains(table.selectedRow)
        addButton.isEnabled = writable
        editButton.isEnabled = writable && selected
        deleteButton.isEnabled = writable && selected
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { shortcuts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard shortcuts.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let shortcut = shortcuts[row]
        let text: String
        switch id {
        case "keys":
            switch shortcut.trigger {
            case .press: text = shortcut.keys
            case .release: text = shortcut.keys + " · release"
            case .longPress: text = shortcut.keys + " · long press"
            case .hold: text = shortcut.keys + " · hold"
            }
        case "action": text = shortcut.action ?? "types \(shortcut.remap ?? "")"
        case "mode": text = shortcut.universal ? "all modes" : shortcut.mode
        case "description": text = shortcut.description ?? ""
        default: text = overrides.contains { $0.kept == .lua && $0.identity == shortcut.identity } ? "replaced by init.lua" : ""
        }
        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingTail
        cell.toolTip = text
        if id == "status" { cell.textColor = .systemOrange }
        return cell
    }

    // MARK: - Actions

    @objc private func add() { present(nil) }

    @objc private func edit() {
        guard writable, shortcuts.indices.contains(table.selectedRow) else { return }
        present(table.selectedRow)
    }

    @objc private func openFile() {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            // `open` needs a file: a header-only file is what the window writes for no shortcuts.
            try? writeShortcuts([], to: fileURL)
        }
        NSWorkspace.shared.open(fileURL)
    }

    @objc private func remove() {
        let row = table.selectedRow
        guard writable, shortcuts.indices.contains(row) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(shortcuts[row].keys)?"
        alert.informativeText = "The shortcut is removed from shortcuts.toml."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var list = shortcuts
        list.remove(at: row)
        save(list)
    }

    /// The edit form for row `index`, or for a new shortcut. The form stays open, with the reason, until the shortcut is
    /// valid (the same checks as the config load) and written.
    private func present(_ index: Int?) {
        let form = ShortcutForm(index.map { shortcuts[$0] }, input: input, canRecord: tapRunning())
        // The key tap must not keep the keys when the form closes, however it closes.
        defer { form.stopRecording() }
        let alert = NSAlert()
        alert.messageText = index == nil ? "Add a shortcut" : "Edit shortcut"
        alert.accessoryView = form.view
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = form.keys
        form.onLayoutChange = { [unowned alert] in
            form.view.frame.size = form.view.fittingSize
            alert.layout()
        }
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                let shortcut = try form.shortcut()
                var list = shortcuts
                if let index { list[index] = shortcut } else { list.append(shortcut) }
                try validateShortcuts(list)
                if save(list) { table.selectRowIndexes([index ?? list.count - 1], byExtendingSelection: false) }
                return
            } catch {
                form.error.stringValue = "\(error)"
            }
        }
    }

    /// Writes `list` and shows the table again. `false` when the file could not be written.
    @discardableResult
    private func save(_ list: [Shortcut]) -> Bool {
        do {
            try writeShortcuts(list, to: fileURL)
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
        refresh()
        return true
    }
}

/// The form of one shortcut: the keys, the action and a description, and the rarely used options behind "More options".
/// Each key field can be typed in or recorded; `shortcut()` reads the fields back, and throws what is wrong in words.
@MainActor
private final class ShortcutForm: NSObject, NSTextFieldDelegate {
    let keys = NSTextField()
    let error = NSTextField(wrappingLabelWithString: "")
    let view: NSView
    /// Called when the form changes its height (More options), so that the alert can follow.
    var onLayoutChange: (() -> Void)?

    private let input: InputRouter
    private let kind = NSPopUpButton()
    private let value = NSTextField()
    private let note = NSTextField()
    private let keysRecord = NSButton(title: "Record", target: nil, action: nil)
    private let valueRecord = NSButton(title: "Record", target: nil, action: nil)
    private let moreButton = NSButton(title: "", target: nil, action: nil)
    private let grid: NSGridView
    private let trigger = NSPopUpButton()
    private let seconds = NSTextField()
    private let mode = NSTextField()
    private let universal = NSButton(checkboxWithTitle: "Works in every mode", target: nil, action: nil)
    private let hidden = NSButton(checkboxWithTitle: "Leave it out of the key label", target: nil, action: nil)

    private var recording: ChordRecording?
    private var recordingField: NSTextField?
    private var recordingButton: NSButton?
    private var textBefore = ""
    private var placeholderBefore: String?
    private var idleTimer: Timer?
    /// The length of the action text at the last change: a longer text is typing, and the suggestions show; a shorter one is a delete.
    private var actionLength = 0

    /// The rows of the grid that "More options" shows.
    private static let moreRows = 4...6
    /// A recording ends when no key comes for this long (seconds) after its first key.
    private static let idle = 1.2

    init(_ shortcut: Shortcut?, input: InputRouter, canRecord: Bool) {
        self.input = input
        kind.addItems(withTitles: ["Run command", "Type key"])
        trigger.addItems(withTitles: ["Key down", "Key down, no repeat", "Key repeat (hold)", "Key up", "Long press"])
        keys.placeholderString = "alt-h, or a sequence: ctrl-p>h"
        seconds.placeholderString = "seconds"
        mode.placeholderString = "main"

        if let shortcut {
            keys.stringValue = shortcut.keys
            kind.selectItem(at: shortcut.remap == nil ? 0 : 1)
            value.stringValue = shortcut.action ?? shortcut.remap ?? ""
            trigger.selectItem(at: shortcut.release ? 3 : shortcut.longPress != nil ? 4 : shortcut.repeating == false ? 1 : shortcut.repeating == true ? 2 : 0)
            if case .seconds(let time)? = shortcut.longPress { seconds.stringValue = String(time) }
            mode.stringValue = shortcut.mode == "main" ? "" : shortcut.mode
            note.stringValue = shortcut.description ?? ""
            universal.state = shortcut.universal ? .on : .off
            hidden.state = shortcut.hidden ? .on : .off
        }

        for button in [keysRecord, valueRecord] {
            button.bezelStyle = .rounded
            button.widthAnchor.constraint(equalToConstant: 76).isActive = true
            button.isEnabled = canRecord
            button.toolTip = canRecord ? "Press the keys of the shortcut. Esc stops." : "Recording needs Accessibility: the key tap of wm is off. Type the keys."
        }
        moreButton.isBordered = false
        moreButton.bezelStyle = .inline

        let keysRow = NSStackView(views: [keys, keysRecord])
        let valueRow = NSStackView(views: [kind, value, valueRecord])
        let whenRow = NSStackView(views: [trigger, seconds])
        let options = NSStackView(views: [universal, hidden])
        options.orientation = .vertical
        options.alignment = .leading
        keys.widthAnchor.constraint(equalToConstant: 320).isActive = true
        kind.widthAnchor.constraint(equalToConstant: 125).isActive = true
        value.widthAnchor.constraint(equalToConstant: 188).isActive = true
        note.widthAnchor.constraint(equalToConstant: 404).isActive = true
        trigger.widthAnchor.constraint(equalToConstant: 190).isActive = true
        seconds.widthAnchor.constraint(equalToConstant: 90).isActive = true
        mode.widthAnchor.constraint(equalToConstant: 190).isActive = true

        grid = NSGridView(views: [
            [NSTextField(labelWithString: "Keys"), keysRow],
            [NSTextField(labelWithString: "Action"), valueRow],
            [NSTextField(labelWithString: "Description"), note],
            [NSView(), moreButton],
            [NSTextField(labelWithString: "When"), whenRow],
            [NSTextField(labelWithString: "Mode"), mode],
            [NSTextField(labelWithString: "Options"), options],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8

        error.textColor = .systemRed
        error.preferredMaxLayoutWidth = 480
        // Room for two lines, so the form does not change its size when a reason shows.
        error.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        let stack = NSStackView(views: [grid, error])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        view = stack
        super.init()

        for (button, action) in [(keysRecord, #selector(recordKeys)), (valueRecord, #selector(recordValue)), (moreButton, #selector(toggleMore))] {
            button.target = self
            button.action = action
        }
        value.delegate = self
        actionLength = value.stringValue.count
        kind.target = self
        kind.action = #selector(kindChanged)
        trigger.target = self
        trigger.action = #selector(triggerChanged)

        // Options that are set show at once, so that an edit never hides what the shortcut does.
        let usesMore = trigger.indexOfSelectedItem != 0 || !mode.stringValue.isEmpty || universal.state == .on || hidden.state == .on
        showMore(usesMore)
        kindChanged()
        triggerChanged()
        stack.frame.size = stack.fittingSize
    }

    // MARK: Layout

    @objc private func kindChanged() {
        let typesKey = kind.indexOfSelectedItem == 1
        value.placeholderString = typesKey ? "the key to type: left, cmd-right" : "focus left (type for suggestions)"
        valueRecord.isHidden = !typesKey
        if typesKey == false, recordingField === value { stopRecording() }
    }

    @objc private func triggerChanged() { seconds.isHidden = trigger.indexOfSelectedItem != 4 }

    @objc private func toggleMore() {
        showMore(grid.row(at: Self.moreRows.lowerBound).isHidden)
        onLayoutChange?()
    }

    private func showMore(_ shown: Bool) {
        for index in Self.moreRows { grid.row(at: index).isHidden = !shown }
        moreButton.title = shown ? "▾ Fewer options" : "▸ More options"
    }

    // MARK: Suggestions for the action

    /// Typing in the action field shows the native list of completions: the words of the wm commands (`focus` → `left`, `right`...).
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === value, let editor = field.currentEditor() as? NSTextView else { return }
        let grew = value.stringValue.count > actionLength
        actionLength = value.stringValue.count
        // After a delete the list stays closed, or the text the user removed would come back.
        if grew, kind.indexOfSelectedItem == 0, recordingField == nil { editor.complete(nil) }
    }

    func control(
        _ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange,
        indexOfSelectedItem index: UnsafeMutablePointer<Int>
    ) -> [String] {
        guard control === value, kind.indexOfSelectedItem == 0 else { return [] }
        let typed = (textView.string as NSString).substring(to: NSMaxRange(charRange))
        let (partial, suggestions) = commandSuggestions(for: typed)
        // The list replaces `charRange`, which can start inside the word (after the `-` of `--wrap`): drop what is before it.
        let skip = charRange.location - (NSMaxRange(charRange) - (partial as NSString).length)
        guard skip >= 0 else { return [] }
        index.pointee = -1
        return suggestions.map { String($0.dropFirst(skip)) }
    }

    // MARK: Recording

    @objc private func recordKeys() { toggleRecording(keys, button: keysRecord, maxSteps: 4) }
    @objc private func recordValue() { toggleRecording(value, button: valueRecord, maxSteps: 1) }

    private func toggleRecording(_ field: NSTextField, button: NSButton, maxSteps: Int) {
        let wasRecordingThis = recordingField === field
        stopRecording()
        if wasRecordingThis { return }
        input.cancelSequence()
        recording = ChordRecording(maxSteps: maxSteps)
        recordingField = field
        recordingButton = button
        textBefore = field.stringValue
        placeholderBefore = field.placeholderString
        field.stringValue = ""
        field.placeholderString = "Press the keys…"
        field.isEditable = false
        button.title = "Stop"
        input.capture = { [weak self] chord in self?.captured(chord) }
    }

    private func captured(_ chord: Chord) {
        guard var current = recording, let field = recordingField else { return }
        let outcome = current.add(chord)
        recording = current
        if outcome == .cancelled { return stopRecording() }
        field.stringValue = current.text
        if outcome == .finished { return stopRecording() }
        // The user may press one more key of a sequence: wait a little, then end.
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: Self.idle, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRecording() }
        }
        // `NSAlert.runModal` does not run the default mode of the run loop.
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    /// Ends the recording and gives the keys back to the binds. Nothing recorded: the field keeps its old text.
    func stopRecording() {
        input.capture = nil
        idleTimer?.invalidate()
        idleTimer = nil
        guard let field = recordingField else { return }
        if recording?.chords.isEmpty ?? true { field.stringValue = textBefore }
        field.placeholderString = placeholderBefore
        field.isEditable = true
        recordingButton?.title = "Record"
        recording = nil
        recordingField = nil
        recordingButton = nil
    }

    // MARK: Reading

    func shortcut() throws -> Shortcut {
        stopRecording()
        let keysText = keys.stringValue.trimmingCharacters(in: .whitespaces)
        let valueText = value.stringValue.trimmingCharacters(in: .whitespaces)
        guard !keysText.isEmpty else { throw ConfigError(message: "Enter the keys, like alt-h, or press Record.") }
        guard !valueText.isEmpty else { throw ConfigError(message: "Enter the command to run, or the key to type.") }
        let modeText = mode.stringValue.trimmingCharacters(in: .whitespaces)
        var shortcut = Shortcut(keys: keysText, mode: modeText.isEmpty ? "main" : modeText)
        if kind.indexOfSelectedItem == 0 { shortcut.action = valueText } else { shortcut.remap = valueText }
        let noteText = note.stringValue.trimmingCharacters(in: .whitespaces)
        shortcut.description = noteText.isEmpty ? nil : noteText
        switch trigger.indexOfSelectedItem {
        case 1: shortcut.repeating = false
        case 2: shortcut.repeating = true
        case 3: shortcut.release = true
        case 4:
            let time = seconds.stringValue.trimmingCharacters(in: .whitespaces)
            if time.isEmpty {
                shortcut.longPress = .on
            } else if let number = Double(time) {
                shortcut.longPress = .seconds(number)
            } else {
                throw ConfigError(message: "The long press time must be a number of seconds, like 0.8.")
            }
        default: break
        }
        shortcut.universal = universal.state == .on
        shortcut.hidden = hidden.state == .on
        return shortcut
    }
}
