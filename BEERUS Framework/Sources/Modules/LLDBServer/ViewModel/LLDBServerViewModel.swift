import Foundation

@MainActor
final class LLDBServerViewModel {

    enum Status {
        case notInstalled, installing, starting, offline, online
    }

    enum Palette {
        case muted, red, orange, green
    }

    struct Presentation {
        let status: Status
        let subtitle: String
        let actionTitle: String?
        let actionDestructive: Bool
        let actionEnabled: Bool
        let showProgress: Bool
        let showConsole: Bool
        let showCommand: Bool
        let showUninstall: Bool
        let connectCommand: String?
    }

    nonisolated(unsafe) weak var coordinator: LLDBServerCoordinator?

    var onPresentation: (Presentation) -> Void = { _ in }
    var onProgress: (Float, String, Palette) -> Void = { _, _, _ in }
    var onFeedback: (String, Palette) -> Void = { _, _ in }
    var onConsoleReset: () -> Void = {}
    var onConsoleAppend: (String) -> Void = { _ in }
    var onServerDied: (String) -> Void = { _ in }
    var onActionEnabled: (Bool) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    private let service: LLDBServerService
    private var status: Status = .notInstalled
    private var foundPath: String?
    private var logTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?

    nonisolated init(service: LLDBServerService = LLDBServerService()) {
        self.service = service
    }

    func viewDidLoad() {
        refreshState()
    }

    func viewWillAppear() {
        refreshState()
    }

    func viewWillDisappear() {
        logTask?.cancel()
        logTask = nil
    }

    func tappedAction() {
        switch status {
        case .notInstalled: install()
        case .offline: coordinator?.showProcessPicker { [weak self] process in self?.attach(to: process) }
        case .online: stopServer()
        case .installing: cancelInstall()
        case .starting: break
        }
    }

    func tappedUninstall() {
        coordinator?.confirmUninstall { [weak self] in self?.performUninstall() }
    }

    // MARK: - Refresh

    func refreshState() {
        guard service.isDaemonRunning else {
            emit(notInstalledPresentation(subtitle: "daemon offline", actionEnabled: false))
            return
        }

        let service = self.service
        Task {
            let discovery = await Self.offload { service.discover() }
            guard let path = discovery.path else {
                self.emit(self.notInstalledPresentation())
                return
            }
            self.foundPath = path
            if let pid = discovery.serverPID {
                self.applyOnline(path: path, targetPID: "?", targetName: "attached", serverPID: pid)
                self.startLogStreaming()
            } else {
                self.emit(self.offlinePresentation(path: path))
            }
        }
    }

    // MARK: - Install

    private func install() {
        guard service.isDaemonRunning else {
            onError("beerus daemon is not running")
            return
        }

        emit(installingPresentation())

        let service = self.service
        installTask = Task {
            self.onProgress(0.1, "checking apt...", .muted)
            if Task.isCancelled { return }
            guard await Self.offload({ service.hasApt() }) else { return self.failInstall("apt-get not found") }

            self.onProgress(0.2, "resolving package...", .muted)
            if Task.isCancelled { return }
            guard await Self.offload({ service.packageAvailable() }) else {
                return self.failInstall("package not found in repos", .orange)
            }

            self.onProgress(0.35, "checking for broken packages...", .muted)
            if Task.isCancelled { return }
            await Self.offload { service.fixBrokenPackages() }

            self.onProgress(0.5, "installing...", .muted)
            if Task.isCancelled { return }
            let result = await Self.offload { service.install() }
            if Task.isCancelled { return }

            if result.success {
                self.onProgress(1.0, "Installed", .green)
                try? await Task.sleep(nanoseconds: 800_000_000)
                self.refreshState()
            } else {
                self.failInstall(result.lastLine)
            }
        }
    }

    private func cancelInstall() {
        installTask?.cancel()
        installTask = nil
        emit(notInstalledPresentation())
        onFeedback("cancelled", .muted)
    }

    private func failInstall(_ message: String, _ palette: Palette = .red) {
        emit(notInstalledPresentation())
        onFeedback(message, palette)

        let canRetry = message.localizedCaseInsensitiveContains("unmet dependencies")
            || message.localizedCaseInsensitiveContains("fix-broken")
        coordinator?.showInstallFailed(message: message, canRetry: canRetry) { [weak self] in
            self?.install()
        }
    }

    // MARK: - Attach / Stop / Uninstall

