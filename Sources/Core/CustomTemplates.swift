import CoreGraphics
import Foundation

/// The frames that the user draws on the grid of the template picker. A frame is a one-cell template with a smaller area
/// (like `center`): the tiled windows share that part of the screen. They live in a file next to the state file, so they
/// survive a restart.
public enum CustomTemplates {
    /// The most frames that wm keeps. Drawing a new one past this drops the oldest.
    public static let limit = 24

    /// The frame that covers `spanColumns` by `spanRows` cells of a grid, from the cell (`column`, `row`) (0 is the top
    /// left). `nil` when it leaves the grid or covers all of it (that is a maximized window, not a frame).
    public static func gridFrame(columns: Int, rows: Int, column: Int, row: Int, spanColumns: Int, spanRows: Int) -> SplitTemplate? {
        guard columns > 0, rows > 0, column >= 0, row >= 0, spanColumns > 0, spanRows > 0,
              column + spanColumns <= columns, row + spanRows <= rows,
              spanColumns < columns || spanRows < rows
        else { return nil }
        let area = CGRect(
            x: Double(column) / Double(columns), y: Double(row) / Double(rows),
            width: Double(spanColumns) / Double(columns), height: Double(spanRows) / Double(rows))
        return SplitTemplate(
            name: "frame-\(column)-\(row)-\(spanColumns)x\(spanRows)-of-\(columns)x\(rows)", key: nil,
            title: "Frame \(spanColumns)x\(spanRows) at \(column),\(row)", cells: [SplitTemplate.unit], area: area)
    }

    /// `list` with `template` last. A template with the same name moves to the end instead of repeating.
    public static func adding(_ template: SplitTemplate, to list: [SplitTemplate]) -> [SplitTemplate] {
        Array((list.filter { $0.name != template.name } + [template]).suffix(limit))
    }

    /// The saved frames. A missing, damaged or invalid file gives no frames; an invalid entry is dropped.
    public static func load(from url: URL) -> [SplitTemplate] {
        guard let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([SplitTemplate].self, from: data) else { return [] }
        let valid = list.filter { $0.isFrame && SplitTemplate.shapeError($0.cells, area: $0.area) == nil && !$0.name.contains(" ") && $0.name != "chain" }
        return Array(valid.suffix(limit))
    }

    public static func write(_ list: [SplitTemplate], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(list).write(to: url, options: .atomic)
    }
}
