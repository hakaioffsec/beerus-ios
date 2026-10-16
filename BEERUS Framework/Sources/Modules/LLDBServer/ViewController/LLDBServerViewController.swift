import UIKit

final class LLDBServerViewController: BaseViewController {

    var viewModel: LLDBServerViewModel!

    private let rootView = LLDBServerView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        rootView.uninstallButton.addTarget(self, action: #selector(uninstallTapped), for: .touchUpInside)
        rootView.copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        bindViewModel()
        viewModel.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.viewWillAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.viewWillDisappear()
    }

    private func bindViewModel() {
        viewModel.onPresentation = { [weak self] presentation in
            self?.rootView.apply(presentation)
        }
        viewModel.onProgress = { [weak self] value, text, palette in
            self?.rootView.setProgress(value, text: text, palette: palette)
        }
        viewModel.onFeedback = { [weak self] text, palette in
            self?.rootView.setFeedback(text, palette: palette)
        }
        viewModel.onConsoleReset = { [weak self] in
            self?.rootView.resetConsole()
        }
        viewModel.onConsoleAppend = { [weak self] text in
            self?.rootView.appendConsole(text)
        }
        viewModel.onServerDied = { [weak self] path in
            self?.rootView.renderServerDied(path: path)
        }
        viewModel.onActionEnabled = { [weak self] enabled in
            self?.rootView.setActionEnabled(enabled)
        }
        viewModel.onError = { [weak self] message in
            self?.showAlert(title: "Error", message: message)
        }
    }
}

private extension LLDBServerViewController {
    @objc func actionTapped() {
        viewModel.tappedAction()
    }

    @objc func uninstallTapped() {
        viewModel.tappedUninstall()
    }

    @objc func copyTapped() {
        rootView.copyCurrentCommand()
    }
}
