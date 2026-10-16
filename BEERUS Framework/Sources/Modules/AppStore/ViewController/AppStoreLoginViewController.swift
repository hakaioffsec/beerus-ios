import UIKit

final class AppStoreLoginViewController: BaseViewController {

    var viewModel: AppStoreLoginViewModel!

    private let rootView = AppStoreLoginView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.emailField.delegate = self
        rootView.passwordField.delegate = self
        rootView.suggestionsTable.dataSource = self
        rootView.suggestionsTable.delegate = self
        rootView.signInButton.addTarget(self, action: #selector(signInTapped), for: .touchUpInside)
        rootView.emailField.addTarget(self, action: #selector(emailFieldChanged), for: .editingChanged)
        rootView.onCopyCommand = { [weak self] in
            guard let self else { return }
            UIPasteboard.general.string = self.viewModel.mfaCommand
            self.rootView.confirmCopy()
        }
        rootView.onCancelMFA = { [weak self] in
            self?.viewModel.cancelMFA()
        }
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onLoading = { [weak self] loading in
            self?.rootView.setLoading(loading)
        }
        viewModel.onStatus = { [weak self] text, style in
            self?.rootView.setStatus(text, style: style)
        }
        viewModel.onShowMFA = { [weak self] command in
            self?.rootView.showMFA(command: command)
        }
        viewModel.onHideMFA = { [weak self] in
            self?.rootView.hideMFA()
        }
        viewModel.onMFATimer = { [weak self] text in
            self?.rootView.setMFATimer(text)
        }
        viewModel.onSuggestionsChanged = { [weak self] in
            guard let self else { return }
            self.rootView.setSuggestionsHidden(self.viewModel.numberOfSuggestions() == 0)
            self.rootView.suggestionsTable.reloadData()
        }
    }
}

private extension AppStoreLoginViewController {
    @objc func signInTapped() {
        viewModel.signIn(email: rootView.emailField.text, password: rootView.passwordField.text)
    }

    @objc func emailFieldChanged() {
        viewModel.emailChanged(rootView.emailField.text)
    }
}

extension AppStoreLoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == rootView.emailField {
            rootView.passwordField.becomeFirstResponder()
            rootView.setSuggestionsHidden(true)
        } else if textField == rootView.passwordField {
            textField.resignFirstResponder()
            signInTapped()
        }
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        if textField == rootView.emailField {
            emailFieldChanged()
        }
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField == rootView.emailField {
            rootView.setSuggestionsHidden(true)
        }
    }
}

extension AppStoreLoginViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.numberOfSuggestions()
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SuggestionCell", for: indexPath)
        cell.textLabel?.text = viewModel.suggestion(at: indexPath.row)
        cell.textLabel?.textColor = .white
        cell.textLabel?.font = AppFont.regular(14)
        cell.backgroundColor = UIColor(white: 0.12, alpha: 1)
        cell.selectionStyle = .default
        let bg = UIView()
        bg.backgroundColor = UIColor(white: 0.2, alpha: 1)
        cell.selectedBackgroundView = bg
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        rootView.emailField.text = viewModel.suggestion(at: indexPath.row)
        rootView.setSuggestionsHidden(true)
        rootView.passwordField.becomeFirstResponder()
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 40 }
}
