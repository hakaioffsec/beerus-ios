import Foundation

final class ScriptListViewModel {

    weak var coordinator: ScriptEditorCoordinator?

    private let storage: ScriptStorageService
    private var allScripts: [FridaScriptModel] = []
    private var filteredScripts: [FridaScriptModel] = []
    private var query: String = ""

    var onReload: () -> Void = {}

    init(storage: ScriptStorageService = .shared) {
        self.storage = storage
    }

    func viewWillAppear() {
        reload()
    }

    func numberOfRows() -> Int { filteredScripts.count }

    func script(at index: Int) -> FridaScriptModel { filteredScripts[index] }

    var isEmpty: Bool { filteredScripts.isEmpty }

    func search(_ text: String) {
        query = text
        applyFilter()
    }

    func didSelect(at index: Int) {
        coordinator?.showEditor(for: filteredScripts[index])
    }

    func delete(at index: Int) {
        storage.delete(filteredScripts[index])
        reload()
    }

    func duplicate(at index: Int) {
        _ = storage.duplicate(filteredScripts[index])
        reload()
    }

    func tappedNew() {
        let autoName = storage.nextAutoName()
        coordinator?.presentNewScript(
            suggestedName: autoName,
            onEmpty: { [weak self] name in self?.createEmpty(named: name) },
            onTemplate: { [weak self] name in self?.chooseTemplate(named: name) }
        )
    }

    private func createEmpty(named name: String) {
        let script = FridaScriptModel(name: name, source: "// \(name)\n\n")
        storage.save(script)
        coordinator?.showEditor(for: script)
    }

    private func chooseTemplate(named name: String) {
        coordinator?.presentTemplatePicker { [weak self] source in
            let script = FridaScriptModel(name: name, source: source)
            self?.storage.save(script)
            self?.coordinator?.showEditor(for: script)
        }
    }

    private func reload() {
        allScripts = storage.loadAll()
        applyFilter()
    }

    private func applyFilter() {
        var scripts = allScripts
        let lowered = query.lowercased()
        if !lowered.isEmpty {
            scripts = scripts.filter {
                $0.name.lowercased().contains(lowered) ||
                $0.source.lowercased().contains(lowered)
            }
        }
        filteredScripts = scripts
        onReload()
    }
}
