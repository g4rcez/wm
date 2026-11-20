import Foundation

/// Accepts connections on a unix socket and answers each one-request-one-answer exchange with `handler`.
public final class SocketServer: @unchecked Sendable {
    private let path: String
    private let source: any DispatchSourceRead

    /// `subscriber` takes over the connection of a `subscribe` request, with the words after `subscribe`: the server keeps
    /// it open and the subscriber owns it (and must close it).
    public init(
        path: String = defaultSocketPath(),
        subscriber: (@Sendable (Int32, [String]) -> Void)? = nil,
        handler: @escaping @Sendable (ClientRequest) -> ServerAnswer
    ) throws {
        let listener = try listenOnSocket(path: path)
        self.path = path
        source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .global())
        source.setEventHandler {
            guard let connection = acceptConnection(listener) else { return }
            DispatchQueue.global().async { Self.serve(connection, subscriber, handler) }
        }
        source.setCancelHandler { close(listener) }
        source.resume()
    }

    public func stop() {
        source.cancel()
        unlink(path)
    }

    private static func serve(
        _ connection: Int32,
        _ subscriber: (@Sendable (Int32, [String]) -> Void)?,
        _ handler: @Sendable (ClientRequest) -> ServerAnswer
    ) {
        var keepOpen = false
        defer { if !keepOpen { close(connection) } }
        // Read or write failures leave no one to answer: the client already went away or timed out.
        guard let frame = try? readFrame(connection) else { return }
        let request = try? JSONDecoder().decode(ClientRequest.self, from: frame)
        let answer: ServerAnswer
        if let request {
            answer = handler(request)
        } else {
            answer = ServerAnswer(exitCode: 2, stderr: "wm: malformed request\n")
        }
        guard let payload = try? JSONEncoder().encode(answer) else { return }
        try? writeFrame(connection, payload)
        if let subscriber, answer.exitCode == 0, let args = request?.args, args.first == "subscribe" {
            // Streaming connections wait for events, so the read timeout no longer applies.
            var none = timeval(tv_sec: 0, tv_usec: 0)
            setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &none, socklen_t(MemoryLayout<timeval>.size))
            keepOpen = true
            subscriber(connection, Array(args.dropFirst()))
        }
    }
}

public func sendRequest(_ request: ClientRequest, socketPath: String = defaultSocketPath(), timeoutSeconds: Int = 5) throws -> ServerAnswer {
    let connection = try connectToServer(path: socketPath, timeoutSeconds: timeoutSeconds)
    defer { close(connection) }
    try writeFrame(connection, JSONEncoder().encode(request))
    return try JSONDecoder().decode(ServerAnswer.self, from: readFrame(connection))
}
