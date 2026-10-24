import UIKit

final class MemoryDumpCoordinator: Coordinator {

    private(set) var childCoordinators: [Coordinator] = []
    private let navigationController: UINavigationController
    private weak var menuDelegate: MenuButtonDelegate?

    private weak var loadingViewController: MemoryDumpLoadingViewController?

    init(navigationController: UINavigationController, menuDelegate: MenuButtonDelegate?) {
        self.navigationController = navigationController
        self.menuDelegate = menuDelegate
    }

    private lazy var rootViewController: MemoryDumpViewController = {
        let viewModel = MemoryDumpViewModel()
        viewModel.coordinator = self
        let viewController = MemoryDumpViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        return viewController
    }()

    func start() {
        navigationController.setViewControllers([rootViewController], animated: false)
    }

    func showProcessList() {
        let viewModel = ProcessListViewModel()
        viewModel.coordinator = self
        let viewController = ProcessListViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        navigationController.pushViewController(viewController, animated: true)
    }

    func confirmDump(for app: AppModel) {
        let alert = UIAlertController(
            title: "Dump Memory",
            message: "\(app.name)\nPID: \(app.pid)\n\nThis will dump all readable memory regions from the process.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Dump", style: .default) { _ in
            self.startDump(for: app)
        })
        navigationController.present(alert, animated: true)
    }

    private func startDump(for app: AppModel) {
        let viewModel = MemoryDumpLoadingViewModel(app: app)
        viewModel.coordinator = self
        let loading = MemoryDumpLoadingViewController()
        loading.viewModel = viewModel
        loading.modalPresentationStyle = .overFullScreen
        loading.modalTransitionStyle = .crossDissolve
        loadingViewController = loading
        navigationController.present(loading, animated: true)
    }

    func dumpDidFinish(zipURL: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.loadingViewController?.dismiss(animated: true) {
                self?.loadingViewController = nil
                self?.showShareSheet(for: zipURL)
            }
        }
    }

    func dumpDidCancel() {
        DispatchQueue.main.async { [weak self] in
            self?.loadingViewController?.dismiss(animated: true) {
                self?.loadingViewController = nil
            }
        }
    }

    private func showShareSheet(for url: URL) {
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityViewController.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
        navigationController.present(activityViewController, animated: true)
    }
}
