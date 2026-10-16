import UIKit

final class SandboxExfiltrationView: UIView {

    private lazy var circuitTopImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "circuit-top"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "circuit-left-2"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitRightImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "circuit-right"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftDownImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "circuit-left-down"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Sandbox Exf/"
        label.font = UIFont.boldSystemFont(ofSize: 20)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var bottomPanelView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 0.96)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var storageLabel: UILabel = {
        let label = UILabel()
        label.text = "Data storage on\n↪ /data/data"
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .lightGray
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let searchTextField: UITextField = {
        let textField = UITextField()
        textField.textColor = .white
        textField.font = UIFont.boldSystemFont(ofSize: 16)
        textField.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1)
        textField.layer.borderColor = UIColor.gray.cgColor
        textField.layer.borderWidth = 1
        textField.layer.cornerRadius = 2
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        textField.leftViewMode = .always
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.attributedPlaceholder = NSAttributedString(
            string: "Search applications",
            attributes: [.foregroundColor: UIColor.lightGray]
        )
        return textField
    }()

    let tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.register(
            SandboxExfiltrationAppCell.self,
            forCellReuseIdentifier: "SandboxExfiltrationAppCell"
        )
        return table
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func dismissKeyboard() {
        endEditing(true)
    }
}

extension SandboxExfiltrationView: ViewCode {
    func buildViewHierarchy() {
        addSubview(titleLabel)

        addSubview(circuitTopImageView)
        addSubview(circuitRightImageView)
        addSubview(circuitLeftImageView)
        addSubview(circuitLeftDownImageView)

        addSubview(bottomPanelView)

        bottomPanelView.addSubview(storageLabel)
        bottomPanelView.addSubview(searchTextField)
        bottomPanelView.addSubview(tableView)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

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

            bottomPanelView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomPanelView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomPanelView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomPanelView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.80),

            storageLabel.topAnchor.constraint(equalTo: bottomPanelView.topAnchor, constant: 18),
            storageLabel.leadingAnchor.constraint(equalTo: bottomPanelView.leadingAnchor, constant: 20),
            storageLabel.trailingAnchor.constraint(equalTo: bottomPanelView.trailingAnchor, constant: -20),

            searchTextField.topAnchor.constraint(equalTo: storageLabel.bottomAnchor, constant: 16),
            searchTextField.leadingAnchor.constraint(equalTo: bottomPanelView.leadingAnchor, constant: 20),
            searchTextField.trailingAnchor.constraint(equalTo: bottomPanelView.trailingAnchor, constant: -20),
            searchTextField.heightAnchor.constraint(equalToConstant: 54),

            tableView.topAnchor.constraint(equalTo: searchTextField.bottomAnchor, constant: 14),
            tableView.leadingAnchor.constraint(equalTo: bottomPanelView.leadingAnchor, constant: 14),
            tableView.trailingAnchor.constraint(equalTo: bottomPanelView.trailingAnchor, constant: -14),
            tableView.bottomAnchor.constraint(equalTo: bottomPanelView.bottomAnchor)
        ])
    }
}
