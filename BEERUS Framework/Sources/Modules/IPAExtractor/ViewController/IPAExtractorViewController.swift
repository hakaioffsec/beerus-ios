import UIKit

final class IPAExtractorViewController: BaseViewController {

    var viewModel: IPAExtractorViewModel!

    private let rootView = IPAExtractorView()

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

private extension IPAExtractorViewController {
    @objc func dumpButtonTapped() {
        viewModel.tappedDump()
    }
}
