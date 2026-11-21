import Foundation

/// The colors of the sheet in a terminal (256-color codes). Off, the text has no escape codes at all and a key cap is `[X]`.
public struct CheatPalette: Sendable {
    public let enabled: Bool

    public init(enabled: Bool) { self.enabled = enabled }

    private func paint(_ code: String, _ text: String) -> String {
        enabled && !text.isEmpty ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
    }

    func title(_ text: String) -> String { paint("1;38;5;255", text) }
    func section(_ text: String) -> String { paint("1;38;5;74", text.uppercased()) }
    func dim(_ text: String) -> String { paint("38;5;245", text) }
    func faint(_ text: String) -> String { paint("38;5;240", text) }
    func row(_ text: String) -> String { paint("38;5;252", text) }
    func tab(_ text: String, active: Bool) -> String { active ? paint("1;48;5;74;38;5;16", " \(text) ") : paint("38;5;245", " \(text) ") }
    func accent(_ text: String) -> String { paint("38;5;74", text) }

    func cap(_ cap: CheatCap) -> String {
        guard enabled else { return "[\(cap.text)]" }
        return cap.isModifier ? paint("48;5;236;38;5;110", " \(cap.text) ") : paint("1;48;5;238;38;5;255", " \(cap.text) ")
    }

    /// The cap adds a blank at each side (or a bracket).
    var capPadding: Int { 2 }
}

/// A piece of text with its width on screen, so that colors do not count.
struct Cell {
    var text: String
    var width: Int

    static let empty = Cell(text: "", width: 0)

    static func + (lhs: Cell, rhs: Cell) -> Cell { Cell(text: lhs.text + rhs.text, width: lhs.width + rhs.width) }

    func padded(to total: Int) -> Cell {
        Cell(text: text + String(repeating: " ", count: max(0, total - width)), width: max(width, total))
    }
}

private func keysCell(_ row: CheatRow, palette: CheatPalette) -> Cell {
    var parts: [Cell] = []
    for (index, step) in row.steps.enumerated() {
        if index > 0 { parts.append(Cell(text: " " + palette.dim("›") + " ", width: 3)) }
        let caps = step.map { Cell(text: palette.cap($0), width: $0.text.count + palette.capPadding) }
        for (position, cap) in caps.enumerated() {
            parts.append(cap)
            if position < caps.count - 1 { parts.append(Cell(text: " ", width: 1)) }
        }
    }
    if !row.note.isEmpty { parts.append(Cell(text: " " + palette.dim(row.note), width: 1 + row.note.count)) }
    return parts.reduce(Cell.empty, +)
}

/// One row of a column: the title at the left, a dotted line, then the keys at the right edge.
private func rowCell(_ row: CheatRow, width: Int, palette: CheatPalette) -> Cell {
    let keys = keysCell(row, palette: palette)
    let room = max(4, width - keys.width - 2)
    let title = row.title.count > room ? String(row.title.prefix(room - 1)) + "…" : row.title
    let gap = max(1, width - title.count - keys.width)
    let leader = gap >= 4 ? " " + String(repeating: "·", count: gap - 2) + " " : String(repeating: " ", count: gap)
    return Cell(text: palette.row(title) + palette.faint(leader) + keys.text, width: title.count + leader.count + keys.width)
}

/// The lines of one column: for every section its title, its rows and a blank line.
private func columnCells(_ sections: [CheatSection], width: Int, palette: CheatPalette) -> [Cell] {
    var cells: [Cell] = []
    for (index, section) in sections.enumerated() {
        if index > 0 { cells.append(.empty) }
        cells.append(Cell(text: palette.section(section.title), width: section.title.count))
        for row in section.rows { cells.append(rowCell(row, width: width, palette: palette)) }
    }
    return cells
}

/// The body of a page as lines: sections in columns that fit `width`.
public func renderPageBody(_ page: CheatPage, width: Int, palette: CheatPalette) -> [String] {
    let margin = 2
    let gutter = 5
    let minimum = 40
    let count = max(1, min(4, (width - margin * 2 + gutter) / (minimum + gutter)))
    let columnWidth = max(minimum - 8, (width - margin * 2 - gutter * (count - 1)) / count)
    let columns = packColumns(page.sections, count: count).map { columnCells($0, width: columnWidth, palette: palette) }
    let height = columns.map(\.count).max() ?? 0
    return (0..<height).map { line in
        var text = String(repeating: " ", count: margin)
        for (index, column) in columns.enumerated() {
            let cell = line < column.count ? column[line] : .empty
            text += index == columns.count - 1 ? cell.text : cell.padded(to: columnWidth).text + String(repeating: " ", count: gutter)
        }
        return text.trimmingTrailingBlanks
    }
}

