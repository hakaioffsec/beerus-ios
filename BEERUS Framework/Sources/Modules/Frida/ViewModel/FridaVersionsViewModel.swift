import Foundation

final class FridaVersionsViewModel {

    weak var coordinator: SetupFridaCoordinator?

    private(set) var releases: [FridaRelease] = []
    private var cellStatuses: [Int: FridaCellStatus] = [:]
    private var activeDownload: FridaDownloadTask?
    private var downloadingIndex: Int?

    var onLoading: (Bool) -> Void = { _ in }
    var onLoaded: () -> Void = {}
    var onError: (String) -> Void = { _ in }
    var onReloadData: () -> Void = {}
    var onReloadRow: (Int) -> Void = { _ in }
    var onUninstalling: (Bool) -> Void = { _ in }

    func viewDidLoad() {
        fetchReleases()
    }

    func numberOfRows() -> Int { releases.count }

    func release(at index: Int) -> FridaRelease { releases[index] }

    func status(at index: Int) -> FridaCellStatus { cellStatuses[index] ?? FridaCellStatus.none }

    func close() {
        activeDownload?.cancel()
        coordinator?.dismissVersions()
    }

    private func fetchReleases() {
        onLoading(true)

        FridaGitHubService.fetchReleases { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.onLoading(false)

                switch result {
                case .success(let releases):
                    self.releases = releases
                    self.onLoaded()
                    self.onReloadData()
                case .failure(let error):
                    self.onError(error.localizedDescription)
                }
            }
        }
    }

    func tappedUninstall() {
        coordinator?.confirmFridaUninstall { [weak self] in
            self?.performUninstall()
        }
    }

    private func performUninstall() {
        guard RootExec.isAvailable else {
            coordinator?.showError(title: "Daemon Offline", message: "The beerus daemon is not running.")
            return
        }

        onUninstalling(true)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = RootExec.uninstallFrida()
            let success = result?.hasPrefix("ok") == true
            DispatchQueue.main.async {
                self?.handleUninstallResult(success: success, result: result)
            }
        }
    }

    private func handleUninstallResult(success: Bool, result: String?) {
        onUninstalling(false)

        if success {
            cellStatuses.removeAll()
            onReloadData()
            FridaChecker.notifyStatusChanged()
            coordinator?.showError(title: "Done", message: "frida-server has been uninstalled.")
        } else {
            coordinator?.showError(title: "Failed", message: result ?? "No response from daemon")
        }
    }

    func didSelectRelease(at index: Int) {
        let release = releases[index]
        let arch = DeviceInfo.architecture
        guard let asset = release.fridaServerAsset(for: arch) else {
            coordinator?.showError(title: "Not Available",
                                   message: "No frida-server package for \(arch) in \(release.version).")
            return
        }
        let sizeStr = String(format: "%.1f MB", Double(asset.size) / 1_048_576.0)
        coordinator?.confirmFridaInstall(
            version: release.version,
            detail: "Install frida-server (\(arch), \(sizeStr)) to /usr/sbin/frida-server?"
        ) { [weak self] in
            self?.installRelease(at: index)
        }
    }

    private func installRelease(at index: Int) {
        let release = releases[index]
        let arch = DeviceInfo.architecture

        guard let asset = release.fridaServerAsset(for: arch) else {
            coordinator?.showError(title: "No Binary", message: "No frida-server package found for \(arch) in this release.")
            return
        }
        guard RootExec.isAvailable else {
            coordinator?.showError(title: "Daemon Offline", message: "The beerus daemon is not running.")
            return
        }

        activeDownload?.cancel()
        if let prev = downloadingIndex {
            cellStatuses[prev] = FridaCellStatus.none
            onReloadRow(prev)
        }

        downloadingIndex = index
        cellStatuses[index] = .downloading(0)
        onReloadRow(index)

        activeDownload = FridaGitHubService.downloadAsset(
            asset,
            progress: { [weak self] progress in
                DispatchQueue.main.async {
                    self?.cellStatuses[index] = .downloading(progress)
                    self?.onReloadRow(index)
                }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch result {
                    case .success(let filePath):
                        self.installBinary(from: filePath, at: index)
                    case .failure(let error):
                        if (error as NSError).code == NSURLErrorCancelled { return }
                        self.cellStatuses[index] = .failed("Download failed")
                        self.onReloadRow(index)
                        self.coordinator?.showError(title: "Download Failed", message: error.localizedDescription)
                    }
                }
            }
        )
    }

    private func installBinary(from filePath: String, at index: Int) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: filePath) else {
            cellStatuses[index] = .failed("Download failed")
            onReloadRow(index)
            coordinator?.showError(title: "Download Failed", message: "File not found at: \(filePath)")
            return
        }

        let attrs = try? fileManager.attributesOfItem(atPath: filePath)
        let size = (attrs?[.size] as? Int) ?? 0

        guard size > 1000 else {
            cellStatuses[index] = .failed("Download incomplete")
            onReloadRow(index)
            coordinator?.showError(title: "Download Failed", message: "File too small (\(size) bytes)")
            return
        }

        cellStatuses[index] = .installing
        onReloadRow(index)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = RootExec.installFrida(from: filePath)
            let success = result?.hasPrefix("ok") == true
            DispatchQueue.main.async {
                self?.handleInstallResult(success: success, result: result, index: index, filePath: filePath)
            }
        }
    }

    private func handleInstallResult(success: Bool, result: String?, index: Int, filePath: String) {
        if success {
            for (key, value) in cellStatuses {
                if case .installed = value { cellStatuses[key] = FridaCellStatus.none }
            }
            cellStatuses[index] = .installed
            onReloadData()
            FridaChecker.notifyStatusChanged()
            try? FileManager.default.removeItem(atPath: filePath)
        } else {
            cellStatuses[index] = .failed("Install failed")
            onReloadRow(index)
            coordinator?.showError(title: "Install Failed", message: result ?? "No response from daemon")
        }
        downloadingIndex = nil
    }
}
