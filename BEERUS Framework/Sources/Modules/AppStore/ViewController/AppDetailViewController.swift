import UIKit

final class AppDetailViewController: BaseViewController {

    private let app: AppStoreApp

    init(app: AppStoreApp) {
        self.app = app
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private lazy var nameLabel = UILabel.styled(text: app.name, font: AppFont.bold(18), alignment: .center)
    private lazy var bundleLabel = UILabel.styled(
        text: app.bundleID, font: AppFont.regular(12),
        color: UIColor(white: 0.5, alpha: 1), alignment: .center
    )
    private lazy var versionLabel = UILabel.styled(
        text: "v\(app.version) • \(app.price == 0 ? "Free" : String(format: "$%.2f", app.price))",
        font: AppFont.regular(13), color: UIColor(white: 0.6, alpha: 1), alignment: .center
    )
    private lazy var idLabel = UILabel.styled(
        text: "App ID: \(app.id)", font: AppFont.regular(11),
        color: UIColor(white: 0.4, alpha: 1), alignment: .center
    )

    private lazy var downloadButton = UIButton.styled(
        title: "Download Latest", target: self, action: #selector(downloadTapped)
    )

    private lazy var versionsButton: UIButton = {
        let btn = UIButton.styled(
            title: "View All Versions",
            backgroundColor: UIColor(white: 0.2, alpha: 1),
            target: self, action: #selector(versionsTapped)
        )
        return btn
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
    }

    @objc private func downloadTapped() {
        let downloadVC = DownloadViewController(app: app, versionID: nil)
        downloadVC.menuDelegate = menuDelegate
        navigationController?.pushViewController(downloadVC, animated: true)
    }

    @objc private func versionsTapped() {
        let versionsVC = VersionListViewController(app: app)
        versionsVC.menuDelegate = menuDelegate
        navigationController?.pushViewController(versionsVC, animated: true)
    }
}

extension AppDetailViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(nameLabel)
        view.addSubview(bundleLabel)
        view.addSubview(versionLabel)
        view.addSubview(downloadButton)
        view.addSubview(versionsButton)
        view.addSubview(idLabel)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            bundleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            bundleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: bundleLabel.bottomAnchor, constant: 4),
            versionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            downloadButton.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 32),
            downloadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            downloadButton.widthAnchor.constraint(equalToConstant: 220),
            downloadButton.heightAnchor.constraint(equalToConstant: 50),

            versionsButton.topAnchor.constraint(equalTo: downloadButton.bottomAnchor, constant: 12),
            versionsButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            versionsButton.widthAnchor.constraint(equalToConstant: 220),
            versionsButton.heightAnchor.constraint(equalToConstant: 50),

            idLabel.topAnchor.constraint(equalTo: versionsButton.bottomAnchor, constant: 24),
            idLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }
}
