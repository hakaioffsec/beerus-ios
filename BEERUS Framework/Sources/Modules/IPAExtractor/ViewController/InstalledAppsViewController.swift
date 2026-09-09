import UIKit

final class InstalledAppsViewController: BaseViewController {

    private var apps: [AppModel] = []

    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorStyle = .singleLine
        table.separatorColor = UIColor.white.withAlphaComponent(0.2)
        table.delegate = self
        table.dataSource = self
        table.register(AppCell.self, forCellReuseIdentifier: AppCell.identifier)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var progressLabel: UILabel = {
        let label = UILabel()
        label.font = AppFont.regular(14)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        loadApps()
    }

    private func loadApps() {
        print("[VC] Loading apps...")
        showProgress("Connecting to Frida...")

        Task {
            do {
                let installedApps = try await FridaManager.shared.getInstalledApps()
                await MainActor.run {
                    self.apps = installedApps
                    self.tableView.reloadData()
                    self.hideProgress()
                    print("[VC] UI updated with \(installedApps.count) apps")
                }
            } catch {
                print("[VC] Failed to load apps: \(error)")
                await MainActor.run {
                    self.hideProgress()
                    self.showError(message: "Failed to connect to Frida:\n\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Dump Flow

    private var loadingVC: LoadingViewController?
    private var dumpTask: Task<Void, Never>?

    private func startDump(for app: AppModel) {
        guard app.isRunning else {
            showError(message: "\(app.name) is not running.\n\nOpen the app first, then come back and try again.")
            return
        }

        // Check available disk space (need ~3x app size for copy + zip)
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSTemporaryDirectory()),
           let freeSpace = attrs[.systemFreeSize] as? Int64,
           freeSpace < 500_000_000 { // Minimum 500MB free
            showError(message: "Low disk space (\(freeSpace / 1_048_576)MB free).\n\nAt least 500MB is recommended for dumping.")
            return
        }

        let loading = LoadingViewController()
        loading.modalPresentationStyle = .overFullScreen
        loading.modalTransitionStyle = .crossDissolve
        loading.onCancel = { [weak self] in
            self?.dumpTask?.cancel()
            self?.dumpTask = nil
            self?.loadingVC = nil
        }
        loadingVC = loading

        present(loading, animated: true) {
            self.performDump(app: app, loadingVC: loading)
        }
    }

    private func performDump(app: AppModel, loadingVC: LoadingViewController) {
        dumpTask = Task {
            do {
                let startTime = Date()

                loadingVC.updatePhase(.checking)
                loadingVC.addLog("checking frida server")
                loadingVC.addLog("target: \(app.name)")
                loadingVC.addLog("bundle: \(app.bundleIdentifier)")

                guard FridaChecker.isRunning() else {
                    throw DumpError.fridaNotRunning
                }
                loadingVC.addLog("frida server running on port 27042")

                try Task.checkCancellation()

                loadingVC.updatePhase(.attaching)
                loadingVC.addLog("attaching to process \(app.pid)")

                let dumpPath = "/tmp/beerus_dump_\(UUID().uuidString)"

                loadingVC.updatePhase(.loading)
                loadingVC.addLog("loading dump script")
                loadingVC.addLog("output: \(dumpPath)")

                loadingVC.updatePhase(.dumping)
                loadingVC.addLog("dumping binary")

                let bundleInfo = try await FridaManager.shared.dumpExecutable(
                    bundleId: app.bundleIdentifier,
                    pid: app.pid,
                    outputPath: dumpPath
                ) { msg in
                    loadingVC.addLog(msg)
                }

                guard FileManager.default.fileExists(atPath: dumpPath) else {
                    throw DumpError.executableNotDumped
                }

                if let attrs = try? FileManager.default.attributesOfItem(atPath: dumpPath),
                   let fileSize = attrs[.size] as? UInt64 {
                    let sizeMB = Double(fileSize) / 1_048_576
                    loadingVC.addLog("executable dumped: \(String(format: "%.2f", sizeMB)) MB")
                } else {
                    loadingVC.addLog("executable dumped successfully")
                }

                loadingVC.addLog("path: \(bundleInfo.bundlePath)")
                loadingVC.addLog("binary: \(bundleInfo.executableName)")

                try Task.checkCancellation()

                let appWithPaths = AppModel(
                    name: bundleInfo.appName,
                    bundleIdentifier: app.bundleIdentifier,
                    bundlePath: bundleInfo.bundlePath,
                    executablePath: bundleInfo.bundlePath + "/" + bundleInfo.executableName,
                    pid: app.pid
                )

                loadingVC.updatePhase(.building)
                loadingVC.addLog("creating ipa archive")
                loadingVC.addLog("packaging: \(bundleInfo.appName)")

                let ipaURL = try IPABuilder.build(app: appWithPaths, dumpedExecutable: dumpPath) { msg in
                    loadingVC.addLog(msg)
                } progressCallback: { done, total in
                    loadingVC.updateProgress(done, total: total)
                }

                try? FileManager.default.removeItem(atPath: dumpPath)

                let duration = Date().timeIntervalSince(startTime)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: ipaURL.path),
                   let fileSize = attrs[.size] as? UInt64 {
                    let sizeMB = Double(fileSize) / 1_048_576
                    loadingVC.addLog("ipa created: \(String(format: "%.2f", sizeMB)) MB")
                }
                loadingVC.addLog("total time: \(String(format: "%.1f", duration))s")

                loadingVC.updatePhase(.complete)
                loadingVC.showSuccess(ipaPath: ipaURL)

                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.loadingVC?.dismiss(animated: true) {
                            self.loadingVC = nil
                            self.showShareSheet(for: ipaURL)
                        }
                    }
                }
            } catch is CancellationError {
                // Cancelled by the user; onCancel already dismissed loadingVC and cleared state.
            } catch {
                loadingVC.showError(error)
                await MainActor.run {
                    self.loadingVC = nil
                }
            }
        }
    }

    private func showShareSheet(for ipaURL: URL) {
        let activityVC = UIActivityViewController(activityItems: [ipaURL], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: ipaURL)
            // Also clean the parent IPADump directory
            try? FileManager.default.removeItem(at: ipaURL.deletingLastPathComponent())
        }
        present(activityVC, animated: true)
    }

