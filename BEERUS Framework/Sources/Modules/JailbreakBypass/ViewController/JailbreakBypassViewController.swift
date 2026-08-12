import UIKit

final class JailbreakBypassViewController: BaseViewController {

    struct AppInfo {
        let bundleId: String
        let name: String
        var isBypassed: Bool
    }

    private var apps: [AppInfo] = []
    private var filtered: [AppInfo] = []
    private var allowedBundleIds: Set<String> = []
    private let selfBundleId = Bundle.main.bundleIdentifier ?? "io.hakaisecurity.BEERUS-Framework"
    private var isSearching: Bool { !(searchBar.text?.isEmpty ?? true) }

    // MARK: - UI

    private lazy var mainToggle: UISwitch = {
        let s = UISwitch()
        s.onTintColor = .systemGreen
        s.addTarget(self, action: #selector(mainToggleChanged), for: .valueChanged)
        return s
    }()

    private lazy var searchBar: UISearchBar = {
        let sb = UISearchBar()
        sb.translatesAutoresizingMaskIntoConstraints = false
        sb.placeholder = "Search apps"
        sb.searchBarStyle = .minimal
        sb.delegate = self
        sb.searchTextField.textColor = .label
        sb.searchTextField.backgroundColor = UIColor(named: "ContainerBackground")
        return sb
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .grouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = .clear
        tv.separatorColor = .separator
        tv.delegate = self
        tv.dataSource = self
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tv.rowHeight = 44
        tv.keyboardDismissMode = .onDrag
        tv.sectionHeaderTopPadding = 0
        return tv
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        loadData()
    }

    // MARK: - Data

    private var displayedApps: [AppInfo] { isSearching ? filtered : apps }

    private func loadData() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let allowlist = self?.loadAllowlist() ?? []
            let apps = self?.loadInstalledApps() ?? []

            DispatchQueue.main.async {
                guard let self else { return }
                self.allowedBundleIds = Set(allowlist)

                if !self.allowedBundleIds.contains(self.selfBundleId) {
                    _ = RootExec.allowlistAdd(self.selfBundleId)
                    self.allowedBundleIds.insert(self.selfBundleId)
                }

                self.apps = apps.map { app in
                    AppInfo(bundleId: app.bundleId, name: app.name, isBypassed: !self.allowedBundleIds.contains(app.bundleId))
                }.sorted { $0.name.lowercased() < $1.name.lowercased() }

                self.checkBypassStatus()
                self.tableView.reloadData()
            }
        }
    }

    private func loadAllowlist() -> [String] {
        guard let response = RootExec.allowlistGet() else { return [] }
        return response.replacingOccurrences(of: "allowlist:", with: "")
            .split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    private func loadInstalledApps() -> [(bundleId: String, name: String)] {
        var result: [(String, String)] = []
        var seen = Set<String>()

        func add(_ plist: String, fallback: String) {
            guard let data = FileManager.default.contents(atPath: plist),
                  let p = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let bid = p["CFBundleIdentifier"] as? String, !seen.contains(bid) else { return }
            seen.insert(bid)
            let name = (p["CFBundleDisplayName"] ?? p["CFBundleName"]) as? String ?? fallback
            result.append((bid, name))
        }

        func scan(_ path: String, nested: Bool = true) {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }
            for item in items {
                let full = "\(path)/\(item)"
                if item.hasSuffix(".app") {
                    add("\(full)/Info.plist", fallback: item.replacingOccurrences(of: ".app", with: ""))
                } else if nested, let sub = try? FileManager.default.contentsOfDirectory(atPath: full) {
                    for s in sub where s.hasSuffix(".app") {
                        add("\(full)/\(s)/Info.plist", fallback: s.replacingOccurrences(of: ".app", with: ""))
                    }
                }
            }
        }

        scan("/var/containers/Bundle/Application")
        scan("/Applications", nested: false)
        scan("/var/jb/Applications", nested: false)
        return result
    }

    private func checkBypassStatus() {
        let active = RootExec.jbBypassStatus()?.contains("toggle_file=1") ?? false
        mainToggle.isOn = active
    }

    // MARK: - Actions

    @objc private func mainToggleChanged() {
        let on = mainToggle.isOn
        mainToggle.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = (on ? RootExec.jbBypassOn() : RootExec.jbBypassOff())?.hasPrefix("ok:") ?? false
            DispatchQueue.main.async {
                if !ok { self?.mainToggle.isOn = !on }
                self?.mainToggle.isEnabled = true
            }
        }
    }

    private func toggle(_ bundleId: String) {
        guard bundleId != selfBundleId, let i = apps.firstIndex(where: { $0.bundleId == bundleId }) else { return }
        let bypass = !apps[i].isBypassed
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = (bypass ? RootExec.allowlistRemove(bundleId) : RootExec.allowlistAdd(bundleId))?.hasPrefix("ok:") ?? false
            DispatchQueue.main.async {
                guard let self, ok else { return }
                self.apps[i].isBypassed = bypass
                if self.isSearching, let fi = self.filtered.firstIndex(where: { $0.bundleId == bundleId }) {
                    self.filtered[fi].isBypassed = bypass
                }
                self.tableView.reloadData()
            }
        }
    }
}

