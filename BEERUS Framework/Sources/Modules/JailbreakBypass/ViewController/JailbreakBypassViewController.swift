import UIKit

final class JailbreakBypassViewController: BaseViewController {

    // MARK: - Constants

    private enum Constants {
        static let cellIdentifier = "AppCell"
    }

    // MARK: - Models

    private struct AppInfo {
        let bundleId: String
        let name: String
        var isEnabled: Bool
    }

    // MARK: - Properties

    private var apps: [AppInfo] = []
    private var filteredApps: [AppInfo] = []
    private let service = ShadowService.shared
    private var isSearching: Bool { !(searchBar.text?.isEmpty ?? true) }
    private var displayedApps: [AppInfo] { isSearching ? filteredApps : apps }

    // MARK: - Circuit Images

    private lazy var circuitTopImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "circuit-top")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitRightImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "circuit-right")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "circuit-left-2")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftDownImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "circuit-left-down")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    // MARK: - UI Components

    private lazy var headerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(named: "ContainerBackground")
        view.layer.cornerRadius = 12
        return view
    }()

    private lazy var titleLabel: UILabel = UILabel.styled(
        text: "Shadow JB Bypass",
        font: AppFont.bold(18),
        alignment: .left
    )

    private lazy var statusLabel: UILabel = UILabel.styled(
        text: "Checking...",
        font: AppFont.regular(14),
        color: .secondaryLabel,
        alignment: .left
    )

    private lazy var versionButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Select Version", for: .normal)
        button.titleLabel?.font = AppFont.regular(14)
        button.setTitleColor(.systemBlue, for: .normal)
        button.addTarget(self, action: #selector(versionTapped), for: .touchUpInside)
        return button
    }()

    private lazy var installButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = AppFont.bold(16)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.addTarget(self, action: #selector(installTapped), for: .touchUpInside)
        return button
    }()

    private lazy var respringButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Respring", for: .normal)
        button.titleLabel?.font = AppFont.regular(14)
        button.setTitleColor(.systemOrange, for: .normal)
        button.addTarget(self, action: #selector(respringTapped), for: .touchUpInside)
        return button
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    private lazy var searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = "Search apps"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.searchTextField.textColor = .label
        searchBar.searchTextField.backgroundColor = UIColor(named: "ContainerBackground")
        return searchBar
    }()

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.2)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Constants.cellIdentifier)
        tableView.rowHeight = 50
        tableView.keyboardDismissMode = .onDrag
        return tableView
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        updateUI()
        fetchVersions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateUI()
    }

    // MARK: - Data Loading

    private func fetchVersions() {
        versionButton.setTitle("Loading...", for: .normal)
        versionButton.isEnabled = false

        service.fetchReleases { [weak self] result in
            guard let self = self else { return }
            self.versionButton.isEnabled = true

            switch result {
            case .success(let releases):
                if let selected = self.service.selectedRelease {
                    self.versionButton.setTitle("Version: \(selected.version)", for: .normal)
                } else if releases.isEmpty {
                    self.versionButton.setTitle("No versions found", for: .normal)
                }
            case .failure:
                self.versionButton.setTitle("Failed to load", for: .normal)
            }
        }
    }

    private func loadApps() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let enabledApps = Set(self.service.getEnabledApps())
            let installedApps = self.loadInstalledApps()

            let appInfos = installedApps.map { app in
                AppInfo(
                    bundleId: app.bundleId,
                    name: app.name,
                    isEnabled: enabledApps.contains(app.bundleId)
                )
            }.sorted { $0.name.lowercased() < $1.name.lowercased() }

            DispatchQueue.main.async {
                self.apps = appInfos
                self.tableView.reloadData()
            }
        }
    }

    private func loadInstalledApps() -> [(bundleId: String, name: String)] {
        var result: [(String, String)] = []
        var seen = Set<String>()

        func addApp(from plistPath: String, fallbackName: String) {
            guard let data = FileManager.default.contents(atPath: plistPath),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let bundleId = plist["CFBundleIdentifier"] as? String,
                  !seen.contains(bundleId) else { return }

            seen.insert(bundleId)
            let name = (plist["CFBundleDisplayName"] ?? plist["CFBundleName"]) as? String ?? fallbackName
            result.append((bundleId, name))
        }

        func scanDirectory(_ path: String, nested: Bool = true) {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }

            for item in items {
                let fullPath = "\(path)/\(item)"

                if item.hasSuffix(".app") {
                    addApp(from: "\(fullPath)/Info.plist", fallbackName: item.replacingOccurrences(of: ".app", with: ""))
                } else if nested, let subItems = try? FileManager.default.contentsOfDirectory(atPath: fullPath) {
                    for subItem in subItems where subItem.hasSuffix(".app") {
                        addApp(from: "\(fullPath)/\(subItem)/Info.plist", fallbackName: subItem.replacingOccurrences(of: ".app", with: ""))
                    }
                }
            }
        }

        scanDirectory("/var/containers/Bundle/Application")
        scanDirectory("/Applications", nested: false)
        scanDirectory("/var/jb/Applications", nested: false)

        return result
    }

    // MARK: - UI Updates

    private func updateUI() {
        let installed = service.isInstalled

        if installed {
            statusLabel.text = "Shadow is installed"
            statusLabel.textColor = .systemGreen
            installButton.setTitle("Uninstall Shadow", for: .normal)
            installButton.backgroundColor = .systemRed
            versionButton.isHidden = true
            respringButton.isHidden = false
            searchBar.isHidden = false
            tableView.isHidden = false
            loadApps()
        } else {
            statusLabel.text = "Shadow is not installed"
            statusLabel.textColor = .systemOrange
            installButton.setTitle("Install Shadow", for: .normal)
            installButton.backgroundColor = .systemBlue
            versionButton.isHidden = false
            respringButton.isHidden = true
            searchBar.isHidden = true
            tableView.isHidden = true
        }
    }

    // MARK: - Actions

    @objc private func versionTapped() {
        let releases = service.availableReleases
        guard !releases.isEmpty else {
            fetchVersions()
            return
        }

        let alert = UIAlertController(title: "Select Version", message: nil, preferredStyle: .actionSheet)

        for release in releases.prefix(10) {
            let isSelected = service.selectedRelease?.version == release.version
            let title = isSelected ? "\(release.version) ✓" : release.version

            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.service.selectRelease(release)
                self?.versionButton.setTitle("Version: \(release.version)", for: .normal)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = versionButton
            popover.sourceRect = versionButton.bounds
        }

        present(alert, animated: true)
    }

    @objc private func installTapped() {
        if service.isInstalled {
            confirmUninstall()
        } else {
            performInstall()
        }
    }

    @objc private func respringTapped() {
        showRespringPrompt()
    }

    // MARK: - Install/Uninstall

    private func performInstall() {
        installButton.isEnabled = false
        activityIndicator.startAnimating()

        service.install { [weak self] status in
            self?.statusLabel.text = status
        } completion: { [weak self] result in
            guard let self = self else { return }

            self.installButton.isEnabled = true
            self.activityIndicator.stopAnimating()
            self.updateUI()

            switch result {
            case .success:
                self.showRespringPrompt()
            case .failure(let error):
                self.showAlert(title: "Error", message: error.localizedDescription)
            }
        }
    }

    private func confirmUninstall() {
        let alert = UIAlertController(title: "Uninstall Shadow?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Uninstall", style: .destructive) { [weak self] _ in
            self?.performUninstall()
        })
        present(alert, animated: true)
    }

    private func performUninstall() {
        installButton.isEnabled = false
        activityIndicator.startAnimating()

        service.uninstall { [weak self] result in
            guard let self = self else { return }

            self.installButton.isEnabled = true
            self.activityIndicator.stopAnimating()
            self.updateUI()

            switch result {
            case .success:
                self.showRespringPrompt()
            case .failure(let error):
                self.showAlert(title: "Error", message: error.localizedDescription)
            }
        }
    }

    private func showRespringPrompt() {
        let alert = UIAlertController(
            title: "Respring Required",
            message: "A respring is needed to apply changes.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Later", style: .cancel))
        alert.addAction(UIAlertAction(title: "Respring Now", style: .destructive) { [weak self] _ in
            self?.service.respring()
        })
        present(alert, animated: true)
    }

    // MARK: - App Toggle

    private func toggleApp(at indexPath: IndexPath) {
        let app = displayedApps[indexPath.row]
        let shouldEnable = !app.isEnabled
        let bundleId = app.bundleId

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = shouldEnable
                ? self?.service.enableBypass(for: bundleId) ?? false
                : self?.service.disableBypass(for: bundleId) ?? false

            DispatchQueue.main.async {
                guard let self = self, success else { return }

                if let index = self.apps.firstIndex(where: { $0.bundleId == bundleId }) {
                    self.apps[index].isEnabled = shouldEnable
                }
                if self.isSearching, let index = self.filteredApps.firstIndex(where: { $0.bundleId == bundleId }) {
                    self.filteredApps[index].isEnabled = shouldEnable
                }

                self.tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
    }
}

