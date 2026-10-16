import UIKit

final class IPAExtractorCoordinator: Coordinator {

    private(set) var childCoordinators: [Coordinator] = []
    private let navigationController: UINavigationController
    private weak var menuDelegate: MenuButtonDelegate?

    private weak var loadingViewController: LoadingViewController?

    init(navigationController: UINavigationController, menuDelegate: MenuButtonDelegate?) {
        self.navigationController = navigationController
        self.menuDelegate = menuDelegate
    }

    private lazy var rootViewController: IPAExtractorViewController = {
        let viewModel = IPAExtractorViewModel()
        viewModel.coordinator = self
        let viewController = IPAExtractorViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        return viewController
    }()

    func start() {
        navigationController.setViewControllers([rootViewController], animated: false)
    }

    func showInstalledApps() {
        let viewModel = InstalledAppsViewModel()
        viewModel.coordinator = self
        let viewController = InstalledAppsViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        navigationController.pushViewController(viewController, animated: true)
    }

    func confirmDump(for app: AppModel, onConfirm: @escaping () -> Void) {
        let status = app.isRunning ? "Running (PID: \(app.pid))" : "Not running"

        let alert = UIAlertController(
            title: "Dump IPA",
            message: "\(app.name)\n\(app.bundleIdentifier)\n\nStatus: \(status)",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if app.isRunning {
            alert.addAction(UIAlertAction(title: "Dump", style: .default) { _ in
                onConfirm()
            })
        } else {
            alert.message! += "\n\n⚠️ Open the app first to dump it."
        }

        navigationController.present(alert, animated: true)
    }

    func presentDump(for app: AppModel) {
        let viewModel = IPADumpLoadingViewModel(app: app)
        viewModel.coordinator = self
        let loading = LoadingViewController()
        loading.viewModel = viewModel
        loading.modalPresentationStyle = .overFullScreen
        loading.modalTransitionStyle = .crossDissolve
        loadingViewController = loading
        navigationController.present(loading, animated: true)
    }

    func dumpDidFinish(ipaURL: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.loadingViewController?.dismiss(animated: true) {
                self?.loadingViewController = nil
                self?.showShareSheet(for: ipaURL)
            }
        }
    }

    private func showShareSheet(for ipaURL: URL) {
        let activityViewController = UIActivityViewController(activityItems: [ipaURL], applicationActivities: nil)
        activityViewController.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: ipaURL)
            try? FileManager.default.removeItem(at: ipaURL.deletingLastPathComponent())
        }
        navigationController.present(activityViewController, animated: true)
    }
}
