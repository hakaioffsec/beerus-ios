import UIKit

final class AppStoreLoginViewController: BaseViewController {

    var onLoginSuccess: ((AppStoreAccount) -> Void)?

    private var mfaTimer: Timer?
    private var mfaTimeoutDate: Date?
    private var pendingEmail: String?
    private var pendingPassword: String?

    // ponytail: email history for autocomplete
    private static let emailHistoryKey = "AppStoreEmailHistory"
    private var emailSuggestions: [String] = []
    private var filteredSuggestions: [String] = []

    private lazy var suggestionsTable: UITableView = {
        let tv = UITableView()
        tv.backgroundColor = UIColor(white: 0.12, alpha: 1)
        tv.layer.cornerRadius = 8
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor(white: 0.2, alpha: 1).cgColor
        tv.separatorColor = UIColor(white: 0.2, alpha: 1)
        tv.delegate = self
        tv.dataSource = self
        tv.isHidden = true
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "SuggestionCell")
        return tv
    }()

    private lazy var titleLabel = UILabel.styled(
        text: "App Store", font: AppFont.bold(20), alignment: .center
    )

    private lazy var emailField: UITextField = makeField(placeholder: "Apple ID", secure: false)
    private lazy var passwordField: UITextField = makeField(placeholder: "Password", secure: true)

    private lazy var signInButton = UIButton.styled(
        title: "Sign In", target: self, action: #selector(signInTapped)
    )

    private lazy var statusLabel = UILabel.styled(
        text: "", font: AppFont.regular(12),
        color: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1),
        alignment: .center, lines: 0
    )

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = .white
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    // MARK: - MFA UI

    private lazy var mfaContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.08, alpha: 1)
        v.layer.cornerRadius = 12
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var mfaTitleLabel = UILabel.styled(
        text: "Aguardando código MFA...", font: AppFont.bold(14), alignment: .center
    )

    private lazy var mfaInstructionLabel: UILabel = {
        let l = UILabel.styled(
            text: "Via SSH, execute:", font: AppFont.regular(12),
            color: UIColor(white: 0.5, alpha: 1), alignment: .center
        )
        return l
    }()

    private lazy var mfaCommandView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.05, alpha: 1)
        v.layer.cornerRadius = 8
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor(white: 0.15, alpha: 1).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var mfaCommandLabel: UILabel = {
        let l = UILabel()
        l.font = AppFont.regular(10)
        l.textColor = UIColor(red: 0.4, green: 0.9, blue: 0.4, alpha: 1)
        l.numberOfLines = 0
        l.lineBreakMode = .byCharWrapping
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var copyButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Copiar Comando", for: .normal)
        btn.titleLabel?.font = AppFont.bold(12)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(named: "RED")
        btn.layer.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(copyCommandTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var cancelMFAButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Cancelar", for: .normal)
        btn.titleLabel?.font = AppFont.bold(12)
        btn.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
        btn.backgroundColor = UIColor(white: 0.15, alpha: 1)
        btn.layer.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(cancelMFATapped), for: .touchUpInside)
        return btn
    }()

    private lazy var mfaTimerLabel = UILabel.styled(
        text: "", font: AppFont.regular(10),
        color: UIColor(white: 0.4, alpha: 1), alignment: .center
    )

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        // ponytail: load email history + setup autocomplete
        emailSuggestions = UserDefaults.standard.stringArray(forKey: Self.emailHistoryKey) ?? []
        emailField.delegate = self
        emailField.addTarget(self, action: #selector(emailFieldChanged), for: .editingChanged)
    }

    deinit {
        stopMFAPolling()
    }

    // MARK: - Actions

    @objc private func dismissKeyboard() {
        view.endEditing(true)
        suggestionsTable.isHidden = true
    }

    // MARK: - Email Autocomplete

    @objc private func emailFieldChanged() {
        guard let text = emailField.text, !text.isEmpty else {
            suggestionsTable.isHidden = true
            return
        }
        filteredSuggestions = emailSuggestions.filter {
            $0.lowercased().contains(text.lowercased()) && $0 != text
        }
        suggestionsTable.isHidden = filteredSuggestions.isEmpty
        suggestionsTable.reloadData()
    }

    private func saveEmailToHistory(_ email: String) {
        var history = emailSuggestions
        history.removeAll { $0.lowercased() == email.lowercased() }
        history.insert(email, at: 0)
        if history.count > 5 { history = Array(history.prefix(5)) }
        emailSuggestions = history
        UserDefaults.standard.set(history, forKey: Self.emailHistoryKey)
    }

    @objc private func signInTapped() {
        guard let email = emailField.text, !email.isEmpty,
              let password = passwordField.text, !password.isEmpty else {
            statusLabel.text = "Enter email and password"
            return
        }

        attemptLogin(email: email, password: password, authCode: "")
    }

    @objc private func copyCommandTapped() {
        let command = "echo \"CODE\" > \(MFAFileWatcher.filePath)"
        UIPasteboard.general.string = command

        let originalTitle = copyButton.title(for: .normal)
        copyButton.setTitle("Copiado!", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.setTitle(originalTitle, for: .normal)
        }
    }

    @objc private func cancelMFATapped() {
        stopMFAPolling()
        hideMFAUI()
        pendingEmail = nil
        pendingPassword = nil
        statusLabel.text = "Login cancelado"
        statusLabel.textColor = UIColor(white: 0.5, alpha: 1)
    }

    // MARK: - Login Flow

    private func attemptLogin(email: String, password: String, authCode: String) {
        setLoading(true)
        statusLabel.text = "Connecting to App Store..."
        statusLabel.textColor = UIColor(white: 0.6, alpha: 1)

        Task { [weak self] in
            guard let self else { return }
            do {
                let account = try await AppStoreService.shared.login(
                    email: email, password: password, authCode: authCode
                )
                await MainActor.run {
                    self.setLoading(false)
                    self.stopMFAPolling()
                    self.saveEmailToHistory(email)
                    self.onLoginSuccess?(account)
                }
            } catch AppStoreError.authCodeRequired {
                NSLog("[AppStore] >>> authCodeRequired caught in LoginVC <<<")
                await MainActor.run {
                    self.setLoading(false)
                    self.pendingEmail = email
                    self.pendingPassword = password
                    self.showMFAUI()
                    self.startMFAPolling()
                }
            } catch {
                await MainActor.run {
                    self.setLoading(false)
                    self.stopMFAPolling()
                    self.hideMFAUI()
                    self.statusLabel.text = error.localizedDescription
                    self.statusLabel.textColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
                }
            }
        }
    }

    // MARK: - MFA File Polling

    private func startMFAPolling() {
        NSLog("[MFA] === Starting MFA Polling ===")
        NSLog("[MFA] File path: %@", MFAFileWatcher.filePath)
        MFAFileWatcher.clear()
        mfaTimeoutDate = Date().addingTimeInterval(300) // 5 min timeout

        mfaTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkMFAFile()
        }
        NSLog("[MFA] Timer started, polling every 1s")
    }

    private func stopMFAPolling() {
        NSLog("[MFA] Stopping MFA polling")
        mfaTimer?.invalidate()
        mfaTimer = nil
        mfaTimeoutDate = nil
        MFAFileWatcher.clear()
    }

    private func checkMFAFile() {
        if let timeout = mfaTimeoutDate {
            let remaining = timeout.timeIntervalSinceNow
            if remaining <= 0 {
                NSLog("[MFA] Timeout reached")
                stopMFAPolling()
                hideMFAUI()
                statusLabel.text = "Timeout - código MFA expirou"
                statusLabel.textColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
                return
            }
            let mins = Int(remaining) / 60
            let secs = Int(remaining) % 60
            mfaTimerLabel.text = String(format: "Expira em %d:%02d", mins, secs)
        }

        guard let code = MFAFileWatcher.read() else { return }

        NSLog("[MFA] >>> Code found: '%@' <<<", code)
        MFAFileWatcher.clear()
        stopMFAPolling()
        hideMFAUI()

        guard let email = pendingEmail, let password = pendingPassword else {
            NSLog("[MFA] ERROR: Missing pending credentials")
            return
        }
        NSLog("[MFA] Retrying login with MFA code...")
        attemptLogin(email: email, password: password, authCode: code)
    }

    // MARK: - UI State

    private func showMFAUI() {
        NSLog("[MFA] Showing MFA UI")
        let command = "echo \"CODE\" > \(MFAFileWatcher.filePath)"
        NSLog("[MFA] Command to use: %@", command)
        mfaCommandLabel.text = command

        emailField.isHidden = true
        passwordField.isHidden = true
        signInButton.isHidden = true
        statusLabel.isHidden = true
        mfaContainer.isHidden = false
    }

    private func hideMFAUI() {
        mfaContainer.isHidden = true
        emailField.isHidden = false
        passwordField.isHidden = false
        signInButton.isHidden = false
        statusLabel.isHidden = false
    }

    private func setLoading(_ loading: Bool) {
        signInButton.isEnabled = !loading
        signInButton.alpha = loading ? 0.5 : 1.0
        loading ? spinner.startAnimating() : spinner.stopAnimating()
    }

    private func makeField(placeholder: String, secure: Bool) -> UITextField {
        let field = UITextField()
        field.font = AppFont.regular(14)
        field.textColor = .white
        field.tintColor = UIColor(named: "RED")
        field.isSecureTextEntry = secure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardAppearance = .dark
        field.returnKeyType = .next
        field.delegate = self
        field.backgroundColor = UIColor(white: 0.1, alpha: 1)
        field.layer.cornerRadius = 8
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        field.leftViewMode = .always
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(white: 0.3, alpha: 1), .font: AppFont.regular(14)]
        )
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }
}

