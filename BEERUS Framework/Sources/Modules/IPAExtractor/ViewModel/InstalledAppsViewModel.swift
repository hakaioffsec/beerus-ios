import Foundation

final class InstalledAppsViewModel {

    weak var coordinator: IPAExtractorCoordinator?

    private(set) var apps: [AppModel] = []

    var onProgress: (String) -> Void = { _ in }
    var onProgressHidden: () -> Void = {}
    var onReload: () -> Void = {}
    var onError: (String) -> Void = { _ in }

    func viewDidLoad() {
        loadApps()
    }

    func numberOfRows() -> Int { apps.count }

    func app(at index: Int) -> AppModel { apps[index] }

    private func loadApps() {
        onProgress("Connecting to Frida...")

        Task {
            do {
                let installedApps = try await FridaManager.shared.getInstalledApps()
                await MainActor.run {
                    self.apps = installedApps
                    self.onReload()
                    self.onProgressHidden()
                }
            } catch {
                await MainActor.run {
                    self.onProgressHidden()
                    self.onError("Failed to connect to Frida:\n\(error.localizedDescription)")
                }
            }
        }
    }

    func didSelectApp(at index: Int) {
        let app = apps[index]

        Task {
            let updatedApps = try? await FridaManager.shared.getInstalledApps()
            await MainActor.run {
                if let updated = updatedApps?.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                    self.apps[index] = updated
                    self.requestDump(for: updated)
                } else {
                    self.requestDump(for: app)
                }
            }
        }
    }

    private func requestDump(for app: AppModel) {
        coordinator?.confirmDump(for: app) { [weak self] in
            self?.startDump(for: app)
        }
    }

    private func startDump(for app: AppModel) {
        guard app.isRunning else {
            onError("\(app.name) is not running.\n\nOpen the app first, then come back and try again.")
            return
        }

        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSTemporaryDirectory()),
           let freeSpace = attrs[.systemFreeSize] as? Int64,
           freeSpace < 500_000_000 {
            onError("Low disk space (\(freeSpace / 1_048_576)MB free).\n\nAt least 500MB is recommended for dumping.")
            return
        }

        coordinator?.presentDump(for: app)
    }
}
