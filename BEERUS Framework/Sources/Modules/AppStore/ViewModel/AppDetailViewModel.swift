import Foundation

final class AppDetailViewModel {

    weak var coordinator: AppStoreCoordinator?

    private let app: AppStoreApp

    init(app: AppStoreApp) {
        self.app = app
    }

    var nameText: String { app.name }
    var bundleText: String { app.bundleID }
    var versionText: String { "v\(app.version) • \(app.price == 0 ? "Free" : String(format: "$%.2f", app.price))" }
    var idText: String { "App ID: \(app.id)" }

    func tappedDownload() {
        coordinator?.showDownload(for: app, versionID: nil)
    }

    func tappedVersions() {
        coordinator?.showVersions(for: app)
    }
}
