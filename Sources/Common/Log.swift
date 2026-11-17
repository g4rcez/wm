import Foundation

/// The severity of a log record. The names follow the OpenTelemetry severity texts (`DEBUG`, `INFO`, `WARN`, `ERROR`).
public enum LogLevel: String, Sendable, CaseIterable {
    case debug, info, warn, error

    /// The OpenTelemetry `SeverityText`.
    public var severityText: String { rawValue.uppercased() }
}

/// One line of the log. The file holds each record as one JSON object per line; `wm logs -o json` prints that line as it is.
public struct LogRecord: Sendable, Equatable {
    /// UTC time in ISO 8601 with milliseconds: `2026-11-16T22:57:03.123Z`.
    public var time: String
    public var level: LogLevel
    public var message: String
    /// Which part of wm wrote it, for example `lua`, `config`, `exec`. Shown as the attribute `source=`.
    public var source: String?

    public init(time: String = LogRecord.timestamp(), level: LogLevel, message: String, source: String? = nil) {
        self.time = time
        self.level = level
        self.message = message
        self.source = source
    }

    private static let formatLock = NSLock()
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public static func timestamp(_ date: Date = Date()) -> String {
        formatLock.lock()
        defer { formatLock.unlock() }
        return formatter.string(from: date)
    }

    /// The record as a line of the OpenTelemetry log data model, in text: time, `SeverityText`, body, then the attributes.
    /// `2026-11-16T22:57:03.123Z INFO  config loaded source=config`. A new line in the message is written `\n`, so a record is one line.
    public var otelLine: String {
        let severity = level.severityText.padding(toLength: 5, withPad: " ", startingAt: 0)
        return "\(time) \(severity) \(message.replacingOccurrences(of: "\n", with: "\\n"))" + (source.map { " source=\($0)" } ?? "")
    }

    /// The record as one flat JSON object: `time`, `level`, `message` and, when there is one, `source`.
    public var jsonLine: String {
        var fields = ["\"time\":\(Self.jsonString(time))", "\"level\":\(Self.jsonString(level.rawValue))", "\"message\":\(Self.jsonString(message))"]
        if let source { fields.append("\"source\":\(Self.jsonString(source))") }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private static func jsonString(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? encoder.encode(text)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }

    private struct Stored: Decodable {
        var time: String
        var level: String
        var message: String
        var source: String?
    }

    /// `nil` for a line that is not a record (damaged, or from another program).
    public init?(jsonLine: String) {
        guard let stored = try? JSONDecoder().decode(Stored.self, from: Data(jsonLine.utf8)), let level = LogLevel(rawValue: stored.level) else { return nil }
        self.init(time: stored.time, level: level, message: stored.message, source: stored.source)
    }
}

/// How `wm logs` prints a record.
public enum LogFormat: String, Sendable, CaseIterable {
    case otel, json

