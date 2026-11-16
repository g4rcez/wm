import Foundation

public enum SocketError: Error, Equatable {
    case pathTooLong
    case alreadyRunning
    case syscall(String, Int32)
    case frameTooLarge(UInt32)
    case closed
}

/// A frame is a 4-byte big-endian length followed by that many bytes of JSON.
private let maxFrameBytes: UInt32 = 1 << 20
private let ioTimeoutSeconds = 5

private func makeAddress(_ path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw SocketError.pathTooLong }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    return address
}

private func makeSocket() throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw SocketError.syscall("socket", errno) }
    // A peer that disappears must produce an error from write(), not kill the process with SIGPIPE.
    var on: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    return descriptor
}

private func setTimeouts(_ descriptor: Int32, seconds: Int) {
    var timeout = timeval(tv_sec: seconds, tv_usec: 0)
    let size = socklen_t(MemoryLayout<timeval>.size)
    setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, size)
    setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, size)
}

private func connectSocket(_ descriptor: Int32, _ address: sockaddr_un) -> Int32 {
    var address = address
    return withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}

/// `timeoutSeconds == 0` waits forever (a `subscribe` client).
public func connectToServer(path: String, timeoutSeconds: Int = 5) throws -> Int32 {
    let address = try makeAddress(path)
    let descriptor = try makeSocket()
    guard connectSocket(descriptor, address) == 0 else {
        let code = errno
        close(descriptor)
        throw SocketError.syscall("connect", code)
    }
    setTimeouts(descriptor, seconds: timeoutSeconds)
    return descriptor
}

/// Creates the listening socket (file mode 0600). A live daemon on the same path is never replaced;
/// only a stale socket file left by a crashed daemon is removed.
func listenOnSocket(path: String) throws -> Int32 {
    let address = try makeAddress(path)
    let probe = try makeSocket()
    let reachable = connectSocket(probe, address) == 0
    close(probe)
    if reachable { throw SocketError.alreadyRunning }
    unlink(path)

    let descriptor = try makeSocket()
    let previousMask = umask(0o177)
    defer { umask(previousMask) }
    var mutableAddress = address
    let bound = withUnsafePointer(to: &mutableAddress) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bound == 0 else {
        let code = errno
        close(descriptor)
        throw SocketError.syscall("bind", code)
    }
    guard listen(descriptor, 16) == 0 else {
        let code = errno
        close(descriptor)
        unlink(path)
        throw SocketError.syscall("listen", code)
    }
    // The read source accepts one connection per event, and accept must never block the queue.
    _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
    return descriptor
}

func acceptConnection(_ listener: Int32) -> Int32? {
    let descriptor = accept(listener, nil, nil)
    guard descriptor >= 0 else { return nil }
    var on: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    // An accepted socket must be blocking, whatever the listener is.
    _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) & ~O_NONBLOCK)
    setTimeouts(descriptor, seconds: ioTimeoutSeconds)
    return descriptor
}

public func writeFrame(_ descriptor: Int32, _ payload: Data) throws {
    guard payload.count <= Int(maxFrameBytes) else { throw SocketError.frameTooLarge(UInt32(clamping: payload.count)) }
    var length = UInt32(payload.count).bigEndian
    let message = Data(bytes: &length, count: 4) + payload
    try message.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
        var offset = 0
        while offset < buffer.count {
            let written = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
            if written < 0 {
                if errno == EINTR { continue }
                throw SocketError.syscall("write", errno)
            }
            offset += written
        }
    }
}

public func readFrame(_ descriptor: Int32) throws -> Data {
    let header = try readExactly(descriptor, 4)
    let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.bigEndian
    guard length <= maxFrameBytes else { throw SocketError.frameTooLarge(length) }
    return try readExactly(descriptor, Int(length))
}

private func readExactly(_ descriptor: Int32, _ count: Int) throws -> Data {
    var data = Data(count: count)
    try data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
        var offset = 0
        while offset < count {
            let received = read(descriptor, buffer.baseAddress! + offset, count - offset)
            if received < 0 {
                if errno == EINTR { continue }
                throw SocketError.syscall("read", errno)
            }
            if received == 0 { throw SocketError.closed }
            offset += received
        }
    }
    return data
}