// MARK: - UITableViewDataSource & UITableViewDelegate

extension JailbreakBypassViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        displayedApps.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellIdentifier, for: indexPath)
        let app = displayedApps[indexPath.row]

        cell.backgroundColor = UIColor(named: "ContainerBackground")
        cell.selectionStyle = .none
        cell.textLabel?.textColor = .label
        cell.textLabel?.font = AppFont.regular(15)
        cell.textLabel?.text = app.name

        let toggle = (cell.accessoryView as? UISwitch) ?? UISwitch()
        toggle.isOn = app.isEnabled
        toggle.onTintColor = .systemGreen
        toggle.tag = indexPath.row
        toggle.removeTarget(nil, action: nil, for: .valueChanged)
        toggle.addTarget(self, action: #selector(appToggleChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle

        return cell
    }

    @objc private func appToggleChanged(_ sender: UISwitch) {
        toggleApp(at: IndexPath(row: sender.tag, section: 0))
    }
}

// MARK: - UISearchBarDelegate

extension JailbreakBypassViewController: UISearchBarDelegate {

    func searchBar(_ searchBar: UISearchBar, textDidChange text: String) {
        filteredApps = text.isEmpty ? [] : apps.filter {
            $0.name.localizedCaseInsensitiveContains(text) ||
            $0.bundleId.localizedCaseInsensitiveContains(text)
        }
        tableView.reloadData()
    }
}

