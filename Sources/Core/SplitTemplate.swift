import CoreGraphics

/// Ribbon-style arrangements: a group of consecutive windows fills one screen of the scrolling strip in a fixed
/// pattern. The cells are in reading order (left to right, top to bottom); the windows of the group take them in the
/// order they have in the strip. "Back to the chain" (no template) is the normal strip of single columns.
public enum SplitTemplate: String, Sendable, CaseIterable, Codable {
    /// Two windows side by side.
    case two = "2"
    /// Three windows in a row.
    case three = "3"
    /// Four windows, two across and two down.
    case four = "4"
    /// Five windows: three on top, two below that stretch to fill the width.
    case five = "5"
    /// Six windows in two rows of three.
    case six = "6"
    /// Two stacked on the left, one full-height window on the right. (Ribbon: `stack-left`.)
    case stackLeft = "2+1"
    /// One full-height window on the left, two stacked on the right. (Ribbon: `stack-right`.)
    case stackRight = "1+2"
    /// The focused window takes two thirds of the width, the next window the last third.
    case twoThirds = "2/3"
    /// The focused window takes three quarters of the width, the next window the last quarter.
    case threeQuarters = "3/4"
    /// The mirror of `threeQuarters`, for a workflow aligned to the right: the focused window takes the left quarter, the
    /// next window the right three quarters.
    case oneQuarter = "1/4"

    /// How many windows the group has.
    public var count: Int { cells.count }

    /// The cells as fractions of the area the group fills: x, y, width, height, each 0...1.
    public var cells: [CGRect] {
        switch self {
        case .two:
            [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]
        case .three:
            (0..<3).map { CGRect(x: Double($0) / 3, y: 0, width: 1.0 / 3, height: 1) }
        case .stackLeft:
            [
                CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
            ]
        case .stackRight:
            [
                CGRect(x: 0, y: 0, width: 0.5, height: 1),
                CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            ]
        case .four:
            [
                CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5),
            ]
        case .five:
            (0..<3).map { CGRect(x: Double($0) / 3, y: 0, width: 1.0 / 3, height: 0.5) }
                + (0..<2).map { CGRect(x: Double($0) / 2, y: 0.5, width: 0.5, height: 0.5) }
        case .twoThirds:
            [CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1), CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)]
        case .threeQuarters:
            [CGRect(x: 0, y: 0, width: 0.75, height: 1), CGRect(x: 0.75, y: 0, width: 0.25, height: 1)]
        case .oneQuarter:
            [CGRect(x: 0, y: 0, width: 0.25, height: 1), CGRect(x: 0.25, y: 0, width: 0.75, height: 1)]
        case .six:
            (0..<6).map { CGRect(x: Double($0 % 3) / 3, y: Double($0 / 3) / 2, width: 1.0 / 3, height: 0.5) }
        }
    }

    /// The one-character key that picks the template in the picker. The grids are named by their number of windows
    /// and use that number. The others use a letter: `l` and `r` (the stack on the left or on the right), `t` (thirds)
    /// `q` (three quarters on the left) and `w` (three quarters on the right). `c` is the chain (see `TemplateGlyph`).
    public var key: String {
        switch self {
        case .stackLeft: "l"
        case .stackRight: "r"
        case .twoThirds: "t"
        case .threeQuarters: "q"
        case .oneQuarter: "w"
        case .two, .three, .four, .five, .six: rawValue
        }
    }

    /// The short name in Ribbon's menu.
    public var title: String {
        switch self {
        case .two: "Two across"
        case .three: "Three in a row"
        case .stackLeft: "Two stacked, one beside"
        case .stackRight: "One, then two stacked"
        case .four: "Four in a grid"
        case .five: "Five in a grid"
        case .six: "Six in a grid"
        case .twoThirds: "Focus two thirds, one third beside"
        case .threeQuarters: "Focus three quarters, one quarter beside"
        case .oneQuarter: "Focus one quarter, three quarters beside"
        }
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
