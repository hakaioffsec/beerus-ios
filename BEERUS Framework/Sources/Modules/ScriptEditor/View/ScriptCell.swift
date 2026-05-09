import UIKit

final class ScriptCell: UITableViewCell {

    static let reuseId = "ScriptCell"

    // MARK: - UI

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.tintColor = UIColor(named: "RED")
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = AppFont.medium(14)
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let dateLabel: UILabel = {
        let l = UILabel()
        l.font = AppFont.regular(10)
        l.textColor = UIColor(white: 0.35, alpha: 1)
        l.textAlignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let previewLabel: UILabel = {
        let l = UILabel()
        l.font = AppFont.regular(10)
        l.textColor = UIColor(white: 0.30, alpha: 1)
        l.numberOfLines = 1
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let container: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(named: "ContainerBackground")
        v.layer.cornerRadius = 10
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(container)
        container.addSubview(iconView)
        container.addSubview(nameLabel)
        container.addSubview(dateLabel)
        container.addSubview(previewLabel)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),

            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -4),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: dateLabel.leadingAnchor, constant: -8),

            dateLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            dateLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            previewLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            previewLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            previewLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            previewLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
    }

    // MARK: - Configure

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    func configure(with script: FridaScriptModel) {
        nameLabel.text = script.name
        iconView.image = UIImage(systemName: "scroll")
        dateLabel.text = Self.dateFormatter.string(from: script.updatedAt)

        let firstLine = script.source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .first ?? ""
        previewLabel.text = firstLine.isEmpty ? "(empty)" : firstLine
    }
}
