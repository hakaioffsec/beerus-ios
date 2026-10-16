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
        guard AppStoreCredentialManager.hasStoredAccount else {
            let loginVC = AppStoreLoginViewController()
            loginVC.menuDelegate = menuDelegate
            loginVC.onLoginSuccess = { [weak self] _ in
                guard let self else { return }
                self.navigationController.setViewControllers([self.makeSearch()], animated: true)
            }
            return loginVC
        }
        return makeSearch()
    }

    private func makeSearch() -> AppStoreSearchViewController {
        if let cached = cachedSearchViewController {
            return cached
        }
        let searchVC = AppStoreSearchViewController()
        searchVC.menuDelegate = menuDelegate
        cachedSearchViewController = searchVC
        return searchVC
    }
}
