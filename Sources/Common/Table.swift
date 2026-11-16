import Foundation

/// Rows in aligned columns under an upper-case header. Every column is as wide as its widest cell; the last column
/// is not padded, so no line ends with blanks. No rows gives `""`.
public func renderTable(_ headers: [String], _ rows: [[String]]) -> String {
    guard !rows.isEmpty else { return "" }
    let widths = headers.indices.map { column in
        ([headers[column].count] + rows.map { column < $0.count ? $0[column].count : 0 }).max() ?? 0
    }
    func line(_ cells: [String]) -> String {
        var text = headers.indices.map { column in
            let cell = column < cells.count ? cells[column] : ""
            return column == headers.count - 1 ? cell : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
        while text.hasSuffix(" ") { text.removeLast() }
        return text
    }
    return ([line(headers.map { $0.uppercased() })] + rows.map(line)).joined(separator: "\n") + "\n"
}

/// `text` cut to `limit` characters, with `…` at the end when it was longer.
public func truncated(_ text: String, to limit: Int) -> String {
    text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
}
