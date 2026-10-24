import UIKit

final class ScriptListViewController: BaseViewController {

    var viewModel: ScriptListViewModel!

    private let rootView = ScriptListView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.tableView.dataSource = self
        rootView.tableView.delegate = self
        rootView.newButton.addTarget(self, action: #selector(newScriptTapped), for: .touchUpInside)
        rootView.searchBar.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        bindViewModel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.viewWillAppear()
    }

    private func bindViewModel() {
        viewModel.onReload = { [weak self] in
            guard let self else { return }
            self.rootView.tableView.reloadData()
            self.rootView.setEmpty(self.viewModel.isEmpty)
        }
    }
}

private extension ScriptListViewController {
    @objc func newScriptTapped() {
        viewModel.tappedNew()
    }

    @objc func searchChanged() {
        viewModel.search(rootView.searchBar.text ?? "")
    }
}

extension ScriptListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfRows()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ScriptCell.reuseId, for: indexPath) as? ScriptCell else {
            return UITableViewCell()
        }
        cell.configure(with: viewModel.script(at: indexPath.row))
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        78
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        viewModel.didSelect(at: indexPath.row)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.viewModel.delete(at: indexPath.row)
            done(true)
        }
        delete.image = UIImage(systemName: "trash")

        let duplicate = UIContextualAction(style: .normal, title: "Copy") { [weak self] _, _, done in
            self?.viewModel.duplicate(at: indexPath.row)
            done(true)
        }
        duplicate.backgroundColor = UIColor(white: 0.25, alpha: 1)
        duplicate.image = UIImage(systemName: "doc.on.doc")

        return UISwipeActionsConfiguration(actions: [delete, duplicate])
    }
}
