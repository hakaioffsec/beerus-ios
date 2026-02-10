import UIKit

enum FridaCellStatus {
    case none
    case downloading(Double)
    case installing
    case installed
    case failed(String)
}

final class FridaReleaseCell: UITableViewCell {

    static let identifier = "FridaReleaseCell"

    private lazy var versionLabel = UILabel.styled(font: AppFont.bold(16))
    private lazy var dateLabel = UILabel.styled(font: AppFont.regular(12), color: .lightGray)
    private lazy var assetCountLabel = UILabel.styled(
        font: AppFont.regular(12), color: UIColor(named: "ButtonColor") ?? .systemBlue
    )

    private lazy var prereleaseTag: UILabel = {
        let label = UILabel.styled(
            text: "pre", font: AppFont.bold(10), color: .black, alignment: .center
        )
        label.backgroundColor = .systemYellow
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        return label
    }()

    private lazy var statusLabel = UILabel.styled(font: AppFont.bold(11), alignment: .right)

    private lazy var progressBar: UIProgressView = {
        let bar = UIProgressView(progressViewStyle: .default)
        bar.progressTintColor = UIColor(named: "ButtonColor") ?? .systemBlue
        bar.trackTintColor = UIColor.white.withAlphaComponent(0.1)
        bar.isHidden = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with release: FridaRelease) {
        versionLabel.text = release.version
        dateLabel.text = release.formattedDate
        prereleaseTag.isHidden = !release.prerelease

        let arch = DeviceInfo.architecture
        if let asset = release.fridaServerAsset(for: arch) {
            let mb = Double(asset.size) / 1_048_576.0
            let kind = asset.name.hasSuffix(".deb") ? "deb" : "binary"
            assetCountLabel.text = "\(arch) \(kind) (\(String(format: "%.1f", mb)) MB)"
            assetCountLabel.textColor = UIColor(named: "ButtonColor") ?? .systemBlue
        } else {
            assetCountLabel.text = "No \(arch) package"
            assetCountLabel.textColor = .systemGray
        }
    }

    func updateStatus(_ status: FridaCellStatus) {
        switch status {
        case .none:
            statusLabel.text = nil
            progressBar.isHidden = true
        case .downloading(let progress):
            statusLabel.text = "\(Int(progress * 100))%"
            statusLabel.textColor = UIColor(named: "ButtonColor") ?? .systemBlue
            progressBar.isHidden = false
            progressBar.progress = Float(progress)
        case .installing:
            statusLabel.text = "Installing..."
            statusLabel.textColor = .systemOrange
            progressBar.isHidden = true
        case .installed:
            statusLabel.text = "✓ Installed"
            statusLabel.textColor = .systemGreen
            progressBar.isHidden = true
        case .failed(let msg):
            statusLabel.text = "✗ \(msg)"
            statusLabel.textColor = UIColor(named: "RED") ?? .systemRed
            progressBar.isHidden = true
        }
    }
}

extension FridaReleaseCell: ViewCode {
    func buildViewHierarchy() {
        contentView.addSubview(versionLabel)
        contentView.addSubview(dateLabel)
        contentView.addSubview(assetCountLabel)
        contentView.addSubview(prereleaseTag)
        contentView.addSubview(statusLabel)
        contentView.addSubview(progressBar)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            versionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            versionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            prereleaseTag.centerYAnchor.constraint(equalTo: versionLabel.centerYAnchor),
            prereleaseTag.leadingAnchor.constraint(equalTo: versionLabel.trailingAnchor, constant: 8),
            prereleaseTag.widthAnchor.constraint(equalToConstant: 30),
            prereleaseTag.heightAnchor.constraint(equalToConstant: 18),

            statusLabel.centerYAnchor.constraint(equalTo: versionLabel.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),

            dateLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: versionLabel.leadingAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            assetCountLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 2),
            assetCountLabel.leadingAnchor.constraint(equalTo: versionLabel.leadingAnchor),
            assetCountLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            progressBar.topAnchor.constraint(equalTo: assetCountLabel.bottomAnchor, constant: 6),
            progressBar.leadingAnchor.constraint(equalTo: versionLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            progressBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    func setupAdditionalConfiguration() {
        backgroundColor = UIColor(named: "ContainerBackground") ?? UIColor(white: 0.12, alpha: 1)
        selectionStyle = .none
    }
}
