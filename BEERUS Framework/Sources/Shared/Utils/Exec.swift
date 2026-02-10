import Foundation
import MachO

struct daemonCommandResult: Decodable {
    let result: String
    let ok: Bool
}

struct beerusRequest: Encodable {
    let action: String = "run_command"
    let binary_path: String
    let arguments: [String]
}

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
    
    private static func findCommandPath(for command: String) -> String? {
        guard let path = getenv("PATH") else {
            return nil
        }

        return String(cString: pathEnv)
            .split(separator: ":")
            .lazy
            .map { String($0) + "/" + command }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    
    
    static func commandAsRoot(_ launchPath: String, arguments: [String] = [], completion: @escaping (String) -> Void) {
        do {
            let client = UnixSockClient(path: "/tmp/beerus.sock")
            
            let requestObj = beerusRequest(binary_path: launchPath, arguments: arguments)
            
            let encoder = JSONEncoder()
            let requestData = try encoder.encode(requestObj)
            
            guard let requestString = String(data: requestData, encoding: .utf8) else {
                completion("")
                return
            }
            
            let rawResponse = try client.request(requestString)
            
            guard let jsonData = rawResponse.data(using: .utf8) else {
                completion("")
                return
            }
            let decoded = try JSONDecoder().decode(daemonCommandResult.self, from: jsonData)
            
            completion(decoded.ok ? decoded.result : "")
            
        } catch {
            completion("")
        }
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
