import UIKit

final class AppDetailView: UIView {

    private let nameLabel = UILabel.styled(font: AppFont.bold(18), alignment: .center)
    private let bundleLabel = UILabel.styled(
        font: AppFont.regular(12),
        color: UIColor(white: 0.5, alpha: 1),
        alignment: .center
    )
    private let versionLabel = UILabel.styled(
        font: AppFont.regular(13),
        color: UIColor(white: 0.6, alpha: 1),
        alignment: .center
    )
    private let idLabel = UILabel.styled(
        font: AppFont.regular(11),
        color: UIColor(white: 0.4, alpha: 1),
        alignment: .center
    )

    let downloadButton = UIButton.styled(title: "Download Latest")
    let versionsButton = UIButton.styled(title: "View All Versions", backgroundColor: UIColor(white: 0.2, alpha: 1))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(name: String, bundle: String, version: String, id: String) {
        nameLabel.text = name
        bundleLabel.text = bundle
        versionLabel.text = version
        idLabel.text = id
    }
}

extension AppDetailView: ViewCode {
    func buildViewHierarchy() {
        addSubview(nameLabel)
        addSubview(bundleLabel)
        addSubview(versionLabel)
        addSubview(downloadButton)
        addSubview(versionsButton)
        addSubview(idLabel)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 80),
            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            bundleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            bundleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: bundleLabel.bottomAnchor, constant: 4),
            versionLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            downloadButton.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 32),
            downloadButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            downloadButton.widthAnchor.constraint(equalToConstant: 220),
            downloadButton.heightAnchor.constraint(equalToConstant: 50),

            versionsButton.topAnchor.constraint(equalTo: downloadButton.bottomAnchor, constant: 12),
            versionsButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            versionsButton.widthAnchor.constraint(equalToConstant: 220),
            versionsButton.heightAnchor.constraint(equalToConstant: 50),

            idLabel.topAnchor.constraint(equalTo: versionsButton.bottomAnchor, constant: 24),
            idLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }
}
