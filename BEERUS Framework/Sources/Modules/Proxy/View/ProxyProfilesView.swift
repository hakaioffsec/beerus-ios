import UIKit

final class ProxyProfilesView: UIView {

    var onToggle: (Int, Bool) -> Void = { _, _ in }
    var onDelete: (Int) -> Void = { _ in }

    private lazy var circuitTopImageView: UIImageView = {
        let image = UIImage(named: "circuit-top")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftImageView: UIImageView = {
        let image = UIImage(named: "circuit-left-2")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitRightImageView: UIImageView = {
        let image = UIImage(named: "circuit-right")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftDownImageView: UIImageView = {
        let image = UIImage(named: "circuit-left-down")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Proxy Profiles"
        label.font = UIFont(name: "IBM Plex Mono Bold", size: 20)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.tintColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let addProfileButton: UIButton = {
        let button = UIButton()
        button.setTitle("Add Profile", for: .normal)
        button.setTitleColor(.RED, for: .normal)
        button.backgroundColor = UIColor(named: "ButtonColorWhite")
        button.layer.cornerRadius = 10
        button.titleLabel?.font = UIFont(name: "IBM Plex Mono Bold", size: 15)
        return button
    }()

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private lazy var profilesStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func render(_ profiles: [ProxyProfile]) {
        profilesStack.arrangedSubviews.forEach { view in
            profilesStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, profile) in profiles.enumerated() {
            let cardView = UIView()
            let nameLabel = UILabel()
            let proxyLabel = UILabel()
            let proxySwitch = UISwitch()
            let deleteButton = UIButton(type: .system)
            let actionRow = UIStackView()

            cardView.translatesAutoresizingMaskIntoConstraints = false
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            proxyLabel.translatesAutoresizingMaskIntoConstraints = false
            proxySwitch.translatesAutoresizingMaskIntoConstraints = false
            deleteButton.translatesAutoresizingMaskIntoConstraints = false
            actionRow.translatesAutoresizingMaskIntoConstraints = false

            cardView.backgroundColor = .secondarySystemBackground
            cardView.layer.cornerRadius = 16
            cardView.layer.borderWidth = 1
            cardView.layer.borderColor = profile.isEnabled
                ? UIColor.systemGreen.cgColor
                : UIColor.systemGray4.cgColor

            nameLabel.text = profile.name
            nameLabel.font = UIFont.boldSystemFont(ofSize: 20)
            nameLabel.textColor = .label
            nameLabel.numberOfLines = 1

            proxyLabel.text = profile.proxy
            proxyLabel.font = UIFont.systemFont(ofSize: 14)
            proxyLabel.textColor = .secondaryLabel
            proxyLabel.numberOfLines = 2
            proxyLabel.lineBreakMode = .byTruncatingMiddle

            proxySwitch.isOn = profile.isEnabled
            proxySwitch.tag = index
            proxySwitch.addTarget(self, action: #selector(switchValueChanged(_:)), for: .valueChanged)

            deleteButton.setTitle("Apagar", for: .normal)
            deleteButton.setTitleColor(.systemRed, for: .normal)
            deleteButton.tag = index
            deleteButton.addTarget(self, action: #selector(deleteProfileTapped(_:)), for: .touchUpInside)

            actionRow.axis = .horizontal
            actionRow.alignment = .center
            actionRow.distribution = .equalSpacing
            actionRow.spacing = 12

            actionRow.addArrangedSubview(deleteButton)
            actionRow.addArrangedSubview(proxySwitch)

            cardView.addSubview(nameLabel)
            cardView.addSubview(proxyLabel)
            cardView.addSubview(actionRow)

            profilesStack.addArrangedSubview(cardView)

            NSLayoutConstraint.activate([
                cardView.heightAnchor.constraint(equalToConstant: 128),

                nameLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 14),
                nameLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
                nameLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),

                proxyLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
                proxyLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14),
                proxyLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionRow.leadingAnchor, constant: -10),

                actionRow.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
                actionRow.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -14)
            ])
        }
    }

    @objc private func switchValueChanged(_ sender: UISwitch) {
        onToggle(sender.tag, sender.isOn)
    }

    @objc private func deleteProfileTapped(_ sender: UIButton) {
        onDelete(sender.tag)
    }
}

extension ProxyProfilesView: ViewCode {
    func buildViewHierarchy() {
        addSubview(titleLabel)

        addSubview(circuitTopImageView)
        addSubview(circuitRightImageView)
        addSubview(circuitLeftImageView)
        addSubview(circuitLeftDownImageView)

        addSubview(stackView)
        stackView.addArrangedSubview(addProfileButton)
        stackView.addArrangedSubview(profilesStack)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            circuitTopImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitTopImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),

            circuitRightImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitRightImageView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            circuitRightImageView.widthAnchor.constraint(equalToConstant: 40),
            circuitRightImageView.heightAnchor.constraint(equalTo: safeAreaLayoutGuide.heightAnchor),

            circuitLeftImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitLeftImageView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),

            circuitLeftDownImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            circuitLeftDownImageView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),

            stackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24)
        ])
    }
}
