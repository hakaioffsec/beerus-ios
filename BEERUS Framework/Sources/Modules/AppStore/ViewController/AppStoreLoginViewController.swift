import UIKit

final class AppStoreLoginViewController: BaseViewController {

    var onLoginSuccess: ((AppStoreAccount) -> Void)?

    private lazy var titleLabel = UILabel.styled(
        text: "App Store", font: AppFont.bold(20), alignment: .center
    )

    private lazy var emailField: UITextField = makeField(placeholder: "Apple ID", secure: false)
    private lazy var passwordField: UITextField = makeField(placeholder: "Password", secure: true)
    private lazy var authCodeField: UITextField = {
        let f = makeField(placeholder: "2FA Code", secure: false)
        f.keyboardType = .numberPad
        f.isHidden = true
        return f
    }()

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

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
    }

    @objc private func signInTapped() {
        guard let email = emailField.text, !email.isEmpty,
              let password = passwordField.text, !password.isEmpty else {
            statusLabel.text = "Enter email and password"
            return
        }

        let authCode = authCodeField.text ?? ""
        setLoading(true)
        statusLabel.text = ""

        Task {
            do {
                let account = try await AppStoreService.shared.login(
                    email: email, password: password, authCode: authCode
                )
                await MainActor.run {
                    setLoading(false)
                    onLoginSuccess?(account)
                }
            } catch AppStoreError.authCodeRequired {
                await MainActor.run {
                    setLoading(false)
                    authCodeField.isHidden = false
                    statusLabel.text = "Enter 2FA code sent to your device"
                    statusLabel.textColor = .white
                }
            } catch {
                await MainActor.run {
                    setLoading(false)
                    statusLabel.text = error.localizedDescription
                    statusLabel.textColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
                }
            }
        }
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

extension AppStoreLoginViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(emailField)
        view.addSubview(passwordField)
        view.addSubview(authCodeField)
        view.addSubview(signInButton)
        view.addSubview(statusLabel)
        view.addSubview(spinner)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),

            emailField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            emailField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emailField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            emailField.heightAnchor.constraint(equalToConstant: 44),

            passwordField.topAnchor.constraint(equalTo: emailField.bottomAnchor, constant: 12),
            passwordField.leadingAnchor.constraint(equalTo: emailField.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: emailField.trailingAnchor),
            passwordField.heightAnchor.constraint(equalToConstant: 44),

            authCodeField.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 12),
            authCodeField.leadingAnchor.constraint(equalTo: emailField.leadingAnchor),
            authCodeField.trailingAnchor.constraint(equalTo: emailField.trailingAnchor),
            authCodeField.heightAnchor.constraint(equalToConstant: 44),

            signInButton.topAnchor.constraint(equalTo: authCodeField.bottomAnchor, constant: 24),
            signInButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            signInButton.widthAnchor.constraint(equalToConstant: 200),
            signInButton.heightAnchor.constraint(equalToConstant: 50),

            spinner.centerYAnchor.constraint(equalTo: signInButton.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: signInButton.trailingAnchor, constant: 12),

            statusLabel.topAnchor.constraint(equalTo: signInButton.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: emailField.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: emailField.trailingAnchor),
        ])
    }
}
