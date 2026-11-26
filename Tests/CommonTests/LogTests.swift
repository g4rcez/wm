import Foundation
import Testing
@testable import Common

struct LogTests {
    private let record = LogRecord(time: "2026-11-16T22:57:03.123Z", level: .info, message: "config loaded", source: "config")

    private func tempLog() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wm-log-\(UUID().uuidString)")
        return dir.appendingPathComponent("wm.log")
    }

    // MARK: Formats

    @Test func theDefaultOutputIsTheOpenTelemetryTextWithTheAttributesLast() {
        #expect(record.otelLine == "2026-11-16T22:57:03.123Z INFO  config loaded source=config")
        #expect(LogRecord(time: "2026-11-16T22:57:04.000Z", level: .error, message: "boom").otelLine == "2026-11-16T22:57:04.000Z ERROR boom")
        #expect(LogRecord(time: "2026-11-16T22:57:04.000Z", level: .warn, message: "careful").otelLine == "2026-11-16T22:57:04.000Z WARN  careful")
    }

    @Test func aNewLineInTheMessageKeepsTheRecordOnOneLine() {
        #expect(LogRecord(time: "t", level: .error, message: "bad\nline two", source: "config").otelLine == #"t ERROR bad\nline two source=config"#)
    }

    @Test func jsonOutputIsOneFlatObjectPerRecord() {
        #expect(record.jsonLine == #"{"time":"2026-11-16T22:57:03.123Z","level":"info","message":"config loaded","source":"config"}"#)
        #expect(LogRecord(time: "t", level: .debug, message: "a/b \"q\"\nnext").jsonLine == #"{"time":"t","level":"debug","message":"a/b \"q\"\nnext"}"#)
    }

    @Test func aJsonLineReadsBackAsTheSameRecord() {
        #expect(LogRecord(jsonLine: record.jsonLine) == record)
        #expect(LogRecord(jsonLine: "not json") == nil)
        #expect(LogRecord(jsonLine: #"{"time":"t","level":"loud","message":"x"}"#) == nil)
    }

    @Test func theTimestampIsUtcWithMilliseconds() {
        #expect(LogRecord.timestamp(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00.000Z")
        #expect(LogRecord.timestamp(Date(timeIntervalSince1970: 1.5)) == "1970-01-01T00:00:01.500Z")
    }

    @Test func theLogFileIsInTheStateFolder() {
        #expect(defaultLogURL(environment: ["XDG_STATE_HOME": "/state"], home: URL(fileURLWithPath: "/home/me")).path == "/state/wm/wm.log")
        #expect(defaultLogURL(environment: [:], home: URL(fileURLWithPath: "/home/me")).path == "/home/me/.local/state/wm/wm.log")
        #expect(defaultLogURL(environment: ["XDG_STATE_HOME": ""], home: URL(fileURLWithPath: "/home/me")).path == "/home/me/.local/state/wm/wm.log")
    }

    // MARK: The file

    @Test func appendedRecordsComeBackInOrderAndTailKeepsTheLastOnes() throws {
        let url = try tempLog()
        for number in 1...5 { LogFile.append(LogRecord(time: "t\(number)", level: .info, message: "m\(number)"), to: url) }
        #expect(LogFile.tail(3, from: url).records.map(\.message) == ["m3", "m4", "m5"])
        #expect(LogFile.tail(0, from: url).records.map(\.message) == ["m1", "m2", "m3", "m4", "m5"])
        #expect(LogFile.tail(9, from: url).records.count == 5)
    }

    @Test func aMissingFileHasNoRecords() throws {
        #expect(LogFile.tail(10, from: try tempLog()).records.isEmpty)
    }

    @Test func aFullFileMovesToTheOldOneAndTailReadsBoth() throws {
        let url = try tempLog()
        LogFile.append(LogRecord(time: "t1", level: .info, message: "old"), to: url, maxBytes: 10)
        LogFile.append(LogRecord(time: "t2", level: .info, message: "new"), to: url, maxBytes: 10)
        #expect(FileManager.default.fileExists(atPath: url.path + ".1"))
        #expect(LogFile.tail(10, from: url).records.map(\.message) == ["old", "new"])
    }

    @Test func theLogFileIsPrivateToTheUser() throws {
        let url = try tempLog()
        LogFile.append(LogRecord(time: "t1", level: .info, message: "a"), to: url)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func aDeletedLogIsCreatedAgainByTheNextRecord() throws {
        let url = try tempLog()
        LogFile.append(LogRecord(time: "t1", level: .info, message: "first"), to: url)
        try FileManager.default.removeItem(at: url)
        LogFile.append(LogRecord(time: "t2", level: .info, message: "second"), to: url)
        #expect(LogFile.tail(10, from: url).records.map(\.message) == ["second"])
    }

    @Test func aLogThatWasMovedAwayIsStartedAgain() throws {
        let url = try tempLog()
        LogFile.append(LogRecord(time: "t1", level: .info, message: "first"), to: url)
        try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("moved"))
        LogFile.append(LogRecord(time: "t2", level: .info, message: "second"), to: url)
        #expect(LogFile.tail(10, from: url).records.map(\.message) == ["second"])
        #expect(LogFile.tail(10, from: url.appendingPathExtension("moved")).records.map(\.message) == ["first"])
    }

    @Test func switchingToAnotherLogFileWritesThere() throws {
        let one = try tempLog(), two = try tempLog()
        LogFile.append(LogRecord(time: "t1", level: .info, message: "one"), to: one)
        LogFile.append(LogRecord(time: "t2", level: .info, message: "two"), to: two)
        LogFile.append(LogRecord(time: "t3", level: .info, message: "one again"), to: one)
        #expect(LogFile.tail(10, from: one).records.map(\.message) == ["one", "one again"])
        #expect(LogFile.tail(10, from: two).records.map(\.message) == ["two"])
    }

    // MARK: The lowest level

    @Test func theLowestLevelComesFromTheEnvironmentAndDefaultsToDebug() {
        #expect(LogLevel.lowest(environment: [:]) == .debug)
        #expect(LogLevel.lowest(environment: ["WM_LOG_LEVEL": ""]) == .debug)
        #expect(LogLevel.lowest(environment: ["WM_LOG_LEVEL": "nonsense"]) == .debug)
        #expect(LogLevel.lowest(environment: ["WM_LOG_LEVEL": "info"]) == .info)
        #expect(LogLevel.lowest(environment: ["WM_LOG_LEVEL": "WARN"]) == .warn)
        #expect(LogLevel.lowest(environment: ["WM_LOG_LEVEL": "Error"]) == .error)
    }

    @Test func aLevelIsBelowAnotherInTheOrderOfSeverity() {
        #expect(LogLevel.debug.isBelow(.info))
        #expect(LogLevel.warn.isBelow(.error))
        #expect(!LogLevel.error.isBelow(.warn))
        #expect(!LogLevel.info.isBelow(.info))
    }

    @Test func linesThatAreNotRecordsAreSkipped() throws {
        let url = try tempLog()
        LogFile.append(record, to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("garbage\n".utf8))
        try handle.close()
        #expect(LogFile.tail(10, from: url).records == [record])
    }

    // MARK: Follow

    @Test func followingGivesOnlyTheNewRecordsAndWaitsForAWholeLine() throws {
        let url = try tempLog()
        LogFile.append(LogRecord(time: "t1", level: .info, message: "first"), to: url)
        var follower = LogFollower(offset: LogFile.tail(10, from: url).offset)
        #expect(follower.poll(url: url).isEmpty)

        LogFile.append(LogRecord(time: "t2", level: .info, message: "second"), to: url)
        #expect(follower.poll(url: url).map(\.message) == ["second"])
        #expect(follower.poll(url: url).isEmpty)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"time":"t3","level":"info","mess"#.utf8))
        #expect(follower.poll(url: url).isEmpty)
        try handle.write(contentsOf: Data("age\":\"third\"}\n".utf8))
        try handle.close()
        #expect(follower.poll(url: url).map(\.message) == ["third"])
    }

    @Test func followingGoesOnWhenTheLogIsRotated() throws {
        let url = try tempLog()
        LogFile.append(LogRecord(time: "t1", level: .info, message: "before"), to: url)
        var follower = LogFollower(offset: LogFile.tail(10, from: url).offset)
        try FileManager.default.removeItem(at: url)
        LogFile.append(LogRecord(time: "t2", level: .info, message: "x"), to: url)
        #expect(follower.poll(url: url).map(\.message) == ["x"])
    }

    // MARK: Options

    @Test func theDefaultsAreOpenTelemetryTextAndTheLast100Records() throws {
        #expect(try LogsOptions(parsing: []) == LogsOptions(format: .otel, lines: 100, follow: false))
    }

    @Test(arguments: [
        (["-o", "json"], LogsOptions(format: .json)),
        (["--output", "json"], LogsOptions(format: .json)),
        (["--output=json"], LogsOptions(format: .json)),
        (["-o", "otel"], LogsOptions(format: .otel)),
        (["-n", "20"], LogsOptions(lines: 20)),
        (["--lines=0"], LogsOptions(lines: 0)),
        (["-f"], LogsOptions(follow: true)),
        (["--follow", "-n", "5", "-o", "json"], LogsOptions(format: .json, lines: 5, follow: true)),
    ])
    func optionsAreRead(words: [String], expected: LogsOptions) throws {
        #expect(try LogsOptions(parsing: words) == expected)
    }

    @Test(arguments: [
        (["-o", "yaml"], "unknown output 'yaml' (use otel or json)"),
        (["-o"], "-o needs a value"),
        (["-n", "many"], "-n needs a whole number (0 is all), not 'many'"),
        (["-n", "-3"], "-n needs a whole number (0 is all), not '-3'"),
        (["--json"], "unknown option --json"),
    ])
    func wrongOptionsNameTheProblem(words: [String], message: String) {
        #expect(throws: LogsOptions.Failure(message: message)) { try LogsOptions(parsing: words) }
    }
}

struct LogTitleTests {
    @Test func titlesAreLoggedOnlyWhenDebugIsAskedFor() {
        #expect(LogLevel.recordsTitles(environment: ["WM_LOG_LEVEL": "debug"]))
        #expect(LogLevel.recordsTitles(environment: ["WM_LOG_LEVEL": "DEBUG"]))
        #expect(!LogLevel.recordsTitles(environment: [:]))
        #expect(!LogLevel.recordsTitles(environment: ["WM_LOG_LEVEL": "info"]))
    }

    @Test func aTitleThatMayNotBeLoggedShowsOnlyItsLength() {
        #expect(LogLevel.loggable(title: "Re: salary review", recordsTitles: false) == "(17 characters)")
        #expect(LogLevel.loggable(title: "", recordsTitles: false) == "\"\"")
        #expect(LogLevel.loggable(title: "Re: salary review", recordsTitles: true) == "\"Re: salary review\"")
    }
}
