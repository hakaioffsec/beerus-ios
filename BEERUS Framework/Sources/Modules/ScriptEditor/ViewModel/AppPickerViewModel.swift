import Foundation

final class AppPickerViewModel {

    weak var coordinator: ScriptEditorCoordinator?

    private var allApps: [AppModel] = []
    private var filtered: [AppModel] = []

    private(set) var titleText = "Select App"
    private(set) var emptyText: String?

    var onLoadingChange: (Bool) -> Void = { _ in }
    var onReload: () -> Void = {}

    func numberOfRows() -> Int { filtered.count }

    func app(at index: Int) -> AppModel { filtered[index] }

    func viewDidLoad() {
        loadApps()
    }

    func didSelect(at index: Int) {
        coordinator?.appPickerDidSelect(filtered[index])
    }

    func cancel() {
        coordinator?.appPickerDidCancel()
    }

    func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            filtered = allApps
        } else {
            filtered = allApps.filter {
                $0.name.lowercased().contains(query) ||
                $0.bundleIdentifier.lowercased().contains(query) ||
                "\($0.pid)".contains(query)
            }
        }
        emptyText = (filtered.isEmpty && !allApps.isEmpty) ? "No matches" : nil
        onReload()
    }

    private func loadApps() {
        onLoadingChange(true)

        Task { @MainActor in
            do {
                let apps = try await FridaManager.shared.getInstalledApps()
                let totalCount = apps.count
                let running = apps.filter { $0.pid > 0 }.sorted { $0.name.lowercased() < $1.name.lowercased() }

                allApps = running
                filtered = running
                onLoadingChange(false)

                if running.isEmpty {
                    emptyText = totalCount > 0
                        ? "No running apps found.\n(\(totalCount) installed — open your target app first)"
                        : "No apps found."
                } else {
                    emptyText = nil
                    titleText = "Running Apps (\(running.count))"
                }
                onReload()
            } catch {
                onLoadingChange(false)
                emptyText = "Failed: \(error.localizedDescription)"
                onReload()
            }
        }
    }
}
