import UIKit

final class LoadingViewController: UIViewController {

    var viewModel: IPADumpLoadingViewModel!

    private let rootView = IPALoadingView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onPhase = { [weak self] in self?.rootView.updatePhase($0) }
        viewModel.onLog = { [weak self] in self?.rootView.addLog($0) }
        viewModel.onProgress = { [weak self] current, total in self?.rootView.updateProgress(current, total: total) }
        viewModel.onSuccess = { [weak self] in self?.rootView.showSuccess() }
        viewModel.onError = { [weak self] in self?.rootView.showError($0) }
    }
}

private extension LoadingViewController {
    @objc func cancelTapped() {
        viewModel.cancel()
        dismiss(animated: true)
    }
}
