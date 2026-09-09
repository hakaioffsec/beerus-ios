import UIKit

final class ContainerViewController: UIViewController {

    private var itemsToActive: [UIView] = []

    enum MenuState {
        case closed
        case opened
    }

    private var menuState: MenuState = .closed
    private var navController: UINavigationController?

    private lazy var homeViewController = HomeViewController()
    private lazy var setupFridaViewController = SetupFridaViewController()
    private lazy var proxyProfilesViewController = ProxyProfilesViewController()
    private lazy var ipaExtractorViewController = IPAExtractorViewController()
    private lazy var memoryDumpViewController = MemoryDumpViewController()
    private lazy var lldbServerViewController = LLDBServerViewController()
    private lazy var terminalViewController = TerminalViewController()
    private lazy var plistReaderViewController = PlistReaderViewController()
    private lazy var scriptListViewController = ScriptListViewController()
    private lazy var jailbreakBypassViewController = JailbreakBypassViewController()
    private lazy var sandboxExfiltrationViewController = SandboxExfiltrationViewController()
    // Cached once the user is authenticated, so leaving the tab and coming back doesn't throw away
    // an already-loaded search screen (auth is still re-checked on every visit via
    // resolveAppStoreViewController(), only the authenticated search screen itself is preserved).
    private var cachedAppStoreSearchVC: AppStoreSearchViewController?

    private func resolveAppStoreViewController() -> UIViewController {
        guard AppStoreCredentialManager.hasStoredAccount else {
            let loginVC = AppStoreLoginViewController()
            loginVC.menuDelegate = self
            loginVC.onLoginSuccess = { [weak self] _ in
                guard let self else { return }
                let searchVC = AppStoreSearchViewController()
                searchVC.menuDelegate = self
                self.cachedAppStoreSearchVC = searchVC
                self.navController?.setViewControllers([searchVC], animated: true)
            }
            return loginVC
        }

        if let cached = cachedAppStoreSearchVC {
            return cached
        }

        let searchVC = AppStoreSearchViewController()
        searchVC.menuDelegate = self
        cachedAppStoreSearchVC = searchVC
        return searchVC
    }

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

        let navController = UINavigationController(rootViewController: homeViewController)
        addChild(navController)
        view.addSubview(navController.view)
        navController.didMove(toParent: self)
        self.navController = navController
    }

    func setupAdditionalConfiguration() {
        view.backgroundColor = .SIDE

        homeViewController.menuDelegate = self
        setupFridaViewController.menuDelegate = self
        proxyProfilesViewController.menuDelegate = self
        ipaExtractorViewController.menuDelegate = self
        memoryDumpViewController.menuDelegate = self
        lldbServerViewController.menuDelegate = self
        terminalViewController.menuDelegate = self
        plistReaderViewController.menuDelegate = self
        scriptListViewController.menuDelegate = self
        jailbreakBypassViewController.menuDelegate = self
        sandboxExfiltrationViewController.menuDelegate = self
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
                navController?.popToRootViewController(animated: false)
            }
            openMenu()
        case .opened:
            closeMenu()
        }
    }

    private func shouldPopNavigationStack() -> Bool {
        guard let navController = navController else { return false }
        return navController.viewControllers.count > 1
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

            self.navController?.view.frame.origin.x = self.view.frame.width / 1.6
            self.navController?.view.layer.cornerRadius = 24
            self.navController?.view.layer.transform = CATransform3DRotate(transform, -16 * (.pi / 180), 0, 1, 0)
            self.sideMenuView.frame.origin.x = 0
        }
    }

    private func closeMenuAnimation() {
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: .curveEaseInOut) { [weak self] in
            guard let self = self else { return }

            self.navController?.view.layer.cornerRadius = 0
            self.navController?.view.layer.transform = CATransform3DIdentity
            self.navController?.view.frame.origin.x = 0
            self.sideMenuView.frame.origin.x = -self.sideMenuView.frame.width
        }
    }
}

extension ContainerViewController: SideMenuViewDelegate {
    func didSelect(item: TabOption) {
        switch item {
        case .home:
            show(viewController: homeViewController)
        case .setupFrida:
            show(viewController: setupFridaViewController)
        case .ipaExtractor:
            show(viewController: ipaExtractorViewController)
        case .memoryDump:
            show(viewController: memoryDumpViewController)
        case .lldbServer:
            show(viewController: lldbServerViewController)
        case .proxyProfiles:
            show(viewController: proxyProfilesViewController)
        case .terminal:
            show(viewController: terminalViewController)
        case .plistReader:
            show(viewController: plistReaderViewController)
        case .scriptEditor:
            show(viewController: scriptListViewController)
        case .appStore:
            show(viewController: resolveAppStoreViewController())
        case .jailbreakBypass:
            show(viewController: jailbreakBypassViewController)
        case .sandboxExfiltration:
            show(viewController: sandboxExfiltrationViewController)
        }
    }

    private func show(viewController: UIViewController) {
        if menuState == .opened {
            closeMenu()
        }
        navController?.setViewControllers([viewController], animated: false)
    }
}

extension ContainerViewController {

    private func disableCurrentViewInteraction() {
        guard let currentViewController = navController?.topViewController else { return }

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
