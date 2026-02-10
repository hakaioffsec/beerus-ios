import UIKit

// MARK: - Process Model

private struct DeviceProcess {
    let pid: String
    let name: String
}

// MARK: - LLDBServerViewController

final class LLDBServerViewController: BaseViewController {

    private enum ServerState {
        case notInstalled, installing, starting, offline(String)
        case online(path: String, targetPID: String, targetName: String, serverPID: String)
    }

    // MARK: - Properties

    private var state: ServerState = .notInstalled
    private var foundPath: String?
    private var logTask: Task<Void, Never>?

    private let port = "1234"
    private let pkg  = "debugserver"
    private let logFile = "/tmp/beerus-debugserver.log"
    private let searchPaths = [
        "/usr/bin/debugserver",       "/var/jb/usr/bin/debugserver",
        "/usr/local/bin/debugserver", "/var/jb/usr/local/bin/debugserver",
    ]

    // MARK: - Colors

    private let green = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
    private let dim   = UIColor(white: 0.3, alpha: 1)
    private let muted = UIColor(white: 0.4, alpha: 1)
    private let iconCfg = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)

    // MARK: - UI

    private lazy var circuitTopImageView     = UIImageView.circuit(named: "circuit-top")
    private lazy var circuitLeftImageView     = UIImageView.circuit(named: "circuit-left")
    private lazy var circuitRightImageView    = UIImageView.circuit(named: "circuit-right")
    private lazy var circuitLeftDownImageView = UIImageView.circuit(named: "circuit-left-down")

    private lazy var titleLabel    = UILabel.styled(text: "LLDB Server", font: AppFont.bold(20), alignment: .center)
    private lazy var statusLabel   = UILabel.styled(font: AppFont.bold(14), alignment: .center)
    private lazy var subtitleLabel = UILabel.styled(font: AppFont.regular(12), color: UIColor(white: 0.35, alpha: 1), alignment: .center, lines: 2)
    private lazy var feedbackLabel = UILabel.styled(font: AppFont.regular(10), color: UIColor(white: 0.35, alpha: 1), alignment: .center, lines: 2)

    private lazy var statusIcon: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private lazy var commandLabel: UILabel = {
        let l = UILabel.styled(font: AppFont.regular(11), color: green, alignment: .center, lines: 2)
        l.isHidden = true
        return l
    }()

    private lazy var copyButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "doc.on.doc",
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)), for: .normal)
        b.tintColor = muted
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(copyCommand), for: .touchUpInside)
        b.isHidden = true
        return b
    }()

    private lazy var progressBar: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .default)
        pv.trackTintColor = UIColor(white: 0.15, alpha: 1)
        pv.progressTintColor = UIColor(named: "ButtonColor") ?? .systemRed
        pv.layer.cornerRadius = 2
        pv.clipsToBounds = true
        pv.translatesAutoresizingMaskIntoConstraints = false
        pv.isHidden = true
        return pv
    }()

    private lazy var consoleView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.backgroundColor = UIColor(white: 0.06, alpha: 1)
        tv.textColor = green
        tv.font = AppFont.regular(10)
        tv.layer.cornerRadius = 8
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor(white: 0.15, alpha: 1).cgColor
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.isHidden = true
        tv.showsVerticalScrollIndicator = true
        tv.indicatorStyle = .white
        return tv
    }()

    private lazy var actionButton = UIButton.styled(
        title: "INSTALL", font: AppFont.bold(13),
        target: self, action: #selector(actionTapped)
    )

    private lazy var uninstallButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("uninstall", for: .normal)
        b.titleLabel?.font = AppFont.regular(11)
        b.setTitleColor(UIColor(white: 0.25, alpha: 1), for: .normal)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(uninstallTapped), for: .touchUpInside)
        b.isHidden = true
        return b
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        refreshState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        logTask?.cancel()
        logTask = nil
    }

    // MARK: - Refresh

    private func refreshState() {
        guard RootExec.isRunning else {
            applyState(.notInstalled)
            subtitleLabel.text = "daemon offline"
            setActionEnabled(false)
            return
        }

        Task.detached { [weak self] in
            guard let self else { return }

            let script = """
            path=$(which debugserver 2>/dev/null); \
            [ -z "$path" ] && for p in \(self.searchPaths.joined(separator: " ")); do \
              [ -x "$p" ] && path=$p && break; done; \
            echo "PATH:${path:-NONE}"; \
            pid=$(ps -eo pid,comm 2>/dev/null | grep debugserver | grep -v grep | head -1 | sed 's/^[[:space:]]*//' | cut -d' ' -f1); \
            echo "PID:${pid:-NONE}"
            """
            let result = RootExec.shell(script)
            let lines = result.output.components(separatedBy: "\n")

            let path = lines.first { $0.hasPrefix("PATH:") }?
                .replacingOccurrences(of: "PATH:", with: "")
            let pid = lines.first { $0.hasPrefix("PID:") }?
                .replacingOccurrences(of: "PID:", with: "")

            guard let path, path != "NONE", !path.isEmpty else {
                await MainActor.run { self.applyState(.notInstalled) }
                return
            }

            self.foundPath = path

            await MainActor.run {
                if let pid, pid != "NONE", !pid.isEmpty {
                    // Server is running  show as online but we don't know the target
                    self.applyState(.online(path: path, targetPID: "?", targetName: "attached", serverPID: pid))
                    self.startLogStreaming()
                } else {
                    self.applyState(.offline(path))
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func actionTapped() {
        switch state {
        case .notInstalled:  install()
        case .offline:       showProcessPicker()
        case .online:        stopServer()
        case .installing, .starting: break
        }
    }

    private func install() {
        guard RootExec.isRunning else {
            showAlert(title: "Error", message: "beerus daemon is not running")
            return
        }

        applyState(.installing)

        Task.detached { [weak self] in
            guard let self else { return }

            await self.setProgress(0.1, "checking apt...")
            guard RootExec.shell("which apt-get 2>/dev/null").exitCode == 0 else {
                await self.failInstall("apt-get not found"); return
            }

            await self.setProgress(0.25, "resolving package...")
            let info = RootExec.shell("apt-cache show \(self.pkg) 2>/dev/null")
            guard info.exitCode == 0, info.output.contains("Package:") else {
                await self.failInstall("package not found in repos", color: .orange); return
            }

            await self.setProgress(0.5, "installing...")
            let result = RootExec.shell("apt-get install -y \(self.pkg) 2>&1")

            if result.exitCode == 0 {
                await self.setProgress(1.0, "Installed", color: self.green)
                try? await Task.sleep(nanoseconds: 800_000_000)
                await MainActor.run { self.refreshState() }
            } else {
                let msg = result.output.components(separatedBy: "\n")
                    .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "unknown error"
                await self.failInstall(msg)
            }
        }
    }

    // MARK: - Process Picker

    private func showProcessPicker() {
        let picker = ProcessPickerViewController { [weak self] process in
            self?.attachToProcess(process)
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(nav, animated: true)
    }

    // MARK: - Attach & Start

    private func attachToProcess(_ process: DeviceProcess) {
        guard let path = foundPath else { return }
        applyState(.starting)

        Task.detached { [weak self] in
            guard let self else { return }

            await self.setProgress(0.1, "stopping previous instance...")
            _ = RootExec.shell("killall -9 debugserver 2>/dev/null")
            try? await Task.sleep(nanoseconds: 300_000_000)

            // Clear old log
            _ = RootExec.shell("> \(self.logFile)")

            await self.setProgress(0.4, "attaching to \(process.name) (\(process.pid))...")

            // Launch debugserver attached to the target PID, log output to file
            let launch = "( \(path) 0.0.0.0:\(self.port) --attach=\(process.pid) "
                       + "> \(self.logFile) 2>&1 & )"
            _ = RootExec.shell(launch)

            await self.setProgress(0.7, "verifying...")

            // Poll for the server process
            var serverPID = ""
            for i in 0..<6 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                let check = RootExec.shell(
                    "ps -eo pid,comm 2>/dev/null | grep debugserver | grep -v grep | head -1 | sed 's/^[[:space:]]*//' | cut -d' ' -f1"
                )
                let p = check.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !p.isEmpty {
                    serverPID = p
                    break
                }
                await self.setProgress(0.7 + Float(i + 1) * 0.04, "verifying...")
            }

            if !serverPID.isEmpty {
                await self.setProgress(1.0, "attached", color: self.green)
                try? await Task.sleep(nanoseconds: 400_000_000)
            }

            await MainActor.run {
                if !serverPID.isEmpty {
                    self.applyState(.online(
                        path: path,
                        targetPID: process.pid,
                        targetName: process.name,
                        serverPID: serverPID
                    ))
                    self.startLogStreaming()
                } else {
                    self.applyState(.offline(path))
                    self.feedbackLabel.text = "failed to attach to \(process.name)"
                    self.feedbackLabel.textColor = UIColor(named: "RED") ?? .red
                }
            }
        }
    }

    private func stopServer() {
        logTask?.cancel()
        logTask = nil
        setActionEnabled(false)

        Task.detached { [weak self] in
            _ = RootExec.shell("killall -9 debugserver 2>/dev/null")
            try? await Task.sleep(nanoseconds: 300_000_000)

            await MainActor.run {
                guard let self else { return }
                self.setActionEnabled(true)
                if let p = self.foundPath { self.applyState(.offline(p)) }
            }
        }
    }

    // MARK: - Log Streaming

    private func startLogStreaming() {
        logTask?.cancel()
        consoleView.text = ""
        consoleView.isHidden = false

        logTask = Task.detached { [weak self] in
            guard let self else { return }
            var lastSize = 0

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 800_000_000)
                if Task.isCancelled { break }

                // Check if debugserver is still running
                let alive = RootExec.shell(
                    "ps -eo comm 2>/dev/null | grep debugserver | grep -v grep | head -1"
                )
                let isAlive = !alive.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                // Read new log content using tail with byte offset
                let result = RootExec.shell("cat \(self.logFile) 2>/dev/null")
                let full = result.output

                if full.count > lastSize {
                    let newContent = String(full.dropFirst(lastSize))
                    lastSize = full.count

                    await MainActor.run {
                        self.consoleView.text += newContent
                        // Auto-scroll to bottom
                        let bottom = NSRange(location: self.consoleView.text.count - 1, length: 1)
                        self.consoleView.scrollRangeToVisible(bottom)
                    }
                }

                // If server died, update state
                if !isAlive {
                    let finalLog = RootExec.shell("cat \(self.logFile) 2>/dev/null")
                    await MainActor.run {
                        if finalLog.output.count > lastSize {
                            self.consoleView.text += String(finalLog.output.dropFirst(lastSize))
                        }
                        self.consoleView.text += "\n[debugserver exited]"
                        self.feedbackLabel.text = "server stopped"
                        self.feedbackLabel.textColor = self.muted
                        if let p = self.foundPath {
                            self.state = .offline(p)
                            self.statusIcon.image = UIImage(systemName: "bolt.slash.fill", withConfiguration: self.iconCfg)
                            self.statusIcon.tintColor = self.dim
                            self.statusLabel.text = "OFFLINE"
                            self.statusLabel.textColor = self.muted
                            self.subtitleLabel.text = p
                            self.subtitleLabel.textColor = UIColor(white: 0.35, alpha: 1)
                            self.actionButton.setTitle("START", for: .normal)
                            self.actionButton.backgroundColor = UIColor(named: "ButtonColor")
                            self.setActionEnabled(true)
                        }
                    }
                    break
                }
            }
        }
    }

    // MARK: - Uninstall / Copy

    @objc private func uninstallTapped() {
        let alert = UIAlertController(title: "Uninstall debugserver?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Uninstall", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.logTask?.cancel()
            Task.detached {
                _ = RootExec.shell("killall -9 debugserver 2>/dev/null")
                _ = RootExec.shell("apt-get remove -y \(self.pkg) 2>&1")
                await MainActor.run { self.refreshState() }
            }
        })
        present(alert, animated: true)
    }

    @objc private func copyCommand() {
        let ip = Self.deviceIP() ?? "<device_ip>"
        UIPasteboard.general.string = "process connect connect://\(ip):\(port)"
        copyButton.tintColor = green
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.copyButton.tintColor = self?.muted
        }
    }

    // MARK: - UI Helpers

    private func setActionEnabled(_ enabled: Bool) {
        actionButton.isEnabled = enabled
        actionButton.alpha = enabled ? 1 : 0.5
    }

    @MainActor
    private func setProgress(_ value: Float, _ text: String,
                             color: UIColor = UIColor(white: 0.4, alpha: 1)) {
        progressBar.setProgress(value, animated: true)
        if value >= 1.0 { progressBar.progressTintColor = green }
        feedbackLabel.text = text
        feedbackLabel.textColor = color
    }

    @MainActor
    private func failInstall(_ msg: String, color: UIColor = UIColor(named: "RED") ?? .red) {
        applyState(.notInstalled)
        feedbackLabel.text = msg
        feedbackLabel.textColor = color
    }

    // MARK: - Apply State

    private func applyState(_ newState: ServerState) {
        state = newState

        // Defaults
        commandLabel.isHidden = true
        copyButton.isHidden = true
        progressBar.isHidden = true
        uninstallButton.isHidden = true
        consoleView.isHidden = true
        actionButton.isHidden = false
        feedbackLabel.text = ""
        setActionEnabled(true)
        actionButton.backgroundColor = UIColor(named: "ButtonColor")
        subtitleLabel.textColor = UIColor(white: 0.35, alpha: 1)

        switch newState {
        case .notInstalled:
            statusIcon.image = UIImage(systemName: "xmark.circle", withConfiguration: iconCfg)
            statusIcon.tintColor = dim
            statusLabel.text = "NOT INSTALLED"
            statusLabel.textColor = muted
            subtitleLabel.text = "LLVM debugserver from Procursus"

        case .installing:
            statusIcon.image = UIImage(systemName: "arrow.down.circle", withConfiguration: iconCfg)
            statusIcon.tintColor = UIColor(named: "ButtonColor") ?? .systemRed
            statusLabel.text = "INSTALLING"
            statusLabel.textColor = UIColor(named: "ButtonColor") ?? .systemRed
            subtitleLabel.text = "installing via apt..."
            progressBar.isHidden = false
            progressBar.progress = 0
            progressBar.progressTintColor = UIColor(named: "ButtonColor") ?? .systemRed
            actionButton.isHidden = true

        case .starting:
            statusIcon.image = UIImage(systemName: "bolt.circle", withConfiguration: iconCfg)
            statusIcon.tintColor = UIColor(named: "ButtonColor") ?? .systemRed
            statusLabel.text = "STARTING"
            statusLabel.textColor = UIColor(named: "ButtonColor") ?? .systemRed
            subtitleLabel.text = "attaching to process..."
            progressBar.isHidden = false
            progressBar.progress = 0
            progressBar.progressTintColor = UIColor(named: "ButtonColor") ?? .systemRed
            actionButton.isHidden = true

        case .offline(let path):
            statusIcon.image = UIImage(systemName: "bolt.slash.fill", withConfiguration: iconCfg)
            statusIcon.tintColor = dim
            statusLabel.text = "OFFLINE"
            statusLabel.textColor = muted
            subtitleLabel.text = path
            actionButton.setTitle("START", for: .normal)
            uninstallButton.isHidden = false

        case .online(_, let targetPID, let targetName, let serverPID):
            statusIcon.image = UIImage(systemName: "bolt.fill", withConfiguration: iconCfg)
            statusIcon.tintColor = green
            statusLabel.text = "ONLINE"
            statusLabel.textColor = green
            subtitleLabel.text = "\(targetName) (\(targetPID))  ·  port \(port)  ·  server \(serverPID)"
            subtitleLabel.textColor = green.withAlphaComponent(0.6)
            actionButton.setTitle("STOP", for: .normal)
            actionButton.backgroundColor = UIColor(named: "RED")
            let ip = Self.deviceIP() ?? "<device_ip>"
            commandLabel.text = "process connect connect://\(ip):\(port)"
            commandLabel.isHidden = false
            copyButton.isHidden = false
            consoleView.isHidden = false
            uninstallButton.isHidden = false
        }
    }

    // MARK: - Device IP

    private static func deviceIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: ptr.pointee.ifa_name) == "en0" else { continue }
            var addr = ptr.pointee.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &addr.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN))
            return String(cString: buf)
        }
        return nil
    }
}

