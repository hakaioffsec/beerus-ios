import Foundation

final class SetupFridaViewModel {

    struct Status {
        let statusText: String
        let versionText: String
        let startTitle: String
    }

    weak var coordinator: SetupFridaCoordinator?

    var onStatus: (Status) -> Void = { _ in }
    var onVersions: ([String]) -> Void = { _ in }
    var onSelectedVersionTitle: (String) -> Void = { _ in }
    var onStartEnabled: (Bool) -> Void = { _ in }
    var onProgress: (String, Float) -> Void = { _, _ in }
    var onHideProgress: () -> Void = {}

    private var versions: [String] = []
    private var selectedVersion = ""
    private var versionRunning = ""
    private var isRunning = false
    private var startDownloading = false

    func viewDidLoad() {
        checkFridaRunning()
    }

    func selectVersion(_ version: String) {
        selectedVersion = version
    }

    func addVersionManually() {
        promptManualVersion(showError: false)
    }

    private func promptManualVersion(showError: Bool) {
        coordinator?.promptFridaVersion(showError: showError) { [weak self] input in
            self?.handleManualVersion(input)
        }
    }

    private func handleManualVersion(_ input: String?) {
        guard let input else { return }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            promptManualVersion(showError: true)
            return
        }

        Github.verifyVersion(repository: "frida/frida", version: trimmed) { [weak self] isValid in
            DispatchQueue.main.async {
                guard let self else { return }
                if isValid {
                    self.onSelectedVersionTitle(trimmed)
                    self.selectedVersion = trimmed
                } else {
                    self.promptManualVersion(showError: true)
                }
            }
        }
    }

    func checkFridaRunning() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            var statusText = "Status: Stopped"
            var versionText = "Version: None"
            var toggleFridaText = "Start Frida"

            if self.startDownloading {
                statusText = "Status: Downloading"
            } else if FridaServerService.isRunning() {
                statusText = "Status: Running"
                toggleFridaText = "Stop Frida"
                self.isRunning = true
            } else {
                self.isRunning = false
            }

            if let version = FridaServerService.installedVersion() {
                versionText = "Version: " + version
                self.versionRunning = version
                if self.selectedVersion.isEmpty {
                    self.selectedVersion = version
                }
            }

            if self.versions.isEmpty {
                Github.getReleaseVersions(repository: "frida/frida") { resultVersions in
                    self.versions = resultVersions
                    DispatchQueue.main.async { self.onVersions(resultVersions) }
                }
            }

            DispatchQueue.main.async {
                self.onStatus(Status(statusText: statusText, versionText: versionText, startTitle: toggleFridaText))
            }
        }
    }

    func toggleFrida() {
        onStartEnabled(false)

        if isRunning {
            FridaServerService.stop { [weak self] in
                DispatchQueue.main.async {
                    self?.onStartEnabled(true)
                    self?.checkFridaRunning()
                }
            }
        } else if !versionRunning.isEmpty && selectedVersion == versionRunning && FridaServerService.daemonExists() {
            FridaServerService.startExisting { [weak self] in
                DispatchQueue.main.async {
                    self?.onStartEnabled(true)
                    self?.checkFridaRunning()
                }
            }
        } else if !selectedVersion.isEmpty {
            downloadAndInstall()
        } else {
            onStartEnabled(true)
            coordinator?.showError(title: "Error", message: "Select a Frida version first")
        }
    }

    private func downloadAndInstall() {
        startDownloading = true
        checkFridaRunning()
        onProgress("Detecting device architecture...", 0.02)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let arch = FridaServerService.detectArchitecture()
            guard !arch.isEmpty else {
                DispatchQueue.main.async {
                    self.failDownload(title: "Error", message: "Could not detect device architecture")
                }
                return
            }

            let debFileName = "frida-server.deb"
            let downloadURL = "https://github.com/frida/frida/releases/download/\(self.selectedVersion)/frida_\(self.selectedVersion)_\(arch).deb"
            let appTmpDir = NSTemporaryDirectory()
            let systemDebPath = BeerusStrings.tmp + debFileName

            Requests.downloadFile(
                from: downloadURL,
                fileName: debFileName,
                destinationPath: appTmpDir,
                progress: { downloaded, total in
                    DispatchQueue.main.async {
                        let pct = total > 0 ? Double(downloaded) / Double(total) : 0
                        let dlMB = Double(downloaded) / 1_048_576
                        let totalMB = Double(total) / 1_048_576
                        let text = total > 0
                            ? String(format: "%.1f / %.1f MB · %.0f%%", dlMB, totalMB, pct * 100)
                            : "Downloading..."
                        self.onProgress(text, 0.05 + Float(pct) * 0.75)
                    }
                }
            ) { result in
                switch result {
                case .success(let fileURL):
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
                    if fileSize < 1000 {
                        DispatchQueue.main.async {
                            self.failDownload(title: "Download Failed", message: "File is too small or empty")
                        }
                        return
                    }

                    DispatchQueue.main.async {
                        self.onProgress("Copying to system...", 0.85)
                    }

                    let copyExit = FridaServerService.copyToSystem(from: fileURL.path, systemPath: systemDebPath)
                    if copyExit != 0 {
                        DispatchQueue.main.async {
                            self.failDownload(title: "Install Failed", message: "Failed to copy to system tmp")
                        }
                        return
                    }

                    DispatchQueue.main.async {
                        self.onProgress("Installing frida-server...", 0.95)
                    }

                    if let response = FridaServerService.install(fromSystemPath: systemDebPath) {
                        DispatchQueue.main.async {
                            self.startDownloading = false
                            self.onStartEnabled(true)
                            if response.hasPrefix("ok:") {
                                self.onProgress("Installed!", 1.0)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    self.onHideProgress()
                                }
                            } else {
                                self.onHideProgress()
                                self.coordinator?.showError(title: "Install Failed", message: response)
                            }
                            self.checkFridaRunning()
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.failDownload(title: "Install Failed", message: "Daemon not responding")
                        }
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.failDownload(title: "Download Failed", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func failDownload(title: String, message: String) {
        startDownloading = false
        onStartEnabled(true)
        checkFridaRunning()
        onHideProgress()
        coordinator?.showError(title: title, message: message)
    }
}
