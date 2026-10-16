import UIKit

final class DownloadViewController: BaseViewController {

    var viewModel: DownloadViewModel!

    private let rootView = DownloadView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.configure(
            name: viewModel.nameText,
            bundle: viewModel.bundleText,
            isSpecificVersion: viewModel.isSpecificVersion
        )
        rootView.onShare = { [weak self] in self?.viewModel.tappedShare() }
        rootView.onFiles = { [weak self] in self?.viewModel.tappedFiles() }
        rootView.onRetry = { [weak self] in self?.viewModel.retry() }
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onIcon = { [weak self] data in
            self?.rootView.setIcon(data)
        }
        viewModel.onStep = { [weak self] index, status in
            self?.rootView.setStep(index, status: status)
        }
        viewModel.onProgress = { [weak self] pct, text in
            self?.rootView.setProgress(pct, text: text)
        }
        viewModel.onComplete = { [weak self] in
            self?.rootView.showComplete()
        }
        viewModel.onError = { [weak self] message in
            self?.rootView.showError(message)
        }
        viewModel.onPrepareRetry = { [weak self] in
            self?.rootView.prepareForRetry()
        }
    }
}
