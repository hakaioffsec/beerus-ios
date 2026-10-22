import Foundation

enum FridaServerService {

    static func daemonExists() -> Bool {
        RootExec.shell("test -f \(BeerusStrings.fridaDaemonPath) && echo 1").output.contains("1")
    }

    static func stop(completion: @escaping () -> Void) {
        let command = daemonExists()
            ? "\(BeerusStrings.launchctlBin) bootout system \(BeerusStrings.fridaDaemonPath)"
            : "killall frida-server"
        RootExec.shellAwait(command) { _ in completion() }
    }

    static func startExisting(completion: @escaping () -> Void) {
        RootExec.shellAwait("\(BeerusStrings.launchctlBin) bootstrap system \(BeerusStrings.fridaDaemonPath)") { _ in
            completion()
        }
    }

    static func detectArchitecture() -> String {
        RootExec.shell("\(BeerusStrings.dpkgBin) --print-architecture")
            .output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func copyToSystem(from localPath: String, systemPath: String) -> Int {
        RootExec.shell("cp '\(localPath)' '\(systemPath)'").exitCode
    }

    static func install(fromSystemPath path: String) -> String? {
        RootExec.installFrida(from: path)
    }

    static func isRunning() -> Bool {
        let result = RootExec.shell("ps aux | grep frida-server | grep -v grep")
        return result.exitCode == 0 && !result.output.isEmpty
    }

    static func installedVersion() -> String? {
        let result = RootExec.shell("\(BeerusStrings.fridaServerPath) --version")
        let cleanOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)

        let isValidVersion = result.exitCode == 0
            && !cleanOutput.isEmpty
            && !cleanOutput.contains("sh:")
            && !cleanOutput.contains("not found")
            && cleanOutput.range(of: #"^\d+\.\d+\.\d+"#, options: .regularExpression) != nil

        return isValidVersion ? cleanOutput : nil
    }
}
