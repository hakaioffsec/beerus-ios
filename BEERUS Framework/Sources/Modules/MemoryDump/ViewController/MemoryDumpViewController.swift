import UIKit

final class MemoryDumpViewController: BaseViewController {

    var viewModel: MemoryDumpViewModel!

    private let rootView = MemoryDumpView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.dumpButton.addTarget(self, action: #selector(dumpButtonTapped), for: .touchUpInside)
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onState = { [weak self] state in
            self?.rootView.statusLabel.text = state.statusText
            self?.rootView.dumpButton.setTitle(state.buttonTitle, for: .normal)
            self?.rootView.dumpButton.isEnabled = state.isDumpEnabled
            self?.rootView.dumpButton.alpha = state.isDumpEnabled ? 1.0 : 0.5
        }
    }
}

private extension MemoryDumpViewController {
    @objc func dumpButtonTapped() {
        viewModel.tappedDump()
    }
}
