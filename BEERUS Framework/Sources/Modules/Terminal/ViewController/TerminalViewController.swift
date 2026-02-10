import UIKit

final class TerminalViewController: BaseViewController {

    // MARK: - UI

    private lazy var titleLabel = UILabel.styled(
        text: "TERMINAL", font: AppFont.bold(14), alignment: .center
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
        text: "root#", font: AppFont.bold(13),
        color: UIColor(named: "RED") ?? .red
    )

    private let inputField: UITextField = {
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

    private lazy var sendButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(
            UIImage(systemName: "arrow.up.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)),
            for: .normal
        )
        btn.tintColor = UIColor(named: "RED")
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var clearButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("CLEAR", for: .normal)
        btn.titleLabel?.font = AppFont.bold(11)
        btn.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
        btn.backgroundColor = UIColor(white: 0.15, alpha: 1)
        btn.layer.cornerRadius = 6
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        return btn
    }()

    // MARK: - Properties

    private var commandHistory: [String] = []
    private var historyIndex: Int = -1
    private var inputBarBottomConstraint: NSLayoutConstraint?
    private var isExecuting = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        setupKeyboardObservers()
        inputField.delegate = self
        printWelcome()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        view.endEditing(true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

        let bottomInset = frame.height - view.safeAreaInsets.bottom
        inputBarBottomConstraint?.constant = -bottomInset - 8

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notif: Notification) {
        guard let duration = notif.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }

        inputBarBottomConstraint?.constant = -12

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: - Welcome

    private func printWelcome() {
        let welcome = """
        beerus terminal 
        running as root via beerusd
        type 'help' for commands
        ─────────────────────────────
        """
        let current = outputTextView.attributedText?.mutableCopy() as? NSMutableAttributedString
            ?? NSMutableAttributedString()
        let startLoc = current.length
        let welcomeText = welcome
        let attrs: [NSAttributedString.Key: Any] = [
            .font: AppFont.regular(12),
            .foregroundColor: UIColor(white: 0.4, alpha: 1),
        ]
        current.append(NSAttributedString(string: welcomeText, attributes: attrs))
        outputTextView.attributedText = current

        let welcomeLength = welcomeText.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self,
                  let mutable = self.outputTextView.attributedText?.mutableCopy() as? NSMutableAttributedString,
                  startLoc + welcomeLength <= mutable.length else { return }
            mutable.deleteCharacters(in: NSRange(location: startLoc, length: welcomeLength))
            self.outputTextView.attributedText = mutable
        }
    }

    // MARK: - Command Execution

    @objc private func sendTapped() {
        executeCurrentInput()
    }

    @objc private func clearTapped() {
        outputTextView.attributedText = NSAttributedString(string: "")
        printWelcome()
    }

    private func executeCurrentInput() {
        guard let cmd = inputField.text?.trimmingCharacters(in: .whitespaces),
              !cmd.isEmpty else { return }
        guard !isExecuting else { return }

        inputField.text = ""

        // Save to history
        if commandHistory.last != cmd {
            commandHistory.append(cmd)
        }
        historyIndex = commandHistory.count

        // Print command
        appendOutput("root# \(cmd)\n", color: UIColor(named: "RED") ?? .red)

        // Built-in commands
        switch cmd.lowercased() {
        case "help":
            printHelp()
            return
        case "clear":
            clearTapped()
            return
        case "history":
            printHistory()
            return
        default:
            break
        }

        // Check daemon
        guard RootExec.isRunning else {
            appendOutput("error: beerus daemon is not running\n",
                         color: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1))
            return
        }

        isExecuting = true
        sendButton.isEnabled = false
        promptLabel.text = "..."

        Task.detached { [weak self] in
            let result = RootExec.shell(cmd)
            await MainActor.run {
                guard let self else { return }
                self.isExecuting = false
                self.sendButton.isEnabled = true
                self.promptLabel.text = "root#"

                if !result.output.isEmpty {
                    self.appendOutput(result.output + "\n", color: .white)
                }

                if result.exitCode != 0 {
                    self.appendOutput(
                        "exit: \(result.exitCode)\n",
                        color: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
                    )
                }
            }
        }
    }

    private func printHelp() {
        let help = """
        help · clear · history
        commands run as root via beerusd
        """
        let current = outputTextView.attributedText?.mutableCopy() as? NSMutableAttributedString
            ?? NSMutableAttributedString()
        let startLoc = current.length
        let helpText = help + "\n"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: AppFont.regular(12),
            .foregroundColor: UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1),
        ]
        current.append(NSAttributedString(string: helpText, attributes: attrs))
        outputTextView.attributedText = current
        let bottom = NSRange(location: current.length - 1, length: 1)
        outputTextView.scrollRangeToVisible(bottom)

        let helpLength = helpText.count
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self,
                  let mutable = self.outputTextView.attributedText?.mutableCopy() as? NSMutableAttributedString,
                  startLoc + helpLength <= mutable.length else { return }
            mutable.deleteCharacters(in: NSRange(location: startLoc, length: helpLength))
            self.outputTextView.attributedText = mutable
        }
    }

    private func printHistory() {
        if commandHistory.isEmpty {
            appendOutput("  (no history)\n", color: UIColor(white: 0.4, alpha: 1))
            return
        }
        for (i, cmd) in commandHistory.enumerated() {
            appendOutput("  \(i + 1)  \(cmd)\n", color: UIColor(white: 0.6, alpha: 1))
        }
    }

    // MARK: - Output

    private func appendOutput(_ text: String, color: UIColor) {
        let current = outputTextView.attributedText?.mutableCopy() as? NSMutableAttributedString
            ?? NSMutableAttributedString()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: AppFont.regular(12),
            .foregroundColor: color,
        ]
        current.append(NSAttributedString(string: text, attributes: attrs))
        outputTextView.attributedText = current

        // Auto-scroll
        let bottom = NSRange(location: current.length - 1, length: 1)
        outputTextView.scrollRangeToVisible(bottom)
    }
}

// MARK: - ViewCode

extension TerminalViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(clearButton)
        view.addSubview(outputContainer)
        outputContainer.addSubview(outputTextView)
        view.addSubview(inputBar)
        inputBar.addSubview(promptLabel)
        inputBar.addSubview(inputField)
        inputBar.addSubview(sendButton)
    }

    func setupConstraints() {
        let bottomConstraint = inputBar.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12
        )
        inputBarBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            // Title row
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 56),

            // Clear button
            clearButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            clearButton.widthAnchor.constraint(equalToConstant: 56),
            clearButton.heightAnchor.constraint(equalToConstant: 28),

            // Output
            outputContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            outputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            outputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            outputContainer.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -8),

            outputTextView.topAnchor.constraint(equalTo: outputContainer.topAnchor),
            outputTextView.leadingAnchor.constraint(equalTo: outputContainer.leadingAnchor),
            outputTextView.trailingAnchor.constraint(equalTo: outputContainer.trailingAnchor),
            outputTextView.bottomAnchor.constraint(equalTo: outputContainer.bottomAnchor),

            // Input bar
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
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

// MARK: - UITextFieldDelegate

extension TerminalViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        executeCurrentInput()
        return false
    }
}
