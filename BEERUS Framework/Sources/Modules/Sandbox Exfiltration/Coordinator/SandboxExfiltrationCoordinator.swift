import UIKit

final class SandboxExfiltrationCoordinator: Coordinator {

    private(set) var childCoordinators: [Coordinator] = []
    private let navigationController: UINavigationController
    private weak var menuDelegate: MenuButtonDelegate?

    init(navigationController: UINavigationController, menuDelegate: MenuButtonDelegate?) {
        self.navigationController = navigationController
        self.menuDelegate = menuDelegate
    }

    func start() {
        let viewModel = SandboxExfiltrationViewModel()
        viewModel.coordinator = self
        let viewController = SandboxExfiltrationViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        navigationController.setViewControllers([viewController], animated: false)
    }

    func showDetail(appInfo: AppManager.AppInfo, bundleId: String) {
        let viewModel = SandboxExfiltrationAppDetailViewModel(
            appInfo: appInfo,
            bundleId: bundleId
        )
        viewModel.coordinator = self
        let viewController = SandboxExfiltrationAppDetailViewController()
        viewController.viewModel = viewModel

        viewController.modalPresentationStyle = .pageSheet

        if let sheet = viewController.sheetPresentationController {
            sheet.detents = [.medium()]
        }

        navigationController.present(viewController, animated: true)
    }

    func showError(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        let presenter = navigationController.presentedViewController ?? navigationController
        presenter.present(alert, animated: true)
    }
}