// MARK: - ViewCode

extension JailbreakBypassViewController: ViewCode {

    func buildViewHierarchy() {
        view.addSubview(circuitTopImageView)
        view.addSubview(circuitRightImageView)
        view.addSubview(circuitLeftImageView)
        view.addSubview(circuitLeftDownImageView)

        view.addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(statusLabel)
        headerView.addSubview(versionButton)
        headerView.addSubview(installButton)
        headerView.addSubview(respringButton)
        headerView.addSubview(activityIndicator)

        view.addSubview(searchBar)
        view.addSubview(tableView)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            // Circuit images
            circuitTopImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitTopImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),

            circuitRightImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitRightImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            circuitRightImageView.widthAnchor.constraint(equalToConstant: 40),
            circuitRightImageView.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor),

            circuitLeftImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitLeftImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),

            circuitLeftDownImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            circuitLeftDownImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),

            // Header
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),

            versionButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            versionButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),

            installButton.topAnchor.constraint(equalTo: versionButton.bottomAnchor, constant: 12),
            installButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            installButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            installButton.heightAnchor.constraint(equalToConstant: 44),

            respringButton.topAnchor.constraint(equalTo: installButton.bottomAnchor, constant: 8),
            respringButton.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            respringButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -16),

            activityIndicator.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            activityIndicator.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),

            // Search & Table
            searchBar.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
