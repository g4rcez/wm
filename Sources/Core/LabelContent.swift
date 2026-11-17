import CoreGraphics

/// One key of the label's key list: the key as it is drawn on its chip, and what it does.
public struct LabelEntry: Sendable, Equatable {
    public var key: String
    public var text: String

    public init(key: String, text: String) {
        self.key = key
        self.text = text
    }
}

/// What the floating label shows. Either a plain message (`text`), or a name chip (`badge`: the binding mode, or the
/// keys of a prefix) followed by the keys that can be pressed next (`entries`).
public struct LabelContent: Sendable, Equatable {
    public var badge: String?
    public var entries: [LabelEntry]
    public var text: String?

    public init(badge: String? = nil, entries: [LabelEntry] = [], text: String? = nil) {
        self.badge = badge
        self.entries = entries
        self.text = text
    }
}

public enum PillLayout {
    /// The shape of the key list: a grid that is filled row by row, so the order reads left to right. `columns` is
    /// `ceil(count / rows)`; the item `i` is in row `i / columns` and column `i % columns`. A column is as wide as its widest
    /// key chip plus `keyGap` plus its widest label, so keys and labels line up in every row.
    public struct Grid: Sendable, Equatable {
        public var rows: Int
        public var columns: Int
        /// How many of the items fit: the first ones. Less than the count when `truncated`.
        public var visible: Int
        public var truncated: Bool
        /// A list is filled column by column (down, then the next column); a grid row by row.
        public var columnMajor = false

        /// The row and the column of an item.
        public func position(of index: Int) -> (row: Int, column: Int) {
            columnMajor ? (index % rows, index / rows) : (index / columns, index % columns)
        }
    }

    /// A list for a side of the screen: one key per line, filled column by column. With more than `maxRows` items it
    /// gets more columns, so it does not grow taller than the screen, and the columns have the same height (up to one
    /// item): 44 items with room for 26 rows are 2 columns of 22, not 26 and 18.
    public static func list(count: Int, maxRows: Int) -> Grid {
        guard count > 0 else { return Grid(rows: 0, columns: 0, visible: 0, truncated: false, columnMajor: true) }
        let capacity = max(maxRows, 1)
        let columns = (count + capacity - 1) / capacity
        return Grid(rows: (count + columns - 1) / columns, columns: columns, visible: count, truncated: false, columnMajor: true)
    }

    /// The grid with the fewest rows (at most `maxRows`) that is not wider than `maxWidth`. When even `maxRows` rows are
    /// too wide, it has as many columns as fit (at least one) and the rest is left out.
    public static func grid(
        keyWidths: [CGFloat], labelWidths: [CGFloat], keyGap: CGFloat, columnGap: CGFloat, maxWidth: CGFloat, maxRows: Int = 3
    ) -> Grid {
        let count = keyWidths.count
        guard count > 0 else { return Grid(rows: 0, columns: 0, visible: 0, truncated: false) }

        func width(rows: Int, columns: Int, visible: Int) -> CGFloat {
            var total: CGFloat = 0
            for column in 0..<columns {
                let members = (0..<visible).filter { $0 % columns == column }
                guard !members.isEmpty else { continue }
                total += members.map { keyWidths[$0] }.max()! + keyGap + members.map { labelWidths[$0] }.max()!
            }
            return total + columnGap * CGFloat(columns - 1)
        }

        for rows in 1...max(maxRows, 1) {
            let columns = (count + rows - 1) / rows
            if width(rows: rows, columns: columns, visible: count) <= maxWidth {
                return Grid(rows: (count + columns - 1) / columns, columns: columns, visible: count, truncated: false)
            }
        }
        let rows = max(maxRows, 1)
        var columns = (count + rows - 1) / rows
        while columns > 1, width(rows: rows, columns: columns, visible: min(count, rows * columns)) > maxWidth { columns -= 1 }
        return Grid(rows: rows, columns: columns, visible: min(count, rows * columns), truncated: true)
    }
}
