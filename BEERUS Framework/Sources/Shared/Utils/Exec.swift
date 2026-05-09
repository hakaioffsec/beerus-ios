import Foundation
import MachO

final class Exec {
    
    static func command(_ launchPath: String, arguments: [String] = [], findPath: Bool = true) -> String? {
        let fullPath: String
        if findPath {
            guard let path = findCommandPath(for: launchPath) else { return nil }
            fullPath = path
        } else {
            fullPath = launchPath
        }

        var outputPipe = [Int32](repeating: 0, count: 2)
        pipe(&outputPipe)

        var pid: pid_t = 0
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, outputPipe[0])

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
     
        let argv: [UnsafeMutablePointer<CChar>?] = ([fullPath] + arguments).map { strdup($0) } + [nil]
        
        let status = posix_spawn(&pid, fullPath, &fileActions, &attr, argv, nil)

        posix_spawn_file_actions_destroy(&fileActions)
        posix_spawnattr_destroy(&attr)

        close(outputPipe[1])

        guard status == 0 else {
<<<<<<< HEAD
            NSLog("Erro ao executar spawn: \(status)")
=======
            NSLog("posix_spawn failed: %d", status)
>>>>>>> ae68300 (feat: add script editor, and frida integration)
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

    static func isRootless() -> Bool{
        return FileManager.default.fileExists(atPath: "/var/jb")
    }
    
    static func arch() -> String {
        guard let archRaw = NXGetLocalArchInfo().pointee.name else {
            return "unknown"
        }
        return String(cString: archRaw)
    }
}
