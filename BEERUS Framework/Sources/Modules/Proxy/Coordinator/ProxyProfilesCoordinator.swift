import UIKit

final class ProxyProfilesCoordinator: Coordinator {

    private(set) var childCoordinators: [Coordinator] = []
    private let navigationController: UINavigationController
    private weak var menuDelegate: MenuButtonDelegate?

    init(navigationController: UINavigationController, menuDelegate: MenuButtonDelegate?) {
        self.navigationController = navigationController
        self.menuDelegate = menuDelegate
    }

    private lazy var rootViewController: ProxyProfilesViewController = {
        let viewController = ProxyProfilesViewController()
        viewController.menuDelegate = menuDelegate
        return viewController
    }()

    func start() {
        navigationController.setViewControllers([rootViewController], animated: false)
    }
}