    // MARK: - UI Helpers

    private func showProgress(_ message: String) {
        activityIndicator.startAnimating()
        progressLabel.text = message
        progressLabel.alpha = 1
    }

    private func hideProgress() {
        activityIndicator.stopAnimating()
        progressLabel.alpha = 0
    }

    private func showSuccess(ipaURL: URL) {
        let alert = UIAlertController(
            title: "Success",
            message: "IPA created:\n\(ipaURL.path)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        alert.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in
            let activityVC = UIActivityViewController(activityItems: [ipaURL], applicationActivities: nil)
            self?.present(activityVC, animated: true)
        })
        present(alert, animated: true)
    }

    private func showError(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableView

extension InstalledAppsViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        apps.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AppCell.identifier, for: indexPath) as! AppCell
        cell.configure(with: apps[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let app = apps[indexPath.row]

        // Refresh app status before showing confirmation
        Task {
            do {
                let updatedApps = try await FridaManager.shared.getInstalledApps()
                if let updatedApp = updatedApps.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                    await MainActor.run {
                        self.apps[indexPath.row] = updatedApp
                        self.showDumpConfirmation(for: updatedApp)
                    }
                } else {
                    await MainActor.run {
                        self.showDumpConfirmation(for: app)
                    }
                }
            } catch {
                await MainActor.run {
                    self.showDumpConfirmation(for: app)
                }
            }
        }
    }

    private func showDumpConfirmation(for app: AppModel) {
        let status = app.isRunning ? "Running (PID: \(app.pid))" : "Not running"

        let alert = UIAlertController(
            title: "Dump IPA",
            message: "\(app.name)\n\(app.bundleIdentifier)\n\nStatus: \(status)",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if app.isRunning {
            alert.addAction(UIAlertAction(title: "Dump", style: .default) { [weak self] _ in
                self?.startDump(for: app)
            })
        } else {
            alert.message! += "\n\n⚠️ Open the app first to dump it."
        }

        present(alert, animated: true)
    }
}

// MARK: - ViewCode

extension InstalledAppsViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        view.addSubview(progressLabel)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            progressLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progressLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            progressLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16)
        ])
    }
}

// MARK: - Errors

enum DumpError: LocalizedError {
    case executableNotDumped
    case fridaNotRunning

    var errorDescription: String? {
        switch self {
        case .executableNotDumped: return "Failed to dump executable"
        case .fridaNotRunning: return "Frida server is not running on port 27042"
        }
    }
}