// MARK: - ViewCode

extension LLDBServerViewController: ViewCode {
    func buildViewHierarchy() {
        [circuitTopImageView, circuitLeftImageView, circuitRightImageView, circuitLeftDownImageView,
         titleLabel, statusIcon, statusLabel, subtitleLabel,
         commandLabel, copyButton, consoleView, progressBar, actionButton, feedbackLabel, uninstallButton]
            .forEach(view.addSubview)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            circuitTopImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitTopImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),

            circuitRightImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitRightImageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            circuitRightImageView.widthAnchor.constraint(equalToConstant: 40),
            circuitRightImageView.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor),

            circuitLeftImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitLeftImageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),

            circuitLeftDownImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            circuitLeftDownImageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 70),

            statusIcon.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusIcon.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            statusIcon.widthAnchor.constraint(equalToConstant: 44),
            statusIcon.heightAnchor.constraint(equalToConstant: 44),

            statusLabel.topAnchor.constraint(equalTo: statusIcon.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),

            commandLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            commandLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            commandLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),

            copyButton.centerYAnchor.constraint(equalTo: commandLabel.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            copyButton.widthAnchor.constraint(equalToConstant: 28),
            copyButton.heightAnchor.constraint(equalToConstant: 28),

            consoleView.topAnchor.constraint(equalTo: commandLabel.bottomAnchor, constant: 12),
            consoleView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            consoleView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            consoleView.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -12),

            progressBar.topAnchor.constraint(equalTo: commandLabel.bottomAnchor, constant: 20),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            progressBar.heightAnchor.constraint(equalToConstant: 4),

            actionButton.bottomAnchor.constraint(equalTo: feedbackLabel.topAnchor, constant: -10),
            actionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actionButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            actionButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            actionButton.heightAnchor.constraint(equalToConstant: 50),

            feedbackLabel.bottomAnchor.constraint(equalTo: uninstallButton.topAnchor, constant: -8),
            feedbackLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            feedbackLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            feedbackLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            uninstallButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            uninstallButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }
}