// MARK: - TableView

extension JailbreakBypassViewController: UITableViewDelegate, UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : displayedApps.count
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 1 else { return nil }
        let container = UIView()
        container.addSubview(searchBar)
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: container.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            searchBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 0 ? 0 : 44
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.backgroundColor = UIColor(named: "ContainerBackground")
        cell.selectionStyle = .none
        cell.textLabel?.textColor = .label
        cell.textLabel?.font = .systemFont(ofSize: 15)

        if indexPath.section == 0 {
            cell.textLabel?.text = "Enable"
            cell.accessoryView = mainToggle
        } else {
            let app = displayedApps[indexPath.row]
            let locked = app.bundleId == selfBundleId

            cell.textLabel?.text = app.name
            cell.textLabel?.alpha = locked ? 0.5 : 1.0

            // ponytail: reuse UISwitch if already present
            let sw = (cell.accessoryView as? UISwitch) ?? UISwitch()
            sw.isOn = app.isBypassed
            sw.onTintColor = .systemGreen
            sw.isEnabled = !locked
            sw.tag = indexPath.row
            sw.removeTarget(nil, action: nil, for: .valueChanged)
            sw.addTarget(self, action: #selector(appToggled(_:)), for: .valueChanged)
            cell.accessoryView = sw
        }
        return cell
    }

    @objc private func appToggled(_ s: UISwitch) { toggle(displayedApps[s.tag].bundleId) }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 1 else { return }
        let app = displayedApps[indexPath.row]
        showAppActions(app)
    }

    private func showAppActions(_ app: AppInfo) {
        let alert = UIAlertController(title: app.name, message: app.bundleId, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Launch with Cloak", style: .default) { [weak self] _ in
            self?.launchWithCloak(app.bundleId)
        })

        alert.addAction(UIAlertAction(title: "Launch Normal", style: .default) { _ in
            RootExec.openApp(app.bundleId)
        })

        let bypassTitle = app.isBypassed ? "Disable Bypass" : "Enable Bypass"
        alert.addAction(UIAlertAction(title: bypassTitle, style: .default) { [weak self] _ in
            self?.toggle(app.bundleId)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }

        present(alert, animated: true)
    }

    private func launchWithCloak(_ bundleId: String) {
        let hud = showLoadingHUD(message: "Launching...")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = RootExec.launchWithCloak(bundleId)
            DispatchQueue.main.async {
                hud.removeFromSuperview()
                if result?.hasPrefix("ok:") != true {
                    self?.showAlert(title: "Error", message: result ?? "Failed to launch")
                }
            }
        }
    }

    private func showLoadingHUD(message: String) -> UIView {
        let hud = UIView(frame: view.bounds)
        hud.backgroundColor = UIColor.black.withAlphaComponent(0.5)

        let container = UIView()
        container.backgroundColor = UIColor(named: "ContainerBackground")
        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.textColor = .label
        label.font = .systemFont(ofSize: 14)
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(spinner)
        container.addSubview(label)
        hud.addSubview(container)
        view.addSubview(hud)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: hud.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: hud.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 120),
            container.heightAnchor.constraint(equalToConstant: 100),
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
        ])

        return hud
    }

}

// MARK: - Search

extension JailbreakBypassViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange text: String) {
        filtered = text.isEmpty ? [] : apps.filter {
            $0.name.localizedCaseInsensitiveContains(text) || $0.bundleId.localizedCaseInsensitiveContains(text)
        }
        tableView.reloadData()
    }
}

// MARK: - ViewCode

extension JailbreakBypassViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(tableView)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
