import UIKit

final class ContainerViewController: UIViewController {

    private var itemsToActive: [UIView] = []

    enum MenuState {
        case closed
        case opened
    }

    private var menuState: MenuState = .closed

    var coordinator: AppCoordinator!
    var hostedNavigationController: UINavigationController!

    private var navController: UINavigationController { hostedNavigationController }

    private lazy var sideMenuView: SideMenuView = {
        let menu = SideMenuView()
        menu.translatesAutoresizingMaskIntoConstraints = false
        menu.frame.origin.x = -menu.frame.width
        return menu
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        setupSwipeGestures()
    }

    private func setupSwipeGestures() {
        addSwipeGesture(for: .left)
        addSwipeGesture(for: .right)
    }

    private func addSwipeGesture(for edge: UIRectEdge) {
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleSwipeGesture(_:)))
        gesture.edges = edge
        view.addGestureRecognizer(gesture)
    }

    @objc private func handleSwipeGesture(_ gestureRecognizer: UIScreenEdgePanGestureRecognizer) {
        if gestureRecognizer.state == .ended {
            toggleMenu()
        }
    }
}

extension ContainerViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(sideMenuView)

        addChild(navController)
        view.addSubview(navController.view)
        navController.didMove(toParent: self)
    }

    func setupAdditionalConfiguration() {
        view.backgroundColor = .SIDE
        sideMenuView.delegate = self
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            sideMenuView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            sideMenuView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sideMenuView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sideMenuView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.7)
        ])
    }
}

extension ContainerViewController: MenuButtonDelegate {
    func didTapMenuButton() {
        toggleMenu()
    }

    var isMenuOpened: Bool {
        menuState == .opened
    }

    func toggleMenu() {
        switch menuState {
        case .closed:
            if shouldPopNavigationStack() {
                navController.popToRootViewController(animated: false)
            }
            openMenu()
        case .opened:
            closeMenu()
        }
    }

    private func shouldPopNavigationStack() -> Bool {
        navController.viewControllers.count > 1
    }

    private func openMenu() {
        menuState = .opened
        openMenuAnimation()
        disableCurrentViewInteraction()
    }

    private func closeMenu() {
        menuState = .closed
        closeMenuAnimation()
        enableCurrentViewInteraction()
    }

    private func openMenuAnimation() {
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: .curveEaseInOut) { [weak self] in
            guard let self = self else { return }

            var transform = CATransform3DIdentity
            transform.m34 = -1.0 / 500

            self.navController.view.frame.origin.x = self.view.frame.width / 1.6
            self.navController.view.layer.cornerRadius = 24
            self.navController.view.layer.transform = CATransform3DRotate(transform, -16 * (.pi / 180), 0, 1, 0)
            self.sideMenuView.frame.origin.x = 0
        }
    }

    private func closeMenuAnimation() {
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: .curveEaseInOut) { [weak self] in
            guard let self = self else { return }

            self.navController.view.layer.cornerRadius = 0
            self.navController.view.layer.transform = CATransform3DIdentity
            self.navController.view.frame.origin.x = 0
            self.sideMenuView.frame.origin.x = -self.sideMenuView.frame.width
        }
    }
}

extension ContainerViewController: SideMenuViewDelegate {
    func didSelect(item: TabOption) {
        if menuState == .opened {
            closeMenu()
        }
        coordinator.select(item)
    }
}

extension ContainerViewController {

    private func disableCurrentViewInteraction() {
        guard let currentViewController = navController.topViewController else { return }

        itemsToActive.removeAll()
        for subview in currentViewController.view.subviews where subview.isUserInteractionEnabled && subview.tag != 10 {
            itemsToActive.append(subview)
            subview.isUserInteractionEnabled = false
        }
    }

    private func enableCurrentViewInteraction() {
        itemsToActive.forEach { $0.isUserInteractionEnabled = true }
        itemsToActive.removeAll()
    }
}
