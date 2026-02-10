import Foundation

enum RootExec {

    private static let sockPath = "/var/run/beerus.sock"

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: sockPath) }
    static var isRunning: Bool  { send("PING") == "PONG" }

    @discardableResult
    static func exec(_ cmd: String) -> String? { send("EXEC \(cmd)") }
    static func whoami() -> String?             { send("WHOAMI") }
    static func restartFrida() -> String?       { send("RESTART_FRIDA") }
    static func installFrida(from path: String) -> String? { send("INSTALL_FRIDA \(path)") }
    static func uninstallFrida() -> String?     { send("UNINSTALL_FRIDA") }

    // MARK: - Shell (streaming)

    struct ShellResult {
        let output: String
        let exitCode: Int
    }

    /// Executes a command via the daemon's SHELL handler, which streams stdout+stderr
    /// and appends an exit code trailer.
    static func shell(_ cmd: String) -> ShellResult {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return ShellResult(output: "error: socket failed", exitCode: -1) }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            sockPath.withCString { strcpy(ptr, $0) }
        }

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard connected else { return ShellResult(output: "error: daemon not running", exitCode: -1) }

        let msg = "SHELL \(cmd)"
        _ = msg.withCString { Darwin.send(fd, $0, strlen($0), 0) }

        // Read all streamed data
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            data.append(contentsOf: buf[..<n])
        }

        // Parse exit code from trailer: \n\0EXIT:<code>\0
        var output = ""
        var exitCode = 0

        // Find EXIT trailer (after null byte)
        let exitMarker = Data([0x00, 0x45, 0x58, 0x49, 0x54, 0x3A]) // \0EXIT:
        if let nullRange = data.range(of: exitMarker) {
            let trailerStart = nullRange.lowerBound
            let codeBytes = data[(nullRange.upperBound)...]
            if let codeStr = String(bytes: codeBytes, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters),
               let code = Int(codeStr) {
                exitCode = code
            }
            // Output is everything before the \n\0EXIT: trailer
            let outputEnd = max(0, trailerStart - 1) // skip the \n before \0
            if outputEnd > 0 {
                let outputData = data[..<outputEnd]
                output = String(data: outputData, encoding: .utf8) ?? ""
            }
        } else {
            output = String(data: data, encoding: .utf8) ?? ""
        }

        return ShellResult(output: output, exitCode: exitCode)
    }

    // MARK: - Private

    private static func send(_ msg: String) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            sockPath.withCString { strcpy(ptr, $0) }
        }

        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard connected else { return nil }

        _ = msg.withCString { Darwin.send(fd, $0, strlen($0), 0) }

        var buf = [CChar](repeating: 0, count: 8192)
        guard recv(fd, &buf, buf.count - 1, 0) > 0 else { return nil }
        return String(cString: buf)
    }
}
