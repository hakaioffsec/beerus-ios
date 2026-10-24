import UIKit

enum ConsoleStatus {
    case connecting, running, stopped, error
}

enum ConsoleLineStyle {
    case log, error, system, result

    var color: UIColor {
        switch self {
        case .log: return UIColor(red: 0.78, green: 0.92, blue: 0.78, alpha: 1)
        case .error: return UIColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1)
        case .system: return UIColor(white: 0.5, alpha: 1)
        case .result: return UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)
        }
    }
}

final class ScriptConsoleView: UIView {

    private let topBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(named: "ContainerBackground")
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    let backButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "chevron.left")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        btn.setImage(img, for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Console"
        l.font = AppFont.bold(14)
        l.textColor = .white
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let statusDot: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    let stopButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "stop.circle.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.tintColor = UIColor(named: "RED")
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let outputView: UITextView = {
        let tv = UITextView()
        tv.backgroundColor = UIColor(named: "Background")
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = AppFont.regular(12)
        tv.textColor = .white
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.indicatorStyle = .white
        return tv
    }()

    private let bottomBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(named: "ContainerBackground")
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    let clearButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("CLEAR", for: .normal)
        btn.titleLabel?.font = AppFont.bold(11)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(white: 0.18, alpha: 1)
        btn.layer.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    let shareButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "square.and.arrow.up")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let pidLabel: UILabel = {
        let l = UILabel()
        l.font = AppFont.regular(10)
        l.textColor = UIColor(white: 0.4, alpha: 1)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let outputText = NSMutableAttributedString()
    private var flushScheduled = false

    private static let tsFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    /// Caps how much text the console keeps, so a chatty script (many console.log()s/sec, common
    /// in tracing) can't grow this view's memory footprint without bound.
    private static let maxOutputLength = 300_000

    var outputPlainText: String { outputText.string }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        buildUI()
        applyStatus(.connecting, title: "Connecting…")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Rendering

    func applyStatus(_ status: ConsoleStatus, title: String) {
        titleLabel.text = title
        switch status {
        case .connecting:
            statusDot.backgroundColor = .yellow
            stopButton.isEnabled = true
        case .running:
            statusDot.backgroundColor = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
            stopButton.isEnabled = true
        case .stopped:
            statusDot.backgroundColor = UIColor(white: 0.45, alpha: 1)
            stopButton.isEnabled = false
        case .error:
            statusDot.backgroundColor = UIColor(named: "RED")
            stopButton.isEnabled = false
        }
    }

    func setPID(_ text: String) {
        pidLabel.text = text
    }

    func append(_ text: String, style: ConsoleLineStyle) {
        let ts = "[\(Self.tsFormatter.string(from: Date()))] "
        let line = NSAttributedString(string: "\(ts)\(text)\n", attributes: [
            .font: AppFont.regular(12),
            .foregroundColor: style.color,
        ])
        outputText.append(line)

        if outputText.length > Self.maxOutputLength {
            let overflow = outputText.length - Self.maxOutputLength
            outputText.deleteCharacters(in: NSRange(location: 0, length: overflow))
        }

        scheduleOutputFlush()
    }

    func clearOutput() {
        outputText.setAttributedString(NSAttributedString())
        outputView.attributedText = outputText
    }

    /// Coalesces bursts of appends (e.g. a hot hooked function logging on every call) into at most
    /// one full text-view re-render per 100ms, instead of reassigning attributedText + scrolling on
    /// every single message.
    private func scheduleOutputFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            self.outputView.attributedText = self.outputText
            guard self.outputText.length > 0 else { return }
            self.outputView.scrollRangeToVisible(NSRange(location: self.outputText.length - 1, length: 1))
        }
    }

    // MARK: - Build

    private func buildUI() {
        addSubview(topBar)
        topBar.addSubview(backButton)
        topBar.addSubview(titleLabel)
        topBar.addSubview(statusDot)
        topBar.addSubview(stopButton)
        addSubview(outputView)
        addSubview(bottomBar)
        bottomBar.addSubview(pidLabel)
        bottomBar.addSubview(clearButton)
        bottomBar.addSubview(shareButton)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 48),

            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 36),

            titleLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            statusDot.trailingAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: -6),
            statusDot.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10),

            stopButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            stopButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: 36),

            outputView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            outputView.leadingAnchor.constraint(equalTo: leadingAnchor),
            outputView.trailingAnchor.constraint(equalTo: trailingAnchor),
            outputView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 44),

            pidLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            pidLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            shareButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            shareButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            shareButton.widthAnchor.constraint(equalToConstant: 36),

            clearButton.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 60),
            clearButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }
}
