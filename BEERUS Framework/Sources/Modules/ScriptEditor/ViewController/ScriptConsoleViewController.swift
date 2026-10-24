import UIKit

final class ScriptConsoleViewController: UIViewController {

    var viewModel: ScriptConsoleViewModel!

    private let rootView = ScriptConsoleView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.isHidden = true
        rootView.backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        rootView.stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        rootView.clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        rootView.shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        bindViewModel()
        viewModel.viewDidLoad()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.viewWillDisappear()
    }

    private func bindViewModel() {
        viewModel.onStatus = { [weak self] status, title in
            self?.rootView.applyStatus(status, title: title)
        }
        viewModel.onLine = { [weak self] text, style in
            self?.rootView.append(text, style: style)
        }
        viewModel.onPID = { [weak self] text in
            self?.rootView.setPID(text)
        }
    }
}

private extension ScriptConsoleViewController {
    @objc func backTapped() {
        viewModel.tappedBack()
    }

    @objc func stopTapped() {
        viewModel.stop()
    }

    @objc func clearTapped() {
        rootView.clearOutput()
    }

    @objc func shareTapped() {
        viewModel.tappedShare(rootView.outputPlainText)
    }
}
