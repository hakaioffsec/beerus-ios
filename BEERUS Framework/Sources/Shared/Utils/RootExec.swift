import Foundation

enum RootExec {

    private static let sockPath = "/var/run/beerus.sock"

    static var isAvailable: Bool { FileManager.default.fileExists(atPath: sockPath) }
    static var isRunning: Bool  { send("PING") == "PONG" }

    @discardableResult
    static func exec(_ cmd: String) -> String? { send("EXEC \(cmd)") }
    static func whoami() -> String?             { send("WHOAMI") }
    static func getStatus() -> String?          { send("GET_STATUS") }
    static func restartFrida() -> String?       { send("RESTART_FRIDA") }
    static func stopFrida() -> String?          { send("STOP_FRIDA") }
    static func installFrida(from path: String) -> String? { send("INSTALL_FRIDA \(path)") }
    static func uninstallFrida() -> String?     { send("UNINSTALL_FRIDA") }
    static func installIPA(path: String) -> String? { send("INSTALL_IPA \(path)") }
    static func installApp(path: String) -> String? { send("INSTALL_APP \(path)") }
    static func openApp(_ bundleId: String) -> String? { send("OPEN_APP \(bundleId)") }
    static func refreshSpringBoard() -> String? { send("REFRESH_SB") }

    static func compress(from sourcePath: String, output destinationPath: String) throws {
        guard let response = send("COMPRESS \(sourcePath)|\(destinationPath)") else {
            throw NSError(domain: "RootExec", code: -1, userInfo: [NSLocalizedDescriptionKey: "Daemon not responding"])
        }
        if !response.hasPrefix("ok:") {
            throw NSError(domain: "RootExec", code: -1, userInfo: [NSLocalizedDescriptionKey: response])
        }
    }