// MARK: - Process Picker

private final class ProcessPickerViewController: UITableViewController, UISearchResultsUpdating {

    private var allProcesses: [DeviceProcess] = []
    private var filtered: [DeviceProcess] = []
    private let onSelect: (DeviceProcess) -> Void

    init(onSelect: @escaping (DeviceProcess) -> Void) {
        self.onSelect = onSelect
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Select Process"
        view.backgroundColor = UIColor(named: "Background") ?? UIColor(white: 0.05, alpha: 1)
        tableView.backgroundColor = view.backgroundColor
        tableView.separatorColor = UIColor(white: 0.15, alpha: 1)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(dismissPicker))

        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Filter processes..."
        search.searchBar.barStyle = .black
        navigationItem.searchController = search
        definesPresentationContext = true

        loadProcesses()
    }

    @objc private func dismissPicker() { dismiss(animated: true) }

    private func loadProcesses() {
        Task.detached { [weak self] in
            guard let self else { return }
            // ps -eo pid,comm — gives PID and command name
            let result = RootExec.shell("ps -eo pid,comm 2>/dev/null")
            var procs: [DeviceProcess] = []

            for line in result.output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("PID") else { continue }

                // Format: "  1234 /path/to/binary" or "  1234 binary"
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                guard parts.count == 2 else { continue }

                let pid = String(parts[0])
                let fullPath = String(parts[1])
                // Show just the binary name, not the full path
                let name = (fullPath as NSString).lastPathComponent

                // Skip kernel threads and debugserver itself
                guard pid != "0", name != "debugserver",
                      !name.hasPrefix("["), !name.hasPrefix("(") else { continue }

                procs.append(DeviceProcess(pid: pid, name: name))
            }

            // Sort by name for easier browsing
            procs.sort { $0.name.lowercased() < $1.name.lowercased() }

            await MainActor.run {
                self.allProcesses = procs
                self.filtered = procs
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - Search

    func updateSearchResults(for searchController: UISearchController) {
        let query = (searchController.searchBar.text ?? "").lowercased()
        filtered = query.isEmpty ? allProcesses : allProcesses.filter {
            $0.name.lowercased().contains(query) || $0.pid.contains(query)
        }
        tableView.reloadData()
    }

    // MARK: - Table

    override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { filtered.count }

    override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "cell", for: ip)
        let proc = filtered[ip.row]

        var content = cell.defaultContentConfiguration()
        content.text = proc.name
        content.secondaryText = "PID \(proc.pid)"
        content.textProperties.font = AppFont.regular(14)
        content.secondaryTextProperties.font = AppFont.regular(11)
        content.textProperties.color = .white
        content.secondaryTextProperties.color = UIColor(white: 0.4, alpha: 1)
        cell.contentConfiguration = content
        cell.backgroundColor = .clear

        let bgView = UIView()
        bgView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        cell.selectedBackgroundView = bgView

        return cell
    }

    override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
        t.deselectRow(at: ip, animated: true)
        let proc = filtered[ip.row]
        dismiss(animated: true) { [onSelect] in
            onSelect(proc)
        }
    }
}
