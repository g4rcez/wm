import Foundation
import Testing

@testable import Common

struct StateBackupTests {
    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wm-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func aMissingFileGetsNoBackup() throws {
        let url = try folder().appendingPathComponent("memory.json")

        #expect(setAsideUnreadableFile(at: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("bak").path))
    }

    @Test func anExistingFileIsCopiedAndStaysWhereItIs() throws {
        let url = try folder().appendingPathComponent("memory.json")
        try Data("{ broken".utf8).write(to: url)

        let backup = setAsideUnreadableFile(at: url)

        #expect(backup?.lastPathComponent == "memory.json.bak")
        #expect(try Data(contentsOf: #require(backup)) == Data("{ broken".utf8))
        #expect(try Data(contentsOf: url) == Data("{ broken".utf8))
    }

    @Test func aSecondBackupReplacesTheFirst() throws {
        let url = try folder().appendingPathComponent("state.json")
        try Data("first".utf8).write(to: url)
        setAsideUnreadableFile(at: url)
        try Data("second".utf8).write(to: url)

        let backup = try #require(setAsideUnreadableFile(at: url))

        #expect(try Data(contentsOf: backup) == Data("second".utf8))
    }
}
