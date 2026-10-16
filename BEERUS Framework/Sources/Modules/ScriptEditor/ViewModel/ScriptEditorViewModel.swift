import Foundation

final class ScriptEditorViewModel {

    weak var coordinator: ScriptEditorCoordinator?

    private var script: FridaScriptModel
    private let storage: ScriptStorageService
    private var currentText: String
    private var hasUnsavedChanges = false

    var onName: (String) -> Void = { _ in }
    var onCode: (String) -> Void = { _ in }
    var onUnsaved: (Bool) -> Void = { _ in }
    var onCharCount: (String) -> Void = { _ in }
    var onSaved: () -> Void = {}

    init(script: FridaScriptModel, storage: ScriptStorageService = .shared) {
        self.script = script
        self.storage = storage
        self.currentText = script.source
    }

    func viewDidLoad() {
        onName(script.name)
        onCode(script.source)
        onCharCount(charCount(for: script.source))
    }

    func viewWillDisappear() {
        if hasUnsavedChanges { save() }
    }

    func textChanged(_ text: String) {
        currentText = text
        hasUnsavedChanges = true
        onUnsaved(true)
        onCharCount(charCount(for: text))
    }

    func tappedSave() {
        save()
        onSaved()
    }

    func tappedRun() {
        if hasUnsavedChanges { save() }
        coordinator?.showConsole(for: script)
    }

    func tappedBack() {
        if hasUnsavedChanges { save() }
        coordinator?.pop()
    }

    func tappedMore() {
        coordinator?.presentEditorMenu(
            onRename: { [weak self] in self?.requestRename() },
            onExport: { [weak self] in self?.export() },
            onDuplicate: { [weak self] in self?.duplicate() },
            onDelete: { [weak self] in self?.delete() }
        )
    }

    private func requestRename() {
        coordinator?.presentRename(currentName: script.name) { [weak self] name in
            guard let self else { return }
            self.script.name = name
            self.onName(name)
            self.save()
        }
    }

    private func export() {
        coordinator?.shareFile(at: storage.exportURL(for: script))
    }

    private func duplicate() {
        let copy = storage.duplicate(script)
        script = copy
        onName(copy.name)
    }

    private func delete() {
        storage.delete(script)
        coordinator?.pop()
    }

    private func save() {
        script.source = currentText
        script.updatedAt = Date()
        storage.save(script)
        hasUnsavedChanges = false
        onUnsaved(false)
    }

    private func charCount(for text: String) -> String {
        let lines = text.components(separatedBy: "\n").count
        return "\(text.count) chars · \(lines) lines"
    }
}
