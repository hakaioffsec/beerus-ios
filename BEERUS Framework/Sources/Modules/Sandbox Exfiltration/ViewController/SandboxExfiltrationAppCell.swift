import UIKit

final class SandboxExfiltrationAppCell: UITableViewCell {

    let iconView = UIImageView()
    let nameLabel = UILabel()
    let bundleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFill
        iconView.layer.cornerRadius = 22
        iconView.clipsToBounds = true
        iconView.tintColor = .white

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = UIFont.boldSystemFont(ofSize: 17)
        nameLabel.textColor = .white

        bundleLabel.translatesAutoresizingMaskIntoConstraints = false
        bundleLabel.font = UIFont.systemFont(ofSize: 12)
        bundleLabel.textColor = .darkGray
        bundleLabel.numberOfLines = 1

        contentView.addSubview(iconView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(bundleLabel)

        NSLayoutConstraint.activate([

            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 50),
            iconView.heightAnchor.constraint(equalToConstant: 50),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),

            bundleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            bundleLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            bundleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
