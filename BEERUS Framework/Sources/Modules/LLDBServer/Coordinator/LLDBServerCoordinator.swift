import UIKit

final class LLDBServerCoordinator: Coordinator {

    private(set) var childCoordinators: [Coordinator] = []
    private let navigationController: UINavigationController
    private weak var menuDelegate: MenuButtonDelegate?
    private let service = LLDBServerService()

    init(navigationController: UINavigationController, menuDelegate: MenuButtonDelegate?) {
        self.navigationController = navigationController
        self.menuDelegate = menuDelegate
    }

    private lazy var rootViewController: LLDBServerViewController = {
        let viewModel = LLDBServerViewModel(service: service)
        viewModel.coordinator = self
        let viewController = LLDBServerViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        return viewController
    }()

    func start() {
        navigationController.setViewControllers([rootViewController], animated: false)
    }

    func showProcessPicker(onSelect: @escaping (DeviceProcess) -> Void) {
        let viewModel = ProcessPickerViewModel(service: service, onSelect: onSelect)
        let picker = ProcessPickerViewController()
        picker.viewModel = viewModel

        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        navigationController.present(nav, animated: true)
    }

    func confirmUninstall(onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(title: "Uninstall debugserver?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Uninstall", style: .destructive) { _ in
            onConfirm()
        })
        navigationController.present(alert, animated: true)
    }

    func showInstallFailed(message: String, canRetry: Bool, onRetry: @escaping () -> Void) {
        let alert = UIAlertController(title: "Install Failed", message: message, preferredStyle: .alert)
        if canRetry {
            alert.addAction(UIAlertAction(title: "Fix & Retry", style: .default) { _ in
                onRetry()
            })
        }
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        navigationController.present(alert, animated: true)
    }
}
