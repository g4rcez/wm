import Common
import Foundation
import Testing

@Suite(.serialized)
struct DaemonProcessTests {
    /// Longer than needed: on a small CI machine, tests that run at the same time can delay each other for several seconds.
    private let patience = 60.0

    private func temporarySocketPath() -> String {
        "/tmp/wm-test-\(UUID().uuidString.prefix(8)).sock"
    }

    private func sleeper(seconds: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        try process.run()
        return process
    }

    @Test func theProcessThatListensIsTheOneOfTheServer() throws {
        let path = temporarySocketPath()
        let server = try SocketServer(path: path) { _ in ServerAnswer(exitCode: 0) }
        defer { server.stop() }

        #expect(daemonProcessID(socketPath: path) == getpid())
    }

    @Test func noServerMeansNoProcess() {
        #expect(daemonProcessID(socketPath: temporarySocketPath()) == nil)
        #expect(stopDaemon(socketPath: temporarySocketPath()) == .notRunning)
    }

    @Test func aServerThatStaysUpIsStillRunning() throws {
        let path = temporarySocketPath()
        let server = try SocketServer(path: path) { _ in ServerAnswer(exitCode: 0) }
        defer { server.stop() }

        // The server of this test is this process, which does not quit: the stop must not report that it did.
        #expect(stopDaemon(socketPath: path, timeoutSeconds: 0.3) == .stillRunning(getpid()))
    }

    @Test func waitingEndsWhenTheProcessDoes() throws {
        let process = try sleeper(seconds: "0.3")
        #expect(waitForExit(process.processIdentifier, timeoutSeconds: patience))
        #expect(!process.isRunning)
    }

    @Test func waitingGivesUpOnAProcessThatStays() throws {
        let process = try sleeper(seconds: "60")
        defer { process.terminate() }

        #expect(!waitForExit(process.processIdentifier, timeoutSeconds: 0.3))
    }

    @Test func retryStopsAtTheFirstSuccess() {
        var attempts = 0
        let succeeded = retry(timeoutSeconds: patience, intervalSeconds: 0.01) {
            attempts += 1
            return attempts == 3
        }
        #expect(succeeded)
        #expect(attempts == 3)
    }

    @Test func retryGivesUpWhenTheTimeIsUp() {
        #expect(!retry(timeoutSeconds: 0.1, intervalSeconds: 0.01) { false })
    }
}
