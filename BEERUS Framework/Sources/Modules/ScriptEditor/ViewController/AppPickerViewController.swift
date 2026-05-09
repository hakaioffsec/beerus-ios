import UIKit

/// Full-screen picker that lists running apps so the user can tap one.
/// Includes a search bar and shows PID + name for each app.
final class AppPickerViewController: UIViewController {

    // MARK: - Callback

    var onSelect: ((AppModel) -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - Data

    private var allApps: [AppModel] = []
    private var filtered: [AppModel] = []

    // MARK: - UI

    private let topBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(named: "ContainerBackground")
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Select App"
        l.font = AppFont.bold(16)
        l.textColor = .white
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Cancel", for: .normal)
        btn.titleLabel?.font = AppFont.regular(14)
        btn.setTitleColor(UIColor(named: "RED"), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var searchBar: UISearchBar = {
        let sb = UISearchBar()
        sb.placeholder = "Search apps…"
        sb.searchBarStyle = .minimal
        sb.barStyle = .black
        sb.tintColor = UIColor(named: "RED")
        sb.translatesAutoresizingMaskIntoConstraints = false
        sb.delegate = self

        // Style the text field inside
        if let tf = sb.searchTextField as UITextField? {
            tf.font = AppFont.regular(13)
            tf.textColor = .white
            tf.attributedPlaceholder = NSAttributedString(
                string: "Search apps…",
                attributes: [.foregroundColor: UIColor(white: 0.45, alpha: 1)]
            )
            tf.backgroundColor = UIColor(white: 0.12, alpha: 1)
        }
        return sb
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.backgroundColor = UIColor(named: "Background")
        tv.separatorColor = UIColor(white: 0.15, alpha: 1)
        tv.rowHeight = 56
        tv.dataSource = self
        tv.delegate = self
        tv.register(AppPickerCell.self, forCellReuseIdentifier: AppPickerCell.id)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.indicatorStyle = .white
        tv.keyboardDismissMode = .onDrag
        return tv
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = .white
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let emptyLabel: UILabel = {
        let l = UILabel()
        l.text = "No running apps found"
        l.font = AppFont.regular(14)
        l.textColor = UIColor(white: 0.4, alpha: 1)
        l.textAlignment = .center
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "Background")
        buildUI()
        loadApps()
    }

    // MARK: - UI Build

    private func buildUI() {
        view.addSubview(topBar)
        topBar.addSubview(titleLabel)
        topBar.addSubview(cancelButton)
        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(spinner)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 48),

            cancelButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            searchBar.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - Load

    private func loadApps() {
        spinner.startAnimating()
        tableView.isHidden = true
        emptyLabel.isHidden = true

        Task { @MainActor in
            do {
                let apps = try await FridaManager.shared.getInstalledApps()
                let totalCount = apps.count
                let running = apps.filter { $0.pid > 0 }.sorted { $0.name.lowercased() < $1.name.lowercased() }

                allApps = running
                filtered = running
                spinner.stopAnimating()

                if running.isEmpty {
                    emptyLabel.text = totalCount > 0
                        ? "No running apps found.\n(\(totalCount) installed — open your target app first)"
                        : "No apps found."
                    emptyLabel.isHidden = false
                } else {
                    tableView.isHidden = false
                    titleLabel.text = "Running Apps (\(running.count))"
                    tableView.reloadData()
                }
            } catch {
                spinner.stopAnimating()
                emptyLabel.text = "Failed: \(error.localizedDescription)"
                emptyLabel.isHidden = false
            }
        }
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onCancel?()
        }
    }
}

// MARK: - UITableViewDataSource & Delegate

extension AppPickerViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filtered.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: AppPickerCell.id, for: indexPath) as? AppPickerCell else {
            return UITableViewCell()
        }
        cell.configure(with: filtered[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let app = filtered[indexPath.row]
        dismiss(animated: true) { [weak self] in
            self?.onSelect?(app)
        }
    }
}

// MARK: - UISearchBarDelegate

extension AppPickerViewController: UISearchBarDelegate {

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            filtered = allApps
        } else {
            filtered = allApps.filter {
                $0.name.lowercased().contains(query) ||
                $0.bundleIdentifier.lowercased().contains(query) ||
                "\($0.pid)".contains(query)
            }
        }
        tableView.reloadData()
        emptyLabel.isHidden = !filtered.isEmpty
        if filtered.isEmpty && !allApps.isEmpty {
            emptyLabel.text = "No matches"
        }
    }
}

// MARK: - Cell

private final class AppPickerCell: UITableViewCell {

    static let id = "AppPickerCell"

    private let appIcon: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(systemName: "app.fill")
        iv.tintColor = UIColor(named: "RED")
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = AppFont.bold(14)
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let detailLabel: UILabel = {
        let l = UILabel()
        l.font = AppFont.regular(11)
        l.textColor = UIColor(white: 0.45, alpha: 1)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let pidBadge: UILabel = {
        let l = UILabel()
        l.font = AppFont.bold(11)
        l.textColor = UIColor(named: "RED")
        l.textAlignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .gray

        let selectedBg = UIView()
        selectedBg.backgroundColor = UIColor(white: 0.15, alpha: 1)
        selectedBackgroundView = selectedBg

        contentView.addSubview(appIcon)
        contentView.addSubview(nameLabel)
        contentView.addSubview(detailLabel)
        contentView.addSubview(pidBadge)

        NSLayoutConstraint.activate([
            appIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            appIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            appIcon.widthAnchor.constraint(equalToConstant: 28),
            appIcon.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.leadingAnchor.constraint(equalTo: appIcon.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: pidBadge.leadingAnchor, constant: -8),

            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: pidBadge.leadingAnchor, constant: -8),

            pidBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            pidBadge.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            pidBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with app: AppModel) {
        nameLabel.text = app.name
        detailLabel.text = app.bundleIdentifier
        pidBadge.text = "PID \(app.pid)"
    }
}
