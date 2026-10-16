import UIKit

final class PlistReaderCoordinator: Coordinator {

    private(set) var childCoordinators: [Coordinator] = []
    private let navigationController: UINavigationController
    private weak var menuDelegate: MenuButtonDelegate?

    init(navigationController: UINavigationController, menuDelegate: MenuButtonDelegate?) {
        self.navigationController = navigationController
        self.menuDelegate = menuDelegate
    }

    private lazy var rootViewController: PlistReaderViewController = {
        let viewModel = PlistReaderViewModel()
        viewModel.coordinator = self
        let viewController = PlistReaderViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        return viewController
    }()

    func start() {
        navigationController.setViewControllers([rootViewController], animated: false)
    }

    func showPlists(for appInfo: AppManager.AppInfo) {
        let menuViewController = BottomSheetViewController(plists: appInfo.plists)
        if #available(iOS 15.0, *) {
            if let sheet = menuViewController.sheetPresentationController {
                sheet.detents = [.large(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        navigationController.present(menuViewController, animated: true, completion: nil)
    }
}
