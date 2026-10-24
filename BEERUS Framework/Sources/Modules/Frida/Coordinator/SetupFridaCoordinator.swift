import UIKit

final class SetupFridaCoordinator: Coordinator {

    private(set) var childCoordinators: [Coordinator] = []
    private let navigationController: UINavigationController
    private weak var menuDelegate: MenuButtonDelegate?

    init(navigationController: UINavigationController, menuDelegate: MenuButtonDelegate?) {
        self.navigationController = navigationController
        self.menuDelegate = menuDelegate
    }

    private lazy var rootViewController: SetupFridaViewController = {
        let viewModel = SetupFridaViewModel()
        viewModel.coordinator = self
        let viewController = SetupFridaViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        return viewController
    }()

    func start() {
        navigationController.setViewControllers([rootViewController], animated: false)
    }

    func showVersions() {
        let viewModel = FridaVersionsViewModel()
        viewModel.coordinator = self
        let viewController = FridaVersionsViewController()
        viewController.viewModel = viewModel
        viewController.modalPresentationStyle = .fullScreen
        topViewController().present(viewController, animated: true)
    }

    func dismissVersions() {
        navigationController.dismiss(animated: true)
    }

    func promptFridaVersion(showError: Bool, onSubmit: @escaping (String?) -> Void) {
        let message = showError
            ? "Invalid version. Please enter a valid Frida version."
            : "Write a version of Frida"

        Alert.showInput(
            title: "Frida Version",
            message: message,
            placeholder: "16.7.12",
            keyboardType: .decimalPad
        ) { versionSelected in
            onSubmit(versionSelected)
        }
    }

    func confirmFridaUninstall(onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(
            title: "Uninstall Frida",
            message: "This will stop frida-server and remove the binary. Continue?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Uninstall", style: .destructive) { _ in
            onConfirm()
        })
        topViewController().present(alert, animated: true)
    }

    func confirmFridaInstall(version: String, detail: String, onConfirm: @escaping () -> Void) {
        let sheet = UIAlertController(
            title: "Frida \(version)",
            message: detail,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Install", style: .default) { _ in
            onConfirm()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        topViewController().present(sheet, animated: true)
    }

    func showError(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        topViewController().present(alert, animated: true)
    }

    private func topViewController() -> UIViewController {
        var top: UIViewController = navigationController
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
