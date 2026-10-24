import UIKit

final class MemoryDumpLoadingViewController: UIViewController {

    var viewModel: MemoryDumpLoadingViewModel!

    private let rootView = MemoryDumpLoadingView()

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
        viewModel.onSuccess = { [weak self] in self?.rootView.showSuccess(message: $0) }
        viewModel.onError = { [weak self] in self?.rootView.showError($0) }
    }
}

private extension MemoryDumpLoadingViewController {
    @objc func cancelTapped() {
        viewModel.cancel()
        dismiss(animated: true)
    }
}
