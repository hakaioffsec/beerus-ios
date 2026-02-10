import Foundation

enum Shell {

    @discardableResult
    static func run(_ command: String) -> Int32 {
        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = []
        argv.append(strdup("sh"))
        argv.append(strdup("-c"))
        argv.append(strdup(command))
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = []
        envp.append(strdup("PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"))
        envp.append(strdup("HOME=\(NSHomeDirectory())"))
        envp.append(nil)
        defer {
            argv.compactMap { $0 }.forEach { free($0) }
            envp.compactMap { $0 }.forEach { free($0) }
        }

        var status: Int32 = -1
        if posix_spawn(&pid, "/bin/sh", nil, nil, argv, envp) == 0 {
            waitpid(pid, &status, 0)
            status = (status & 0x7f) == 0 ? (status >> 8) & 0xff : status
        }
        return status
    }
}
