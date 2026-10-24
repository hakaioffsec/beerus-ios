import UIKit

final class VersionListViewController: BaseViewController {

    var viewModel: VersionListViewModel!

    private let rootView = VersionListView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.setTitle(viewModel.titleText)
        rootView.tableView.dataSource = self
        rootView.tableView.delegate = self
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onLoading = { [weak self] isLoading in
            if isLoading {
                self?.rootView.spinner.startAnimating()
            } else {
                self?.rootView.spinner.stopAnimating()
            }
        }
        viewModel.onReload = { [weak self] in
            self?.rootView.tableView.reloadData()
        }
        viewModel.onRowUpdated = { [weak self] index in
            guard let self else { return }
            let indexPath = IndexPath(row: index, section: 0)
            if self.rootView.tableView.indexPathsForVisibleRows?.contains(indexPath) == true {
                self.rootView.tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
        viewModel.onError = { [weak self] message in
            self?.showAlert(title: "Error", message: message)
        }
    }
}

extension VersionListViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfRows()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VersionCell.identifier, for: indexPath) as! VersionCell
        cell.configure(
            versionID: viewModel.versionID(at: indexPath.row),
            metadata: viewModel.metadata(at: indexPath.row),
            isLatest: viewModel.isLatest(at: indexPath.row)
        )
        cell.onGetTapped = { [weak self] in
            self?.viewModel.didTapGet(at: indexPath.row)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 60 }
}
