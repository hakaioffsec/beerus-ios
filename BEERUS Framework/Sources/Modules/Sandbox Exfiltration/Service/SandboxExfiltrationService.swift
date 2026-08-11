import Foundation

enum SandboxExfiltrationService {

    enum StorageError: LocalizedError {
        case bundleNotFound
        case dataContainerNotFound
        case pathNotAccessible
        case zipCreationFailed(Error)

        var errorDescription: String? {
            switch self {
            case .bundleNotFound:
                return "Bundle ID not found in installed applications"
            case .dataContainerNotFound:
                return "Data container not found for this application"
            case .pathNotAccessible:
                return "Cannot access storage path"
            case .zipCreationFailed(let error):
                return "Failed to create ZIP: \(error.localizedDescription)"
            }
        }
    }

    struct StorageInfo {
        let basePath: String
        let documentsPath: String
        let libraryPath: String
        let preferencesPath: String
        let cachesPath: String
        let tmpPath: String

        var allPaths: [String: String] {
            [
                "Base": basePath,
                "Documents": documentsPath,
                "Library": libraryPath,
                "Preferences": preferencesPath,
                "Caches": cachesPath,
                "tmp": tmpPath
            ]
        }
    }

    // MARK: - Public

    static func getStoragePath(for bundleId: String) -> Result<String, StorageError> {
        guard let dataContainer = getDataContainerPath(for: bundleId) else {
            return .failure(.dataContainerNotFound)
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: dataContainer) else {
            return .failure(.pathNotAccessible)
        }

        return .success(dataContainer)
    }

    static func getStorageInfo(for bundleId: String) -> Result<StorageInfo, StorageError> {
        switch getStoragePath(for: bundleId) {
        case .success(let basePath):
            let info = StorageInfo(
                basePath: basePath,
                documentsPath: (basePath as NSString).appendingPathComponent("Documents"),
                libraryPath: (basePath as NSString).appendingPathComponent("Library"),
                preferencesPath: (basePath as NSString).appendingPathComponent("Library/Preferences"),
                cachesPath: (basePath as NSString).appendingPathComponent("Library/Caches"),
                tmpPath: (basePath as NSString).appendingPathComponent("tmp")
            )
            return .success(info)

        case .failure(let error):
            return .failure(error)
        }
    }

    static func compactStorage(
        for bundleId: String,
        to destinationURL: URL,
        progress: ((Int, Int) -> Void)? = nil
    ) -> Result<URL, StorageError> {
        switch getStoragePath(for: bundleId) {
        case .success(let storagePath):
            return compactDirectory(
                at: URL(fileURLWithPath: storagePath),
                to: destinationURL,
                rootName: bundleId,
                progress: progress
            )

        case .failure(let error):
            return .failure(error)
        }
    }

    static func compactDirectory(
        at sourceURL: URL,
        to destinationURL: URL,
        rootName: String = "",
        progress: ((Int, Int) -> Void)? = nil
    ) -> Result<URL, StorageError> {
        do {
            try RootExec.compress(
                from: sourceURL.path,
                output: destinationURL.path
            )
            NSLog("[BEERUS] ZIP Success")
            return .success(destinationURL)
        } catch {
            NSLog("[BEERUS] ZIP Fail")
            return .failure(.zipCreationFailed(error))
        }
    }

    static func calculateStorageSize(for bundleId: String) -> Result<UInt64, StorageError> {
        switch getStoragePath(for: bundleId) {
        case .success(let path):
            return .success(calculateDirectorySize(at: path))

        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Private

    private static func getDataContainerPath(for bundleId: String) -> String? {
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
              let workspace = workspaceClass.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue(),
              let apps = workspace.perform(NSSelectorFromString("allInstalledApplications"))?.takeUnretainedValue() as? [NSObject]
        else {
            return nil
        }

        for app in apps {
            guard let appBundleId = app.perform(NSSelectorFromString("bundleIdentifier"))?.takeUnretainedValue() as? String,
                  appBundleId == bundleId,
                  let dataURL = app.perform(NSSelectorFromString("dataContainerURL"))?.takeUnretainedValue() as? URL
            else { continue }

            return dataURL.path
        }

        return nil
    }

    private static func calculateDirectorySize(at path: String) -> UInt64 {
        let fm = FileManager.default
        var totalSize: UInt64 = 0

        guard let enumerator = fm.enumerator(atPath: path) else {
            return 0
        }

        for case let file as String in enumerator {
            let fullPath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let size = attrs[.size] as? UInt64 {
                totalSize += size
            }
        }

        return totalSize
    }
}

extension SandboxExfiltrationService {

    static func formattedSize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
