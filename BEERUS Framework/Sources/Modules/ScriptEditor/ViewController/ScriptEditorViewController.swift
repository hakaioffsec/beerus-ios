import UIKit

final class ScriptEditorViewController: UIViewController {

    var viewModel: ScriptEditorViewModel!

    private let rootView = ScriptEditorView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.isHidden = true
        rootView.backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        rootView.moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        rootView.saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        rootView.runButton.addTarget(self, action: #selector(runTapped), for: .touchUpInside)
        rootView.onTextChange = { [weak self] text in
            self?.viewModel.textChanged(text)
        }
        bindViewModel()
        viewModel.viewDidLoad()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.viewWillDisappear()
    }

    private func bindViewModel() {
        viewModel.onName = { [weak self] name in
            self?.rootView.setName(name)
        }
        viewModel.onCode = { [weak self] source in
            self?.rootView.setCode(source)
        }
        viewModel.onUnsaved = { [weak self] unsaved in
            self?.rootView.setUnsaved(unsaved)
        }
        viewModel.onCharCount = { [weak self] text in
            self?.rootView.setCharCount(text)
        }
        viewModel.onSaved = { [weak self] in
            self?.rootView.showSavedFeedback()
        }
    }
}

private extension ScriptEditorViewController {
    @objc func backTapped() {
        viewModel.tappedBack()
    }

    @objc func moreTapped() {
        viewModel.tappedMore()
    }

    @objc func saveTapped() {
        viewModel.tappedSave()
    }

    @objc func runTapped() {
        viewModel.tappedRun()
    }
}
