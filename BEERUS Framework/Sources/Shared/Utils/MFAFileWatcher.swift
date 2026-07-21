import Foundation

enum MFAFileWatcher {

    // ponytail: fixed path accessible by both app and SSH, no sandbox issues
    static let filePath = "/var/tmp/beerus-mfa-code.txt"

    static func exists() -> Bool {
        let exists = FileManager.default.fileExists(atPath: filePath)
        return exists
    }

    static func read() -> String? {
        // ponytail: removed excessive NSLog - was blocking main thread every 1s poll
        guard exists() else { return nil }
        guard let data = FileManager.default.contents(atPath: filePath),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }
        let code = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return code.isEmpty ? nil : code
    }

    static func clear() {
        try? FileManager.default.removeItem(atPath: filePath)
    }

    static func logPath() {
        NSLog("[MFA] === MFA File Path ===")
        NSLog("[MFA] Path: %@", filePath)
        NSLog("[MFA] SSH command: echo \"CODE\" > %@", filePath)
    }
}
