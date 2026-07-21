import UIKit

final class SearchResultCell: UITableViewCell {

    static let identifier = "SearchResultCell"

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.backgroundColor = UIColor(white: 0.15, alpha: 1)
        iv.layer.cornerRadius = 12
        iv.clipsToBounds = true
        iv.contentMode = .scaleAspectFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameLabel = UILabel.styled(font: AppFont.medium(14))
    private let bundleLabel = UILabel.styled(font: AppFont.regular(11), color: UIColor(white: 0.5, alpha: 1))
    private let priceLabel = UILabel.styled(font: AppFont.regular(11), color: UIColor(white: 0.6, alpha: 1))

    private var currentIconURL: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(iconImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(bundleLabel)
        contentView.addSubview(priceLabel)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 44),
            iconImageView.heightAnchor.constraint(equalToConstant: 44),

            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
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

    override func prepareForReuse() {
        super.prepareForReuse()
        iconImageView.image = nil
        currentIconURL = nil
    }

    func configure(with app: AppStoreApp) {
        nameLabel.text = app.name
        bundleLabel.text = app.bundleID
        priceLabel.text = app.price == 0 ? "Free" : String(format: "$%.2f", app.price)

        currentIconURL = app.iconURL
        iconImageView.image = nil

        guard let urlString = app.iconURL, let url = URL(string: urlString) else {
            // ponytail: debug missing icon URLs
            NSLog("[AppStore] No icon URL for: %@", app.bundleID)
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        // ponytail: uncomment to debug icon URL loading
        // NSLog("[AppStore] Loading icon: %@", urlString)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self, self.currentIconURL == urlString else { return }

            if let error = error {
                NSLog("[AppStore] Icon load error for %@: %@", app.bundleID, error.localizedDescription)
                return
            }

            guard let data = data, !data.isEmpty,
                  let image = UIImage(data: data) else {
                NSLog("[AppStore] Invalid icon data for %@", app.bundleID)
                return
            }

            DispatchQueue.main.async {
                self.iconImageView.image = image
            }
        }.resume()
    }
}
