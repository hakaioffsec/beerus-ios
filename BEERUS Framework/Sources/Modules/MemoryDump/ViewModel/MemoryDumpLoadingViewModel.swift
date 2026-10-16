import Foundation

final class MemoryDumpLoadingViewModel {

    weak var coordinator: MemoryDumpCoordinator?

    private let app: AppModel

    var onPhase: (MemoryDumpPhase) -> Void = { _ in }
    var onLog: (String) -> Void = { _ in }
    var onSuccess: (String) -> Void = { _ in }
    var onError: (Error) -> Void = { _ in }

    private var dumpTask: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
    }

    func viewDidLoad() {
        startDump()
    }

    func cancel() {
        dumpTask?.cancel()
    }

    private func startDump() {
        dumpTask = Task {
            do {
                let startTime = Date()

                onPhase(.connecting)

                guard FridaChecker.isRunning() else {
                    throw DumpError.fridaNotRunning
                }

                onPhase(.attaching)

                let safeName = app.name.replacingOccurrences(of: " ", with: "_")
                let outputDir = NSTemporaryDirectory() + "beerus_memdump_\(safeName)_\(Int(Date().timeIntervalSince1970))"

                onPhase(.dumping)

                try Task.checkCancellation()

                let result = try await FridaManager.shared.dumpMemory(
                    pid: app.pid,
                    outputDir: outputDir
                ) { msg in
                    self.onLog(msg)
                }

                try Task.checkCancellation()

                onPhase(.packaging)

                let zipPath = NSTemporaryDirectory() + "\(safeName)_memdump.zip"
                try? FileManager.default.removeItem(atPath: zipPath)

                let zipURL = URL(fileURLWithPath: zipPath)
                try ZipArchive.create(
                    at: zipURL,
                    from: URL(fileURLWithPath: outputDir)
                )

                try? FileManager.default.removeItem(atPath: outputDir)

                let duration = Date().timeIntervalSince(startTime)
                let sizeMB = Double(result.dumpedBytes) / 1_048_576

                onPhase(.complete)
                onSuccess(
                    "\(result.dumpedRanges) regions (\(String(format: "%.1f", sizeMB)) MB)\n"
                    + "\(String(format: "%.1f", duration))s"
                )
                coordinator?.dumpDidFinish(zipURL: zipURL)
            } catch is CancellationError {
                coordinator?.dumpDidCancel()
            } catch {
                onError(error)
            }
        }
    }
}
