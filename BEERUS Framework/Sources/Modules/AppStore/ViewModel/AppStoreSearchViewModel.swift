import Foundation

final class AppStoreSearchViewModel {

    weak var coordinator: AppStoreCoordinator?

    private(set) var results: [AppStoreApp] = []
    private var searchTask: Task<Void, Never>?

    var onAccount: (String) -> Void = { _ in }
    var onLoading: (Bool) -> Void = { _ in }
    var onResults: (_ isEmpty: Bool) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    func viewDidLoad() {
        if let account = try? AppStoreService.shared.accountInfo() {
            onAccount("\(account.email) ✓")
        }
    }

    func numberOfRows() -> Int { results.count }

    func app(at index: Int) -> AppStoreApp { results[index] }

    func search(_ term: String) {
        searchTask?.cancel()
        onLoading(true)
        searchTask = Task { @MainActor in
            do {
                let apps = try await AppStoreService.shared.search(term: term)
                guard !Task.isCancelled else { return }
                onLoading(false)
                results = apps
                onResults(apps.isEmpty)
            } catch {
                guard !Task.isCancelled else { return }
                onLoading(false)
                onError(error.localizedDescription)
            }
        }
    }

    func didSelectApp(at index: Int) {
        coordinator?.showDetail(for: results[index])
    }

    func tappedLogout() {
        coordinator?.logout()
    }
}
