import UIKit

final class SandboxExfiltrationViewController: BaseViewController {

    private let appManager = AppManager()

    private var apps: [(bundleId: String, info: AppManager.AppInfo)] = []
    private var filteredApps: [(bundleId: String, info: AppManager.AppInfo)] = []

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

    private lazy var searchTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "Search applications"
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

        textField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)

        return textField
    }()

    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.showsVerticalScrollIndicator = false
        table.register(
            SandboxExfiltrationAppCell.self,
            forCellReuseIdentifier: "SandboxExfiltrationAppCell"
        )
        return table
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        apps = appManager
            .getApps()
            .map { ($0.key, $0.value) }
            .sorted { $0.info.name.lowercased() < $1.info.name.lowercased() }

        filteredApps = apps

        applyViewCode()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func searchChanged() {
        let text = searchTextField.text?.lowercased() ?? ""

        if text.isEmpty {
            filteredApps = apps
        } else {
            filteredApps = apps.filter {
                $0.info.name.lowercased().contains(text) ||
                $0.bundleId.lowercased().contains(text)
            }
        }

        tableView.reloadData()
    }
}

// MARK: - ViewCode

extension SandboxExfiltrationViewController: ViewCode {

    func buildViewHierarchy() {
        view.addSubview(titleLabel)

        view.addSubview(circuitTopImageView)
        view.addSubview(circuitRightImageView)
        view.addSubview(circuitLeftImageView)
        view.addSubview(circuitLeftDownImageView)

        view.addSubview(bottomPanelView)

        bottomPanelView.addSubview(storageLabel)
        bottomPanelView.addSubview(searchTextField)
        bottomPanelView.addSubview(tableView)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([

            titleLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 20
            ),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            circuitTopImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitTopImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),

            circuitRightImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitRightImageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            circuitRightImageView.widthAnchor.constraint(equalToConstant: 40),
            circuitRightImageView.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor),

            circuitLeftImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitLeftImageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),

            circuitLeftDownImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            circuitLeftDownImageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),

            bottomPanelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomPanelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomPanelView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomPanelView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.80),

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

// MARK: - UITableView

extension SandboxExfiltrationViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        filteredApps.count
    }

    func tableView(
        _ tableView: UITableView,
        heightForRowAt indexPath: IndexPath
    ) -> CGFloat {
        72
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {

        let cell = tableView.dequeueReusableCell(
            withIdentifier: "SandboxExfiltrationAppCell",
            for: indexPath
        ) as! SandboxExfiltrationAppCell

        let app = filteredApps[indexPath.row]

        cell.nameLabel.text = app.info.name
        cell.bundleLabel.text = app.bundleId

        if !app.info.icone.isEmpty,
           let image = UIImage(contentsOfFile: app.info.icone) {
            cell.iconView.image = image
        } else {
            cell.iconView.image = UIImage(systemName: "app.fill")
        }

        return cell
    }

    func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        let app = filteredApps[indexPath.row]

        let detailVC = SandboxExfiltrationAppDetailViewController(
            appInfo: app.info,
            bundleId: app.bundleId
        )

        if let sheet = detailVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = false
            sheet.preferredCornerRadius = 20
        }

        present(detailVC, animated: true)
    }
}
