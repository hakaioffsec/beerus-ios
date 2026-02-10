import UIKit

final class ProcessListViewController: BaseViewController {

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

    private lazy var emptyLabel = UILabel.styled(
        text: "No running processes found",
        font: AppFont.regular(14),
        color: UIColor(white: 0.4, alpha: 1),
        alignment: .center
    )

    private var loadingVC: MemoryDumpLoadingViewController?
    private var dumpTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        loadRunningApps()
    }

    private func loadRunningApps() {
        activityIndicator.startAnimating()
        emptyLabel.isHidden = true

        Task {
            do {
                let allApps = try await FridaManager.shared.getInstalledApps()
                let running = allApps.filter { $0.isRunning }
                await MainActor.run {
                    self.apps = running
                    self.tableView.reloadData()
                    self.activityIndicator.stopAnimating()
                    self.emptyLabel.isHidden = !running.isEmpty
                }
            } catch {
                await MainActor.run {
                    self.activityIndicator.stopAnimating()
                    self.showAlert(title: "Error",
                                   message: "Failed to list processes:\n\(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Dump Flow

    private func startDump(for app: AppModel) {
        let loading = MemoryDumpLoadingViewController()
        loading.modalPresentationStyle = .overFullScreen
        loading.modalTransitionStyle = .crossDissolve
        loading.onCancel = { [weak self] in
            self?.dumpTask?.cancel()
            self?.dumpTask = nil
            self?.loadingVC = nil
        }
        loadingVC = loading

        present(loading, animated: true) {
            self.performMemoryDump(app: app, loadingVC: loading)
        }
    }

    private func performMemoryDump(app: AppModel, loadingVC: MemoryDumpLoadingViewController) {
        dumpTask = Task {
            do {
                let startTime = Date()

                loadingVC.updatePhase(.connecting)

                guard FridaChecker.isRunning() else {
                    throw DumpError.fridaNotRunning
                }

                loadingVC.updatePhase(.attaching)

                let safeName = app.name.replacingOccurrences(of: " ", with: "_")
                let outputDir = NSTemporaryDirectory() + "beerus_memdump_\(safeName)_\(Int(Date().timeIntervalSince1970))"

                loadingVC.updatePhase(.dumping)

                try Task.checkCancellation()

                let result = try await FridaManager.shared.dumpMemory(
                    pid: app.pid,
                    outputDir: outputDir
                ) { msg in
                    loadingVC.addLog(msg)
                }

                try Task.checkCancellation()

                loadingVC.updatePhase(.packaging)

                // Zip only the single dump.bin + index.json (fast — just 2 files)
                let zipPath = NSTemporaryDirectory() + "\(safeName)_memdump.zip"
                try? FileManager.default.removeItem(atPath: zipPath)

                let zipURL = URL(fileURLWithPath: zipPath)
                try ZipArchive.create(
                    at: zipURL,
                    from: URL(fileURLWithPath: outputDir)
                )

                // Remove raw dump directory
                try? FileManager.default.removeItem(atPath: outputDir)

                let duration = Date().timeIntervalSince(startTime)
                let sizeMB = Double(result.dumpedBytes) / 1_048_576

                loadingVC.updatePhase(.complete)
                loadingVC.showSuccess(
                    message: "\(result.dumpedRanges) regions (\(String(format: "%.1f", sizeMB)) MB)\n"
                           + "\(String(format: "%.1f", duration))s"
                )

                await MainActor.run {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.loadingVC?.dismiss(animated: true) {
                            self.loadingVC = nil
                            self.showShareSheet(for: zipURL)
                        }
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    loadingVC.dismiss(animated: true) {
                        self.loadingVC = nil
                    }
                }
            } catch {
                loadingVC.showError(error)
                await MainActor.run {
                    self.loadingVC = nil
                }
            }
        }
    }

    private func showShareSheet(for url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: url)
        }
        present(activityVC, animated: true)
    }
}

// MARK: - UITableView

extension ProcessListViewController: UITableViewDelegate, UITableViewDataSource {
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

        let alert = UIAlertController(
            title: "Dump Memory",
            message: "\(app.name)\nPID: \(app.pid)\n\nThis will dump all readable memory regions from the process.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Dump", style: .default) { [weak self] _ in
            self?.startDump(for: app)
        })
        present(alert, animated: true)
    }
}

// MARK: - ViewCode

extension ProcessListViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        view.addSubview(emptyLabel)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
