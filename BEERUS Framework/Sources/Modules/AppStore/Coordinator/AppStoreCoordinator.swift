import UIKit

final class AppStoreCoordinator: Coordinator {

    private(set) var childCoordinators: [Coordinator] = []
    private let navigationController: UINavigationController
    private weak var menuDelegate: MenuButtonDelegate?

    private var cachedSearchViewController: AppStoreSearchViewController?

    init(navigationController: UINavigationController, menuDelegate: MenuButtonDelegate?) {
        self.navigationController = navigationController
        self.menuDelegate = menuDelegate
    }

    func start() {
        navigationController.setViewControllers([makeRoot()], animated: false)
    }

    private func makeRoot() -> UIViewController {
        AppStoreCredentialManager.hasStoredAccount ? makeSearch() : makeLogin()
    }

    private func makeLogin() -> AppStoreLoginViewController {
        let viewModel = AppStoreLoginViewModel()
        viewModel.coordinator = self
        let viewController = AppStoreLoginViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        return viewController
    }

    private func makeSearch() -> AppStoreSearchViewController {
        if let cached = cachedSearchViewController {
            return cached
        }
        let viewModel = AppStoreSearchViewModel()
        viewModel.coordinator = self
        let viewController = AppStoreSearchViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        cachedSearchViewController = viewController
        return viewController
    }

    func loginSucceeded() {
        cachedSearchViewController = nil
        navigationController.setViewControllers([makeSearch()], animated: true)
    }

    func logout() {
        AppStoreService.shared.revoke()
        cachedSearchViewController = nil
        navigationController.setViewControllers([makeLogin()], animated: true)
    }

    func sessionExpired() {
        AppStoreService.shared.revoke()
        cachedSearchViewController = nil

        let alert = UIAlertController(
            title: "Session Expired",
            message: "Your login has expired. Please sign in again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self else { return }
            self.navigationController.setViewControllers([self.makeLogin()], animated: true)
        })
        navigationController.present(alert, animated: true)
    }

    func showDetail(for app: AppStoreApp) {
        let viewModel = AppDetailViewModel(app: app)
        viewModel.coordinator = self
        let viewController = AppDetailViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        navigationController.pushViewController(viewController, animated: true)
    }

    func showVersions(for app: AppStoreApp) {
        let viewModel = VersionListViewModel(app: app)
        viewModel.coordinator = self
        let viewController = VersionListViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        navigationController.pushViewController(viewController, animated: true)
    }

    func showDownload(for app: AppStoreApp, versionID: String?) {
        let viewModel = DownloadViewModel(app: app, versionID: versionID)
        viewModel.coordinator = self
        let viewController = DownloadViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        navigationController.pushViewController(viewController, animated: true)
    }

    func shareIPA(at path: String) {
        let url = URL(fileURLWithPath: path)
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        navigationController.present(activityViewController, animated: true)
    }

    func showFilesLocation(path: String) {
        let directory = (path as NSString).deletingLastPathComponent
        let alert = UIAlertController(title: "IPA Location", message: directory, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        navigationController.present(alert, animated: true)
    }
}
