import CoreGraphics

/// Ribbon-style arrangements: a group of consecutive windows fills one screen of the scrolling strip in a fixed
/// pattern. The cells are in reading order (left to right, top to bottom); the windows of the group take them in the
/// order they have in the strip. "Back to the chain" (no template) is the normal strip of single columns.
///
/// The built-in templates are `static` values (`allCases` lists them). A config can make its own with `init`.
public struct SplitTemplate: Sendable, Equatable, Codable {
    /// What `layout tile <name>` takes. Unique in a list of templates.
    public let name: String
    /// The one-character key that picks the template in the picker, or `nil` for a template that has none.
    /// The built-in grids use their number of windows; the others use a letter: `l` and `r` (the stack on the left or
    /// on the right), `t` (thirds), `q` (three quarters on the left) and `w` (three quarters on the right). `c` is the
    /// chain (see `TemplateGlyph`).
    public let key: String?
    /// The text in the menu bar menu.
    public let title: String
    /// The cells as fractions of the area the group fills: x, y, width, height, each 0...1.
    public let cells: [CGRect]
    /// Where the cells sit, as fractions of the area that the layout tiles: x, y, width, height. The whole area by default.
    /// A smaller area leaves a margin, for example the middle two thirds.
    public let area: CGRect

    /// The whole area.
    public static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

    public init(name: String, key: String? = nil, title: String? = nil, cells: [CGRect], area: CGRect = SplitTemplate.unit) {
        self.name = name
        self.key = key
        self.title = title ?? name
        self.cells = cells
        self.area = area
    }

    /// How many windows the group has.
    public var count: Int { cells.count }

    /// A template with one cell and a smaller area (`center`). It does not arrange windows: the tiling layout keeps its
    /// windows as they are and lays them out inside the area, for any number of windows.
    public var isFrame: Bool { cells.count == 1 }

