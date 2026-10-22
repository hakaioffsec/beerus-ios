import UIKit

final class SandboxExfiltrationViewController: BaseViewController {

    var viewModel: SandboxExfiltrationViewModel!

    private let rootView = SandboxExfiltrationView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.tableView.dataSource = self
        rootView.tableView.delegate = self
        rootView.searchTextField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onReload = { [weak self] in
            self?.rootView.tableView.reloadData()
        }
    }
}

private extension SandboxExfiltrationViewController {
    @objc func searchChanged() {
        viewModel.search(rootView.searchTextField.text ?? "")
    }
}

extension SandboxExfiltrationViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfRows()
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        72
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "SandboxExfiltrationAppCell",
            for: indexPath
        ) as! SandboxExfiltrationAppCell

        let app = viewModel.app(at: indexPath.row)

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

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        viewModel.didSelectApp(at: indexPath.row)
    }
}
