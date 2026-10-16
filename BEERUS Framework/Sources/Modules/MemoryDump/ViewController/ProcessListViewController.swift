import UIKit

final class ProcessListViewController: BaseViewController {

    var viewModel: ProcessListViewModel!

    private let rootView = ProcessListView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.tableView.dataSource = self
        rootView.tableView.delegate = self
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onLoadingStateChange = { [weak self] isLoading in
            if isLoading {
                self?.rootView.activityIndicator.startAnimating()
                self?.rootView.emptyLabel.isHidden = true
            } else {
                self?.rootView.activityIndicator.stopAnimating()
            }
        }
        viewModel.onAppsLoaded = { [weak self] isEmpty in
            self?.rootView.tableView.reloadData()
            self?.rootView.emptyLabel.isHidden = !isEmpty
        }
        viewModel.onError = { [weak self] message in
            self?.showAlert(title: "Error", message: message)
        }
    }
}

extension ProcessListViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfRows()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AppCell.identifier, for: indexPath) as! AppCell
        cell.configure(with: viewModel.app(at: indexPath.row))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        viewModel.didSelectApp(at: indexPath.row)
    }
}
