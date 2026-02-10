import Foundation

enum IPABuilder {

    static func build(app: AppModel, dumpedExecutable: String,
                     onLog: @escaping (String) -> Void,
                     progressCallback: ((Int, Int) -> Void)? = nil) throws -> URL {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("IPADump/\(app.bundleIdentifier)")
        let payload = temp.appendingPathComponent("Payload")

        let appName = URL(fileURLWithPath: app.bundlePath).lastPathComponent
        let execName = URL(fileURLWithPath: app.executablePath).lastPathComponent

        // Setup workspace
        try? fm.removeItem(at: temp)
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)

        // Measure app bundle size for progress
        let bundleSize = directorySize(at: app.bundlePath)
        if bundleSize > 0 {
            let sizeMB = Double(bundleSize) / 1_048_576
            onLog("app bundle: \(String(format: "%.1f", sizeMB)) MB")
        }

        // Copy app bundle
        onLog("copying app bundle...")
        let destApp = payload.appendingPathComponent(appName)
        try fm.copyItem(atPath: app.bundlePath, toPath: destApp.path)
        onLog("copy complete")

        // Replace encrypted executable with decrypted
        onLog("replacing executable")
        let destExec = destApp.appendingPathComponent(execName)
        try fm.removeItem(at: destExec)
        try fm.copyItem(atPath: dumpedExecutable, toPath: destExec.path)

        // Create IPA
        onLog("compressing files (deflate)")
        let ipaPath = temp.appendingPathComponent("\(app.name.replacingOccurrences(of: " ", with: "_")).ipa")

        try ZipArchive.create(at: ipaPath, from: payload, root: "Payload") { done, total in
            if done % 100 == 0 || done == total {
                onLog("compressing \(done)/\(total)")
                progressCallback?(done, total)
            }
        }

        guard fm.fileExists(atPath: ipaPath.path) else { throw IPAError.zipFailed }

        // Show compression ratio
        if bundleSize > 0,
           let attrs = try? fm.attributesOfItem(atPath: ipaPath.path),
           let ipaSize = attrs[.size] as? UInt64 {
            let ratio = Int((1.0 - Double(ipaSize) / Double(bundleSize)) * 100)
            onLog("compressed \(ratio)% smaller")
        }

        // Cleanup
        try? fm.removeItem(at: payload)

        return ipaPath
    }

    private static func directorySize(at path: String) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        var total: UInt64 = 0
        while let file = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let size = attrs[.size] as? UInt64 {
                total += size
            }
        }
        return total
    }
}

enum IPAError: LocalizedError {
    case zipFailed
    var errorDescription: String? { "Failed to create IPA" }
}
