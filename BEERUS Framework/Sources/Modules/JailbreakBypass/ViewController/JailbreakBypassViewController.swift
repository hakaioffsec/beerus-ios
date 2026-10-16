import UIKit

final class JailbreakBypassViewController: BaseViewController {

    private enum Constants {
        static let cellIdentifier = "AppCell"
    }

    var viewModel: JailbreakBypassViewModel!

    private let rootView = JailbreakBypassView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.tableView.dataSource = self
        rootView.tableView.delegate = self
        rootView.tableView.register(UITableViewCell.self, forCellReuseIdentifier: Constants.cellIdentifier)
        rootView.searchBar.delegate = self
        rootView.versionButton.addTarget(self, action: #selector(versionTapped), for: .touchUpInside)
        rootView.installButton.addTarget(self, action: #selector(installTapped), for: .touchUpInside)
        rootView.respringButton.addTarget(self, action: #selector(respringTapped), for: .touchUpInside)
        bindViewModel()
        viewModel.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.viewWillAppear()
    }

    private func bindViewModel() {
        viewModel.onState = { [weak self] state in
            self?.rootView.apply(state)
        }
        viewModel.onVersionTitle = { [weak self] title in
            self?.rootView.setVersionTitle(title)
        }
        viewModel.onVersionEnabled = { [weak self] enabled in
            self?.rootView.setVersionEnabled(enabled)
        }
        viewModel.onStatusText = { [weak self] text in
            self?.rootView.setStatusText(text)
        }
        viewModel.onInstallingChange = { [weak self] installing in
            self?.rootView.setInstalling(installing)
        }
        viewModel.onReload = { [weak self] in
            self?.rootView.tableView.reloadData()
        }
        viewModel.onRowUpdated = { [weak self] index in
            self?.rootView.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
        }
        viewModel.onError = { [weak self] message in
            self?.showAlert(title: "Error", message: message)
        }
    }
}

private extension JailbreakBypassViewController {
    @objc func versionTapped() {
        viewModel.tappedVersion()
    }

    @objc func installTapped() {
        viewModel.tappedInstall()
    }

    @objc func respringTapped() {
        viewModel.tappedRespring()
    }

    @objc func appToggleChanged(_ sender: UISwitch) {
        viewModel.toggleApp(at: sender.tag)
    }
}

extension JailbreakBypassViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfRows()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellIdentifier, for: indexPath)
        let app = viewModel.app(at: indexPath.row)

        cell.backgroundColor = UIColor(named: "ContainerBackground")
        cell.selectionStyle = .none
        cell.textLabel?.textColor = .label
        cell.textLabel?.font = AppFont.regular(15)
        cell.textLabel?.text = app.name

        let toggle = (cell.accessoryView as? UISwitch) ?? UISwitch()
        toggle.isOn = app.isEnabled
        toggle.onTintColor = .systemGreen
        toggle.tag = indexPath.row
        toggle.removeTarget(nil, action: nil, for: .valueChanged)
        toggle.addTarget(self, action: #selector(appToggleChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle

        return cell
    }
}

extension JailbreakBypassViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange text: String) {
        viewModel.search(text)
    }
}
