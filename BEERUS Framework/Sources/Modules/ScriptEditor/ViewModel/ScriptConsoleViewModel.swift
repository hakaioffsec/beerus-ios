import Foundation

final class ScriptConsoleViewModel {

    weak var coordinator: ScriptEditorCoordinator?

    private let scriptModel: FridaScriptModel
    private var scriptSession: ScriptSession?
    private var eventTask: Task<Void, Never>?
    private var isRunning = false
    private var didReceiveOutput = false

    var onStatus: (ConsoleStatus, String) -> Void = { _, _ in }
    var onLine: (String, ConsoleLineStyle) -> Void = { _, _ in }
    var onPID: (String) -> Void = { _ in }

    init(script: FridaScriptModel) {
        self.scriptModel = script
    }

    func viewDidLoad() {
        startExecution()
    }

    func viewWillDisappear() {
        stopExecution()
    }

    func stop() {
        stopExecution()
        onStatus(.stopped, "Stopped")
        onLine("Stopped by user.", .system)
    }

    func tappedBack() {
        stopExecution()
        coordinator?.pop()
    }

    func tappedShare(_ text: String) {
        guard !text.isEmpty else { return }
        coordinator?.shareText(text)
    }

    // MARK: - Execution

    private func startExecution() {
        guard FridaChecker.isRunning() else {
            onLine("Frida server is not running. Start it from the Setup Frida tab.", .error)
            onStatus(.error, "Error")
            return
        }

        onLine("Starting script: \(scriptModel.name)", .system)
        onLine("Waiting for app selection…", .system)

        coordinator?.presentAppPicker(
            onSelect: { [weak self] app in
                guard let self else { return }
                self.onPID("PID: \(app.pid) — \(app.name)")
                self.executeOnTarget(pid: UInt(app.pid))
            },
            onCancel: { [weak self] in
                self?.onStatus(.stopped, "Stopped")
                self?.onLine("Cancelled — no app selected.", .system)
            }
        )
    }

    private func executeOnTarget(pid: UInt) {
        Task { [weak self] in
            guard let self else { return }
            do {
                await self.log("Attaching to PID \(pid)…", .system)
                await MainActor.run { self.onStatus(.connecting, "Connecting…") }

                let session = try await FridaManager.shared.beginScript(source: self.scriptModel.source, pid: pid)
                self.scriptSession = session

                self.eventTask = Task {
                    for await rawJSON in session.rawMessages {
                        await self.handleRawMessage(rawJSON)
                    }
                    await self.log("Event stream ended.", .system)
                    if !self.didReceiveOutput {
                        await self.log("(script produced no output)", .system)
                    }
                    await MainActor.run {
                        self.isRunning = false
                        self.onStatus(.stopped, "Stopped")
                    }
                }

                await MainActor.run {
                    self.isRunning = true
                    self.onStatus(.running, "Running — \(self.scriptModel.name)")
                }
                await self.log("Script loaded and running.", .system)
            } catch {
                await self.log("Failed: \(error.localizedDescription)", .error)
                await MainActor.run { self.onStatus(.error, "Error") }
            }
        }
    }

    private func handleRawMessage(_ rawJSON: String) async {
        guard let data = rawJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        switch dict["type"] as? String {
        case "send":
            let (text, style) = parseSendPayload(dict["payload"])
            didReceiveOutput = true
            await log(text, style)
        case "error":
            let desc = dict["description"] as? String ?? "Unknown script error"
            didReceiveOutput = true
            await log("ERROR: \(desc)", .error)
            if let stack = dict["stack"] as? String { await log(stack, .error) }
        case "log":
            let level = dict["level"] as? String ?? "info"
            let text = dict["payload"] as? String ?? rawJSON
            didReceiveOutput = true
            await log(text, level == "error" ? .error : .log)
        default:
            break
        }
    }

    private func log(_ text: String, _ style: ConsoleLineStyle) async {
        await MainActor.run { onLine(text, style) }
    }

    private func parseSendPayload(_ payload: Any?) -> (String, ConsoleLineStyle) {
        if let dict = payload as? [String: Any] {
            let logType = dict["type"] as? String ?? "log"
            let msg = dict["message"] as? String ?? "\(dict)"
            let style: ConsoleLineStyle = logType == "error" ? .error
                : logType == "result" ? .result : .log
            return (msg, style)
        }
        return ("\(payload ?? "nil")", .log)
    }

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
}
