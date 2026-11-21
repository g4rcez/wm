import AppKit
import Cheatsheet
import struct Core.ResolvedStyle
import Platform
import Observation
import SwiftUI

/// What the cheatsheet panel shows and what the keys change: the page, the filter, and the size that the panel was given.
@MainActor @Observable
final class CheatsheetModel {
    var sheet: Cheatsheet
    var page: Int
    var query = ""
    var size: CGSize
    let theme: Theme

    init(sheet: Cheatsheet, page: Int, size: CGSize, theme: Theme) {
        self.sheet = sheet
        self.page = page
        self.size = size
        self.theme = theme
    }

    var rowHeight: CGFloat { CheatsheetMetrics.rowHeight(theme.style) }

    var current: CheatPage {
        sheet.pages.indices.contains(page) ? sheet.pages[page].filtered(by: query) : CheatPage(mode: "main", sections: [])
    }

    func move(_ delta: Int) {
        guard sheet.pages.count > 1 else { return }
        page = (page + delta + sheet.pages.count) % sheet.pages.count
    }

    /// The columns for the width of the panel (3 from 1000 points, 2 from 700), unless the style says how many.
    var columnCount: Int { CheatsheetMetrics.columns(forWidth: size.width) }
}

enum CheatsheetMetrics {
    static let columnSpacing: CGFloat = 44
    static let sectionSpacing: CGFloat = 26
    static let sectionTitleHeight: CGFloat = 30
    static let headerHeight: CGFloat = 112

    static func padding(_ style: ResolvedStyle) -> CGFloat { (30 * style.scale).rounded() }
    static func rowHeight(_ style: ResolvedStyle) -> CGFloat { CGFloat(style.cheatsheetRowHeight) }

    /// 3 columns from 1000 points, 2 from 700.
    static func columns(forWidth width: CGFloat) -> Int { width >= 1000 ? 3 : width >= 700 ? 2 : 1 }

    /// The height that the sections need in `count` columns, for the tallest page: the panel keeps one height while you filter.
    static func contentHeight(_ sheet: Cheatsheet, columns count: Int, rowHeight: CGFloat) -> CGFloat {
        sheet.pages.map { page in
            packColumns(page.sections, count: count).map { column in
                column.reduce(CGFloat(0)) { $0 + sectionTitleHeight + CGFloat($1.rows.count) * rowHeight } + CGFloat(max(0, column.count - 1)) * sectionSpacing
            }.max() ?? 0
        }.max() ?? 0
    }
}

struct CheatsheetView: View {
    let model: CheatsheetModel

    private var theme: Theme { model.theme }
    private var primary: Color { Color(nsColor: theme.foreground) }
    private var secondary: Color { Color(nsColor: theme.secondary) }
    private var tertiary: Color { Color(nsColor: theme.tertiary) }
    private var accent: Color { Color(nsColor: theme.accent) }

