import UIKit

final class FridaVersionsViewController: UIViewController {

    // MARK: - State
    private var releases: [FridaRelease] = []
    private var cellStatuses: [Int: FridaCellStatus] = [:]
    private var activeDownload: FridaDownloadTask?
    private var downloadingIndex: Int?

    // MARK: - UI

    private lazy var titleLabel = UILabel.styled(
        text: "Frida Versions", font: AppFont.bold(20), alignment: .center
    )
    private lazy var subtitleLabel = UILabel.styled(
        text: "Device: \(DeviceInfo.architecture)", font: AppFont.regular(13),
        color: .lightGray, alignment: .center
    )

    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorColor = UIColor.white.withAlphaComponent(0.1)
        table.delegate = self
        table.dataSource = self
        table.register(FridaReleaseCell.self, forCellReuseIdentifier: FridaReleaseCell.identifier)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var errorLabel: UILabel = {
        let label = UILabel.styled(
            font: AppFont.regular(14), color: UIColor(named: "RED") ?? .systemRed,
            alignment: .center, lines: 0
        )
        label.isHidden = true
        return label
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton()
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var uninstallButton = UIButton.styled(
        title: "Uninstall Frida", font: AppFont.bold(13),
        backgroundColor: UIColor(named: "RED") ?? .systemRed,
        cornerRadius: 8, target: self, action: #selector(uninstallTapped)
    )

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "Background") ?? UIColor(white: 0.08, alpha: 1)
        applyViewCode()
        fetchReleases()
    }

    // MARK: - Data

    private func fetchReleases() {
        activityIndicator.startAnimating()
        tableView.isHidden = true
        errorLabel.isHidden = true
        uninstallButton.isHidden = true

        FridaGitHubService.fetchReleases { [weak self] result in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()

                switch result {
                case .success(let releases):
                    self?.releases = releases
                    self?.tableView.isHidden = false
                    self?.uninstallButton.isHidden = false
                    self?.tableView.reloadData()
                case .failure(let error):
                    self?.errorLabel.text = error.localizedDescription
                    self?.errorLabel.isHidden = false
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        activeDownload?.cancel()
        dismiss(animated: true)
    }

    @objc private func uninstallTapped() {
        let alert = UIAlertController(
            title: "Uninstall Frida",
            message: "This will stop frida-server and remove the binary. Continue?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Uninstall", style: .destructive) { [weak self] _ in
            self?.performUninstall()
        })
        present(alert, animated: true)
    }

    private func performUninstall() {
        guard RootExec.isAvailable else {
            showAlert(title: "Daemon Offline", message: "The beerus daemon is not running.")
            return
        }

        uninstallButton.isEnabled = false
        uninstallButton.setTitle("Uninstalling...", for: .normal)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = RootExec.uninstallFrida()
            let success = result?.hasPrefix("ok") == true

            DispatchQueue.main.async {
                self?.uninstallButton.isEnabled = true
                self?.uninstallButton.setTitle("Uninstall Frida", for: .normal)

                if success {
                    self?.cellStatuses.removeAll()
                    self?.tableView.reloadData()
                    FridaChecker.notifyStatusChanged()
                    self?.showAlert(title: "Done", message: "frida-server has been uninstalled.")
                } else {
                    self?.showAlert(title: "Failed", message: result ?? "No response from daemon")
                }
            }
        }
    }

    // MARK: - Install Flow

    private func installRelease(at index: Int) {
        let release = releases[index]
        let arch = DeviceInfo.architecture

        guard let asset = release.fridaServerAsset(for: arch) else {
            showAlert(title: "No Binary", message: "No frida-server package found for \(arch) in this release.")
            return
        }
        guard RootExec.isAvailable else {
            showAlert(title: "Daemon Offline", message: "The beerus daemon is not running.")
            return
        }

        activeDownload?.cancel()
        if let prev = downloadingIndex {
            cellStatuses[prev] = .none
            reloadCell(at: prev)
        }

        downloadingIndex = index
        cellStatuses[index] = .downloading(0)
        reloadCell(at: index)

        activeDownload = FridaGitHubService.downloadAsset(
            asset,
            progress: { [weak self] progress in
                DispatchQueue.main.async {
                    self?.cellStatuses[index] = .downloading(progress)
                    self?.reloadCell(at: index)
                }
            },
            completion: { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let filePath):
                        NSLog("[FridaDownload] Download completed, path: %@", filePath)
                        self?.installBinary(from: filePath, at: index)
                    case .failure(let error):
                        if (error as NSError).code == NSURLErrorCancelled { return }
                        self?.cellStatuses[index] = .failed("Download failed")
                        self?.reloadCell(at: index)
                        self?.showAlert(title: "Download Failed", message: error.localizedDescription)
                    }
                }
            }
        )
    }

    private func installBinary(from filePath: String, at index: Int) {
        // ponytail: verify file exists and get size before sending to daemon
        let fm = FileManager.default
        guard fm.fileExists(atPath: filePath) else {
            NSLog("[FridaInstall] ERROR: File does not exist at: %@", filePath)
            cellStatuses[index] = .failed("Download failed")
            reloadCell(at: index)
            showAlert(title: "Download Failed", message: "File not found at: \(filePath)")
            return
        }

        let attrs = try? fm.attributesOfItem(atPath: filePath)
        let size = (attrs?[.size] as? Int) ?? 0
        NSLog("[FridaInstall] File exists at %@ with size %d bytes", filePath, size)

        guard size > 1000 else {
            cellStatuses[index] = .failed("Download incomplete")
            reloadCell(at: index)
            showAlert(title: "Download Failed", message: "File too small (\(size) bytes)")
            return
        }

        NSLog("[FridaInstall] Installing from: %@", filePath)
        cellStatuses[index] = .installing
        reloadCell(at: index)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = RootExec.installFrida(from: filePath)
            let success = result?.hasPrefix("ok") == true

            DispatchQueue.main.async {
                if success {
                    for (key, value) in self?.cellStatuses ?? [:] {
                        if case .installed = value { self?.cellStatuses[key] = .none }
                    }
                    self?.cellStatuses[index] = .installed
                    self?.tableView.reloadData()
                    FridaChecker.notifyStatusChanged()
                    // ponytail: cleanup after successful install
                    try? FileManager.default.removeItem(atPath: filePath)
                } else {
                    self?.cellStatuses[index] = .failed("Install failed")
                    self?.reloadCell(at: index)
                    self?.showAlert(title: "Install Failed", message: result ?? "No response from daemon")
                }
                self?.downloadingIndex = nil
            }
        }
    }

    // MARK: - Helpers

    private func reloadCell(at index: Int) {
        let indexPath = IndexPath(row: index, section: 0)
        guard let cell = tableView.cellForRow(at: indexPath) as? FridaReleaseCell else { return }
        cell.updateStatus(cellStatuses[index] ?? .none)
    }
}

