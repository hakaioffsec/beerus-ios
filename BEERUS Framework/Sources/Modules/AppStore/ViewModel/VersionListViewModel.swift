import Foundation

final class VersionListViewModel {

    weak var coordinator: AppStoreCoordinator?

    private let app: AppStoreApp
    private var versionIDs: [String] = []
    private var latestID: String = ""
    private var metadataCache: [String: VersionMetadata] = [:]
    private var metadataTask: Task<Void, Never>?

    var titleText: String { "\(app.name) — Versions" }

    var onLoading: (Bool) -> Void = { _ in }
    var onReload: () -> Void = {}
    var onRowUpdated: (Int) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    init(app: AppStoreApp) {
        self.app = app
    }

    func numberOfRows() -> Int { versionIDs.count }
    func versionID(at index: Int) -> String { versionIDs[index] }
    func metadata(at index: Int) -> VersionMetadata? { metadataCache[versionIDs[index]] }
    func isLatest(at index: Int) -> Bool { versionIDs[index] == latestID }

    func viewDidLoad() {
        loadVersions()
    }

    func didTapGet(at index: Int) {
        coordinator?.showDownload(for: app, versionID: versionIDs[index])
    }

    private func loadVersions() {
        onLoading(true)
        Task { @MainActor in
            do {
                let result = try await fetchVersionsWithPurchase()
                onLoading(false)
                versionIDs = result.identifiers.reversed()
                latestID = result.latestID
                onReload()
                loadMetadataProgressively()
            } catch AppStoreError.tokenExpired {
                onLoading(false)
                coordinator?.sessionExpired()
            } catch {
                onLoading(false)
                onError(error.localizedDescription)
            }
        }
    }

    private func fetchVersionsWithPurchase() async throws -> VersionListResult {
        do {
            return try await AppStoreService.shared.listVersions(app: app)
        } catch AppStoreError.licenseRequired {
            try await AppStoreService.shared.purchase(app: app)
            return try await AppStoreService.shared.listVersions(app: app)
        }
    }

    private func loadMetadataProgressively() {
        metadataTask = Task { [weak self] in
            guard let self else { return }
            let app = self.app
            let maxConcurrent = 5
            for batch in stride(from: 0, to: versionIDs.count, by: maxConcurrent) {
                let end = min(batch + maxConcurrent, versionIDs.count)
                let slice = Array(versionIDs[batch..<end])
                await withTaskGroup(of: (Int, String, VersionMetadata?).self) { group in
                    for (offset, versionID) in slice.enumerated() {
                        let index = batch + offset
                        group.addTask {
                            let meta = try? await AppStoreService.shared.getVersionMetadata(
                                app: app, versionID: versionID
                            )
                            return (index, versionID, meta)
                        }
                    }
                    for await (index, versionID, meta) in group {
                        guard !Task.isCancelled else { return }
                        guard let meta else { continue }
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            self.metadataCache[versionID] = meta
                            self.onRowUpdated(index)
                        }
                    }
                }
                if Task.isCancelled { return }
            }
        }
    }

    deinit {
        metadataTask?.cancel()
    }
}
