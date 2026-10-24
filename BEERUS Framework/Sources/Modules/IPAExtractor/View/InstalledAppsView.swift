import UIKit

final class InstalledAppsView: UIView {

    let tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorStyle = .singleLine
        table.separatorColor = UIColor.white.withAlphaComponent(0.2)
        table.register(AppCell.self, forCellReuseIdentifier: AppCell.identifier)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let progressLabel: UILabel = {
        let label = UILabel()
        label.font = AppFont.regular(14)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showProgress(_ message: String) {
        activityIndicator.startAnimating()
        progressLabel.text = message
        progressLabel.alpha = 1
    }

    func hideProgress() {
        activityIndicator.stopAnimating()
        progressLabel.alpha = 0
    }
}

extension InstalledAppsView: ViewCode {
    func buildViewHierarchy() {
        addSubview(tableView)
        addSubview(activityIndicator)
        addSubview(progressLabel)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 56),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),

            progressLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 16),
            progressLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            progressLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
    }
}
