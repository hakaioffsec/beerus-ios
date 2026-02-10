import Foundation

final class Exec {

    @discardableResult
    static func command(_ path: String, args: [String] = []) -> String? {
        let fullPath = path.hasPrefix("/") ? path : findInPath(path)
        guard let execPath = fullPath else { return nil }

        var pipe = [Int32](repeating: 0, count: 2)
        guard Darwin.pipe(&pipe) == 0 else { return nil }
        defer { close(pipe[0]) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }

        posix_spawn_file_actions_adddup2(&actions, pipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, pipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, pipe[0])

        var pid: pid_t = 0
        var argv: [UnsafeMutablePointer<CChar>?] = []
        argv.append(strdup(execPath))
        args.forEach { argv.append(strdup($0)) }
        argv.append(nil)
        defer { argv.compactMap { $0 }.forEach { free($0) } }

        guard posix_spawn(&pid, execPath, &actions, nil, argv, nil) == 0 else {
            close(pipe[1])
            return nil
        }
        close(pipe[1])

        let output = FileHandle(fileDescriptor: pipe[0]).readDataToEndOfFile()
        waitpid(pid, nil, 0)

        return String(data: output, encoding: .utf8)
    }

    private static func findInPath(_ command: String) -> String? {
        guard let pathEnv = getenv("PATH") else { return nil }

        return String(cString: pathEnv)
            .split(separator: ":")
            .lazy
            .map { String($0) + "/" + command }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
