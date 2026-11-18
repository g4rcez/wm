import Foundation

/// A TOML subset: `[[name]]` tables of `key = value` lines, with strings, booleans, integers and floats. Nothing else
/// in TOML is accepted, so a file that wm cannot read fails with a line number and is never half read.
public enum TomlValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
}

public struct TomlError: Error, Equatable, Sendable, CustomStringConvertible {
    public var line: Int
    public var message: String
    public var description: String { "line \(line): \(message)" }
}

/// One `[[name]]` table with the line numbers, so a later check can point at the line that is wrong.
public struct TomlTable: Equatable, Sendable {
    public var name: String
    public var line: Int
    public var values: [String: TomlValue] = [:]
    public var keyLines: [String: Int] = [:]
}

/// The `[[...]]` tables of `text`, in order. A key outside a table, a plain `[table]`, a repeated key and any
/// unsupported value are errors.
public func parseToml(_ text: String) throws -> [TomlTable] {
    var tables: [TomlTable] = []
    // "\r\n" is one Character in Swift: make it "\n" first, so the split gives the right line numbers.
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
    for (offset, raw) in lines.enumerated() {
        let number = offset + 1
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("#") { continue }

        if line.hasPrefix("[") {
            let header = stripComment(line)
            guard header.hasPrefix("[["), header.hasSuffix("]]") else {
                throw TomlError(line: number, message: "only [[name]] tables are supported")
            }
            let name = header.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)
            guard isBareKey(name) else { throw TomlError(line: number, message: "'\(header)' is not a valid table name") }
            tables.append(TomlTable(name: name, line: number))
            continue
        }

        guard let equals = line.firstIndex(of: "=") else { throw TomlError(line: number, message: "expected `key = value`") }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        guard isBareKey(key) else { throw TomlError(line: number, message: "'\(key)' is not a valid key") }
        guard !tables.isEmpty else { throw TomlError(line: number, message: "'\(key)' is outside of a [[table]]") }
        if tables[tables.count - 1].values[key] != nil { throw TomlError(line: number, message: "the key '\(key)' is set twice") }
        let value = try parseValue(Array(line[line.index(after: equals)...]), line: number)
        tables[tables.count - 1].values[key] = value
        tables[tables.count - 1].keyLines[key] = number
    }
    return tables
}

/// `text` as a TOML basic string: quoted, with the escapes that `parseToml` reads back.
public func tomlString(_ text: String) -> String {
    var result = "\""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\"": result += "\\\""
        case "\\": result += "\\\\"
        case "\n": result += "\\n"
        case "\t": result += "\\t"
        case "\r": result += "\\r"
        default:
            if scalar.value < 0x20 || scalar.value == 0x7f {
                result += "\\u" + String(format: "%04X", scalar.value)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
    }
    return result + "\""
}

private func isBareKey(_ text: String) -> Bool {
    !text.isEmpty && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
}

/// `line` without a trailing `# comment`. Only used on lines that have no string.
private func stripComment(_ line: String) -> String {
    (line.firstIndex(of: "#").map { String(line[..<$0]) } ?? line).trimmingCharacters(in: .whitespaces)
}

private func parseValue(_ chars: [Character], line: Int) throws -> TomlValue {
    var index = 0
    while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 }
    guard index < chars.count, chars[index] != "#" else { throw TomlError(line: line, message: "the key has no value") }

    let value: TomlValue
    switch chars[index] {
    case "\"":
        (value, index) = try parseBasicString(chars, from: index + 1, line: line)
    case "'":
        guard let end = chars[(index + 1)...].firstIndex(of: "'") else { throw TomlError(line: line, message: "the string is not closed") }
        value = .string(String(chars[(index + 1)..<end]))
        index = end + 1
    default:
        let start = index
        while index < chars.count, !chars[index].isWhitespace, chars[index] != "#" { index += 1 }
        value = try parseBare(String(chars[start..<index]), line: line)
    }

    let rest = String(chars[index...]).trimmingCharacters(in: .whitespaces)
    guard rest.isEmpty || rest.hasPrefix("#") else { throw TomlError(line: line, message: "unexpected text after the value: '\(rest)'") }
    return value
}

private func parseBare(_ token: String, line: Int) throws -> TomlValue {
    if token == "true" { return .bool(true) }
    if token == "false" { return .bool(false) }
    if let number = Int(token) { return .int(number) }
    // Only plain decimals: Double("nan"), Double("inf") and hex floats are not TOML values here.
    if token.allSatisfy({ "0123456789+-.eE".contains($0) }), let number = Double(token) { return .double(number) }
    throw TomlError(line: line, message: "'\(token)' is not a string, boolean or number (strings need quotes)")
}

private func parseBasicString(_ chars: [Character], from start: Int, line: Int) throws -> (TomlValue, Int) {
    var result = ""
    var index = start
    while index < chars.count {
        let char = chars[index]
        index += 1
        if char == "\"" { return (.string(result), index) }
        guard char == "\\" else {
            result.append(char)
            continue
        }
        guard index < chars.count else { break }
        let escape = chars[index]
        index += 1
        switch escape {
        case "\"": result.append("\"")
        case "\\": result.append("\\")
        case "n": result.append("\n")
        case "t": result.append("\t")
        case "r": result.append("\r")
        case "b": result.append("\u{8}")
        case "f": result.append("\u{c}")
        case "u", "U":
            let length = escape == "u" ? 4 : 8
            guard index + length <= chars.count, let code = UInt32(String(chars[index..<(index + length)]), radix: 16),
                  let scalar = Unicode.Scalar(code)
            else { throw TomlError(line: line, message: "the \\\(escape) escape needs \(length) hex digits") }
            result.unicodeScalars.append(scalar)
            index += length
        default:
            throw TomlError(line: line, message: "the escape \\\(escape) is not valid")
        }
    }
    throw TomlError(line: line, message: "the string is not closed")
}
