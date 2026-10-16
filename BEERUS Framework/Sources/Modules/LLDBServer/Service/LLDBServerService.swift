import Foundation

struct DeviceProcess {
    let pid: String
    let name: String
}

final class LLDBServerService: Sendable {

    let port = "1234"
    let package = "debugserver"
    let logFile = "/tmp/beerus-debugserver.log"

    private let searchPaths = [
        "/usr/bin/debugserver",
        "/var/jb/usr/bin/debugserver",
        "/usr/local/bin/debugserver",
        "/var/jb/usr/local/bin/debugserver",
    ]

    var isDaemonRunning: Bool { RootExec.isRunning }

    struct Discovery {
        let path: String?
        let serverPID: String?
    }

    func discover() -> Discovery {
        let script = """
        path=$(which debugserver 2>/dev/null); \
        [ -z "$path" ] && for p in \(searchPaths.joined(separator: " ")); do \
          [ -x "$p" ] && path=$p && break; done; \
        echo "PATH:${path:-NONE}"; \
        pid=$(ps -eo pid,comm 2>/dev/null | grep debugserver | grep -v grep | head -1 | sed 's/^[[:space:]]*//' | cut -d' ' -f1); \
        echo "PID:${pid:-NONE}"
        """
        let lines = RootExec.shell(script).output.components(separatedBy: "\n")
        let rawPath = lines.first { $0.hasPrefix("PATH:") }?.replacingOccurrences(of: "PATH:", with: "")
        let rawPID = lines.first { $0.hasPrefix("PID:") }?.replacingOccurrences(of: "PID:", with: "")

        let path = normalize(rawPath)
        let pid = normalize(rawPID)
        return Discovery(path: path, serverPID: pid)
    }

    func hasApt() -> Bool {
        RootExec.shell("which apt-get 2>/dev/null").exitCode == 0
    }

    func packageAvailable() -> Bool {
        let info = RootExec.shell("apt-cache show \(package) 2>/dev/null")
        return info.exitCode == 0 && info.output.contains("Package:")
    }

    func fixBrokenPackages() {
        _ = RootExec.shell("apt-get install -f -y 2>&1")
    }

    struct InstallResult {
        let success: Bool
        let lastLine: String
    }

    func install() -> InstallResult {
        let result = RootExec.shell("apt-get install -y \(package) 2>&1")
        if result.exitCode == 0 {
            return InstallResult(success: true, lastLine: "")
        }
        let lastLine = result.output.components(separatedBy: "\n")
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "unknown error"
        return InstallResult(success: false, lastLine: lastLine)
    }

    func removePackage() {
        _ = RootExec.shell("killall -9 debugserver 2>/dev/null")
        _ = RootExec.shell("apt-get remove -y \(package) 2>&1")
    }

    func killServer() {
        _ = RootExec.shell("killall -9 debugserver 2>/dev/null")
    }

    func clearLog() {
        _ = RootExec.shell("> \(logFile)")
    }

    func launchAttached(path: String, targetPID: String) {
        let launch = "( \(path) 0.0.0.0:\(port) --attach=\(targetPID) > \(logFile) 2>&1 & )"
        _ = RootExec.shell(launch)
    }

    func runningServerPID() -> String {
        RootExec.shell(
            "ps -eo pid,comm 2>/dev/null | grep debugserver | grep -v grep | head -1 | sed 's/^[[:space:]]*//' | cut -d' ' -f1"
        ).output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isServerAlive() -> Bool {
        !RootExec.shell("ps -eo comm 2>/dev/null | grep debugserver | grep -v grep | head -1")
            .output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func readLog(fromByteOffset offset: Int) -> String {
        RootExec.shell("tail -c +\(offset + 1) \(logFile) 2>/dev/null").output
    }

    func listProcesses() -> [DeviceProcess] {
        let result = RootExec.shell("ps -eo pid,comm 2>/dev/null")
        var procs: [DeviceProcess] = []

        for line in result.output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("PID") else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let pid = String(parts[0])
            let fullPath = String(parts[1])
            let name = (fullPath as NSString).lastPathComponent

            guard pid != "0", name != "debugserver",
                  !name.hasPrefix("["), !name.hasPrefix("(") else { continue }

            procs.append(DeviceProcess(pid: pid, name: name))
        }

        procs.sort { $0.name.lowercased() < $1.name.lowercased() }
        return procs
    }

    func connectCommand() -> String {
        "process connect connect://\(deviceIP() ?? "<device_ip>"):\(port)"
    }

    private func normalize(_ value: String?) -> String? {
        guard let value, value != "NONE", !value.isEmpty else { return nil }
        return value
    }

    private func deviceIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: ptr.pointee.ifa_name) == "en0" else { continue }
            var addr = ptr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &addr.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
            return String(cString: buf)
        }
        return nil
    }
}
