import Foundation

final class PlistReaderViewModel {

    weak var coordinator: PlistReaderCoordinator?

    var onReload: () -> Void = {}

    private(set) var apps: [String: AppManager.AppInfo] = [:]
    private(set) var sortedPackages: [String] = []

    private let appManager: AppManager

    init(appManager: AppManager = AppManager()) {
        self.appManager = appManager
    }

    func viewDidLoad() {
        apps = appManager.getApps()
        sortedPackages = apps.keys.sorted()
        onReload()
    }

    func numberOfRows() -> Int {
        apps.count
    }

    func package(at index: Int) -> String {
        sortedPackages[index]
    }

    func didSelectRow(at index: Int) {
        let package = sortedPackages[index]
        guard let appInfo = apps[package] else { return }
        coordinator?.showPlists(for: appInfo)
    }
}
