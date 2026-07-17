import UIKit

final class VersionCell: UITableViewCell {

    static let identifier = "VersionCell"

    private let versionLabel = UILabel.styled(font: AppFont.medium(13))
    private let dateLabel = UILabel.styled(font: AppFont.regular(11), color: UIColor(white: 0.5, alpha: 1))
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    let getButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("GET", for: .normal)
        btn.titleLabel?.font = AppFont.bold(11)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(named: "ButtonColor")
        btn.layer.cornerRadius = 4
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    var onGetTapped: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(versionLabel)
        contentView.addSubview(dateLabel)
        contentView.addSubview(loadingIndicator)
        contentView.addSubview(getButton)

        getButton.addTarget(self, action: #selector(getTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            versionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            versionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

            dateLabel.leadingAnchor.constraint(equalTo: versionLabel.leadingAnchor),
            dateLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 2),
            dateLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            loadingIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            loadingIndicator.leadingAnchor.constraint(equalTo: versionLabel.trailingAnchor, constant: 8),

            getButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            getButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            getButton.widthAnchor.constraint(equalToConstant: 52),
            getButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(versionID: String, metadata: VersionMetadata?, isLatest: Bool) {
        if let meta = metadata {
            versionLabel.text = "v\(meta.displayVersion)\(isLatest ? " • Latest" : "")"
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            dateLabel.text = formatter.string(from: meta.releaseDate)
            loadingIndicator.stopAnimating()
        } else {
            versionLabel.text = "Version \(versionID)\(isLatest ? " • Latest" : "")"
            dateLabel.text = "Loading..."
            loadingIndicator.startAnimating()
        }

        getButton.backgroundColor = isLatest ? UIColor(named: "ButtonColor") : UIColor(white: 0.2, alpha: 1)
    }

    @objc private func getTapped() {
        onGetTapped?()
    }
}
