import UIKit

final class JailbreakBypassCoordinator: Coordinator {

    private(set) var childCoordinators: [Coordinator] = []
    private let navigationController: UINavigationController
    private weak var menuDelegate: MenuButtonDelegate?

    init(navigationController: UINavigationController, menuDelegate: MenuButtonDelegate?) {
        self.navigationController = navigationController
        self.menuDelegate = menuDelegate
    }

    private lazy var rootViewController: JailbreakBypassViewController = {
        let viewModel = JailbreakBypassViewModel()
        viewModel.coordinator = self
        let viewController = JailbreakBypassViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        return viewController
    }()

    func start() {
        navigationController.setViewControllers([rootViewController], animated: false)
    }

    func selectVersion(releases: [ShadowRelease], selected: ShadowRelease?, onSelect: @escaping (ShadowRelease) -> Void) {
        let alert = UIAlertController(title: "Select Version", message: nil, preferredStyle: .actionSheet)

        for release in releases {
            let isSelected = selected?.version == release.version
            let title = isSelected ? "\(release.version) ✓" : release.version
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                onSelect(release)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = navigationController.view
            popover.sourceRect = CGRect(x: navigationController.view.bounds.midX,
                                        y: navigationController.view.bounds.midY,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        navigationController.present(alert, animated: true)
    }

    func confirmUninstall(onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(title: "Uninstall Shadow?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Uninstall", style: .destructive) { _ in
            onConfirm()
        })
        navigationController.present(alert, animated: true)
    }

    func promptRespring(onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(
            title: "Respring Required",
            message: "A respring is needed to apply changes.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Later", style: .cancel))
        alert.addAction(UIAlertAction(title: "Respring Now", style: .destructive) { _ in
            onConfirm()
        })
        navigationController.present(alert, animated: true)
    }
}
