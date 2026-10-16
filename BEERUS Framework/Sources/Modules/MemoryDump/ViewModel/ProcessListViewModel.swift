import Foundation

final class ProcessListViewModel {

    weak var coordinator: MemoryDumpCoordinator?

    private(set) var apps: [AppModel] = []

    var onLoadingStateChange: (Bool) -> Void = { _ in }
    var onAppsLoaded: (_ isEmpty: Bool) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    func numberOfRows() -> Int { apps.count }

    func app(at index: Int) -> AppModel { apps[index] }

    func viewDidLoad() {
        loadRunningApps()
    }

    func loadRunningApps() {
        onLoadingStateChange(true)

        Task { @MainActor in
            do {
                let allApps = try await FridaManager.shared.getInstalledApps()
                let running = allApps.filter { $0.isRunning }
                self.apps = running
                self.onLoadingStateChange(false)
                self.onAppsLoaded(running.isEmpty)
            } catch {
                self.onLoadingStateChange(false)
                self.onError("Failed to list processes:\n\(error.localizedDescription)")
            }
        }
    }

    func didSelectApp(at index: Int) {
        coordinator?.confirmDump(for: apps[index])
    }
}
