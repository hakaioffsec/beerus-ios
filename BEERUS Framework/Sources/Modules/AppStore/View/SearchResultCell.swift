import UIKit

final class SearchResultCell: UITableViewCell {

    static let identifier = "SearchResultCell"

    private let iconView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.15, alpha: 1)
        v.layer.cornerRadius = 12
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let nameLabel = UILabel.styled(font: AppFont.medium(14))
    private let bundleLabel = UILabel.styled(font: AppFont.regular(11), color: UIColor(white: 0.5, alpha: 1))
    private let priceLabel = UILabel.styled(font: AppFont.regular(11), color: UIColor(white: 0.6, alpha: 1))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(iconView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(bundleLabel)
        contentView.addSubview(priceLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: priceLabel.leadingAnchor, constant: -8),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

            bundleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            bundleLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            bundleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            bundleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            priceLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            priceLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with app: AppStoreApp) {
        nameLabel.text = app.name
        bundleLabel.text = app.bundleID
        priceLabel.text = app.price == 0 ? "Free" : String(format: "$%.2f", app.price)
    }
}