    // Injector commands
    static func injectorStart() -> String?  { send("INJECT_START") }
    static func injectorStop() -> String?   { send("INJECT_STOP") }
    static func injectPid(_ pid: Int) -> String? { send("INJECT_PID \(pid)") }
    static func injectApp(_ bundleId: String) -> String? { send("INJECT_APP \(bundleId)") }
    static func injectAll() -> String? { send("INJECT_ALL") }

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
        setRecvSendTimeout(fd: fd, seconds: shellTimeoutSec)

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
        var timedOut = false
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0 {
                data.append(contentsOf: buf[..<n])
                continue
            }
            if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                timedOut = true
            }
            break
        }

        if timedOut {
            return ShellResult(output: "error: daemon timed out", exitCode: -1)
        }

        // Parse exit code from trailer: \n\0EXIT:<code>\0
        var output = ""
        var exitCode = 0

        if let raw = String(data: data, encoding: .utf8) {
            output = raw
        } else {
            // Binary-safe: convert what we can
            output = String(bytes: data, encoding: .utf8) ?? ""
        }

        // Find EXIT trailer (after null byte)
        if let nullRange = data.range(of: Data([0x00, 0x45, 0x58, 0x49, 0x54, 0x3A])) { // \0EXIT:
            let trailerStart = nullRange.lowerBound
            let codeBytes = data[(nullRange.upperBound)...]
            if let codeStr = String(bytes: codeBytes, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters),
               let code = Int(codeStr) {
                exitCode = code
            }
            // Output is everything before the \n\0EXIT: trailer
            let outputEnd = max(0, trailerStart - 1) // skip the \n before \0
            let outputData = data[..<outputEnd]
            output = String(data: outputData, encoding: .utf8) ?? ""
        }

        return ShellResult(output: output, exitCode: exitCode)
    }

    // MARK: - Shell Await

    static func shellAwait(_ cmd: String, completion: @escaping (ShellResult) -> Void) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            completion(ShellResult(output: "error: socket failed", exitCode: -1))
            return
        }
        defer { close(fd) }
        setRecvSendTimeout(fd: fd, seconds: shellTimeoutSec)

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
        guard connected else { 
            completion(ShellResult(output: "error: daemon not running", exitCode: -1))
            return
        }

        let msg = "SHELL \(cmd)"
        _ = msg.withCString { Darwin.send(fd, $0, strlen($0), 0) }

        // Read all streamed data
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        var timedOut = false
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0 {
                data.append(contentsOf: buf[..<n])
                continue
            }
            if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                timedOut = true
            }
            break
        }

        if timedOut {
            completion(ShellResult(output: "error: daemon timed out", exitCode: -1))
            return
        }

        // Parse exit code from trailer: \n\0EXIT:<code>\0
        var output = ""
        var exitCode = 0

        if let raw = String(data: data, encoding: .utf8) {
            output = raw
        } else {
            // Binary-safe: convert what we can
            output = String(bytes: data, encoding: .utf8) ?? ""
        }

        // Find EXIT trailer (after null byte)
        if let nullRange = data.range(of: Data([0x00, 0x45, 0x58, 0x49, 0x54, 0x3A])) { // \0EXIT:
            let trailerStart = nullRange.lowerBound
            let codeBytes = data[(nullRange.upperBound)...]
            if let codeStr = String(bytes: codeBytes, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters),
               let code = Int(codeStr) {
                exitCode = code
            }
            // Output is everything before the \n\0EXIT: trailer
            let outputEnd = max(0, trailerStart - 1) // skip the \n before \0
            let outputData = data[..<outputEnd]
            output = String(data: outputData, encoding: .utf8) ?? ""
        }

        completion(ShellResult(output: output, exitCode: exitCode))
    }

    // Mark: - SetProxy

    static func setProxy(_ proxyOptions: String) -> ShellResult {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return ShellResult(output: "error: socket failed", exitCode: -1) }
        defer { close(fd) }
        setRecvSendTimeout(fd: fd, seconds: quickTimeoutSec)

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

        let msg = "SET_PROXY \(proxyOptions)"
        _ = msg.withCString { Darwin.send(fd, $0, strlen($0), 0) }

        // Read all streamed data
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        var timedOut = false
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0 {
                data.append(contentsOf: buf[..<n])
                continue
            }
            if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                timedOut = true
            }
            break
        }

        if timedOut {
            return ShellResult(output: "error: daemon timed out", exitCode: -1)
        }

        // Parse exit code from trailer: \n\0EXIT:<code>\0
        var output = ""
        var exitCode = 0

        if let raw = String(data: data, encoding: .utf8) {
            output = raw
        } else {
            // Binary-safe: convert what we can
            output = String(bytes: data, encoding: .utf8) ?? ""
        }

        // Find EXIT trailer (after null byte)
        if let nullRange = data.range(of: Data([0x00, 0x45, 0x58, 0x49, 0x54, 0x3A])) { // \0EXIT:
            let trailerStart = nullRange.lowerBound
            let codeBytes = data[(nullRange.upperBound)...]
            if let codeStr = String(bytes: codeBytes, encoding: .utf8)?
                .trimmingCharacters(in: .controlCharacters),
               let code = Int(codeStr) {
                exitCode = code
            }
            // Output is everything before the \n\0EXIT: trailer
            let outputEnd = max(0, trailerStart - 1) // skip the \n before \0
            let outputData = data[..<outputEnd]
            output = String(data: outputData, encoding: .utf8) ?? ""
        }

        return ShellResult(output: output, exitCode: exitCode)
    }

    // MARK: - Private

    /// Quick daemon queries (PING/WHOAMI/status/etc). SET_PROXY also uses this class of timeout.
    private static let quickTimeoutSec: Int = 10
    /// Streaming SHELL commands (can legitimately run long, but SO_RCVTIMEO applies per-recv(),
    /// so this only trips if the daemon goes fully silent between output chunks).
    private static let shellTimeoutSec: Int = 30

    private static func setRecvSendTimeout(fd: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func send(_ msg: String) -> String? {
        print("[RootExec] send(\(msg)) - sockPath: \(sockPath)")

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            print("[RootExec] socket() failed: \(errno) - \(String(cString: strerror(errno)))")
            return nil
        }
        defer { close(fd) }
        setRecvSendTimeout(fd: fd, seconds: quickTimeoutSec)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            sockPath.withCString { strcpy(ptr, $0) }
        }

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if connectResult != 0 {
            print("[RootExec] connect() failed: \(errno) - \(String(cString: strerror(errno)))")
            return nil
        }
        print("[RootExec] connected to daemon")

        let sentBytes = msg.withCString { Darwin.send(fd, $0, strlen($0), 0) }
        print("[RootExec] sent \(sentBytes) bytes")

        var buf = [CChar](repeating: 0, count: 8192)
        let recvBytes = recv(fd, &buf, buf.count - 1, 0)
        guard recvBytes > 0 else {
            print("[RootExec] recv() failed or empty: \(recvBytes), errno: \(errno)")
            return nil
        }

        let response = String(cString: buf)
        print("[RootExec] recv \(recvBytes) bytes: \(response)")
        return response
    }

}
