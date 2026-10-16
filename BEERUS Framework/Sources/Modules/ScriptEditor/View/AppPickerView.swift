import UIKit

final class AppPickerView: UIView {

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

    let cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Cancel", for: .normal)
        btn.titleLabel?.font = AppFont.regular(14)
        btn.setTitleColor(UIColor(named: "RED"), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    let searchBar: UISearchBar = {
        let sb = UISearchBar()
        sb.placeholder = "Search apps…"
        sb.searchBarStyle = .minimal
        sb.barStyle = .black
        sb.tintColor = UIColor(named: "RED")
        sb.translatesAutoresizingMaskIntoConstraints = false

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

    let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.backgroundColor = UIColor(named: "Background")
        tv.separatorColor = UIColor(white: 0.15, alpha: 1)
        tv.rowHeight = 56
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
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ text: String) {
        titleLabel.text = text
    }

    func setLoading(_ loading: Bool) {
        if loading {
            spinner.startAnimating()
            tableView.isHidden = true
            emptyLabel.isHidden = true
        } else {
            spinner.stopAnimating()
        }
    }

    func setEmpty(_ text: String?) {
        if let text {
            emptyLabel.text = text
            emptyLabel.isHidden = false
            tableView.isHidden = true
        } else {
            emptyLabel.isHidden = true
            tableView.isHidden = false
        }
    }

    private func buildUI() {
        addSubview(topBar)
        topBar.addSubview(titleLabel)
        topBar.addSubview(cancelButton)
        addSubview(searchBar)
        addSubview(tableView)
        addSubview(spinner)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 48),

            cancelButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            searchBar.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])
    }
}

final class AppPickerCell: UITableViewCell {

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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with app: AppModel) {
        nameLabel.text = app.name
        detailLabel.text = app.bundleIdentifier
        pidBadge.text = "PID \(app.pid)"
    }
}
