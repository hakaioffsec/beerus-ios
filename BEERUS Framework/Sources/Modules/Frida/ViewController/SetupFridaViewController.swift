import UIKit

final class SetupFridaViewController: BaseViewController {

    var viewModel: SetupFridaViewModel!

    private let rootView = SetupFridaView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.buttonStart.addTarget(self, action: #selector(toggleFrida), for: .touchUpInside)
        rootView.onSelectVersion = { [weak self] version in
            self?.viewModel.selectVersion(version)
        }
        rootView.onAddManually = { [weak self] in
            self?.viewModel.addVersionManually()
        }
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onStatus = { [weak self] status in
            self?.rootView.setStatus(
                statusText: status.statusText,
                versionText: status.versionText,
                startTitle: status.startTitle
            )
        }
        viewModel.onVersions = { [weak self] versions in
            self?.rootView.setVersions(versions)
        }
        viewModel.onSelectedVersionTitle = { [weak self] title in
            self?.rootView.setSelectedVersionTitle(title)
            self?.rootView.dismissDropdown()
        }
        viewModel.onStartEnabled = { [weak self] enabled in
            self?.rootView.setStartEnabled(enabled)
        }
        viewModel.onProgress = { [weak self] text, fraction in
            self?.rootView.showProgress(text, fraction: fraction)
        }
        viewModel.onHideProgress = { [weak self] in
            self?.rootView.hideProgress()
        }
    }
}

private extension SetupFridaViewController {
    @objc func toggleFrida() {
        viewModel.toggleFrida()
    }
}
