import UIKit

final class ScriptListView: UIView {

    private lazy var titleLabel = UILabel.styled(
        text: "FRIDA SCRIPTS",
        font: AppFont.bold(14),
        alignment: .center
    )

    let newButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "plus.circle.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.tintColor = UIColor(named: "RED")
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    let searchBar: UITextField = {
        let f = UITextField()
        f.font = AppFont.regular(12)
        f.textColor = .white
        f.tintColor = UIColor(named: "RED")
        f.keyboardAppearance = .dark
        f.autocapitalizationType = .none
        f.autocorrectionType = .no
        f.returnKeyType = .search
        f.attributedPlaceholder = NSAttributedString(
            string: "Search scripts...",
            attributes: [
                .foregroundColor: UIColor(white: 0.3, alpha: 1),
                .font: AppFont.regular(12),
            ]
        )
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = UIColor(white: 0.3, alpha: 1)
        icon.frame = CGRect(x: 0, y: 0, width: 28, height: 20)
        icon.contentMode = .scaleAspectFit
        f.leftView = icon
        f.leftViewMode = .always
        f.backgroundColor = UIColor(named: "ContainerBackground")
        f.layer.cornerRadius = 8
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 8, height: 1))
        f.rightView = paddingView
        f.rightViewMode = .always
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }()

    let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.backgroundColor = .clear
        tv.separatorStyle = .none
        tv.showsVerticalScrollIndicator = false
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(ScriptCell.self, forCellReuseIdentifier: ScriptCell.reuseId)
        return tv
    }()

    private let emptyLabel: UILabel = {
        let l = UILabel()
        l.text = "No scripts yet.\nTap + to create one."
        l.font = AppFont.regular(13)
        l.textColor = UIColor(white: 0.35, alpha: 1)
        l.numberOfLines = 0
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setEmpty(_ isEmpty: Bool) {
        emptyLabel.isHidden = !isEmpty
    }
}

extension ScriptListView: ViewCode {
    func buildViewHierarchy() {
        addSubview(titleLabel)
        addSubview(newButton)
        addSubview(searchBar)
        addSubview(tableView)
        addSubview(emptyLabel)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 56),

            newButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            newButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            newButton.widthAnchor.constraint(equalToConstant: 32),
            newButton.heightAnchor.constraint(equalToConstant: 32),

            searchBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            searchBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            searchBar.heightAnchor.constraint(equalToConstant: 36),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])
    }
}
