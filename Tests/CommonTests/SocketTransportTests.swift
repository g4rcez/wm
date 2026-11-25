import Common
import Foundation
import Testing

@Suite(.serialized)
struct SocketTransportTests {
    /// Longer than the default: on a small CI machine, tests that run at the same time can delay the server for several seconds.
    private let patience = 60

    private func temporarySocketPath() -> String {
        "/tmp/wm-test-\(UUID().uuidString.prefix(8)).sock"
    }

    /// Binds a unix socket and closes it without removing the file: what a crashed daemon leaves behind.
    private func leaveStaleSocketFile(at path: String) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(bound == 0)
    }

    @Test func theSocketFileIsPrivateToTheUser() throws {
        let path = temporarySocketPath()
        let server = try SocketServer(path: path) { _ in ServerAnswer(exitCode: 0) }
        defer { server.stop() }

        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func listeningDoesNotChangeTheMaskOfTheProcess() throws {
        // The mask belongs to the whole process: a change, even a short one, locks other threads out of the files they create.
        let before = umask(0o022)
        defer { umask(before) }
        let path = temporarySocketPath()
        let server = try SocketServer(path: path) { _ in ServerAnswer(exitCode: 0) }
        defer { server.stop() }

        let after = umask(0o022)
        #expect(after == 0o022)
    }

    @Test func clientGetsTheServerAnswer() throws {
        let path = temporarySocketPath()
        let server = try SocketServer(path: path) { request in
            ServerAnswer(exitCode: 3, stdout: request.args.joined(separator: " "), stderr: "warn")
        }
        defer { server.stop() }

        let answer = try sendRequest(ClientRequest(args: ["focus", "left"]), socketPath: path, timeoutSeconds: patience)

        #expect(answer == ServerAnswer(exitCode: 3, stdout: "focus left", stderr: "warn"))
    }

    @Test func malformedRequestGetsExitCodeTwo() throws {
        let path = temporarySocketPath()
        let server = try SocketServer(path: path) { _ in ServerAnswer(exitCode: 0) }
        defer { server.stop() }

        let connection = try connectToServer(path: path, timeoutSeconds: patience)
        defer { close(connection) }
        try writeFrame(connection, Data("not json".utf8))
        let answer = try JSONDecoder().decode(ServerAnswer.self, from: readFrame(connection))

        #expect(answer == ServerAnswer(exitCode: 2, stdout: "", stderr: "wm: malformed request\n"))
    }

    @Test func secondServerOnALivePathIsRefused() throws {
        let path = temporarySocketPath()
        let first = try SocketServer(path: path) { _ in ServerAnswer(exitCode: 0) }
        defer { first.stop() }

        #expect(throws: SocketError.alreadyRunning) {
            _ = try SocketServer(path: path) { _ in ServerAnswer(exitCode: 0) }
        }
    }

    @Test func serverReplacesAStaleSocketFile() throws {
        let path = temporarySocketPath()
        try leaveStaleSocketFile(at: path)

        let server = try SocketServer(path: path) { _ in ServerAnswer(exitCode: 0, stdout: "alive") }
        defer { server.stop() }

        #expect(try sendRequest(ClientRequest(args: ["ping"]), socketPath: path, timeoutSeconds: patience).stdout == "alive")
    }

    @Test func clientWithoutServerFailsToConnect() {
        let path = temporarySocketPath()

        #expect(throws: SocketError.syscall("connect", ENOENT)) {
            _ = try sendRequest(ClientRequest(args: ["ping"]), socketPath: path)
        }
    }
}
