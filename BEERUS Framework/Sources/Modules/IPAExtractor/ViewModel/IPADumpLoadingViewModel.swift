import Foundation

final class IPADumpLoadingViewModel {

    weak var coordinator: IPAExtractorCoordinator?

    private let app: AppModel

    var onPhase: (DumpPhase) -> Void = { _ in }
    var onLog: (String) -> Void = { _ in }
    var onProgress: (Int, Int) -> Void = { _, _ in }
    var onSuccess: () -> Void = {}
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

                onPhase(.checking)
                onLog("checking frida server")
                onLog("target: \(app.name)")
                onLog("bundle: \(app.bundleIdentifier)")

                guard FridaChecker.isRunning() else {
                    throw DumpError.fridaNotRunning
                }
                onLog("frida server running on port 27042")

                try Task.checkCancellation()

                onPhase(.attaching)
                onLog("attaching to process \(app.pid)")

                let dumpPath = "/tmp/beerus_dump_\(UUID().uuidString)"

                onPhase(.loading)
                onLog("loading dump script")
                onLog("output: \(dumpPath)")

                onPhase(.dumping)
                onLog("dumping binary")

                let bundleInfo = try await FridaManager.shared.dumpExecutable(
                    bundleId: app.bundleIdentifier,
                    pid: app.pid,
                    outputPath: dumpPath
                ) { [weak self] msg in
                    self?.onLog(msg)
                }

                guard FileManager.default.fileExists(atPath: dumpPath) else {
                    throw DumpError.executableNotDumped
                }

                if let attrs = try? FileManager.default.attributesOfItem(atPath: dumpPath),
                   let fileSize = attrs[.size] as? UInt64 {
                    let sizeMB = Double(fileSize) / 1_048_576
                    onLog("executable dumped: \(String(format: "%.2f", sizeMB)) MB")
                } else {
                    onLog("executable dumped successfully")
                }

                onLog("path: \(bundleInfo.bundlePath)")
                onLog("binary: \(bundleInfo.executableName)")

                try Task.checkCancellation()

                let appWithPaths = AppModel(
                    name: bundleInfo.appName,
                    bundleIdentifier: app.bundleIdentifier,
                    bundlePath: bundleInfo.bundlePath,
                    executablePath: bundleInfo.bundlePath + "/" + bundleInfo.executableName,
                    pid: app.pid
                )

                onPhase(.building)
                onLog("creating ipa archive")
                onLog("packaging: \(bundleInfo.appName)")

                let ipaURL = try IPABuilder.build(app: appWithPaths, dumpedExecutable: dumpPath) { [weak self] msg in
                    self?.onLog(msg)
                } progressCallback: { [weak self] done, total in
                    self?.onProgress(done, total)
                }

                try? FileManager.default.removeItem(atPath: dumpPath)

                let duration = Date().timeIntervalSince(startTime)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: ipaURL.path),
                   let fileSize = attrs[.size] as? UInt64 {
                    let sizeMB = Double(fileSize) / 1_048_576
                    onLog("ipa created: \(String(format: "%.2f", sizeMB)) MB")
                }
                onLog("total time: \(String(format: "%.1f", duration))s")

                onPhase(.complete)
                onSuccess()
                coordinator?.dumpDidFinish(ipaURL: ipaURL)
            } catch is CancellationError {
                // Cancelled by the user; the loading screen dismisses itself.
            } catch {
                onError(error)
            }
        }
    }
}