    /// The font of the style at `size` points (13 is the body size; `font_size` scales them all).
    private func font(_ size: CGFloat, _ weight: Font.Weight = .regular, rounded: Bool = false) -> Font {
        if let name = theme.style.font { return .custom(name, size: theme.size(size)).weight(weight) }
        return .system(size: theme.size(size), weight: weight, design: rounded ? .rounded : .default)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                content
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .frame(maxHeight: .infinity)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 8)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 14)
                })
        }
        .padding(CheatsheetMetrics.padding(theme.style))
        .frame(width: model.size.width, height: model.size.height, alignment: .topLeading)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Text("Keybinds")
                    .font(font(26, .bold, rounded: true))
                    .foregroundStyle(primary)
                if model.sheet.pages.count > 1 || model.sheet.pages.first?.mode != "main" { modeTabs }
                Spacer(minLength: 20)
                searchPill
            }
            HStack(spacing: 10) {
                if !model.sheet.legend.isEmpty {
                    ForEach(Array(model.sheet.legend.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 5) {
                            Text(item.symbol).font(font(13, .medium)).foregroundStyle(secondary)
                            Text(item.name).font(font(12)).foregroundStyle(tertiary)
                        }
                    }
                }
                Spacer()
                Text("esc to close").font(font(12)).foregroundStyle(tertiary)
            }
        }
        .frame(height: CheatsheetMetrics.headerHeight - 28, alignment: .top)
        .padding(.bottom, 4)
    }

    private var modeTabs: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.sheet.pages.enumerated()), id: \.offset) { index, page in
                let active = index == model.page
                Button { model.page = index } label: {
                    Text(page.mode)
                        .font(font(13, .semibold))
                        .foregroundStyle(active ? accent : secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(active ? accent.opacity(0.16) : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(primary.opacity(0.05)))
    }

    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(font(13, .medium)).foregroundStyle(tertiary)
            if model.query.isEmpty {
                Text("Type to filter").font(font(14)).foregroundStyle(tertiary)
            } else {
                Text(model.query).font(font(14)).foregroundStyle(primary).lineLimit(1).truncationMode(.head)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 230, height: 34, alignment: .leading)
        .background(Capsule().fill(primary.opacity(model.query.isEmpty ? 0.05 : 0.09)))
        .overlay(Capsule().strokeBorder(model.query.isEmpty ? Color.clear : accent.opacity(0.55), lineWidth: 1))
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        let page = model.current
        if page.sections.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: model.query.isEmpty ? "keyboard" : "magnifyingglass").font(font(30, .light)).foregroundStyle(tertiary)
                Text(model.query.isEmpty ? "No key binds in this mode" : "No key matches “\(model.query)”")
                    .font(font(15)).foregroundStyle(secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            let columns = packColumns(page.sections, count: model.columnCount)
            HStack(alignment: .top, spacing: CheatsheetMetrics.columnSpacing) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: CheatsheetMetrics.sectionSpacing) {
                        ForEach(column, id: \.title) { section in
                            sectionView(section)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private func sectionView(_ section: CheatSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title.uppercased())
                .font(font(11, .bold))
                .tracking(1.6)
                .foregroundStyle(accent)
                .frame(height: CheatsheetMetrics.sectionTitleHeight, alignment: .topLeading)
            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    Text(row.title)
                        .font(font(15))
                        .foregroundStyle(primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    keys(of: row)
                }
                .frame(height: model.rowHeight)
            }
        }
    }

    private func keys(of row: CheatRow) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(row.steps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Text("›").font(font(13, .medium)).foregroundStyle(tertiary).padding(.horizontal, 2) }
                ForEach(Array(step.enumerated()), id: \.offset) { _, cap in
                    KeyCap(cap: cap, theme: theme)
                }
            }
            if !row.note.isEmpty { Text(row.note).font(font(11)).foregroundStyle(tertiary).padding(.leading, 3) }
        }
        .fixedSize()
    }
}

/// One key as a small rounded box. A modifier is quieter than the key that goes with it.
struct KeyCap: View {
    let cap: CheatCap
    let theme: Theme

    private var radius: CGFloat { min(7, max(3, theme.cornerRadius / 3)) }

    var body: some View {
        Text(cap.text)
            .font(theme.style.monoFont.map { .custom($0, size: theme.size(cap.isModifier ? 13 : 12)) } ?? .system(size: theme.size(cap.isModifier ? 13 : 12), weight: .semibold, design: .rounded))
            .foregroundStyle(Color(nsColor: cap.isModifier ? theme.secondary : theme.foreground))
            .padding(.horizontal, 6)
            .frame(minWidth: 25, minHeight: 25)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color(nsColor: theme.foreground).opacity(cap.isModifier ? 0.045 : 0.09)))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color(nsColor: theme.foreground).opacity(cap.isModifier ? 0.09 : 0.15), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.10), radius: 0, x: 0, y: 1)
    }
}
