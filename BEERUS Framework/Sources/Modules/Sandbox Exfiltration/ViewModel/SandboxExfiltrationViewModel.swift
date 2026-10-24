import Foundation

final class SandboxExfiltrationViewModel {

    typealias AppEntry = (bundleId: String, info: AppManager.AppInfo)

    weak var coordinator: SandboxExfiltrationCoordinator?

    private let appManager: AppManager
    private var apps: [AppEntry] = []
    private var filteredApps: [AppEntry] = []

    var onReload: () -> Void = {}

    init(appManager: AppManager = AppManager()) {
        self.appManager = appManager
    }

    func viewDidLoad() {
        apps = appManager
            .getApps()
            .map { ($0.key, $0.value) }
            .sorted { $0.info.name.lowercased() < $1.info.name.lowercased() }
        filteredApps = apps
        onReload()
    }

    func search(_ text: String) {
        let query = text.lowercased()
        filteredApps = query.isEmpty ? apps : apps.filter {
            $0.info.name.lowercased().contains(query) ||
            $0.bundleId.lowercased().contains(query)
        }
        onReload()
    }

    func numberOfRows() -> Int { filteredApps.count }

    func app(at index: Int) -> AppEntry { filteredApps[index] }

    func didSelectApp(at index: Int) {
        let app = filteredApps[index]
        coordinator?.showDetail(appInfo: app.info, bundleId: app.bundleId)
    }
}