// MARK: - UITableViewDataSource

extension FridaVersionsViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        releases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: FridaReleaseCell.identifier, for: indexPath
        ) as? FridaReleaseCell else { return UITableViewCell() }
        cell.configure(with: releases[indexPath.row])
        cell.updateStatus(cellStatuses[indexPath.row] ?? .none)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension FridaVersionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat { 80 }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let release = releases[indexPath.row]
        let arch = DeviceInfo.architecture
        guard let asset = release.fridaServerAsset(for: arch) else {
            showAlert(title: "Not Available",
                      message: "No frida-server package for \(arch) in \(release.version).")
            return
        }
        let sizeStr = String(format: "%.1f MB", Double(asset.size) / 1_048_576.0)
        let sheet = UIAlertController(
            title: "Frida \(release.version)",
            message: "Install frida-server (\(arch), \(sizeStr)) to /usr/sbin/frida-server?",
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(title: "Install", style: .default) { [weak self] _ in
            self?.installRelease(at: indexPath.row)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(sheet, animated: true)
    }
}

// MARK: - ViewCode

extension FridaVersionsViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(closeButton)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        view.addSubview(errorLabel)
        view.addSubview(uninstallButton)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: uninstallButton.topAnchor, constant: -12),

            uninstallButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            uninstallButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            uninstallButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            uninstallButton.heightAnchor.constraint(equalToConstant: 44),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }
}
