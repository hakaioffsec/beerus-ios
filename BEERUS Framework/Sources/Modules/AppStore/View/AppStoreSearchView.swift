import UIKit

final class AppStoreSearchView: UIView {

    let emptyLabel: UILabel = {
        let label = UILabel()
        label.text = "No results"
        label.font = AppFont.regular(16)
        label.textColor = UIColor(white: 0.4, alpha: 1)
        label.textAlignment = .center
        return label
    }()

    private let titleLabel = UILabel.styled(
        text: "App Store",
        font: AppFont.bold(20),
        alignment: .center
    )

    let accountLabel = UILabel.styled(
        font: AppFont.regular(11),
        color: UIColor(white: 0.5, alpha: 1),
        alignment: .center
    )

    let logoutButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Logout", for: .normal)
        btn.titleLabel?.font = AppFont.bold(11)
        btn.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    let searchBar: UITextField = {
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
        return field
    }()

    let tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorColor = UIColor(white: 0.15, alpha: 1)
        table.register(SearchResultCell.self, forCellReuseIdentifier: SearchResultCell.identifier)
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = .white
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func dismissKeyboard() {
        endEditing(true)
    }
}

extension AppStoreSearchView: ViewCode {
    func buildViewHierarchy() {
        addSubview(titleLabel)
        addSubview(accountLabel)
        addSubview(logoutButton)
        addSubview(searchBar)
        addSubview(tableView)
        addSubview(spinner)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            accountLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            accountLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            logoutButton.centerYAnchor.constraint(equalTo: accountLabel.centerYAnchor),
            logoutButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            searchBar.topAnchor.constraint(equalTo: accountLabel.bottomAnchor, constant: 16),
            searchBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            searchBar.heightAnchor.constraint(equalToConstant: 40),

            spinner.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor, constant: -12),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
