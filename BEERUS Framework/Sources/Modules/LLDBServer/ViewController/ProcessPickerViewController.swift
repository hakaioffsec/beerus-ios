import UIKit

final class ProcessPickerViewController: UITableViewController, UISearchResultsUpdating {

    var viewModel: ProcessPickerViewModel!

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Select Process"
        view.backgroundColor = UIColor(named: "Background") ?? UIColor(white: 0.05, alpha: 1)
        tableView.backgroundColor = view.backgroundColor
        tableView.separatorColor = UIColor(white: 0.15, alpha: 1)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(dismissPicker))

        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Filter processes..."
        search.searchBar.barStyle = .black
        navigationItem.searchController = search
        definesPresentationContext = true

        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onReload = { [weak self] in
            self?.tableView.reloadData()
        }
    }

    @objc private func dismissPicker() {
        dismiss(animated: true)
    }

    func updateSearchResults(for searchController: UISearchController) {
        viewModel.filter(searchController.searchBar.text ?? "")
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfRows()
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let process = viewModel.process(at: indexPath.row)

        var content = cell.defaultContentConfiguration()
        content.text = process.name
        content.secondaryText = "PID \(process.pid)"
        content.textProperties.font = AppFont.regular(14)
        content.secondaryTextProperties.font = AppFont.regular(11)
        content.textProperties.color = .white
        content.secondaryTextProperties.color = UIColor(white: 0.4, alpha: 1)
        cell.contentConfiguration = content
        cell.backgroundColor = .clear

        let bgView = UIView()
        bgView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        cell.selectedBackgroundView = bgView

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        dismiss(animated: true) { [weak self] in
            self?.viewModel.selectProcess(at: indexPath.row)
        }
    }
}
