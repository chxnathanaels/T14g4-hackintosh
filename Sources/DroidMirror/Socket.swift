import Foundation

enum SocketError: Error {
    case connectFailed
    case closed
}

/// Minimal blocking TCP client for 127.0.0.1 (the adb forward endpoint).
final class TCPSocket {
    private var fd: Int32
    private let writeLock = NSLock()

    init(port: UInt16) throws {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.connectFailed }
        var one: Int32 = 1
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if rc != 0 {
            Darwin.close(fd)
            fd = -1
            throw SocketError.connectFailed
        }
    }

    deinit { close() }

    func close() {
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
            fd = -1
        }
    }

    /// Reads exactly `count` bytes or throws.
    func read(_ count: Int) throws -> Data {
        var data = Data(count: count)
        var got = 0
        try data.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
            guard let base = buf.baseAddress else { return }
            while got < count {
                let n = recv(fd, base + got, count - got, 0)
                if n <= 0 { throw SocketError.closed }
                got += n
            }
        }
        return data
    }

    func write(_ data: Data) throws {
        writeLock.lock()
        defer { writeLock.unlock() }
        var sent = 0
        try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            guard let base = buf.baseAddress else { return }
            while sent < data.count {
                let n = send(fd, base + sent, data.count - sent, 0)
                if n <= 0 { throw SocketError.closed }
                sent += n
            }
        }
    }
}

extension Data {
    func be32(_ offset: Int) -> UInt32 {
        var v: UInt32 = 0
        for i in 0..<4 { v = (v << 8) | UInt32(self[startIndex + offset + i]) }
        return v
    }

    func be64(_ offset: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<8 { v = (v << 8) | UInt64(self[startIndex + offset + i]) }
        return v
    }

    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }
}
