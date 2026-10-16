import UIKit

enum TerminalOutputStyle {
    case command
    case stdout
    case error
    case help
    case welcome
    case history

    var color: UIColor {
        switch self {
        case .command: return UIColor(named: "RED") ?? .red
        case .stdout: return .white
        case .error: return UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
        case .help: return UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
        case .welcome: return UIColor(white: 0.4, alpha: 1)
        case .history: return UIColor(white: 0.6, alpha: 1)
        }
    }
}

final class TerminalView: UIView {

    private lazy var titleLabel = UILabel.styled(
        text: "TERMINAL",
        font: AppFont.bold(14),
        alignment: .center
    )

    private let outputTextView: UITextView = {
        let tv = UITextView()
        tv.font = AppFont.regular(12)
        tv.textColor = .white
        tv.backgroundColor = .clear
        tv.isEditable = false
        tv.isScrollEnabled = true
        tv.showsVerticalScrollIndicator = true
        tv.indicatorStyle = .white
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let outputContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(named: "ContainerBackground")
        v.layer.cornerRadius = 12
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let inputBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(named: "ContainerBackground")
        v.layer.cornerRadius = 12
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var promptLabel = UILabel.styled(
        text: "root#",
        font: AppFont.bold(13),
        color: UIColor(named: "RED") ?? .red
    )

    let inputField: UITextField = {
        let field = UITextField()
        field.font = AppFont.regular(13)
        field.textColor = .white
        field.tintColor = UIColor(named: "RED")
        field.attributedPlaceholder = NSAttributedString(
            string: "type a command...",
            attributes: [
                .foregroundColor: UIColor(white: 0.3, alpha: 1),
                .font: AppFont.regular(13)
            ]
        )
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.returnKeyType = .go
        field.keyboardAppearance = .dark
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    let sendButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(
            UIImage(systemName: "arrow.up.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)),
            for: .normal
        )
        btn.tintColor = UIColor(named: "RED")
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    let clearButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("CLEAR", for: .normal)
        btn.titleLabel?.font = AppFont.bold(11)
        btn.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
        btn.backgroundColor = UIColor(white: 0.15, alpha: 1)
        btn.layer.cornerRadius = 6
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private var inputBarBottomConstraint: NSLayoutConstraint?

    var currentInput: String? {
        inputField.text
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()
        setupKeyboardObservers()
        showWelcome()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public rendering

    func clearInput() {
        inputField.text = ""
    }

    func setExecuting(_ executing: Bool) {
        sendButton.isEnabled = !executing
        promptLabel.text = executing ? "..." : "root#"
    }

    func append(_ text: String, style: TerminalOutputStyle) {
        let current = outputTextView.attributedText?.mutableCopy() as? NSMutableAttributedString
            ?? NSMutableAttributedString()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: AppFont.regular(12),
            .foregroundColor: style.color,
        ]
        current.append(NSAttributedString(string: text, attributes: attrs))
        outputTextView.attributedText = current

        let bottom = NSRange(location: current.length - 1, length: 1)
        outputTextView.scrollRangeToVisible(bottom)
    }

    func clear() {
        outputTextView.attributedText = NSAttributedString(string: "")
        showWelcome()
    }

    func showWelcome() {
        let welcome = """
        beerus terminal
        running as root via beerusd
        type 'help' for commands
        ─────────────────────────────
        """
        appendTemporary(welcome, style: .welcome)
    }

    func showHelp() {
        let help = """
        help · clear · history
        commands run as root via beerusd
        """
        appendTemporary(help + "\n", style: .help, scrollToBottom: true)
    }

    // MARK: - Private

    private func appendTemporary(_ text: String, style: TerminalOutputStyle, scrollToBottom: Bool = false) {
        let current = outputTextView.attributedText?.mutableCopy() as? NSMutableAttributedString
            ?? NSMutableAttributedString()
        let startLoc = current.length
        let attrs: [NSAttributedString.Key: Any] = [
            .font: AppFont.regular(12),
            .foregroundColor: style.color,
        ]
        current.append(NSAttributedString(string: text, attributes: attrs))
        outputTextView.attributedText = current

        if scrollToBottom {
            let bottom = NSRange(location: current.length - 1, length: 1)
            outputTextView.scrollRangeToVisible(bottom)
        }

        let length = text.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self,
                  let mutable = self.outputTextView.attributedText?.mutableCopy() as? NSMutableAttributedString,
                  startLoc + length <= mutable.length else { return }
            mutable.deleteCharacters(in: NSRange(location: startLoc, length: length))
            self.outputTextView.attributedText = mutable
        }
    }

    // MARK: - Keyboard

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil
        )

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        outputTextView.addGestureRecognizer(tap)
    }

    @objc private func keyboardWillShow(_ notif: Notification) {
        guard let frame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notif.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }

        let bottomInset = frame.height - safeAreaInsets.bottom
        inputBarBottomConstraint?.constant = -bottomInset - 8

        UIView.animate(withDuration: duration) {
            self.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notif: Notification) {
        guard let duration = notif.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }

        inputBarBottomConstraint?.constant = -12

        UIView.animate(withDuration: duration) {
            self.layoutIfNeeded()
        }
    }

    @objc private func dismissKeyboard() {
        endEditing(true)
    }
}

extension TerminalView: ViewCode {
    func buildViewHierarchy() {
        addSubview(titleLabel)
        addSubview(clearButton)
        addSubview(outputContainer)
        outputContainer.addSubview(outputTextView)
        addSubview(inputBar)
        inputBar.addSubview(promptLabel)
        inputBar.addSubview(inputField)
        inputBar.addSubview(sendButton)
    }

    func setupConstraints() {
        let bottomConstraint = inputBar.bottomAnchor.constraint(
            equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12
        )
        inputBarBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 56),

            clearButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            clearButton.widthAnchor.constraint(equalToConstant: 56),
            clearButton.heightAnchor.constraint(equalToConstant: 28),

            outputContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            outputContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            outputContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            outputContainer.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -8),

            outputTextView.topAnchor.constraint(equalTo: outputContainer.topAnchor),
            outputTextView.leadingAnchor.constraint(equalTo: outputContainer.leadingAnchor),
            outputTextView.trailingAnchor.constraint(equalTo: outputContainer.trailingAnchor),
            outputTextView.bottomAnchor.constraint(equalTo: outputContainer.bottomAnchor),

            inputBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            inputBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            inputBar.heightAnchor.constraint(equalToConstant: 48),
            bottomConstraint,

            promptLabel.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 14),
            promptLabel.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),

            inputField.leadingAnchor.constraint(equalTo: promptLabel.trailingAnchor, constant: 8),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -4),
            inputField.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            inputField.heightAnchor.constraint(equalToConstant: 36),

            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -8),
            sendButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }
}
