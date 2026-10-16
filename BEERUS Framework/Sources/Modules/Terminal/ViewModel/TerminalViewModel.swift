import Foundation

final class TerminalViewModel {

    weak var coordinator: TerminalCoordinator?

    var onOutput: (String, TerminalOutputStyle) -> Void = { _, _ in }
    var onClearInput: () -> Void = {}
    var onExecutingChange: (Bool) -> Void = { _ in }
    var onShowHelp: () -> Void = {}
    var onClear: () -> Void = {}

    private var commandHistory: [String] = []
    private var isExecuting = false

    func submit(_ raw: String?) {
        guard let cmd = raw?.trimmingCharacters(in: .whitespaces), !cmd.isEmpty else { return }
        guard !isExecuting else { return }

        onClearInput()

        if commandHistory.last != cmd {
            commandHistory.append(cmd)
        }

        onOutput("root# \(cmd)\n", .command)

        switch cmd.lowercased() {
        case "help":
            onShowHelp()
            return
        case "clear":
            tappedClear()
            return
        case "history":
            printHistory()
            return
        default:
            break
        }

        guard RootExec.isRunning else {
            onOutput("error: beerus daemon is not running\n", .error)
            return
        }

        isExecuting = true
        onExecutingChange(true)

        Task {
            let result = await Task.detached { RootExec.shell(cmd) }.value
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isExecuting = false
                self.onExecutingChange(false)

                if !result.output.isEmpty {
                    self.onOutput(result.output + "\n", .stdout)
                }

                if result.exitCode != 0 {
                    self.onOutput("exit: \(result.exitCode)\n", .error)
                }
            }
        }
    }

    func tappedClear() {
        onClear()
    }

    private func printHistory() {
        if commandHistory.isEmpty {
            onOutput("  (no history)\n", .welcome)
            return
        }
        for (i, cmd) in commandHistory.enumerated() {
            onOutput("  \(i + 1)  \(cmd)\n", .history)
        }
    }
}
