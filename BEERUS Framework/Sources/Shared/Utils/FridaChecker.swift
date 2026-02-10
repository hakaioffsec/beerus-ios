import Foundation

enum FridaChecker {

    /// Posted whenever frida-server status may have changed (install, uninstall, restart).
    static let statusDidChangeNotification = Notification.Name("FridaStatusDidChange")

    /// Posts the status change notification (call from main or background — observers handle threading).
    static func notifyStatusChanged() {
        NotificationCenter.default.post(name: statusDidChangeNotification, object: nil)
    }

    /// Checks if frida-server is listening on the given port (synchronous, up to 1s timeout).
    static func isRunning(port: UInt16 = 27042) -> Bool {
        let sockfd = socket(AF_INET, SOCK_STREAM, 0)
        guard sockfd != -1 else { return false }
        defer { close(sockfd) }

        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: UInt8(AF_INET),
            sin_port: port.bigEndian,
            sin_addr: in_addr(s_addr: inet_addr("127.0.0.1")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sockfd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    /// Checks status after a delay (for server startup/shutdown), then calls back on main thread.
    static func checkAfterDelay(_ delay: UInt32 = 2, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            sleep(delay)
            let running = isRunning()
            DispatchQueue.main.async { completion(running) }
        }
    }
}