    public func render(_ record: LogRecord) -> String {
        switch self {
        case .otel: record.otelLine
        case .json: record.jsonLine
        }
    }
}

/// `$XDG_STATE_HOME/wm/wm.log`, else `~/.local/state/wm/wm.log`: the folder of the saved state. The daemon writes it and
/// `wm logs` reads it, so they always agree.
public func defaultLogURL(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
) -> URL {
    let base = environment["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".local/state")
    return base.appendingPathComponent("wm/wm.log")
}

/// The log file: records appended as JSON lines. At `maxBytes` the file becomes `wm.log.1` (the one before it is dropped),
/// so the log never takes more than about twice that.
public enum LogFile {
    public static let maxBytes = 5 * 1024 * 1024
    private static let lock = NSLock()

    static func rotatedURL(of url: URL) -> URL { url.appendingPathExtension("1") }

    public static func append(_ record: LogRecord, to url: URL = defaultLogURL(), maxBytes: Int = maxBytes) {
        lock.lock()
        defer { lock.unlock() }
        let files = FileManager.default
        do {
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = try? files.attributesOfItem(atPath: url.path)[.size] as? Int, size >= maxBytes {
                try? files.removeItem(at: rotatedURL(of: url))
                try files.moveItem(at: url, to: rotatedURL(of: url))
            }
            if !files.fileExists(atPath: url.path) {
                files.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((record.jsonLine + "\n").utf8))
        } catch {
            // The message went to stderr as well. A log that cannot be written must not stop the daemon.
        }
    }

    /// The records in `data`, in order. Lines that are not records are left out.
    static func records(in data: Data) -> [LogRecord] {
        String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { LogRecord(jsonLine: String($0)) }
    }

    /// The last `count` records (all of them for 0), with the end of the file that they were read to, for `LogFollower`.
    public static func tail(_ count: Int, from url: URL = defaultLogURL()) -> (records: [LogRecord], offset: UInt64) {
        let current = (try? Data(contentsOf: url)) ?? Data()
        let older = (try? Data(contentsOf: rotatedURL(of: url))) ?? Data()
        let all = records(in: older) + records(in: current)
        return (count > 0 ? Array(all.suffix(count)) : all, UInt64(current.count))
    }
}

/// `wm logs --follow`: the records that were added since the last `poll`.
public struct LogFollower {
    private var offset: UInt64

    public init(offset: UInt64) { self.offset = offset }

    public mutating func poll(url: URL = defaultLogURL()) -> [LogRecord] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        // A smaller file is a new one: the log was rotated.
        if size < offset { offset = 0 }
        guard size > offset, (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else { return [] }
        // Only whole lines: the end of a line that is being written waits for the next poll.
        guard let end = data.lastIndex(of: UInt8(ascii: "\n")) else { return [] }
        let complete = data[data.startIndex...end]
        offset += UInt64(complete.count)
        return LogFile.records(in: Data(complete))
    }
}

/// What the daemon writes: to stderr (as before) and to the log file.
public enum Log {
    /// `prefix` is what stderr shows before the message.
    public static func write(_ level: LogLevel, _ message: String, source: String? = nil, prefix: String = "wm") {
        FileHandle.standardError.write(Data("\(prefix): \(message)\n".utf8))
        LogFile.append(LogRecord(level: level, message: message, source: source))
    }
}

/// The options of `wm logs`.
public struct LogsOptions: Sendable, Equatable {
    public var format = LogFormat.otel
    /// How many records to print: the last ones. 0 is all of them.
    public var lines = 100
    public var follow = false

    public init(format: LogFormat = .otel, lines: Int = 100, follow: Bool = false) {
        self.format = format
        self.lines = lines
        self.follow = follow
    }

    public static let usage = "wm logs [-n|--lines <count>] [-f|--follow] [-o|--output <otel|json>]"

    public struct Failure: Error, Equatable { public let message: String }

    /// The words after `wm logs`. `-o json`, `--output json` and `--output=json` all work, as do `-n` and `--lines`.
    public init(parsing words: [String]) throws {
        self.init()
        var rest = words[...]
        func value(of name: String, inline: String?) throws -> String {
            if let inline { return inline }
            guard let next = rest.popFirst() else { throw Failure(message: "\(name) needs a value") }
            return next
        }
        while let word = rest.popFirst() {
            let parts = word.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let inline = parts.count == 2 ? parts[1] : nil
            switch parts[0] {
            case "-f", "--follow":
                follow = true
            case "-o", "--output":
                let name = try value(of: parts[0], inline: inline)
                guard let parsed = LogFormat(rawValue: name) else {
                    throw Failure(message: "unknown output '\(name)' (use \(LogFormat.allCases.map(\.rawValue).joined(separator: " or ")))")
                }
                format = parsed
            case "-n", "--lines":
                let text = try value(of: parts[0], inline: inline)
                guard let count = Int(text), count >= 0 else { throw Failure(message: "\(parts[0]) needs a whole number (0 is all), not '\(text)'") }
                lines = count
            default:
                throw Failure(message: "unknown option \(word)")
            }
        }
    }
}
