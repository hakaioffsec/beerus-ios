import UIKit

final class LLDBServerView: UIView {

    private let green = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
    private let dim = UIColor(white: 0.3, alpha: 1)
    private let muted = UIColor(white: 0.4, alpha: 1)
    private let iconCfg = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)

    private static let maxConsoleLogLength = 300_000

    private lazy var circuitTopImageView = UIImageView.circuit(named: "circuit-top")
    private lazy var circuitLeftImageView = UIImageView.circuit(named: "circuit-left")
    private lazy var circuitRightImageView = UIImageView.circuit(named: "circuit-right")
    private lazy var circuitLeftDownImageView = UIImageView.circuit(named: "circuit-left-down")

    private lazy var titleLabel = UILabel.styled(text: "LLDB Server", font: AppFont.bold(20), alignment: .center)
    private lazy var statusLabel = UILabel.styled(font: AppFont.bold(14), alignment: .center)
    private lazy var subtitleLabel = UILabel.styled(font: AppFont.regular(12), color: UIColor(white: 0.35, alpha: 1), alignment: .center, lines: 2)
    private lazy var feedbackLabel = UILabel.styled(font: AppFont.regular(10), color: UIColor(white: 0.35, alpha: 1), alignment: .center, lines: 2)

    private lazy var statusIcon: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private lazy var commandLabel: UILabel = {
        let l = UILabel.styled(font: AppFont.regular(11), color: green, alignment: .center, lines: 2)
        l.isHidden = true
        return l
    }()

    lazy var copyButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "doc.on.doc",
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)), for: .normal)
        b.tintColor = muted
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isHidden = true
        return b
    }()

    private lazy var progressBar: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .default)
        pv.trackTintColor = UIColor(white: 0.15, alpha: 1)
        pv.progressTintColor = UIColor(named: "ButtonColor") ?? .systemRed
        pv.layer.cornerRadius = 2
        pv.clipsToBounds = true
        pv.translatesAutoresizingMaskIntoConstraints = false
        pv.isHidden = true
        return pv
    }()

    private lazy var consoleView: UITextView = {
        let tv = UITextView()
        tv.isEditable = false
        tv.backgroundColor = UIColor(white: 0.06, alpha: 1)
        tv.textColor = green
        tv.font = AppFont.regular(10)
        tv.layer.cornerRadius = 8
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor(white: 0.15, alpha: 1).cgColor
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.isHidden = true
        tv.showsVerticalScrollIndicator = true
        tv.indicatorStyle = .white
        return tv
    }()

    lazy var actionButton = UIButton.styled(title: "INSTALL", font: AppFont.bold(13))

    lazy var uninstallButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("uninstall", for: .normal)
        b.titleLabel?.font = AppFont.regular(11)
        b.setTitleColor(UIColor(white: 0.25, alpha: 1), for: .normal)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isHidden = true
        return b
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Rendering

    func apply(_ presentation: LLDBServerViewModel.Presentation) {
        commandLabel.isHidden = true
        copyButton.isHidden = true
        progressBar.isHidden = true
        uninstallButton.isHidden = true
        consoleView.isHidden = true
        feedbackLabel.text = ""

        let appearance = appearance(for: presentation.status)
        statusIcon.image = UIImage(systemName: appearance.icon, withConfiguration: iconCfg)
        statusIcon.tintColor = appearance.iconColor
        statusLabel.text = appearance.text
        statusLabel.textColor = appearance.textColor

        subtitleLabel.text = presentation.subtitle
        subtitleLabel.textColor = presentation.status == .online
            ? green.withAlphaComponent(0.6)
            : UIColor(white: 0.35, alpha: 1)

        if let title = presentation.actionTitle {
            actionButton.isHidden = false
            actionButton.setTitle(title, for: .normal)
            actionButton.backgroundColor = presentation.actionDestructive
                ? UIColor(named: "RED")
                : UIColor(named: "ButtonColor")
            setActionEnabled(presentation.actionEnabled)
        } else {
            actionButton.isHidden = true
        }

        if presentation.showProgress {
            progressBar.isHidden = false
            progressBar.progress = 0
            progressBar.progressTintColor = UIColor(named: "ButtonColor") ?? .systemRed
        }
        if presentation.showConsole {
            consoleView.isHidden = false
        }
        if presentation.showCommand {
            commandLabel.isHidden = false
            copyButton.isHidden = false
            commandLabel.text = presentation.connectCommand
        }
        if presentation.showUninstall {
            uninstallButton.isHidden = false
        }
    }

    func renderServerDied(path: String) {
        statusIcon.image = UIImage(systemName: "bolt.slash.fill", withConfiguration: iconCfg)
        statusIcon.tintColor = dim
        statusLabel.text = "OFFLINE"
        statusLabel.textColor = muted
        subtitleLabel.text = path
        subtitleLabel.textColor = UIColor(white: 0.35, alpha: 1)
        actionButton.setTitle("START", for: .normal)
        actionButton.backgroundColor = UIColor(named: "ButtonColor")
        setActionEnabled(true)
    }

    func setProgress(_ value: Float, text: String, palette: LLDBServerViewModel.Palette) {
        progressBar.setProgress(value, animated: true)
        if value >= 1.0 { progressBar.progressTintColor = green }
        feedbackLabel.text = text
        feedbackLabel.textColor = color(palette)
    }

    func setFeedback(_ text: String, palette: LLDBServerViewModel.Palette) {
        feedbackLabel.text = text
        feedbackLabel.textColor = color(palette)
    }

    func setActionEnabled(_ enabled: Bool) {
        actionButton.isEnabled = enabled
        actionButton.alpha = enabled ? 1 : 0.5
    }

    func resetConsole() {
        consoleView.text = ""
        consoleView.isHidden = false
    }

    func appendConsole(_ newContent: String) {
        guard !newContent.isEmpty else { return }
        consoleView.text += newContent
        if consoleView.text.count > Self.maxConsoleLogLength {
            let overflow = consoleView.text.count - Self.maxConsoleLogLength
            consoleView.text.removeFirst(overflow)
        }
        guard !consoleView.text.isEmpty else { return }
        let bottom = NSRange(location: consoleView.text.count - 1, length: 1)
        consoleView.scrollRangeToVisible(bottom)
    }

    func copyCurrentCommand() {
        UIPasteboard.general.string = commandLabel.text
        copyButton.tintColor = green
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.copyButton.tintColor = self?.muted
        }
    }

    // MARK: - Styling

    private func appearance(for status: LLDBServerViewModel.Status) -> (icon: String, iconColor: UIColor, text: String, textColor: UIColor) {
        let buttonColor = UIColor(named: "ButtonColor") ?? .systemRed
        switch status {
        case .notInstalled: return ("xmark.circle", dim, "NOT INSTALLED", muted)
        case .installing: return ("arrow.down.circle", buttonColor, "INSTALLING", buttonColor)
        case .starting: return ("bolt.circle", buttonColor, "STARTING", buttonColor)
        case .offline: return ("bolt.slash.fill", dim, "OFFLINE", muted)
        case .online: return ("bolt.fill", green, "ONLINE", green)
        }
    }

    private func color(_ palette: LLDBServerViewModel.Palette) -> UIColor {
        switch palette {
        case .muted: return muted
        case .red: return UIColor(named: "RED") ?? .red
        case .orange: return .orange
        case .green: return green
        }
    }
}

