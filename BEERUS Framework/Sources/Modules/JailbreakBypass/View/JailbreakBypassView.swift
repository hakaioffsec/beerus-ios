import UIKit

final class JailbreakBypassView: UIView {

    private lazy var circuitTopImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "circuit-top")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitRightImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "circuit-right")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "circuit-left-2")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftDownImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "circuit-left-down")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var headerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(named: "ContainerBackground")
        view.layer.cornerRadius = 12
        return view
    }()

    private lazy var titleLabel = UILabel.styled(
        text: "Shadow JB Bypass",
        font: AppFont.bold(18),
        alignment: .left
    )

    private lazy var statusLabel = UILabel.styled(
        text: "Checking...",
        font: AppFont.regular(14),
        color: .secondaryLabel,
        alignment: .left
    )

    let versionButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Select Version", for: .normal)
        button.titleLabel?.font = AppFont.regular(14)
        button.setTitleColor(.systemBlue, for: .normal)
        return button
    }()

    let installButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = AppFont.bold(16)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        return button
    }()

    let respringButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Respring", for: .normal)
        button.titleLabel?.font = AppFont.regular(14)
        button.setTitleColor(.systemOrange, for: .normal)
        return button
    }()

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()

    let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = "Search apps"
        searchBar.searchBarStyle = .minimal
        searchBar.searchTextField.textColor = .label
        searchBar.searchTextField.backgroundColor = UIColor(named: "ContainerBackground")
        return searchBar
    }()

    let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.2)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tableView.rowHeight = 50
        tableView.keyboardDismissMode = .onDrag
        return tableView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Rendering

    func apply(_ state: JailbreakBypassViewModel.HeaderState) {
        statusLabel.text = state.statusText
        statusLabel.textColor = color(state.statusColor)
        installButton.setTitle(state.installTitle, for: .normal)
        installButton.backgroundColor = color(state.installColor)
        versionButton.isHidden = state.versionHidden
        respringButton.isHidden = state.respringHidden
        searchBar.isHidden = state.searchHidden
        tableView.isHidden = state.tableHidden
    }

    func setVersionTitle(_ title: String) {
        versionButton.setTitle(title, for: .normal)
    }

    func setVersionEnabled(_ enabled: Bool) {
        versionButton.isEnabled = enabled
    }

    func setStatusText(_ text: String) {
        statusLabel.text = text
    }

    func setInstalling(_ installing: Bool) {
        installButton.isEnabled = !installing
        if installing {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    private func color(_ palette: JailbreakBypassViewModel.Palette) -> UIColor {
        switch palette {
        case .green: return .systemGreen
        case .orange: return .systemOrange
        case .red: return .systemRed
        case .blue: return .systemBlue
        }
    }
}

extension JailbreakBypassView: ViewCode {
    func buildViewHierarchy() {
        addSubview(circuitTopImageView)
        addSubview(circuitRightImageView)
        addSubview(circuitLeftImageView)
        addSubview(circuitLeftDownImageView)

        addSubview(headerView)
        headerView.addSubview(titleLabel)
        headerView.addSubview(statusLabel)
        headerView.addSubview(versionButton)
        headerView.addSubview(installButton)
        headerView.addSubview(respringButton)
        headerView.addSubview(activityIndicator)

        addSubview(searchBar)
        addSubview(tableView)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            circuitTopImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitTopImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),

            circuitRightImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitRightImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            circuitRightImageView.widthAnchor.constraint(equalToConstant: 40),
            circuitRightImageView.heightAnchor.constraint(equalTo: safeAreaLayoutGuide.heightAnchor),

            circuitLeftImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitLeftImageView.leadingAnchor.constraint(equalTo: leadingAnchor),

            circuitLeftDownImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            circuitLeftDownImageView.leadingAnchor.constraint(equalTo: leadingAnchor),

            headerView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),

            versionButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            versionButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),

            installButton.topAnchor.constraint(equalTo: versionButton.bottomAnchor, constant: 12),
            installButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            installButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            installButton.heightAnchor.constraint(equalToConstant: 44),

            respringButton.topAnchor.constraint(equalTo: installButton.bottomAnchor, constant: 8),
            respringButton.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            respringButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -16),

            activityIndicator.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            activityIndicator.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),

            searchBar.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 16),
            searchBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: trailingAnchor),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
