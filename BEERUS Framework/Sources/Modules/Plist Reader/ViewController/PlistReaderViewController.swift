import UIKit

final class PlistReaderViewController: BaseViewController {

    var viewModel: PlistReaderViewModel!

    private let rootView = PlistReaderView()

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
        viewModel.onReload = { [weak self] in
            self?.rootView.tableView.reloadData()
        }
    }
}

extension PlistReaderViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfRows()
    }
}

extension PlistReaderViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: PlistReaderView.cellReuseIdentifier,
            for: indexPath
        ) as? PlistReaderResultCell else {
            return PlistReaderResultCell(style: .default, reuseIdentifier: PlistReaderView.cellReuseIdentifier)
        }

        if viewModel.numberOfRows() > 0 {
            cell.setupInfos(package: viewModel.package(at: indexPath.row), apps: viewModel.apps)
        }

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 110
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        viewModel.didSelectRow(at: indexPath.row)
    }
}
