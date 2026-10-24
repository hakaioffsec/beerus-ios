import Foundation

final class JailbreakBypassViewModel {

    struct AppInfo {
        let bundleId: String
        let name: String
        var isEnabled: Bool
    }

    enum Palette {
        case green, orange, red, blue
    }

    struct HeaderState {
        let statusText: String
        let statusColor: Palette
        let installTitle: String
        let installColor: Palette
        let versionHidden: Bool
        let respringHidden: Bool
        let searchHidden: Bool
        let tableHidden: Bool
    }

    weak var coordinator: JailbreakBypassCoordinator?

    private let service: ShadowService
    private var apps: [AppInfo] = []
    private var filteredApps: [AppInfo] = []
    private var searchText: String = ""

    private var isSearching: Bool { !searchText.isEmpty }
    private var displayedApps: [AppInfo] { isSearching ? filteredApps : apps }

    var onState: (HeaderState) -> Void = { _ in }
    var onVersionTitle: (String) -> Void = { _ in }
    var onVersionEnabled: (Bool) -> Void = { _ in }
    var onStatusText: (String) -> Void = { _ in }
    var onInstallingChange: (Bool) -> Void = { _ in }
    var onReload: () -> Void = {}
    var onRowUpdated: (Int) -> Void = { _ in }
    var onError: (String) -> Void = { _ in }

    init(service: ShadowService = .shared) {
        self.service = service
    }

    func viewDidLoad() {
        refreshState()
        fetchVersions()
    }

    func viewWillAppear() {
        refreshState()
    }

    func numberOfRows() -> Int { displayedApps.count }

    func app(at index: Int) -> AppInfo { displayedApps[index] }

    // MARK: - Header

    private func refreshState() {
        let installed = service.isInstalled
        onState(HeaderState(
            statusText: installed ? "Shadow is installed" : "Shadow is not installed",
            statusColor: installed ? .green : .orange,
            installTitle: installed ? "Uninstall Shadow" : "Install Shadow",
            installColor: installed ? .red : .blue,
            versionHidden: installed,
            respringHidden: !installed,
            searchHidden: !installed,
            tableHidden: !installed
        ))
        if installed {
            loadApps()
        }
    }

    // MARK: - Versions

    func fetchVersions() {
        onVersionTitle("Loading...")
        onVersionEnabled(false)

        service.fetchReleases { [weak self] result in
            guard let self else { return }
            self.onVersionEnabled(true)

            switch result {
            case .success(let releases):
                if let selected = self.service.selectedRelease {
                    self.onVersionTitle("Version: \(selected.version)")
                } else if releases.isEmpty {
                    self.onVersionTitle("No versions found")
                }
            case .failure:
                self.onVersionTitle("Failed to load")
            }
        }
    }

    func tappedVersion() {
        let releases = service.availableReleases
        guard !releases.isEmpty else {
            fetchVersions()
            return
        }

        coordinator?.selectVersion(
            releases: Array(releases.prefix(10)),
            selected: service.selectedRelease
        ) { [weak self] release in
            self?.service.selectRelease(release)
            self?.onVersionTitle("Version: \(release.version)")
        }
    }

    // MARK: - Install / Uninstall / Respring

    func tappedInstall() {
        if service.isInstalled {
            coordinator?.confirmUninstall { [weak self] in self?.performUninstall() }
        } else {
            performInstall()
        }
    }

    func tappedRespring() {
        coordinator?.promptRespring { [weak self] in self?.service.respring() }
    }

    private func performInstall() {
        onInstallingChange(true)

        service.install { [weak self] status in
            self?.onStatusText(status)
        } completion: { [weak self] result in
            guard let self else { return }
            self.onInstallingChange(false)
            self.refreshState()

            switch result {
            case .success:
                self.coordinator?.promptRespring { [weak self] in self?.service.respring() }
            case .failure(let error):
                self.onError(error.localizedDescription)
            }
        }
    }

    private func performUninstall() {
        onInstallingChange(true)

        service.uninstall { [weak self] result in
            guard let self else { return }
            self.onInstallingChange(false)
            self.refreshState()

            switch result {
            case .success:
                self.coordinator?.promptRespring { [weak self] in self?.service.respring() }
            case .failure(let error):
                self.onError(error.localizedDescription)
            }
        }
    }

    // MARK: - Apps

    func search(_ text: String) {
        searchText = text
        filteredApps = text.isEmpty ? [] : apps.filter {
            $0.name.localizedCaseInsensitiveContains(text) ||
            $0.bundleId.localizedCaseInsensitiveContains(text)
        }
        onReload()
    }

    func toggleApp(at index: Int) {
        let app = displayedApps[index]
        let shouldEnable = !app.isEnabled
        let bundleId = app.bundleId

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = shouldEnable
                ? self?.service.enableBypass(for: bundleId) ?? false
                : self?.service.disableBypass(for: bundleId) ?? false

            DispatchQueue.main.async {
                guard let self, success else { return }

                if let i = self.apps.firstIndex(where: { $0.bundleId == bundleId }) {
                    self.apps[i].isEnabled = shouldEnable
                }
                if self.isSearching, let i = self.filteredApps.firstIndex(where: { $0.bundleId == bundleId }) {
                    self.filteredApps[i].isEnabled = shouldEnable
                }

                self.onRowUpdated(index)
            }
        }
    }

    private func loadApps() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let enabledApps = Set(self.service.getEnabledApps())
            let installedApps = self.loadInstalledApps()

            let appInfos = installedApps.map {
                AppInfo(bundleId: $0.bundleId, name: $0.name, isEnabled: enabledApps.contains($0.bundleId))
            }.sorted { $0.name.lowercased() < $1.name.lowercased() }

            DispatchQueue.main.async {
                self.apps = appInfos
                self.onReload()
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
}
