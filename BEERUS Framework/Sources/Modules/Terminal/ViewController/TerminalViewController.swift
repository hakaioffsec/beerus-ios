import UIKit

final class TerminalViewController: BaseViewController {

    var viewModel: TerminalViewModel!

    private let rootView = TerminalView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.inputField.delegate = self
        rootView.sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        rootView.clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        bindViewModel()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.endEditing(true)
    }

    private func bindViewModel() {
        viewModel.onOutput = { [weak self] text, style in
            self?.rootView.append(text, style: style)
        }
        viewModel.onClearInput = { [weak self] in
            self?.rootView.clearInput()
        }
        viewModel.onExecutingChange = { [weak self] executing in
            self?.rootView.setExecuting(executing)
        }
        viewModel.onShowHelp = { [weak self] in
            self?.rootView.showHelp()
        }
        viewModel.onClear = { [weak self] in
            self?.rootView.clear()
        }
    }
}

private extension TerminalViewController {
    @objc func sendTapped() {
        viewModel.submit(rootView.currentInput)
    }

    @objc func clearTapped() {
        viewModel.tappedClear()
    }
}

extension TerminalViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        viewModel.submit(rootView.currentInput)
        return false
    }
}
