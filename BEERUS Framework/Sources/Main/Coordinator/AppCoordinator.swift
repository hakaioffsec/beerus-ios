import UIKit

final class AppCoordinator: Coordinator {

    private(set) var childCoordinators: [Coordinator] = []

    private let window: UIWindow
    private let navigationController = UINavigationController()
    private let containerViewController = ContainerViewController()

    private var tabCoordinators: [TabOption: Coordinator] = [:]

    init(window: UIWindow) {
        self.window = window
    }

    func start() {
        containerViewController.coordinator = self
        containerViewController.hostedNavigationController = navigationController

        window.rootViewController = containerViewController
        window.makeKeyAndVisible()

        select(.home)
    }

    func select(_ tab: TabOption) {
        coordinator(for: tab).start()
    }

    private func coordinator(for tab: TabOption) -> Coordinator {
        if let existing = tabCoordinators[tab] {
            return existing
        }
        let created = makeCoordinator(for: tab)
        tabCoordinators[tab] = created
        childCoordinators.append(created)
        return created
    }

    private func makeCoordinator(for tab: TabOption) -> Coordinator {
        let menuDelegate = containerViewController
        switch tab {
        case .home:
            return HomeCoordinator(navigationController: navigationController, menuDelegate: menuDelegate)
        case .setupFrida:
            return SetupFridaCoordinator(navigationController: navigationController, menuDelegate: menuDelegate)
        case .ipaExtractor:
            return IPAExtractorCoordinator(navigationController: navigationController, menuDelegate: menuDelegate)
        case .memoryDump:
            return MemoryDumpCoordinator(navigationController: navigationController, menuDelegate: menuDelegate)
        case .lldbServer:
            return LLDBServerCoordinator(navigationController: navigationController, menuDelegate: menuDelegate)
        case .proxyProfiles:
            return ProxyProfilesCoordinator(navigationController: navigationController, menuDelegate: menuDelegate)
        case .terminal:
            return TerminalCoordinator(navigationController: navigationController, menuDelegate: menuDelegate)
        case .plistReader:
            return PlistReaderCoordinator(navigationController: navigationController, menuDelegate: menuDelegate)
        case .scriptEditor:
            return ScriptEditorCoordinator(navigationController: navigationController, menuDelegate: menuDelegate)
        case .appStore:
            return AppStoreCoordinator(navigationController: navigationController, menuDelegate: menuDelegate)
        case .jailbreakBypass:
            return JailbreakBypassCoordinator(navigationController: navigationController, menuDelegate: menuDelegate)
        case .sandboxExfiltration:
            return SandboxExfiltrationCoordinator(navigationController: navigationController, menuDelegate: menuDelegate)
        }
    }
}
