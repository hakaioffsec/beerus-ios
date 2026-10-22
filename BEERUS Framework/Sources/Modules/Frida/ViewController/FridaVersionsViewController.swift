import UIKit

final class FridaVersionsViewController: UIViewController {

    var viewModel: FridaVersionsViewModel!

    private let rootView = FridaVersionsView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.tableView.dataSource = self
        rootView.tableView.delegate = self
        rootView.closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        rootView.uninstallButton.addTarget(self, action: #selector(uninstallTapped), for: .touchUpInside)
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onLoading = { [weak self] loading in
            self?.rootView.setLoading(loading)
        }
        viewModel.onLoaded = { [weak self] in
            self?.rootView.showContent()
        }
        viewModel.onError = { [weak self] message in
            self?.rootView.showError(message)
        }
        viewModel.onReloadData = { [weak self] in
            self?.rootView.tableView.reloadData()
        }
        viewModel.onReloadRow = { [weak self] index in
            guard let self,
                  let cell = self.rootView.tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? FridaReleaseCell
            else { return }
            cell.updateStatus(self.viewModel.status(at: index))
        }
        viewModel.onUninstalling = { [weak self] uninstalling in
            self?.rootView.setUninstalling(uninstalling)
        }
    }
}

private extension FridaVersionsViewController {
    @objc func closeTapped() {
        viewModel.close()
    }

    @objc func uninstallTapped() {
        viewModel.tappedUninstall()
    }
}

extension FridaVersionsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfRows()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: FridaReleaseCell.identifier, for: indexPath
        ) as? FridaReleaseCell else { return UITableViewCell() }
        cell.configure(with: viewModel.release(at: indexPath.row))
        cell.updateStatus(viewModel.status(at: indexPath.row))
        return cell
    }
}

extension FridaVersionsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat { 80 }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        viewModel.didSelectRelease(at: indexPath.row)
    }
}
