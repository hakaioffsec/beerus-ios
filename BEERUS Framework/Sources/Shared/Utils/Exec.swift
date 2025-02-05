import Foundation

final class Exec {

    static func command(_ launchPath: String, arguments: [String] = []) -> String? {
        guard let fullPath = findCommandPath(for: launchPath) else {
            return nil
        }

        var outputPipe = [Int32](repeating: 0, count: 2)
        pipe(&outputPipe)

        var pid: pid_t = 0
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, outputPipe[0])

        let argv: [UnsafeMutablePointer<CChar>?] = ([fullPath] + arguments).map { strdup($0) } + [nil]

        let status = posix_spawn(&pid, fullPath, &fileActions, nil, argv, nil)

        close(outputPipe[1])

        guard status == 0 else {
            return nil
        }

        let fileHandle = FileHandle(fileDescriptor: outputPipe[0])
        let outputData = fileHandle.readDataToEndOfFile()
        fileHandle.closeFile()

        return String(data: outputData, encoding: .utf8)
    }

    private static func findCommandPath(for command: String) -> String? {
        guard let path = getenv("PATH") else {
            return nil
        }

        let pathString = String(cString: path)
        let directories = pathString.split(separator: ":")

        for directory in directories {
            let fullPath = "\(directory)/\(command)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        
        return nil
    }
}
