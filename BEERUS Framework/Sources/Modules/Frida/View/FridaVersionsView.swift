import UIKit

final class FridaVersionsView: UIView {

    private lazy var titleLabel = UILabel.styled(
        text: "Frida Versions",
        font: AppFont.bold(20),
        alignment: .center
    )

    private lazy var subtitleLabel = UILabel.styled(
        text: "Device: \(DeviceInfo.architecture)",
        font: AppFont.regular(13),
        color: .lightGray,
        alignment: .center
    )

    let tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorColor = UIColor.white.withAlphaComponent(0.1)
        table.register(FridaReleaseCell.self, forCellReuseIdentifier: FridaReleaseCell.identifier)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var errorLabel: UILabel = {
        let label = UILabel.styled(
            font: AppFont.regular(14),
            color: UIColor(named: "RED") ?? .systemRed,
            alignment: .center,
            lines: 0
        )
        label.isHidden = true
        return label
    }()

    let closeButton: UIButton = {
        let button = UIButton()
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let uninstallButton = UIButton.styled(
        title: "Uninstall Frida",
        font: AppFont.bold(13),
        backgroundColor: UIColor(named: "RED") ?? .systemRed,
        cornerRadius: 8
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background") ?? UIColor(white: 0.08, alpha: 1)
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Rendering

    func setLoading(_ loading: Bool) {
        if loading {
            activityIndicator.startAnimating()
            tableView.isHidden = true
            errorLabel.isHidden = true
            uninstallButton.isHidden = true
        } else {
            activityIndicator.stopAnimating()
        }
    }

    func showContent() {
        tableView.isHidden = false
        uninstallButton.isHidden = false
    }

    func showError(_ message: String) {
        errorLabel.text = message
        errorLabel.isHidden = false
    }

    func setUninstalling(_ uninstalling: Bool) {
        uninstallButton.isEnabled = !uninstalling
        uninstallButton.setTitle(uninstalling ? "Uninstalling..." : "Uninstall Frida", for: .normal)
    }
}

extension FridaVersionsView: ViewCode {
    func buildViewHierarchy() {
        addSubview(closeButton)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(tableView)
        addSubview(activityIndicator)
        addSubview(errorLabel)
        addSubview(uninstallButton)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: uninstallButton.topAnchor, constant: -12),

            uninstallButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            uninstallButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            uninstallButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            uninstallButton.heightAnchor.constraint(equalToConstant: 44),

            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])
    }
}