    /// Two windows side by side.
    public static let two = SplitTemplate(
        name: "2", key: "2", title: "Two across",
        cells: [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)])
    /// Three windows in a row.
    public static let three = SplitTemplate(
        name: "3", key: "3", title: "Three in a row",
        cells: (0..<3).map { CGRect(x: Double($0) / 3, y: 0, width: 1.0 / 3, height: 1) })
    /// Four windows, two across and two down.
    public static let four = SplitTemplate(
        name: "4", key: "4", title: "Four in a grid",
        cells: [
            CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ])
    /// Five windows: three on top, two below that stretch to fill the width.
    public static let five = SplitTemplate(
        name: "5", key: "5", title: "Five in a grid",
        cells: (0..<3).map { CGRect(x: Double($0) / 3, y: 0, width: 1.0 / 3, height: 0.5) }
            + (0..<2).map { CGRect(x: Double($0) / 2, y: 0.5, width: 0.5, height: 0.5) })
    /// Six windows in two rows of three.
    public static let six = SplitTemplate(
        name: "6", key: "6", title: "Six in a grid",
        cells: (0..<6).map { CGRect(x: Double($0 % 3) / 3, y: Double($0 / 3) / 2, width: 1.0 / 3, height: 0.5) })
    /// Two stacked on the left, one full-height window on the right. (Ribbon: `stack-left`.)
    public static let stackLeft = SplitTemplate(
        name: "2+1", key: "l", title: "Two stacked, one beside",
        cells: [
            CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
        ])
    /// One full-height window on the left, two stacked on the right. (Ribbon: `stack-right`.)
    public static let stackRight = SplitTemplate(
        name: "1+2", key: "r", title: "One, then two stacked",
        cells: [
            CGRect(x: 0, y: 0, width: 0.5, height: 1),
            CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
            CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ])
    /// The focused window takes two thirds of the width, the next window the last third.
    public static let twoThirds = SplitTemplate(
        name: "2/3", key: "t", title: "Focus two thirds, one third beside",
        cells: [CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1), CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)])
    /// The focused window takes three quarters of the width, the next window the last quarter.
    public static let threeQuarters = SplitTemplate(
        name: "3/4", key: "q", title: "Focus three quarters, one quarter beside",
        cells: [CGRect(x: 0, y: 0, width: 0.75, height: 1), CGRect(x: 0.75, y: 0, width: 0.25, height: 1)])
    /// The mirror of `threeQuarters`, for a workflow aligned to the right: the focused window takes the left quarter, the
    /// next window the right three quarters.
    public static let oneQuarter = SplitTemplate(
        name: "1/4", key: "w", title: "Focus one quarter, three quarters beside",
        cells: [CGRect(x: 0, y: 0, width: 0.25, height: 1), CGRect(x: 0.25, y: 0, width: 0.75, height: 1)])

    /// The windows share the middle two thirds of the width, with a sixth of margin on each side. Tiling layout only.
    public static let centered = SplitTemplate(
        name: "center", key: "z", title: "Centered, two thirds wide",
        cells: [unit], area: CGRect(x: 1.0 / 6, y: 0, width: 2.0 / 3, height: 1))

    /// The built-in templates, in the order of Ribbon's menu, then the wide ones. Both layouts can use them.
    public static let allCases: [SplitTemplate] = [
        .two, .three, .four, .five, .six, .stackLeft, .stackRight, .twoThirds, .threeQuarters, .oneQuarter,
    ]

    /// What the tiling layout lists without `templates` in the config: the grids and the centered frame.
    public static let tilingCases: [SplitTemplate] = allCases + [.centered]

    /// The built-in template with this name.
    public static func builtIn(named name: String) -> SplitTemplate? {
        tilingCases.first { $0.name == name }
    }

    /// Why `cells` cannot be a template, or `nil` when they can: two or more cells that fill the unit square with
    /// straight cuts (the tiling layout builds a split tree from them). One cell is a frame: it is the whole unit square, and
    /// `area` is smaller than the unit square. `area` stays inside the unit square.
    public static func shapeError(_ cells: [CGRect], area: CGRect = unit) -> String? {
        let eps = 1e-9
        func inside(_ rect: CGRect) -> Bool {
            rect.width > eps && rect.height > eps && rect.minX > -eps && rect.minY > -eps && rect.maxX < 1 + eps && rect.maxY < 1 + eps
        }
        guard inside(area) else { return "the area needs a positive size and must stay inside 0 to 1" }
        let isWholeArea = abs(area.minX) < eps && abs(area.minY) < eps && abs(area.width - 1) < eps && abs(area.height - 1) < eps
        if cells.count == 1, !isWholeArea {
            let cell = cells[0]
            let isUnit = abs(cell.minX) < eps && abs(cell.minY) < eps && abs(cell.width - 1) < eps && abs(cell.height - 1) < eps
            return isUnit ? nil : "a template with one cell and an area needs the cell { 0, 0, 1, 1 }"
        }
        guard cells.count >= 2 else { return "a template needs at least two cells" }
        guard cells.allSatisfy(inside) else { return "every cell needs a positive size and must stay inside 0 to 1" }
        let total = cells.reduce(0.0) { $0 + Double($1.width * $1.height) }
        guard abs(total - 1) < 1e-6, DwindleEngine.canPartition(cells) else {
            return "the cells must fill the screen with straight cuts and no overlap"
        }
        return nil
    }

    // A state file that an older version wrote has the name of a built-in template (a string) where this has the struct.
    private enum CodingKeys: String, CodingKey { case name, key, title, cells, area }

    public init(from decoder: Decoder) throws {
        if let name = try? decoder.singleValueContainer().decode(String.self) {
            guard let template = Self.builtIn(named: name) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown template '\(name)'"))
            }
            self = template
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            name: try values.decode(String.self, forKey: .name), key: try values.decodeIfPresent(String.self, forKey: .key),
            title: try values.decode(String.self, forKey: .title), cells: try values.decode([CGRect].self, forKey: .cells),
            area: try values.decodeIfPresent(CGRect.self, forKey: .area) ?? Self.unit)
    }

    /// The cell next to cell `index` in `direction`: the one that touches the edge on that side and overlaps it the
    /// most; `nil` at the edge of the template.
    public func neighbor(of index: Int, _ direction: Direction) -> Int? {
        let cells = cells
        let source = cells[index]
        let eps = 1e-9
        var best: (index: Int, overlap: CGFloat)?
        for (other, cell) in cells.enumerated() where other != index {
            let touches: Bool
            let overlap: CGFloat
            switch direction {
            case .left: touches = abs(cell.maxX - source.minX) < eps; overlap = Self.overlap(cell.minY, cell.maxY, source.minY, source.maxY)
            case .right: touches = abs(cell.minX - source.maxX) < eps; overlap = Self.overlap(cell.minY, cell.maxY, source.minY, source.maxY)
            case .up: touches = abs(cell.maxY - source.minY) < eps; overlap = Self.overlap(cell.minX, cell.maxX, source.minX, source.maxX)
            case .down: touches = abs(cell.minY - source.maxY) < eps; overlap = Self.overlap(cell.minX, cell.maxX, source.minX, source.maxX)
            }
            guard touches, overlap > eps else { continue }
            if best == nil || overlap > best!.overlap + eps { best = (other, overlap) }
        }
        return best?.index
    }

    /// The cell that touches the left (`fromLeft`) or right edge and is nearest to the height `y` (0...1).
    public func entryCell(fromLeft: Bool, nearY y: CGFloat) -> Int {
        let cells = cells
        let edge = cells.indices.filter { fromLeft ? cells[$0].minX < 1e-9 : cells[$0].maxX > 1 - 1e-9 }
        return edge.min { abs(cells[$0].midY - y) < abs(cells[$1].midY - y) } ?? 0
    }

    private static func overlap(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> CGFloat {
        max(0, min(a1, b1) - max(a0, b0))
    }
}
