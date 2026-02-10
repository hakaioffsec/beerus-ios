import UIKit

final class AppCell: UITableViewCell {

    static let identifier = "AppCell"

    private lazy var nameLabel = UILabel.styled(font: AppFont.bold(16))
    private lazy var bundleIdLabel = UILabel.styled(font: AppFont.regular(12), color: .lightGray)
    private lazy var runningIndicator: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGreen
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with app: AppModel) {
        nameLabel.text = app.name
        bundleIdLabel.text = app.bundleIdentifier
        runningIndicator.isHidden = !app.isRunning
    }
}

extension AppCell: ViewCode {
    func buildViewHierarchy() {
        contentView.addSubview(runningIndicator)
        contentView.addSubview(nameLabel)
        contentView.addSubview(bundleIdLabel)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            runningIndicator.widthAnchor.constraint(equalToConstant: 8),
            runningIndicator.heightAnchor.constraint(equalToConstant: 8),
            runningIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            runningIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: runningIndicator.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            bundleIdLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            bundleIdLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            bundleIdLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bundleIdLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    func setupAdditionalConfiguration() {
        backgroundColor = .clear
        selectionStyle = .none
    }
}
