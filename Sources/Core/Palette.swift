import Foundation

/// What the command palette lists. `all` and `apps` are the running apps with their windows; the others list one kind.
/// `tabs` are the tabs of browsers and terminals.
public enum PaletteMode: String, Sendable, CaseIterable {
    case all, windows, apps, tabs, commands, menu
}

/// What the user typed, split into the list to search and the words to search for.
public struct PaletteQuery: Equatable, Sendable {
    public var mode: PaletteMode
    public var text: String

    public init(mode: PaletteMode, text: String) {
        self.mode = mode
        self.text = text
    }

    /// `>` at the start picks the commands and `/` the menu items of the frontmost app. Without one of them the query
    /// searches the list that `mode` names. The space after the prefix is not part of the text.
    public static func parse(_ input: String, default mode: PaletteMode = .all) -> PaletteQuery {
        let trimmed = input.drop { $0 == " " }
        let rest = { (text: Substring) in String(text.dropFirst().drop { $0 == " " }) }
        if trimmed.hasPrefix(">") { return PaletteQuery(mode: .commands, text: rest(trimmed)) }
        if trimmed.hasPrefix("/") { return PaletteQuery(mode: .menu, text: rest(trimmed)) }
        return PaletteQuery(mode: mode, text: String(trimmed))
    }
}

/// One row of the palette.
public struct PaletteEntry: Sendable, Equatable {
    /// `windows`, `apps`, `tabs`, `commands` or `menu`.
    public var kind: PaletteMode
    public var title: String
    public var detail: String
    /// What the app needs to run the row: a window id, an app path, a command, a menu token.
    public var key: String

    public init(kind: PaletteMode, title: String, detail: String = "", key: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.key = key
    }
}

/// How well `query` matches `text`: its letters in order, anywhere, ignoring case. `nil` when they do not. Letters that
/// follow each other, and letters at the start of a word, score more; letters far from the last match score less.
public func fuzzyScore(_ query: String, _ text: String) -> Int? {
    let wanted = Array(query.lowercased().filter { !$0.isWhitespace })
    let haystack = Array(text.lowercased())
    guard !wanted.isEmpty else { return 0 }
    var score = 0
    var position = 0
    var previous = -2
    for letter in wanted {
        guard let found = haystack[position...].firstIndex(of: letter) else { return nil }
        score += 10
        if found == previous + 1 { score += 15 }
        if found == 0 { score += 20 } else if !haystack[found - 1].isLetter && !haystack[found - 1].isNumber { score += 12 }
        score -= min(found - position, 8)
        previous = found
        position = found + 1
    }
    // A shorter text that matches is a closer match.
    return score - min(haystack.count / 8, 10)
}

/// The entries that `query` finds, best first. Without text every entry of the mode stays, in the order given. A match in
/// the title beats a match in the detail. The `all` list finds tabs too, but only once there is text: without text it is
/// the apps with their windows. The `tabs` list has the tabs and the windows that the caller puts in it: a window is the
/// tab of an app that has no tabs.
public func rank(_ entries: [PaletteEntry], query: PaletteQuery) -> [PaletteEntry] {
    let hasText = !query.text.trimmingCharacters(in: .whitespaces).isEmpty
    let listed = entries.filter { entry in
        switch query.mode {
        case .all: entry.kind == .windows || entry.kind == .apps || (entry.kind == .tabs && hasText)
        case .apps: entry.kind == .windows || entry.kind == .apps
        case .tabs: entry.kind == .tabs || entry.kind == .windows
        default: entry.kind == query.mode
        }
    }
    guard hasText else { return listed }
    let scored: [(entry: PaletteEntry, score: Int, order: Int)] = listed.enumerated().compactMap { index, entry in
        let title = fuzzyScore(query.text, entry.title)
        let detail = fuzzyScore(query.text, entry.detail).map { $0 - 25 }
        guard let best = [title, detail].compactMap({ $0 }).max() else { return nil }
        return (entry, best, index)
    }
    return scored.sorted { ($1.score, $0.order) < ($0.score, $1.order) }.map(\.entry)
}

/// A running app for the palette.
public struct PaletteApp: Sendable, Equatable {
    public var pid: Int32
    public var name: String

    public init(pid: Int32, name: String) {
        self.pid = pid
        self.name = name
    }
}

/// A window that the palette can focus.
public struct PaletteWindow: Sendable, Equatable {
    public var id: WindowID
    public var pid: Int32
    public var title: String
    /// Where the window is, for example `workspace 2 · mark:mail`.
    public var place: String

    public init(id: WindowID, pid: Int32, title: String, place: String) {
        self.id = id
        self.pid = pid
        self.title = title
        self.place = place
    }
}

