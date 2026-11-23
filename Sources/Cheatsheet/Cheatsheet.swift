import Common
import Foundation
import Scripting

/// One bind as the cheatsheet needs it. The daemon builds it from a `BindRecord`; the CLI reads it from `wm list binds --json`.
public struct CheatBind: Sendable, Equatable {
    public var mode: String
    public var keys: String
    public var command: String
    public var description: String?
    public var trigger: BindTrigger
    public var hidden: Bool

    public init(mode: String, keys: String, command: String, description: String? = nil, trigger: BindTrigger = .press, hidden: Bool = false) {
        self.mode = mode
        self.keys = keys
        self.command = command
        self.description = description
        self.trigger = trigger
        self.hidden = hidden
    }

    public init(_ record: BindRecord) {
        self.init(
            mode: record.mode, keys: record.keys, command: record.action, description: record.options.description,
            trigger: record.trigger, hidden: record.options.hidden)
    }

    /// The binds from the JSON of `wm list binds --json`. A line that does not read is left out.
    public static func decode(json: Data) -> [CheatBind] {
        guard let items = (try? JSONSerialization.jsonObject(with: json)) as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let mode = item["mode"] as? String, let keys = item["keys"] as? String, let command = item["command"] as? String else { return nil }
            let trigger = (item["trigger"] as? String).flatMap(BindTrigger.init(rawValue:)) ?? .press
            return CheatBind(
                mode: mode, keys: keys, command: command, description: item["description"] as? String, trigger: trigger,
                hidden: item["hidden"] as? Bool ?? false)
        }
    }
}

/// One row of the sheet: what a key does, and the keys. `steps` is a sequence (`ctrl-p>h` has two); every step is the
/// caps that are pressed together, modifiers first.
public struct CheatRow: Sendable, Equatable {
    public var title: String
    public var command: String
    public var steps: [[CheatCap]]
    /// `hold` for a bind that runs when the key is held down; empty for a plain press.
    public var note: String

    public init(title: String, command: String, steps: [[CheatCap]], note: String = "") {
        self.title = title
        self.command = command
        self.steps = steps
        self.note = note
    }

    /// The text that the filter looks in.
    public var searchText: String {
        ([title, command, note] + steps.map { $0.map(\.text).joined(separator: " ") }).joined(separator: " ").lowercased()
    }
}

/// One key cap: `⌥`, `H`, `Tab`, `←↑↓→`.
public struct CheatCap: Sendable, Equatable {
    public var text: String
    public var isModifier: Bool

    public init(_ text: String, isModifier: Bool = false) {
        self.text = text
        self.isModifier = isModifier
    }
}

public struct CheatSection: Sendable, Equatable {
    public var title: String
    public var rows: [CheatRow]

    public init(title: String, rows: [CheatRow]) {
        self.title = title
        self.rows = rows
    }
}

/// The binds of one mode.
public struct CheatPage: Sendable, Equatable {
    public var mode: String
    public var sections: [CheatSection]

    public init(mode: String, sections: [CheatSection]) {
        self.mode = mode
        self.sections = sections
    }

    public var rowCount: Int { sections.reduce(0) { $0 + $1.rows.count } }

    /// The same page with the rows that match every word of `query`. A section with no row is left out.
    public func filtered(by query: String) -> CheatPage {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return self }
        let sections = sections.compactMap { section -> CheatSection? in
            let rows = section.rows.filter { row in
                let text = row.searchText + " " + section.title.lowercased()
                return words.allSatisfy { text.contains($0) }
            }
            return rows.isEmpty ? nil : CheatSection(title: section.title, rows: rows)
        }
        return CheatPage(mode: mode, sections: sections)
    }
}

public struct Cheatsheet: Sendable, Equatable {
    /// `main` first, then the other modes by name. A mode with nothing to show is not here.
    public var pages: [CheatPage]
    /// The modifier symbols that the sheet uses, with their names, for the line that explains them.
    public var legend: [(symbol: String, name: String)]

