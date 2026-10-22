import UIKit

final class AppPickerViewController: UIViewController {

    var viewModel: AppPickerViewModel!

    private let rootView = AppPickerView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.tableView.dataSource = self
        rootView.tableView.delegate = self
        rootView.searchBar.delegate = self
        rootView.cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onLoadingChange = { [weak self] loading in
            self?.rootView.setLoading(loading)
        }
        viewModel.onReload = { [weak self] in
            guard let self else { return }
            self.rootView.tableView.reloadData()
            self.rootView.setTitle(self.viewModel.titleText)
            self.rootView.setEmpty(self.viewModel.emptyText)
        }
    }
}

private extension AppPickerViewController {
    @objc func cancelTapped() {
        viewModel.cancel()
    }
}

extension AppPickerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfRows()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: AppPickerCell.id, for: indexPath) as? AppPickerCell else {
            return UITableViewCell()
        }
        cell.configure(with: viewModel.app(at: indexPath.row))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        viewModel.didSelect(at: indexPath.row)
    }
}

extension AppPickerViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        viewModel.search(searchText)
    }
}
