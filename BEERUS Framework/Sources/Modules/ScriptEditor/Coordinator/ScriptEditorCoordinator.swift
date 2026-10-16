import UIKit

final class ScriptEditorCoordinator: Coordinator {

    private(set) var childCoordinators: [Coordinator] = []
    private let navigationController: UINavigationController
    private weak var menuDelegate: MenuButtonDelegate?

    private weak var appPicker: UIViewController?
    private var appPickerOnSelect: ((AppModel) -> Void)?
    private var appPickerOnCancel: (() -> Void)?

    init(navigationController: UINavigationController, menuDelegate: MenuButtonDelegate?) {
        self.navigationController = navigationController
        self.menuDelegate = menuDelegate
    }

    private lazy var rootViewController: ScriptListViewController = {
        let viewModel = ScriptListViewModel()
        viewModel.coordinator = self
        let viewController = ScriptListViewController()
        viewController.viewModel = viewModel
        viewController.menuDelegate = menuDelegate
        return viewController
    }()

    func start() {
        navigationController.setViewControllers([rootViewController], animated: false)
    }

    func pop() {
        navigationController.popViewController(animated: true)
    }

    // MARK: - Navigation

    func showEditor(for script: FridaScriptModel) {
        let viewModel = ScriptEditorViewModel(script: script)
        viewModel.coordinator = self
        let viewController = ScriptEditorViewController()
        viewController.viewModel = viewModel
        navigationController.pushViewController(viewController, animated: true)
    }

    func showConsole(for script: FridaScriptModel) {
        let viewModel = ScriptConsoleViewModel(script: script)
        viewModel.coordinator = self
        let viewController = ScriptConsoleViewController()
        viewController.viewModel = viewModel
        navigationController.pushViewController(viewController, animated: true)
    }

    // MARK: - New script

    func presentNewScript(suggestedName: String,
                          onEmpty: @escaping (String) -> Void,
                          onTemplate: @escaping (String) -> Void) {
        let alert = UIAlertController(title: "New Script", message: nil, preferredStyle: .alert)
        alert.overrideUserInterfaceStyle = .dark
        alert.addTextField { field in
            field.placeholder = suggestedName
            field.autocapitalizationType = .words
            field.font = AppFont.regular(14)
        }

        func resolvedName() -> String {
            let raw = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            return raw.isEmpty ? suggestedName : raw
        }

        alert.addAction(UIAlertAction(title: "Empty Script", style: .default) { _ in
            onEmpty(resolvedName())
        })
        alert.addAction(UIAlertAction(title: "From Template", style: .default) { _ in
            onTemplate(resolvedName())
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        navigationController.present(alert, animated: true)
    }

    func presentTemplatePicker(onPick: @escaping (String) -> Void) {
        let picker = UIAlertController(title: "Choose Template", message: nil, preferredStyle: .actionSheet)
        picker.overrideUserInterfaceStyle = .dark

        for (title, source) in ScriptTemplates.all {
            picker.addAction(UIAlertAction(title: title, style: .default) { _ in
                onPick(source)
            })
        }
        picker.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        anchorToCenter(picker)
        navigationController.present(picker, animated: true)
    }

    // MARK: - Editor menu

    func presentEditorMenu(onRename: @escaping () -> Void,
                           onExport: @escaping () -> Void,
                           onDuplicate: @escaping () -> Void,
                           onDelete: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.overrideUserInterfaceStyle = .dark
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { _ in onRename() })
        alert.addAction(UIAlertAction(title: "Export as .js", style: .default) { _ in onExport() })
        alert.addAction(UIAlertAction(title: "Duplicate", style: .default) { _ in onDuplicate() })
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in onDelete() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        anchorToCenter(alert)
        navigationController.present(alert, animated: true)
    }

    func presentRename(currentName: String, onRename: @escaping (String) -> Void) {
        let alert = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
        alert.overrideUserInterfaceStyle = .dark
        alert.addTextField { field in
            field.text = currentName
            field.font = AppFont.regular(14)
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            guard let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { return }
            onRename(name)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        navigationController.present(alert, animated: true)
    }

    // MARK: - Share

    func shareFile(at url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.overrideUserInterfaceStyle = .dark
        anchorToCenter(activity)
        navigationController.present(activity, animated: true)
    }

    func shareText(_ text: String) {
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activity.overrideUserInterfaceStyle = .dark
        anchorToCenter(activity)
        navigationController.present(activity, animated: true)
    }

    // MARK: - App picker

    func presentAppPicker(onSelect: @escaping (AppModel) -> Void, onCancel: @escaping () -> Void) {
        appPickerOnSelect = onSelect
        appPickerOnCancel = onCancel

        let viewModel = AppPickerViewModel()
        viewModel.coordinator = self
        let picker = AppPickerViewController()
        picker.viewModel = viewModel
        picker.modalPresentationStyle = .formSheet
        appPicker = picker
        navigationController.present(picker, animated: true)
    }

    func appPickerDidSelect(_ app: AppModel) {
        let onSelect = appPickerOnSelect
        clearAppPicker()
        appPicker?.dismiss(animated: true) { onSelect?(app) }
    }

    func appPickerDidCancel() {
        let onCancel = appPickerOnCancel
        clearAppPicker()
        appPicker?.dismiss(animated: true) { onCancel?() }
    }

    private func clearAppPicker() {
        appPickerOnSelect = nil
        appPickerOnCancel = nil
    }

    private func anchorToCenter(_ controller: UIViewController) {
        guard let popover = controller.popoverPresentationController else { return }
        popover.sourceView = navigationController.view
        popover.sourceRect = CGRect(x: navigationController.view.bounds.midX,
                                    y: navigationController.view.bounds.midY,
                                    width: 0, height: 0)
        popover.permittedArrowDirections = []
    }
}