/// The running apps, each one followed by its windows. An app with one window is one row: the detail of the row is the
/// title and the place of that window. The app with the most recent window comes first; apps without a window follow, by
/// name. `recent` lists window ids, most recent first.
public func paletteAppGroups(apps: [PaletteApp], windows: [PaletteWindow], recent: [WindowID]) -> [PaletteEntry] {
    let rank = { (id: WindowID) in recent.firstIndex(of: id) ?? Int.max }
    let byApp = Dictionary(grouping: windows, by: \.pid).mapValues { $0.sorted { (rank($0.id), $0.id) < (rank($1.id), $1.id) } }
    let ordered = apps.sorted { left, right in
        let l = byApp[left.pid]?.first.map { (rank($0.id), $0.id) }
        let r = byApp[right.pid]?.first.map { (rank($0.id), $0.id) }
        switch (l, r) {
        case let (l?, r?): return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }
    return ordered.flatMap { app -> [PaletteEntry] in
        let own = byApp[app.pid] ?? []
        if let only = own.first, own.count == 1 {
            let title = only.title.caseInsensitiveCompare(app.name) == .orderedSame ? "" : only.title
            let detail = [title, only.place].filter { !$0.isEmpty }.joined(separator: " · ")
            return [PaletteEntry(kind: .apps, title: app.name, detail: detail, key: String(app.pid))]
        }
        let windows = own.map { PaletteEntry(kind: .windows, title: $0.title, detail: app.name + " · " + $0.place, key: String($0.id)) }
        return [PaletteEntry(kind: .apps, title: app.name, key: String(app.pid))] + windows
    }
}

/// The picture that a command gets in the palette. Each case has its own drawing.
public enum CommandGlyph: Equatable, Sendable {
    case focus(Direction), focusBack, move(Direction), swap(Direction), resize, close, float, fullscreen, maximize
    case nativeFullscreen, mark, sendWorkspace, sendMonitor, workspace, special, layoutTiling, layoutScrolling, layoutMaster
    case balance, rotate, flip, split, column, stack, preselect, overview, switcher, pointer, mode, notify, daemon, generic
}

/// The glyph for the words of a command. The longest known command path wins; a direction word turns `focus`, `move` and
/// `swap` into their arrow.
public func commandGlyph(for words: [String]) -> CommandGlyph {
    let direction = words.lazy.compactMap { Direction(rawValue: $0) }.first ?? .right
    let path = { (count: Int) in words.prefix(count).joined(separator: " ") }
    switch path(3) {
    case "window send workspace": return .sendWorkspace
    case "window send monitor": return .sendMonitor
    case "workspace move monitor": return .sendMonitor
    case "layout set scrolling": return .layoutScrolling
    case "layout set master": return .layoutMaster
    case "window native-fullscreen": return .nativeFullscreen
    default: break
    }
    switch path(2) {
    case "focus back": return .focusBack
    case "window close": return .close
    case "window float", "window raise-floating", "window rescue", "window pseudo": return .float
    case "window fullscreen": return .fullscreen
    case "window maximize": return .maximize
    case "window native-fullscreen": return .nativeFullscreen
    case "window mark", "window unmark", "focus mark": return .mark
    case "focus app": return .focus(.right)
    case "window snap": return .float
    case "workspace special": return .special
    case "layout balance": return .balance
    case "layout rotate": return .rotate
    case "layout flip": return .flip
    case "layout split": return .split
    case "layout column": return .column
    case "layout master": return .layoutMaster
    case "layout stack": return .stack
    case "layout preselect": return .preselect
    case "layout tile", "layout set": return .layoutTiling
    case "daemon start", "daemon stop", "daemon status", "daemon reload": return .daemon
    default: break
    }
    switch words.first {
    case "focus": return .focus(direction)
    case "move": return .move(direction)
    case "swap": return .swap(direction)
    case "resize": return .resize
    case "workspace": return .workspace
    case "layout": return .layoutTiling
    case "overview": return .overview
    case "switcher": return .switcher
    case "pointer": return .pointer
    case "mode": return .mode
    case "notify": return .notify
    default: return .generic
    }
}

/// Where the user left the palette: the center and the top edge as fractions of the visible frame of a screen, counted from
/// the top left. A fraction, not a point, so the same spot holds on every screen.
public struct PalettePosition: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Where the palette opens until it is moved: centered, a little above the middle.
    public static let standard = PalettePosition(x: 0.5, y: 0.22)
}

/// The fractions for a palette whose top edge is at `topCenter` (a point of the screen, y up) on a screen of `area`.
public func palettePosition(topCenter: CGPoint, in area: CGRect) -> PalettePosition {
    guard area.width > 0, area.height > 0 else { return .standard }
    return PalettePosition(x: (topCenter.x - area.minX) / area.width, y: (area.maxY - topCenter.y) / area.height)
}

/// The top center of a palette of `width` on a screen of `area` (y up). The palette stays inside the area sideways, and its
/// top keeps 100 points above the bottom edge, so the field can always be reached.
public func paletteTopCenter(_ saved: PalettePosition?, in area: CGRect, width: CGFloat) -> CGPoint {
    let position = saved ?? .standard
    let half = min(width, area.width) / 2
    let x = min(max(area.minX + position.x * area.width, area.minX + half), area.maxX - half)
    let y = min(max(area.maxY - position.y * area.height, area.minY + min(100, area.height)), area.maxY)
    return CGPoint(x: x, y: y)
}
