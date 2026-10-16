import UIKit

final class LLDBServerCoordinator: Coordinator {

    private(set) var childCoordinators: [Coordinator] = []
    private let navigationController: UINavigationController
    private weak var menuDelegate: MenuButtonDelegate?

    init(navigationController: UINavigationController, menuDelegate: MenuButtonDelegate?) {
        self.navigationController = navigationController
        self.menuDelegate = menuDelegate
    }

    private lazy var rootViewController: LLDBServerViewController = {
        let viewController = LLDBServerViewController()
        viewController.menuDelegate = menuDelegate
        return viewController
    }()

    func start() {
        navigationController.setViewControllers([rootViewController], animated: false)
    }
}
