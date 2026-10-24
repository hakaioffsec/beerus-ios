import UIKit

final class InstalledAppsViewController: BaseViewController {

    var viewModel: InstalledAppsViewModel!

    private let rootView = InstalledAppsView()

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
        viewModel.onProgress = { [weak self] message in
            self?.rootView.showProgress(message)
        }
        viewModel.onProgressHidden = { [weak self] in
            self?.rootView.hideProgress()
        }
        viewModel.onReload = { [weak self] in
            self?.rootView.tableView.reloadData()
        }
        viewModel.onError = { [weak self] message in
            self?.showAlert(title: "Error", message: message)
        }
    }
}

extension InstalledAppsViewController: UITableViewDelegate, UITableViewDataSource {
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
