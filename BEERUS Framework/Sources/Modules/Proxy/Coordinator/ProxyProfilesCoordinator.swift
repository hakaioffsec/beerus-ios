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
        let viewModel = ProxyProfilesViewModel()
        viewModel.coordinator = self
        let viewController = ProxyProfilesViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        return viewController
    }()

    func start() {
        navigationController.setViewControllers([rootViewController], animated: false)
    }

    func presentAddProfile(completion: @escaping (String, String) -> Void) {
        Alert.showMultipleInput(
            title: "Add Profile",
            message: "",
            inputs: [
                (name: "Proxy Name", placeholder: "Proxy name"),
                (name: "IpAddress", placeholder: "127.0.0.1:8083")
            ]
        ) { inputValues in
            guard let values = inputValues else { return }
            completion(values["Proxy Name"] ?? "", values["IpAddress"] ?? "")
        }
    }
}
