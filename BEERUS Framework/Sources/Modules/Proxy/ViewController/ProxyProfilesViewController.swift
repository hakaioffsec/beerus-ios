import UIKit

final class ProxyProfilesViewController: BaseViewController {

    var viewModel: ProxyProfilesViewModel!

    private let rootView = ProxyProfilesView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.addProfileButton.addTarget(self, action: #selector(addProfileTapped), for: .touchUpInside)
        rootView.onToggle = { [weak self] index, isOn in
            self?.viewModel.toggle(at: index, isOn: isOn)
        }
        rootView.onDelete = { [weak self] index in
            self?.viewModel.delete(at: index)
        }
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onProfilesChanged = { [weak self] profiles in
            self?.rootView.render(profiles)
        }
        viewModel.onError = { [weak self] message in
            self?.showAlert(title: "Erro", message: message)
        }
    }
}

private extension ProxyProfilesViewController {
    @objc func addProfileTapped() {
        viewModel.tappedAddProfile()
    }
}