extension LLDBServerView: ViewCode {
    func buildViewHierarchy() {
        [circuitTopImageView, circuitLeftImageView, circuitRightImageView, circuitLeftDownImageView,
         titleLabel, statusIcon, statusLabel, subtitleLabel,
         commandLabel, copyButton, consoleView, progressBar, actionButton, feedbackLabel, uninstallButton]
            .forEach(addSubview)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            circuitTopImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitTopImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),

            circuitRightImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitRightImageView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            circuitRightImageView.widthAnchor.constraint(equalToConstant: 40),
            circuitRightImageView.heightAnchor.constraint(equalTo: safeAreaLayoutGuide.heightAnchor),

            circuitLeftImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitLeftImageView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),

            circuitLeftDownImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            circuitLeftDownImageView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 70),

            statusIcon.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusIcon.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            statusIcon.widthAnchor.constraint(equalToConstant: 44),
            statusIcon.heightAnchor.constraint(equalToConstant: 44),

            statusLabel.topAnchor.constraint(equalTo: statusIcon.bottomAnchor, constant: 8),
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),

            commandLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            commandLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            commandLabel.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),

            copyButton.centerYAnchor.constraint(equalTo: commandLabel.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            copyButton.widthAnchor.constraint(equalToConstant: 28),
            copyButton.heightAnchor.constraint(equalToConstant: 28),

            consoleView.topAnchor.constraint(equalTo: commandLabel.bottomAnchor, constant: 12),
            consoleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            consoleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            consoleView.bottomAnchor.constraint(equalTo: actionButton.topAnchor, constant: -12),

            progressBar.topAnchor.constraint(equalTo: commandLabel.bottomAnchor, constant: 20),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            progressBar.heightAnchor.constraint(equalToConstant: 4),

            actionButton.bottomAnchor.constraint(equalTo: feedbackLabel.topAnchor, constant: -10),
            actionButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            actionButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            actionButton.heightAnchor.constraint(equalToConstant: 50),

            feedbackLabel.bottomAnchor.constraint(equalTo: uninstallButton.topAnchor, constant: -8),
            feedbackLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            feedbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            feedbackLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            uninstallButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
            uninstallButton.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }
}
