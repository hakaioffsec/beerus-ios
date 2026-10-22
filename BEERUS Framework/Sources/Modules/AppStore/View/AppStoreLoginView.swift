import UIKit

final class AppStoreLoginView: UIView {

    var onCopyCommand: () -> Void = {}
    var onCancelMFA: () -> Void = {}

    private lazy var titleLabel = UILabel.styled(
        text: "App Store",
        font: AppFont.bold(20),
        alignment: .center
    )

    let emailField = AppStoreLoginView.makeField(placeholder: "Apple ID", secure: false)
    let passwordField = AppStoreLoginView.makeField(placeholder: "Password", secure: true)

    let signInButton = UIButton.styled(title: "Sign In")

    private lazy var statusLabel = UILabel.styled(
        font: AppFont.regular(12),
        color: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1),
        alignment: .center,
        lines: 0
    )

    let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = .white
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    let suggestionsTable: UITableView = {
        let tv = UITableView()
        tv.backgroundColor = UIColor(white: 0.12, alpha: 1)
        tv.layer.cornerRadius = 8
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor(white: 0.2, alpha: 1).cgColor
        tv.separatorColor = UIColor(white: 0.2, alpha: 1)
        tv.isHidden = true
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "SuggestionCell")
        return tv
    }()

    private lazy var mfaContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.08, alpha: 1)
        v.layer.cornerRadius = 12
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var mfaTitleLabel = UILabel.styled(
        text: "Aguardando código MFA...",
        font: AppFont.bold(14),
        alignment: .center
    )

    private lazy var mfaInstructionLabel = UILabel.styled(
        text: "Via SSH, execute:",
        font: AppFont.regular(12),
        color: UIColor(white: 0.5, alpha: 1),
        alignment: .center
    )

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
        btn.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
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
        btn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var mfaTimerLabel = UILabel.styled(
        font: AppFont.regular(10),
        color: UIColor(white: 0.4, alpha: 1),
        alignment: .center
    )

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Rendering

    func setLoading(_ loading: Bool) {
        signInButton.isEnabled = !loading
        signInButton.alpha = loading ? 0.5 : 1.0
        loading ? spinner.startAnimating() : spinner.stopAnimating()
    }

    func setStatus(_ text: String, style: AppStoreLoginViewModel.StatusStyle) {
        statusLabel.text = text
        switch style {
        case .info: statusLabel.textColor = UIColor(white: 0.6, alpha: 1)
        case .muted: statusLabel.textColor = UIColor(white: 0.5, alpha: 1)
        case .error: statusLabel.textColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
        }
    }

    func showMFA(command: String) {
        mfaCommandLabel.text = command
        emailField.isHidden = true
        passwordField.isHidden = true
        signInButton.isHidden = true
        statusLabel.isHidden = true
        mfaContainer.isHidden = false
    }

    func hideMFA() {
        mfaContainer.isHidden = true
        emailField.isHidden = false
        passwordField.isHidden = false
        signInButton.isHidden = false
        statusLabel.isHidden = false
    }

    func setMFATimer(_ text: String) {
        mfaTimerLabel.text = text
    }

    func setSuggestionsHidden(_ hidden: Bool) {
        suggestionsTable.isHidden = hidden
    }

    func confirmCopy() {
        let original = copyButton.title(for: .normal)
        copyButton.setTitle("Copiado!", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.setTitle(original, for: .normal)
        }
    }

    @objc private func dismissKeyboard() {
        endEditing(true)
        suggestionsTable.isHidden = true
    }

    @objc private func copyTapped() {
        onCopyCommand()
    }

    @objc private func cancelTapped() {
        onCancelMFA()
    }

    private static func makeField(placeholder: String, secure: Bool) -> UITextField {
        let field = UITextField()
        field.font = AppFont.regular(14)
        field.textColor = .white
        field.tintColor = UIColor(named: "RED")
        field.isSecureTextEntry = secure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardAppearance = .dark
        field.returnKeyType = .next
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

extension AppStoreLoginView: ViewCode {
    func buildViewHierarchy() {
        addSubview(titleLabel)
        addSubview(emailField)
        addSubview(passwordField)
        addSubview(signInButton)
        addSubview(statusLabel)
        addSubview(spinner)
        addSubview(suggestionsTable)

        addSubview(mfaContainer)
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
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 80),

            emailField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            emailField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            emailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
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
            signInButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            signInButton.widthAnchor.constraint(equalToConstant: 200),
            signInButton.heightAnchor.constraint(equalToConstant: 50),

            spinner.centerYAnchor.constraint(equalTo: signInButton.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: signInButton.trailingAnchor, constant: 12),

            statusLabel.topAnchor.constraint(equalTo: signInButton.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: emailField.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: emailField.trailingAnchor),

            mfaContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            mfaContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            mfaContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

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
