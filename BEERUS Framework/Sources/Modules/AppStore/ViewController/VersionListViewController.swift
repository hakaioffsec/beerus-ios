import UIKit

final class VersionListViewController: BaseViewController {

    private let app: AppStoreApp
    private var versionIDs: [String] = []
    private var latestID: String = ""
    private var metadataCache: [String: VersionMetadata] = [:]
    private var metadataTask: Task<Void, Never>?

    init(app: AppStoreApp) {
        self.app = app
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private lazy var titleLabel = UILabel.styled(
        text: "\(app.name) — Versions", font: AppFont.bold(16), alignment: .center
    )

    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorColor = UIColor(white: 0.15, alpha: 1)
        table.register(VersionCell.self, forCellReuseIdentifier: VersionCell.identifier)
        table.delegate = self
        table.dataSource = self
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .large)
        s.color = .white
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        loadVersions()
    }

    private func loadVersions() {
        spinner.startAnimating()
        Task { @MainActor in
            do {
                let result = try await fetchVersionsWithPurchase()
                spinner.stopAnimating()
                versionIDs = result.identifiers.reversed()
                latestID = result.latestID
                tableView.reloadData()
                loadMetadataProgressively()
            } catch AppStoreError.tokenExpired {
                spinner.stopAnimating()
                handleTokenExpired()
            } catch {
                spinner.stopAnimating()
                showAlert(title: "Error", message: error.localizedDescription)
            }
        }
    }

    private func handleTokenExpired() {
        AppStoreService.shared.revoke()
        let alert = UIAlertController(
            title: "Session Expired",
            message: "Your login has expired. Please sign in again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self else { return }
            let nav = self.navigationController
            let delegate = self.menuDelegate
            let loginVC = AppStoreLoginViewController()
            loginVC.menuDelegate = delegate
            loginVC.onLoginSuccess = { _ in
                let searchVC = AppStoreSearchViewController()
                searchVC.menuDelegate = delegate
                nav?.setViewControllers([searchVC], animated: true)
            }
            nav?.setViewControllers([loginVC], animated: true)
        })
        present(alert, animated: true)
    }

    private func fetchVersionsWithPurchase() async throws -> VersionListResult {
        do {
            return try await AppStoreService.shared.listVersions(app: app)
        } catch AppStoreError.licenseRequired {
            // ponytail: auto-purchase free app to acquire license
            try await AppStoreService.shared.purchase(app: app)
            return try await AppStoreService.shared.listVersions(app: app)
        }
    }

    private func loadMetadataProgressively() {
        metadataTask = Task { [weak self] in
            guard let self else { return }
            // ponytail: capture app before entering task group to avoid force-unwrap crash
            let app = self.app
            let maxConcurrent = 5
            for batch in stride(from: 0, to: versionIDs.count, by: maxConcurrent) {
                let end = min(batch + maxConcurrent, versionIDs.count)
                let slice = Array(versionIDs[batch..<end])
                await withTaskGroup(of: (Int, String, VersionMetadata?).self) { group in
                    for (offset, versionID) in slice.enumerated() {
                        let index = batch + offset
                        group.addTask {
                            let meta = try? await AppStoreService.shared.getVersionMetadata(
                                app: app, versionID: versionID
                            )
                            return (index, versionID, meta)
                        }
                    }
                    for await (index, versionID, meta) in group {
                        guard !Task.isCancelled else { return }
                        guard let meta else { continue }
                        await MainActor.run { [weak self] in
                            guard let self else { return }
                            self.metadataCache[versionID] = meta
                            let indexPath = IndexPath(row: index, section: 0)
                            if self.tableView.indexPathsForVisibleRows?.contains(indexPath) == true {
                                self.tableView.reloadRows(at: [indexPath], with: .none)
                            }
                        }
                    }
                }
                if Task.isCancelled { return }
            }
        }
    }

    deinit {
        metadataTask?.cancel()
    }
}

extension VersionListViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        versionIDs.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VersionCell.identifier, for: indexPath) as! VersionCell
        let versionID = versionIDs[indexPath.row]
        let isLatest = versionID == latestID
        cell.configure(versionID: versionID, metadata: metadataCache[versionID], isLatest: isLatest)
        cell.onGetTapped = { [weak self] in
            guard let self else { return }
            let downloadVC = DownloadViewController(app: self.app, versionID: versionID)
            downloadVC.menuDelegate = self.menuDelegate
            self.navigationController?.pushViewController(downloadVC, animated: true)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 60 }
}

extension VersionListViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(tableView)
        view.addSubview(spinner)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