extension AppStoreLoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == emailField {
            passwordField.becomeFirstResponder()
            suggestionsTable.isHidden = true
        } else if textField == passwordField {
            textField.resignFirstResponder()
            signInTapped()
        }
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        if textField == emailField {
            emailFieldChanged()
        }
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField == emailField {
            suggestionsTable.isHidden = true
        }
    }
}

extension AppStoreLoginViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredSuggestions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SuggestionCell", for: indexPath)
        cell.textLabel?.text = filteredSuggestions[indexPath.row]
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
        emailField.text = filteredSuggestions[indexPath.row]
        suggestionsTable.isHidden = true
        passwordField.becomeFirstResponder()
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 40 }
}

extension AppStoreLoginViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(emailField)
        view.addSubview(passwordField)
        view.addSubview(signInButton)
        view.addSubview(statusLabel)
        view.addSubview(spinner)
        view.addSubview(suggestionsTable) // ponytail: on top so it overlays other fields

        view.addSubview(mfaContainer)
        mfaContainer.addSubview(mfaTitleLabel)
        mfaContainer.addSubview(mfaInstructionLabel)
        mfaContainer.addSubview(mfaCommandView)
        mfaCommandView.addSubview(mfaCommandLabel)
        mfaContainer.addSubview(copyButton)
        mfaContainer.addSubview(cancelMFAButton)
        mfaContainer.addSubview(mfaTimerLabel)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),

            emailField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            emailField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emailField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            emailField.heightAnchor.constraint(equalToConstant: 44),

            suggestionsTable.topAnchor.constraint(equalTo: emailField.bottomAnchor, constant: 4),
            suggestionsTable.leadingAnchor.constraint(equalTo: emailField.leadingAnchor),
            suggestionsTable.trailingAnchor.constraint(equalTo: emailField.trailingAnchor),
            suggestionsTable.heightAnchor.constraint(lessThanOrEqualToConstant: 160),

            passwordField.topAnchor.constraint(equalTo: emailField.bottomAnchor, constant: 12),
            passwordField.leadingAnchor.constraint(equalTo: emailField.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: emailField.trailingAnchor),
            passwordField.heightAnchor.constraint(equalToConstant: 44),

            signInButton.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 24),
            signInButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            signInButton.widthAnchor.constraint(equalToConstant: 200),
            signInButton.heightAnchor.constraint(equalToConstant: 50),

            spinner.centerYAnchor.constraint(equalTo: signInButton.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: signInButton.trailingAnchor, constant: 12),

            statusLabel.topAnchor.constraint(equalTo: signInButton.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: emailField.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: emailField.trailingAnchor),

            // MFA Container
            mfaContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            mfaContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            mfaContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            mfaTitleLabel.topAnchor.constraint(equalTo: mfaContainer.topAnchor, constant: 20),
            mfaTitleLabel.leadingAnchor.constraint(equalTo: mfaContainer.leadingAnchor, constant: 16),
            mfaTitleLabel.trailingAnchor.constraint(equalTo: mfaContainer.trailingAnchor, constant: -16),

            mfaInstructionLabel.topAnchor.constraint(equalTo: mfaTitleLabel.bottomAnchor, constant: 16),
            mfaInstructionLabel.leadingAnchor.constraint(equalTo: mfaTitleLabel.leadingAnchor),
            mfaInstructionLabel.trailingAnchor.constraint(equalTo: mfaTitleLabel.trailingAnchor),

            mfaCommandView.topAnchor.constraint(equalTo: mfaInstructionLabel.bottomAnchor, constant: 12),
            mfaCommandView.leadingAnchor.constraint(equalTo: mfaContainer.leadingAnchor, constant: 12),
            mfaCommandView.trailingAnchor.constraint(equalTo: mfaContainer.trailingAnchor, constant: -12),

            mfaCommandLabel.topAnchor.constraint(equalTo: mfaCommandView.topAnchor, constant: 12),
            mfaCommandLabel.leadingAnchor.constraint(equalTo: mfaCommandView.leadingAnchor, constant: 12),
            mfaCommandLabel.trailingAnchor.constraint(equalTo: mfaCommandView.trailingAnchor, constant: -12),
            mfaCommandLabel.bottomAnchor.constraint(equalTo: mfaCommandView.bottomAnchor, constant: -12),

            copyButton.topAnchor.constraint(equalTo: mfaCommandView.bottomAnchor, constant: 16),
            copyButton.leadingAnchor.constraint(equalTo: mfaContainer.leadingAnchor, constant: 16),
            copyButton.trailingAnchor.constraint(equalTo: mfaContainer.trailingAnchor, constant: -16),
            copyButton.heightAnchor.constraint(equalToConstant: 44),

            cancelMFAButton.topAnchor.constraint(equalTo: copyButton.bottomAnchor, constant: 8),
            cancelMFAButton.leadingAnchor.constraint(equalTo: copyButton.leadingAnchor),
            cancelMFAButton.trailingAnchor.constraint(equalTo: copyButton.trailingAnchor),
            cancelMFAButton.heightAnchor.constraint(equalToConstant: 44),

            mfaTimerLabel.topAnchor.constraint(equalTo: cancelMFAButton.bottomAnchor, constant: 12),
            mfaTimerLabel.centerXAnchor.constraint(equalTo: mfaContainer.centerXAnchor),
            mfaTimerLabel.bottomAnchor.constraint(equalTo: mfaContainer.bottomAnchor, constant: -16),
        ])
    }
}