extension String {
    var trimmingTrailingBlanks: String {
        var text = self
        while text.hasSuffix(" ") { text.removeLast() }
        return text
    }
}

private func headerLines(_ sheet: Cheatsheet, page: Int, query: String, width: Int, palette: CheatPalette, hint: String) -> [String] {
    var left = Cell(text: "  " + palette.title("Keybinds"), width: 10)
    if sheet.pages.count > 1 || sheet.pages.first?.mode != "main" {
        left = left + Cell(text: "  ", width: 2)
        for (index, item) in sheet.pages.enumerated() {
            left = left + Cell(text: palette.tab(item.mode, active: index == page), width: item.mode.count + 2)
        }
    }
    let right = Cell(text: palette.dim(hint), width: hint.count + 2)
    let gap = max(2, width - left.width - right.width)
    var lines = [left.text + String(repeating: " ", count: gap) + right.text]
    var second = "  "
    if !sheet.legend.isEmpty { second += palette.dim(sheet.legendText) }
    lines.append(second.trimmingTrailingBlanks)
    return lines
}

/// Every page one after the other, for a terminal that is not interactive (or a pipe). A page of a mode other than `main` gets
/// a title line. `query` keeps the rows that match.
public func renderStatic(_ sheet: Cheatsheet, query: String = "", width: Int, palette: CheatPalette) -> String {
    var lines = ["  " + palette.title("Keybinds")]
    if !sheet.legend.isEmpty { lines.append("  " + palette.dim(sheet.legendText)) }
    let named = sheet.pages.count > 1 || sheet.pages.first?.mode != "main"
    var shown = false
    for page in sheet.pages {
        let filtered = page.filtered(by: query)
        guard filtered.rowCount > 0 else { continue }
        shown = true
        lines.append("")
        if named {
            lines.append("  " + palette.tab(page.mode, active: true))
            lines.append("")
        }
        lines += renderPageBody(filtered, width: width, palette: palette)
    }
    if !shown { lines += ["", "  " + palette.dim(query.isEmpty ? "no key binds: run `wm init` to make a config" : "no key matches \"\(query)\"")] }
    return lines.joined(separator: "\n") + "\n"
}

/// The whole screen of the interactive sheet: exactly `height` lines, and the largest scroll that the page allows.
public func renderScreen(
    _ sheet: Cheatsheet, page: Int, query: String, scroll: Int, width: Int, height: Int, palette: CheatPalette
) -> (lines: [String], maxScroll: Int) {
    let hint = query.isEmpty ? "type to filter · esc to close" : "esc clears the filter"
    var lines = headerLines(sheet, page: page, query: query, width: width, palette: palette, hint: hint)
    lines.append("  " + (query.isEmpty ? palette.faint("›  filter") : palette.accent("›") + "  " + palette.row(query) + palette.accent("▏")))
    lines.append("")
    let current = sheet.pages.indices.contains(page) ? sheet.pages[page].filtered(by: query) : CheatPage(mode: "main", sections: [])
    var body = renderPageBody(current, width: width, palette: palette)
    if body.isEmpty { body = ["  " + palette.dim(query.isEmpty ? "no key binds in this mode" : "no key matches")] }
    let room = max(1, height - lines.count - 2)
    let maxScroll = max(0, body.count - room)
    let offset = min(max(0, scroll), maxScroll)
    var visible = Array(body[offset..<min(body.count, offset + room)])
    while visible.count < room { visible.append("") }
    let keys = (sheet.pages.count > 1 ? "←/→ mode   " : "") + (maxScroll > 0 ? "↑/↓ scroll   " : "") + "esc close"
    let position = maxScroll > 0 ? palette.faint("   \(offset + 1)–\(min(body.count, offset + room)) of \(body.count)") : ""
    lines += visible
    lines.append("  " + palette.faint(String(repeating: "─", count: max(0, width - 4))))
    lines.append("  " + palette.dim(keys) + position)
    return (Array(lines.prefix(height)), maxScroll)
}