    public init(pages: [CheatPage], legend: [(symbol: String, name: String)] = []) {
        self.pages = pages
        self.legend = legend
    }

    public static func == (lhs: Cheatsheet, rhs: Cheatsheet) -> Bool {
        lhs.pages == rhs.pages && lhs.legend.map(\.symbol) == rhs.legend.map(\.symbol)
    }

    /// The page of a mode, or the first one.
    public func pageIndex(of mode: String?) -> Int {
        pages.firstIndex { $0.mode == mode } ?? 0
    }

    /// The row count of the longest page.
    public var longestPage: Int { pages.map(\.rowCount).max() ?? 0 }

    /// `✦ hyper · ⌥ alt`, for the line under the title.
    public var legendText: String { legend.map { "\($0.symbol) \($0.name)" }.joined(separator: "  ·  ") }
}

// MARK: - Building

/// The order of the sections; a section that is not here goes last.
private let sectionOrder = ["Focus & move", "Windows", "Workspaces", "Layout", "Interface", "Apps & scripts", "Modes", "System"]

private let sectionNames: [String: String] = [
    "Focus and move": "Focus & move", "Windows": "Windows", "Workspaces": "Workspaces", "Layout": "Layout", "Interface": "Interface",
    "Inspect": "System", "Memory": "System", "Daemon": "System",
]

/// The section of a command: the section of its `wm help` entry, with a few commands moved to a place that fits a bind better.
func cheatCategory(of command: String) -> String {
    let words = command.split(separator: " ").map(String.init)
    guard let first = words.first, command != "function" else { return "Apps & scripts" }
    if first == "exec" || (first == "focus" && words.dropFirst().first == "app") { return "Apps & scripts" }
    if first == "mode" { return "Modes" }
    var best: (length: Int, section: String)?
    for section in commandSections {
        for spec in section.specs where Array(words.prefix(spec.words.count)) == spec.words && spec.words.count > (best?.length ?? 0) {
            best = (spec.words.count, sectionNames[section.title] ?? section.title)
        }
    }
    return best?.section ?? "Apps & scripts"
}

private let arrowKeys: [String: String] = ["left": "←", "up": "↑", "down": "↓", "right": "→"]

private let keyNames: [String: String] = [
    "esc": "Esc", "space": "Space", "tab": "Tab", "enter": "Return", "backspace": "Delete", "delete": "Fwd Delete",
    "home": "Home", "end": "End", "pageup": "Page Up", "pagedown": "Page Down",
    "minus": "-", "equal": "=", "comma": ",", "period": ".", "slash": "/", "backslash": "\\", "semicolon": ";", "quote": "'",
    "backtick": "`", "leftsquarebracket": "[", "rightsquarebracket": "]",
]

private func keyText(_ key: String) -> String {
    if let arrow = arrowKeys[key] { return arrow }
    if let name = keyNames[key] { return name }
    return key.uppercased()
}

