import Foundation

final class DownloadViewModel {

    enum StepStatus { case pending, inProgress, done }

    weak var coordinator: AppStoreCoordinator?

    private let app: AppStoreApp
    private let versionID: String?
    private var downloadedPath: String?
    private var downloadTask: Task<Void, Never>?

    var isSpecificVersion: Bool { versionID != nil }
    var nameText: String { app.name }
    var bundleText: String { app.bundleID }

    var onIcon: (Data) -> Void = { _ in }
    var onStep: (Int, StepStatus) -> Void = { _, _ in }
    var onProgress: (Float, String) -> Void = { _, _ in }
    var onComplete: () -> Void = {}
    var onError: (String) -> Void = { _ in }
    var onPrepareRetry: () -> Void = {}

    init(app: AppStoreApp, versionID: String?) {
        self.app = app
        self.versionID = versionID
    }

    func viewDidLoad() {
        loadIcon()
        startDownload()
    }

    func retry() {
        onPrepareRetry()
        startDownload()
    }

    func tappedShare() {
        guard let downloadedPath else { return }
        coordinator?.shareIPA(at: downloadedPath)
    }

    func tappedFiles() {
        guard let downloadedPath else { return }
        coordinator?.showFilesLocation(path: downloadedPath)
    }

    private func loadIcon() {
        guard let urlString = app.iconURL, let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data else { return }
            DispatchQueue.main.async { self?.onIcon(data) }
        }.resume()
    }

    private func startDownload() {
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                await self.emitStep(0, .inProgress)
                do {
                    try await AppStoreService.shared.purchase(app: self.app)
                } catch AppStoreError.purchaseFailed(let msg) where msg.contains("already") {
                } catch AppStoreError.paidAppNotSupported {
                    throw AppStoreError.paidAppNotSupported
                } catch {
                    throw error
                }
                try Task.checkCancellation()
                await self.emitStep(0, .done)

                await self.emitStep(1, .inProgress)
                let result = try await AppStoreService.shared.download(
                    app: self.app, externalVersionID: self.versionID
                ) { [weak self] downloaded, total in
                    Task { @MainActor in
                        guard let self, !Task.isCancelled else { return }
                        let pct = total > 0 ? Float(downloaded) / Float(total) : 0
                        let dlMB = Double(downloaded) / 1_048_576
                        let totalMB = Double(total) / 1_048_576
                        self.onProgress(pct, String(format: "%.1f MB / %.1f MB (%.0f%%)", dlMB, totalMB, pct * 100))
                    }
                }
                try Task.checkCancellation()
                await self.emitStep(1, .done)

                await self.emitStep(2, .inProgress)
                try? await Task.sleep(nanoseconds: 200_000_000)
                await self.emitStep(2, .done)

                await self.emitStep(3, .inProgress)
                try? await Task.sleep(nanoseconds: 200_000_000)
                await self.emitStep(3, .done)

                await self.emitStep(4, .done)

                await MainActor.run {
                    self.downloadedPath = result.destinationPath
                    self.onComplete()
                }
            } catch is CancellationError {
            } catch AppStoreError.tokenExpired {
                await MainActor.run { self.coordinator?.sessionExpired() }
            } catch {
                let message = self.friendlyError(error)
                await MainActor.run { self.onError(message) }
            }
        }
    }

    private func emitStep(_ index: Int, _ status: StepStatus) async {
        await MainActor.run { self.onStep(index, status) }
    }

    private func friendlyError(_ error: Error) -> String {
        if let appError = error as? AppStoreError {
            switch appError {
            case .paidAppNotSupported:
                return "Paid apps require purchase on device"
            case .licenseRequired:
                return "This app requires a valid license on your account."
            case .tokenExpired:
                return "Your session expired. Please log in again."
            case .purchaseFailed:
                return "Could not complete the purchase. Please try again later."
            case .downloadFailed, .installFailed:
                return "Could not complete the download. Please try again later."
            case .keychainSaveFailed, .bagFailed, .loginFailed, .authCodeRequired,
                 .accountDisabled, .searchFailed, .lookupFailed, .versionsFailed, .metadataFailed:
                return "Something went wrong. Please try again."
            }
        }
        if error is URLError {
            return "Connection failed. Check your internet and try again."
        }
        return "Could not complete the download. Please try again later."
    }

    deinit {
        downloadTask?.cancel()
    }
}
