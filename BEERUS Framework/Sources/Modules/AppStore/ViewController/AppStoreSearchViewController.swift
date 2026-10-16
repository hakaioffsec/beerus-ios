import UIKit

final class AppStoreSearchViewController: BaseViewController {

    var viewModel: AppStoreSearchViewModel!

    private let rootView = AppStoreSearchView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.searchBar.delegate = self
        rootView.tableView.dataSource = self
        rootView.tableView.delegate = self
        rootView.logoutButton.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onAccount = { [weak self] text in
            self?.rootView.accountLabel.text = text
        }
        viewModel.onLoading = { [weak self] isLoading in
            if isLoading {
                self?.rootView.spinner.startAnimating()
            } else {
                self?.rootView.spinner.stopAnimating()
            }
        }
        viewModel.onResults = { [weak self] isEmpty in
            guard let self else { return }
            self.rootView.tableView.backgroundView = isEmpty ? self.rootView.emptyLabel : nil
            self.rootView.tableView.reloadData()
        }
        viewModel.onError = { [weak self] message in
            self?.showAlert(title: "Search Failed", message: message)
        }
    }
}

private extension AppStoreSearchViewController {
    @objc func logoutTapped() {
        viewModel.tappedLogout()
    }
}

extension AppStoreSearchViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let term = textField.text, !term.isEmpty else { return false }
        textField.resignFirstResponder()
        viewModel.search(term)
        return true
    }
}

extension AppStoreSearchViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfRows()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.identifier, for: indexPath) as! SearchResultCell
        cell.configure(with: viewModel.app(at: indexPath.row))
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 64 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        viewModel.didSelectApp(at: indexPath.row)
    }
}
