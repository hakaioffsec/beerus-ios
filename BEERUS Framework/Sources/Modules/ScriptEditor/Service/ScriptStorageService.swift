import Foundation

final class ScriptStorageService {

    static let shared = ScriptStorageService()

    private let fileManager = FileManager.default
    private var scriptsDir: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return docs.appendingPathComponent("FridaScripts", isDirectory: true)
    }
    private var indexURL: URL { scriptsDir.appendingPathComponent("index.json") }

    private init() {
        try? fileManager.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: indexURL.path) {
            seedTemplates()
        }
    }

    // MARK: - CRUD

    func loadAll() -> [FridaScriptModel] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let scripts = try? decoder.decode([FridaScriptModel].self, from: data) else {
            // Preserve corrupt file before returning empty — prevents next save from destroying it
            let backupURL = indexURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? fileManager.replaceItem(at: backupURL, withItemAt: indexURL,
                                         backupItemName: nil, options: [], resultingItemURL: nil)
            return []
        }
        return scripts.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ script: FridaScriptModel) {
        var scripts = loadAll()
        if let idx = scripts.firstIndex(where: { $0.id == script.id }) {
            scripts[idx] = script
        } else {
            scripts.append(script)
        }
        persist(scripts)
    }

    func delete(_ script: FridaScriptModel) {
        var scripts = loadAll()
        scripts.removeAll { $0.id == script.id }
        persist(scripts)
    }

    func duplicate(_ script: FridaScriptModel) -> FridaScriptModel {
        let copy = FridaScriptModel(
            name: script.name + " (copy)",
            source: script.source,
            targetBundle: script.targetBundle
        )
        save(copy)
        return copy
    }

    /// Returns the next auto-generated name like frida1, frida2, etc.
    func nextAutoName() -> String {
        let scripts = loadAll()
        var maxNum = 0
        for s in scripts {
            let name = s.name.lowercased()
            if name.hasPrefix("frida"), let num = Int(name.dropFirst(5)) {
                maxNum = max(maxNum, num)
            }
        }
        return "frida\(maxNum + 1)"
    }

    // MARK: - Export / Import

    func exportURL(for script: FridaScriptModel) -> URL {
        let tmpDir = fileManager.temporaryDirectory
        let safeName = script.name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let url = tmpDir.appendingPathComponent("\(safeName).js")
        try? script.source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func importScript(from url: URL) -> FridaScriptModel? {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        let script = FridaScriptModel(name: name, source: source)
        save(script)
        return script
    }

    // MARK: - Private

    private func persist(_ scripts: [FridaScriptModel]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(scripts) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Templates

    private func seedTemplates() {
        let templates = ScriptTemplates.all.map { FridaScriptModel(name: $0.name, source: $0.source) }
        persist(templates)
    }
}
