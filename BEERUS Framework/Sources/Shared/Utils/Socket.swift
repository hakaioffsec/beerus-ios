//
//  Socket.swift
//  BEERUS Framework
//
//  Created by Daniel França Lima on 05/02/26.
//

import Foundation

enum UnixSockError: Error {
    case socketFailed(Int32)
    case connectFailed(Int32)
    case sendFailed(Int32)
    case recvFailed(Int32)
    case invalidPath
    case responseTooLarge
}

final class UnixSockClient {
    private let path: String
    private let maxResponseBytes: Int

    init(path: String, maxResponseBytes: Int = 1_048_576) { // 1MB
        self.path = path
        self.maxResponseBytes = maxResponseBytes
    }

    func request(_ message: String, timeoutSec: Int = 60) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { throw UnixSockError.socketFailed(errno) }
        defer { close(fd) }

        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(tv_sec: timeoutSec, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_un()
        memset(&addr, 0, MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)

        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard let pathData = path.data(using: .utf8), pathData.count < maxLen else {
            throw UnixSockError.invalidPath
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            ptr.copyBytes(from: pathData)
            ptr[pathData.count] = 0
        }

        let baseLen = MemoryLayout.size(ofValue: addr.sun_family)
        let addrLen = socklen_t(baseLen + pathData.count + 1)

        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, addrLen)
            }
        }
        if rc != 0 { throw UnixSockError.connectFailed(errno) }

        let payload = Data((message + "\n").utf8)
        try sendAll(fd: fd, data: payload)

        let newline: UInt8 = 0x0A

        let responseData = try recvUntilDelimiter(fd: fd, delimiter: newline)

        let trimmed = responseData.last == newline ? responseData.dropLast() : responseData[...]

        return String(decoding: trimmed, as: UTF8.self)
    }

    private func sendAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var totalSent = 0
            while totalSent < rawBuf.count {
                let ptr = base.advanced(by: totalSent)
                let remaining = rawBuf.count - totalSent

                
                let n = send(fd, ptr, remaining, 0)
                if n > 0 {
                    totalSent += n
                    continue
                }
                if n == 0 {
                    throw UnixSockError.sendFailed(ECONNRESET)
                }

                // n < 0
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    throw UnixSockError.sendFailed(errno)
                }
                throw UnixSockError.sendFailed(errno)
            }
        }
    }

    private func recvUntilDelimiter(fd: Int32, delimiter: UInt8) throws -> Data {
        var out = Data()
        var buf = [UInt8](repeating: 0, count: 4096)

        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0 {
                out.append(buf, count: n)

                if out.count > maxResponseBytes {
                    throw UnixSockError.responseTooLarge
                }

                if out.contains(delimiter) {
                    
                    if let idx = out.firstIndex(of: delimiter) {
                        return out.prefix(idx + 1)
                    }
                    return out
                }
                continue
            }

            if n == 0 {
                return out
            }

            // n < 0
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                throw UnixSockError.recvFailed(errno) // timeout / would block
            }
            throw UnixSockError.recvFailed(errno)
        }
    }
}

