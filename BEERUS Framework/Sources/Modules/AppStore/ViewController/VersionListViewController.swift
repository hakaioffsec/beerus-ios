import UIKit

final class VersionListViewController: BaseViewController {

    private let app: AppStoreApp
    private var versionIDs: [String] = []
    private var latestID: String = ""
    private var metadataCache: [String: VersionMetadata] = [:]

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
        Task {
            do {
                let result = try await AppStoreService.shared.listVersions(app: app)
                await MainActor.run {
                    spinner.stopAnimating()
                    versionIDs = result.identifiers.reversed()
                    latestID = result.latestID
                    tableView.reloadData()
                    loadMetadataProgressively()
                }
            } catch {
                await MainActor.run {
                    spinner.stopAnimating()
                    showAlert(title: "Error", message: error.localizedDescription)
                }
            }
        }
    }

    private func loadMetadataProgressively() {
        for (index, versionID) in versionIDs.enumerated() {
            Task {
                do {
                    let meta = try await AppStoreService.shared.getVersionMetadata(
                        app: app, versionID: versionID
                    )
                    await MainActor.run {
                        metadataCache[versionID] = meta
                        let indexPath = IndexPath(row: index, section: 0)
                        if tableView.indexPathsForVisibleRows?.contains(indexPath) == true {
                            tableView.reloadRows(at: [indexPath], with: .none)
                        }
                    }
                } catch {
                    // Metadata load failure is non-fatal — cell stays in loading state
                }
            }
        }
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
