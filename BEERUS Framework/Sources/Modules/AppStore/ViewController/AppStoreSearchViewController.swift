import UIKit

final class AppStoreSearchViewController: BaseViewController {

    private var results: [AppStoreApp] = []
    private var hasSearched = false  // ponytail: tracks if user searched vs initial empty state
    private var searchTask: Task<Void, Never>?

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No results"
        label.font = AppFont.regular(16)
        label.textColor = UIColor(white: 0.4, alpha: 1)
        label.textAlignment = .center
        return label
    }()

    private lazy var titleLabel = UILabel.styled(
        text: "App Store", font: AppFont.bold(20), alignment: .center
    )

    private lazy var accountLabel = UILabel.styled(
        font: AppFont.regular(11), color: UIColor(white: 0.5, alpha: 1), alignment: .center
    )

    private lazy var logoutButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Logout", for: .normal)
        btn.titleLabel?.font = AppFont.bold(11)
        btn.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var searchBar: UITextField = {
        let field = UITextField()
        field.font = AppFont.regular(14)
        field.textColor = .white
        field.tintColor = UIColor(named: "RED")
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.keyboardAppearance = .dark
        field.backgroundColor = UIColor(white: 0.1, alpha: 1)
        field.layer.cornerRadius = 8
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        field.leftViewMode = .always
        field.attributedPlaceholder = NSAttributedString(
            string: "Search apps...",
            attributes: [.foregroundColor: UIColor(white: 0.3, alpha: 1), .font: AppFont.regular(14)]
        )
        field.translatesAutoresizingMaskIntoConstraints = false
        field.delegate = self
        return field
    }()

    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorColor = UIColor(white: 0.15, alpha: 1)
        table.register(SearchResultCell.self, forCellReuseIdentifier: SearchResultCell.identifier)
        table.delegate = self
        table.dataSource = self
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = .white
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        updateAccountLabel()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func updateAccountLabel() {
        if let account = try? AppStoreService.shared.accountInfo() {
            accountLabel.text = "\(account.email) ✓"
        }
    }

    private func performSearch(_ term: String) {
        searchTask?.cancel()
        spinner.startAnimating()
        searchTask = Task { @MainActor in
            do {
                let apps = try await AppStoreService.shared.search(term: term)
                guard !Task.isCancelled else { return }
                spinner.stopAnimating()
                hasSearched = true
                results = apps
                tableView.backgroundView = apps.isEmpty ? emptyLabel : nil
                tableView.reloadData()
            } catch {
                guard !Task.isCancelled else { return }
                spinner.stopAnimating()
                showAlert(title: "Search Failed", message: error.localizedDescription)
            }
        }
    }

    @objc private func logoutTapped() {
        AppStoreService.shared.revoke()
        let nav = navigationController
        let delegate = menuDelegate
        let loginVC = AppStoreLoginViewController()
        loginVC.menuDelegate = delegate
        loginVC.onLoginSuccess = { _ in
            let searchVC = AppStoreSearchViewController()
            searchVC.menuDelegate = delegate
            nav?.setViewControllers([searchVC], animated: true)
        }
        nav?.setViewControllers([loginVC], animated: true)
    }
}

extension AppStoreSearchViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let term = textField.text, !term.isEmpty else { return false }
        textField.resignFirstResponder()
        performSearch(term)
        return true
    }
}

extension AppStoreSearchViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.identifier, for: indexPath) as! SearchResultCell
        cell.configure(with: results[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 64 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let detailVC = AppDetailViewController(app: results[indexPath.row])
        detailVC.menuDelegate = menuDelegate
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

extension AppStoreSearchViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(accountLabel)
        view.addSubview(logoutButton)
        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(spinner)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            accountLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            accountLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            logoutButton.centerYAnchor.constraint(equalTo: accountLabel.centerYAnchor),
            logoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            searchBar.topAnchor.constraint(equalTo: accountLabel.bottomAnchor, constant: 16),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchBar.heightAnchor.constraint(equalToConstant: 40),

            spinner.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor, constant: -12),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