    private func attach(to process: DeviceProcess) {
        guard let path = foundPath else { return }
        emit(startingPresentation())

        let service = self.service
        Task {
            self.onProgress(0.1, "stopping previous instance...", .muted)
            await Self.offload { service.killServer() }
            try? await Task.sleep(nanoseconds: 300_000_000)
            await Self.offload { service.clearLog() }

            self.onProgress(0.4, "attaching to \(process.name) (\(process.pid))...", .muted)
            await Self.offload { service.launchAttached(path: path, targetPID: process.pid) }

            self.onProgress(0.7, "verifying...", .muted)
            let serverPID = await self.pollForServer()

            if !serverPID.isEmpty {
                self.onProgress(1.0, "attached", .green)
                try? await Task.sleep(nanoseconds: 400_000_000)
                self.applyOnline(path: path, targetPID: process.pid, targetName: process.name, serverPID: serverPID)
                self.startLogStreaming()
            } else {
                self.emit(self.offlinePresentation(path: path))
                self.onFeedback("failed to attach to \(process.name)", .red)
            }
        }
    }

    private func pollForServer() async -> String {
        let service = self.service
        for i in 0..<6 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let pid = await Self.offload { service.runningServerPID() }
            if !pid.isEmpty { return pid }
            onProgress(0.7 + Float(i + 1) * 0.04, "verifying...", .muted)
        }
        return ""
    }

    private func stopServer() {
        logTask?.cancel()
        logTask = nil
        onActionEnabled(false)

        let service = self.service
        Task {
            await Self.offload { service.killServer() }
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.onActionEnabled(true)
            if let path = self.foundPath {
                self.emit(self.offlinePresentation(path: path))
            }
        }
    }

    private func performUninstall() {
        logTask?.cancel()
        let service = self.service
        Task {
            await Self.offload { service.removePackage() }
            self.refreshState()
        }
    }

    // MARK: - Log streaming

    private func startLogStreaming() {
        logTask?.cancel()
        onConsoleReset()

        let service = self.service
        logTask = Task {
            var lastByteOffset = 0

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 800_000_000)
                if Task.isCancelled { break }

                let alive = await Self.offload { service.isServerAlive() }

                let offset = lastByteOffset
                let chunk = await Self.offload { service.readLog(fromByteOffset: offset) }
                if !chunk.isEmpty {
                    lastByteOffset += chunk.utf8.count
                    self.onConsoleAppend(chunk)
                }

                if !alive {
                    let finalOffset = lastByteOffset
                    let finalChunk = await Self.offload { service.readLog(fromByteOffset: finalOffset) }
                    self.onConsoleAppend(finalChunk)
                    self.onConsoleAppend("\n[debugserver exited]")
                    self.onFeedback("server stopped", .muted)
                    if let path = self.foundPath {
                        self.status = .offline
                        self.onServerDied(path)
                    }
                    break
                }
            }
        }
    }

    // MARK: - Presentations

    private func emit(_ presentation: Presentation) {
        status = presentation.status
        onPresentation(presentation)
    }

    private func notInstalledPresentation(subtitle: String = "LLVM debugserver from Procursus",
                                          actionEnabled: Bool = true) -> Presentation {
        Presentation(status: .notInstalled, subtitle: subtitle, actionTitle: "INSTALL",
                     actionDestructive: false, actionEnabled: actionEnabled, showProgress: false,
                     showConsole: false, showCommand: false, showUninstall: false, connectCommand: nil)
    }

    private func installingPresentation() -> Presentation {
        Presentation(status: .installing, subtitle: "installing via apt...", actionTitle: "CANCEL",
                     actionDestructive: true, actionEnabled: true, showProgress: true,
                     showConsole: false, showCommand: false, showUninstall: false, connectCommand: nil)
    }

    private func startingPresentation() -> Presentation {
        Presentation(status: .starting, subtitle: "attaching to process...", actionTitle: nil,
                     actionDestructive: false, actionEnabled: true, showProgress: true,
                     showConsole: false, showCommand: false, showUninstall: false, connectCommand: nil)
    }

    private func offlinePresentation(path: String) -> Presentation {
        Presentation(status: .offline, subtitle: path, actionTitle: "START",
                     actionDestructive: false, actionEnabled: true, showProgress: false,
                     showConsole: false, showCommand: false, showUninstall: true, connectCommand: nil)
    }

    private func applyOnline(path: String, targetPID: String, targetName: String, serverPID: String) {
        let subtitle = "\(targetName) (\(targetPID))  ·  port \(service.port)  ·  server \(serverPID)"
        emit(Presentation(status: .online, subtitle: subtitle, actionTitle: "STOP",
                          actionDestructive: true, actionEnabled: true, showProgress: false,
                          showConsole: true, showCommand: true, showUninstall: true,
                          connectCommand: service.connectCommand()))
    }

    private static func offload<T: Sendable>(_ work: @Sendable @escaping () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }
}