/// The caps of one chord: the modifiers as symbols, then the key.
func cheatCaps(_ chord: Chord) -> [CheatCap] {
    var caps: [CheatCap] = []
    for (modifier, symbol) in [(Modifiers.hyper, "✦"), (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")] where chord.modifiers.contains(modifier) {
        caps.append(CheatCap(symbol, isModifier: true))
    }
    return caps + [CheatCap(keyText(chord.key))]
}

private let legendNames: [(String, String)] = [("✦", "hyper"), ("⌃", "ctrl"), ("⌥", "alt"), ("⇧", "shift"), ("⌘", "cmd")]

private struct Entry {
    var bind: CheatBind
    var chords: [Chord]?
    var category: String
}

/// The text of a row when the bind has no description: `exec open -a Safari` is `Run open -a Safari`.
func cheatTitle(command: String) -> String {
    if command == "function" { return "Lua function" }
    if command.hasPrefix("exec ") { return "Run " + command.dropFirst(5) }
    return command.prefix(1).uppercased() + command.dropFirst()
}

private let directionWords = ["left", "right", "up", "down"]

/// `text` with the first whole word for which `matches` says yes replaced by `replacement`.
private func replacingWord(in text: String, where matches: (String) -> Bool, with replacement: String) -> String? {
    var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard let index = words.lastIndex(where: { matches($0.lowercased()) }) else { return nil }
    words[index] = replacement
    return words.joined(separator: " ")
}

/// The binds of the sheet, with the keys that only differ in a direction or a number joined into one row.
private func rows(of entries: [Entry]) -> [(category: String, row: CheatRow)] {
    enum Family: Hashable { case direction, number }
    struct Group {
        var family: Family
        var title: String
        var members: [Int]
    }
    // A key that is part of a family: the same command with another direction or number, on the same modifiers.
    var groups: [String: Group] = [:]
    var order: [String] = []
    var familyOf: [Int: String] = [:]
    for (index, entry) in entries.enumerated() {
        guard let chords = entry.chords, chords.count == 1, entry.bind.trigger != .longPress else { continue }
        let words = entry.bind.command.split(separator: " ").map(String.init)
        guard let last = words.last, words.count > 1 || Int(last) != nil else { continue }
        let family: Family
        if directionWords.contains(last) {
            family = .direction
        } else if Int(last) != nil, chords[0].key.count == 1, Int(chords[0].key) != nil {
            family = .number
        } else {
            continue
        }
        let described = entry.bind.description ?? cheatTitle(command: entry.bind.command)
        let title = family == .direction
            ? replacingWord(in: described, where: { directionWords.contains($0) }, with: "direction")
            : replacingWord(in: described, where: { Int($0) != nil }, with: "N")
        guard let title else { continue }
        let id = "\(entry.bind.mode)|\(entry.bind.trigger.rawValue)|\(chords[0].modifiers.rawValue)|\(family)|\(words.dropLast().joined(separator: " "))|\(title)"
        if groups[id] == nil {
            groups[id] = Group(family: family, title: title, members: [])
            order.append(id)
        }
        groups[id]?.members.append(index)
        familyOf[index] = id
    }
    var joined: [String: (title: String, caps: [CheatCap])] = [:]
    for id in order {
        guard let group = groups[id], group.members.count >= 3 else { continue }
        let chords = group.members.compactMap { entries[$0].chords?.first }
        var caps = Array(cheatCaps(chords[0]).dropLast())
        if group.family == .direction, chords.allSatisfy({ arrowKeys[$0.key] != nil }) {
            caps.append(CheatCap(["left", "up", "down", "right"].filter { key in chords.contains { $0.key == key } }.compactMap { arrowKeys[$0] }.joined()))
        } else if group.family == .number {
            let digits = chords.compactMap { Int($0.key) }.sorted()
            let run = digits.last.map { $0 - digits[0] + 1 == digits.count } ?? false
            caps.append(CheatCap(run ? "\(digits[0])–\(digits[digits.count - 1])" : digits.map(String.init).joined(separator: " ")))
        } else {
            caps += chords.map { CheatCap(keyText($0.key)) }
        }
        joined[id] = (group.title.prefix(1).uppercased() + group.title.dropFirst(), caps)
    }

    var result: [(String, CheatRow)] = []
    var done = Set<String>()
    for (index, entry) in entries.enumerated() {
        let note = entry.bind.trigger == .longPress ? "hold" : ""
        if let id = familyOf[index], let join = joined[id] {
            guard done.insert(id).inserted else { continue }
            result.append((entry.category, CheatRow(title: join.title, command: entry.bind.command, steps: [join.caps], note: note)))
            continue
        }
        let steps = entry.chords.map { $0.map(cheatCaps) } ?? [[CheatCap(entry.bind.keys)]]
        let title = entry.bind.description.flatMap { $0.isEmpty ? nil : $0 } ?? cheatTitle(command: entry.bind.command)
        result.append((entry.category, CheatRow(title: title, command: entry.bind.command, steps: steps, note: note)))
    }
    return result
}

/// The sheet for a list of binds. A bind shows when it runs on a press (or a hold, when the key has no plain bind) or a long
/// press, and is not hidden and not `noop`. The binds that work in every mode (`*`) are on the `main` page.
public func buildCheatsheet(_ binds: [CheatBind]) -> Cheatsheet {
    let plain = Set(binds.filter { $0.trigger == .press }.map { "\($0.mode)\u{0}\($0.keys)" })
    let shown = binds.filter { bind in
        guard !bind.hidden, bind.command != "noop" else { return false }
        switch bind.trigger {
        case .press, .longPress: return true
        case .hold: return !plain.contains("\(bind.mode)\u{0}\(bind.keys)")
        case .release: return false
        }
    }
    var used = Set<String>()
    var byMode: [String: [Entry]] = [:]
    for bind in shown {
        let chords = try? parseChordSequence(bind.keys)
        for chord in chords ?? [] { used.formUnion(cheatCaps(chord).filter(\.isModifier).map(\.text)) }
        let mode = bind.mode == universalMode ? "main" : bind.mode
        byMode[mode, default: []].append(Entry(bind: bind, chords: chords, category: cheatCategory(of: bind.command)))
    }
    let modes = byMode.keys.sorted { ($0 == "main" ? 0 : 1, $0) < ($1 == "main" ? 0 : 1, $1) }
    let pages = modes.map { mode -> CheatPage in
        var sections: [String: [CheatRow]] = [:]
        for (category, row) in rows(of: byMode[mode] ?? []) { sections[category, default: []].append(row) }
        let titles = sections.keys.sorted {
            let (a, b) = (sectionOrder.firstIndex(of: $0) ?? sectionOrder.count, sectionOrder.firstIndex(of: $1) ?? sectionOrder.count)
            return (a, $0) < (b, $1)
        }
        return CheatPage(mode: mode, sections: titles.map { CheatSection(title: $0, rows: sections[$0] ?? []) })
    }
    return Cheatsheet(pages: pages, legend: legendNames.filter { used.contains($0.0) }.map { (symbol: $0.0, name: $0.1) })
}

// MARK: - Columns

/// Splits sections into `count` columns of about the same height, in order: each section goes to the shortest column. A
/// section weighs its rows plus two (the title and the gap).
public func packColumns(_ sections: [CheatSection], count: Int) -> [[CheatSection]] {
    var columns = Array(repeating: [CheatSection](), count: max(1, count))
    var heights = Array(repeating: 0, count: columns.count)
    for section in sections {
        let target = heights.indices.min { (heights[$0], $0) < (heights[$1], $1) } ?? 0
        columns[target].append(section)
        heights[target] += section.rows.count + 2
    }
    return columns
}

/// The sheet as plain text, one bind per line: `alt+shift+H  # Swap left  (focus swap left)`. No colors, no columns, no
/// control codes, so `grep`, `less`, `more` and `cat` get the whole bind on a line. A chord of several steps is `hyper+W > H`.
public func renderPlainCheatsheet(_ sheet: Cheatsheet) -> String {
    let names = Dictionary(uniqueKeysWithValues: legendNames)
    func keys(_ row: CheatRow) -> String {
        row.steps.map { step in
            // `alt+L+H+K+J` is one row for four binds: the modifiers, then the keys that differ, as `alt+L/H/K/J`.
            let modifiers = step.filter(\.isModifier).map { names[$0.text] ?? $0.text }
            return (modifiers + [step.filter { !$0.isModifier }.map(\.text).joined(separator: "/")]).joined(separator: "+")
        }.joined(separator: " > ")
    }
    var lines: [String] = []
    for page in sheet.pages {
        for section in page.sections {
            if !lines.isEmpty { lines.append("") }
            lines.append("## \(page.mode) / \(section.title)")
            let width = section.rows.map { keys($0).count }.max() ?? 0
            for row in section.rows {
                let note = row.note.isEmpty ? "" : " (\(row.note))"
                lines.append(keys(row).padding(toLength: width, withPad: " ", startingAt: 0) + "  # " + row.title + note + "  [" + row.command + "]")
            }
        }
    }
    return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
}
