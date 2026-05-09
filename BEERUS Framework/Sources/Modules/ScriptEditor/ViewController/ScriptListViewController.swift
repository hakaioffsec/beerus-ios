import UIKit

final class ScriptListViewController: BaseViewController {

    // MARK: - UI

    private lazy var titleLabel = UILabel.styled(
        text: "FRIDA SCRIPTS", font: AppFont.bold(14), alignment: .center
    )

    private lazy var newButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "plus.circle.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.tintColor = UIColor(named: "RED")
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(newScriptTapped), for: .touchUpInside)
        return btn
    }()

    private let searchBar: UITextField = {
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

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.backgroundColor = .clear
        tv.separatorStyle = .none
        tv.showsVerticalScrollIndicator = false
        tv.translatesAutoresizingMaskIntoConstraints = false
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

    // MARK: - Data

    private let storage = ScriptStorageService.shared
    private var allScripts: [FridaScriptModel] = []
    private var filteredScripts: [FridaScriptModel] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ScriptCell.self, forCellReuseIdentifier: ScriptCell.reuseId)
        searchBar.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    // MARK: - Data

    private func reload() {
        allScripts = storage.loadAll()
        applyFilter()
    }

    private func applyFilter() {
        var scripts = allScripts

        // Search filter
        if let query = searchBar.text?.lowercased(), !query.isEmpty {
            scripts = scripts.filter {
                $0.name.lowercased().contains(query) ||
                $0.source.lowercased().contains(query)
            }
        }

        filteredScripts = scripts
        tableView.reloadData()
        emptyLabel.isHidden = !filteredScripts.isEmpty
    }

    // MARK: - Actions

    @objc private func newScriptTapped() {
        showNewScriptDialog()
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    // MARK: - New Script Dialog

    private func showNewScriptDialog() {
        let autoName = storage.nextAutoName()

        let alert = UIAlertController(title: "New Script", message: nil, preferredStyle: .alert)
        alert.overrideUserInterfaceStyle = .dark
        alert.addTextField { field in
            field.placeholder = autoName
            field.autocapitalizationType = .words
            field.font = AppFont.regular(14)
        }

        alert.addAction(UIAlertAction(title: "Empty Script", style: .default) { [weak self] _ in
            let raw = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = raw.isEmpty ? autoName : raw
            let script = FridaScriptModel(name: name, source: "// \(name)\n\n")
            self?.storage.save(script)
            self?.openEditor(for: script)
        })

        alert.addAction(UIAlertAction(title: "From Template", style: .default) { [weak self] _ in
            let raw = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = raw.isEmpty ? autoName : raw
            self?.showTemplatePicker(named: name)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func showTemplatePicker(named name: String) {
        let picker = UIAlertController(title: "Choose Template", message: nil, preferredStyle: .actionSheet)
        picker.overrideUserInterfaceStyle = .dark

        for (title, source) in ScriptTemplates.all {
            picker.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                let script = FridaScriptModel(name: name, source: source)
                self?.storage.save(script)
                self?.openEditor(for: script)
            })
        }

        picker.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = picker.popoverPresentationController {
            pop.sourceView = newButton
            pop.sourceRect = newButton.bounds
        }
        present(picker, animated: true)
    }

    private func openEditor(for script: FridaScriptModel) {
        let editor = ScriptEditorViewController(script: script)
        navigationController?.pushViewController(editor, animated: true)
    }
}

// MARK: - ViewCode

extension ScriptListViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(newButton)
        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 56),

            newButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            newButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            newButton.widthAnchor.constraint(equalToConstant: 32),
            newButton.heightAnchor.constraint(equalToConstant: 32),

            searchBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchBar.heightAnchor.constraint(equalToConstant: 36),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: tableView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableView.centerYAnchor),
        ])
    }
}

// MARK: - UITableViewDataSource & Delegate

extension ScriptListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredScripts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ScriptCell.reuseId, for: indexPath) as? ScriptCell else {
            return UITableViewCell()
        }
        cell.configure(with: filteredScripts[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        78
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        openEditor(for: filteredScripts[indexPath.row])
    }

    func tableView(_ tableView: UITableView,
                    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        let script = filteredScripts[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.storage.delete(script)
            self?.reload()
            done(true)
        }
        delete.image = UIImage(systemName: "trash")

        let duplicate = UIContextualAction(style: .normal, title: "Copy") { [weak self] _, _, done in
            _ = self?.storage.duplicate(script)
            self?.reload()
            done(true)
        }
        duplicate.backgroundColor = UIColor(white: 0.25, alpha: 1)
        duplicate.image = UIImage(systemName: "doc.on.doc")

        return UISwipeActionsConfiguration(actions: [delete, duplicate])
    }
}
