import UIKit

final class ScriptConsoleViewController: UIViewController {

    // MARK: - Properties

    private let scriptModel: FridaScriptModel
    private var scriptSession: ScriptSession?
    private var eventTask: Task<Void, Never>?
    private var isRunning = false
    private var didReceiveOutput = false

    /// Accumulated output for the session.
    private let outputText = NSMutableAttributedString()

    // MARK: - Colors

    private let logColor      = UIColor(red: 0.78, green: 0.92, blue: 0.78, alpha: 1)   // green-ish
    private let errorColor    = UIColor(red: 1.0,  green: 0.45, blue: 0.45, alpha: 1)    // red
    private let systemColor   = UIColor(white: 0.5, alpha: 1)                             // gray
    private let resultColor   = UIColor(red: 0.55, green: 0.85, blue: 1.0,  alpha: 1)    // cyan

    // MARK: - UI

    private let topBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(named: "ContainerBackground")
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var backButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "chevron.left")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        btn.setImage(img, for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
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

    private lazy var stopButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "stop.circle.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 20, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.tintColor = UIColor(named: "RED")
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
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

    private lazy var clearButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("CLEAR", for: .normal)
        btn.titleLabel?.font = AppFont.bold(11)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(white: 0.18, alpha: 1)
        btn.layer.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var shareButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "square.and.arrow.up")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        return btn
    }()

    private let pidLabel: UILabel = {
        let l = UILabel()
        l.font = AppFont.regular(10)
        l.textColor = UIColor(white: 0.4, alpha: 1)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    // MARK: - Init

    init(script: FridaScriptModel) {
        self.scriptModel = script
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "Background")
        navigationController?.navigationBar.isHidden = true
        buildUI()
        startExecution()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopExecution()
    }

    // MARK: - UI Build

    private func buildUI() {
        view.addSubview(topBar)
        topBar.addSubview(backButton)
        topBar.addSubview(titleLabel)
        topBar.addSubview(statusDot)
        topBar.addSubview(stopButton)
        view.addSubview(outputView)
        view.addSubview(bottomBar)
        bottomBar.addSubview(pidLabel)
        bottomBar.addSubview(clearButton)
        bottomBar.addSubview(shareButton)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
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
            outputView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            outputView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            outputView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
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

        setStatus(.connecting)
    }

    // MARK: - Status

    private enum Status { case connecting, running, stopped, error }

    private func setStatus(_ s: Status) {
        switch s {
        case .connecting:
            statusDot.backgroundColor = .yellow
            titleLabel.text = "Connecting…"
            stopButton.isEnabled = true
        case .running:
            statusDot.backgroundColor = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
            titleLabel.text = "Running — \(scriptModel.name)"
            stopButton.isEnabled = true
        case .stopped:
            statusDot.backgroundColor = UIColor(white: 0.45, alpha: 1)
            titleLabel.text = "Stopped"
            stopButton.isEnabled = false
        case .error:
            statusDot.backgroundColor = UIColor(named: "RED")
            titleLabel.text = "Error"
            stopButton.isEnabled = false
        }
    }

    // MARK: - Output

    private static let tsFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    private func appendOutput(_ text: String, color: UIColor) {
        let ts = "[\(Self.tsFormatter.string(from: Date()))] "
        let line = NSAttributedString(string: "\(ts)\(text)\n", attributes: [
            .font: AppFont.regular(12),
            .foregroundColor: color,
        ])
        outputText.append(line)
        outputView.attributedText = outputText
        outputView.scrollRangeToVisible(NSRange(location: outputText.length - 1, length: 1))
    }

    // MARK: - Execution

    private func startExecution() {
        guard FridaChecker.isRunning() else {
            appendOutput("Frida server is not running. Start it from the Setup Frida tab.", color: errorColor)
            setStatus(.error)
            return
        }

        appendOutput("Starting script: \(scriptModel.name)", color: systemColor)
        appendOutput("Waiting for app selection…", color: systemColor)

        let picker = AppPickerViewController()
        picker.modalPresentationStyle = .formSheet

        picker.onSelect = { [weak self] app in
            guard let self else { return }
            self.pidLabel.text = "PID: \(app.pid) — \(app.name)"
            self.executeOnTarget(pid: UInt(app.pid))
        }

        picker.onCancel = { [weak self] in
            self?.setStatus(.stopped)
            self?.appendOutput("Cancelled — no app selected.", color: self?.systemColor ?? .gray)
        }

        present(picker, animated: true)
    }

    private func executeOnTarget(pid: UInt) {
        Task {
            do {
                await log("Attaching to PID \(pid)…", systemColor)
                await MainActor.run { setStatus(.connecting) }

                let session = try await FridaManager.shared.beginScript(
                    source: scriptModel.source, pid: pid)
                self.scriptSession = session

                eventTask = Task { [weak self] in
                    guard let self else { return }
                    for await rawJSON in session.rawMessages {
                        await self.handleRawMessage(rawJSON)
                    }
                    await log("Event stream ended.", systemColor)
                    if !self.didReceiveOutput {
                        await log("(script produced no output)", systemColor)
                    }
                    await MainActor.run {
                        self.isRunning = false
                        self.setStatus(.stopped)
                    }
                }

                await MainActor.run {
                    isRunning = true
                    setStatus(.running)
                }
                await log("Script loaded and running.", systemColor)
            } catch {
                await log("Failed: \(error.localizedDescription)", errorColor)
                await MainActor.run { setStatus(.error) }
            }
        }
    }

    private func handleRawMessage(_ rawJSON: String) async {
        guard let data = rawJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let msgType = dict["type"] as? String

        switch msgType {
        case "send":
            let (text, color) = parseSendPayload(dict["payload"])
            didReceiveOutput = true
            await log(text, color)
        case "error":
            let desc = dict["description"] as? String ?? "Unknown script error"
            didReceiveOutput = true
            await log("ERROR: \(desc)", errorColor)
            if let stack = dict["stack"] as? String { await log(stack, errorColor) }
        case "log":
            let level = dict["level"] as? String ?? "info"
            let text = dict["payload"] as? String ?? rawJSON
            didReceiveOutput = true
            await log(text, level == "error" ? errorColor : logColor)
        default:
            break
        }
    }

    /// Thread-safe logging helper — dispatches to MainActor.
    private func log(_ text: String, _ color: UIColor) async {
        await MainActor.run { appendOutput(text, color: color) }
    }

    private func parseSendPayload(_ payload: Any?) -> (String, UIColor) {
        if let dict = payload as? [String: Any] {
            let logType = dict["type"] as? String ?? "log"
            let msg = dict["message"] as? String ?? "\(dict)"
            let color: UIColor = logType == "error" ? errorColor
                : logType == "result" ? resultColor : logColor
            return (msg, color)
        }
        return ("\(payload ?? "nil")", logColor)
    }

    // MARK: - Stop

    private func stopExecution() {
        guard isRunning else { return }
        isRunning = false
        eventTask?.cancel()
        eventTask = nil

        if let session = scriptSession {
            scriptSession = nil
            Task { await session.finish() }
        }
    }

    @objc private func stopTapped() {
        stopExecution()
        setStatus(.stopped)
        appendOutput("Stopped by user.", color: systemColor)
    }

    // MARK: - Actions

    @objc private func backTapped() {
        stopExecution()
        navigationController?.popViewController(animated: true)
    }

    @objc private func clearTapped() {
        outputText.setAttributedString(NSAttributedString())
        outputView.attributedText = outputText
    }

    @objc private func shareTapped() {
        let plain = outputText.string
        guard !plain.isEmpty else { return }
        let activity = UIActivityViewController(activityItems: [plain], applicationActivities: nil)
        activity.overrideUserInterfaceStyle = .dark
        if let pop = activity.popoverPresentationController {
            pop.sourceView = shareButton
            pop.sourceRect = shareButton.bounds
        }
        present(activity, animated: true)
    }
}
