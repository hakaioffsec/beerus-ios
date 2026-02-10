import Foundation
import Frida

final class FridaManager {

    static let shared = FridaManager()
    private let deviceManager = DeviceManager()
    private var device: Device?

    private init() {}

    // MARK: - Public

    func getInstalledApps() async throws -> [AppModel] {
        let apps = try await getDevice().enumerateApplications()
        return apps
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
            .map { AppModel(name: $0.name, bundleIdentifier: $0.identifier,
                           bundlePath: "", executablePath: "", pid: $0.pid ?? 0) }
    }

    func dumpExecutable(bundleId: String, pid: UInt, outputPath: String,
                       onLog: @escaping (String) -> Void) async throws -> BundleInfo {
        device = nil
        let device = try await getDevice()

        onLog("attaching to process")
        let session = try await attachWithRetry(device: device, pid: pid)
        defer { Task { try? await session.detach() } }

        onLog("loading script")
        let script = try await session.createScript(FridaScripts.dumpScript(outputPath: outputPath))

        onLog("extracting binary")
        let result = try await executeScript(script, onLog: onLog)

        guard (result["success"] as? Bool) ?? ((result["success"] as? Int) == 1),
              let bundlePath = result["bundlePath"] as? String,
              let executableName = result["executableName"] as? String else {
            throw FridaError.dumpFailed
        }

        return BundleInfo(
            appName: result["appName"] as? String ?? executableName,
            bundlePath: bundlePath,
            executableName: executableName
        )
    }

    func dumpMemory(pid: UInt, outputDir: String,
                    onLog: @escaping (String) -> Void) async throws -> MemoryDumpResult {
        device = nil
        let device = try await getDevice()

        onLog("attaching to process \(pid)")
        let session = try await attachWithRetry(device: device, pid: pid)
        defer { Task { try? await session.detach() } }

        // Create output directory
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        onLog("loading memory dump script")
        let script = try await session.createScript(FridaScripts.memoryDumpScript(outputDir: outputDir))

        onLog("dumping memory regions")
        let result = try await executeScriptWithProgress(script, onLog: onLog, idleTimeout: 120)

        guard (result["success"] as? Bool) ?? ((result["success"] as? Int) == 1) else {
            throw FridaError.memoryDumpFailed
        }

        return MemoryDumpResult(
            dumpedRanges: result["dumpedRanges"] as? Int ?? 0,
            totalRanges: result["totalRanges"] as? Int ?? 0,
            dumpedBytes: result["dumpedBytes"] as? Int ?? 0,
            errors: result["errors"] as? Int ?? 0
        )
    }

    // MARK: - Private

    private func getDevice() async throws -> Device {
        if let device { return device }
        device = try await deviceManager.addRemoteDevice(address: "localhost")
        return device!
    }

    private func attachWithRetry(device: Device, pid: UInt, attempts: Int = 3,
                                 timeout: Double = 30) async throws -> Session {
        for i in 1...attempts {
            do {
                return try await withTimeout(timeout) { try await device.attach(to: pid) }
            } catch {
                guard i < attempts else { throw error }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        throw FridaError.attachFailed
    }

    private func withTimeout<T>(_ seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw FridaError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// Execute a long-running script with a per-message idle timeout.
    /// The deadline resets every time a log or progress message arrives.
    private func executeScriptWithProgress(_ script: Script, onLog: @escaping (String) -> Void, idleTimeout: TimeInterval = 120) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let lock = NSLock()
            var lastActivity = Date()

            func resumeSuccess(_ value: [String: Any]) {
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                continuation.resume(returning: value)
            }

            func resumeError(_ error: FridaError) {
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                continuation.resume(throwing: error)
            }

            func resumeLoadError(_ error: Swift.Error) {
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                continuation.resume(throwing: error)
            }

            // Subscribe to events BEFORE loading
            let eventTask = Task {
                for await event in script.events {
                    guard case .message(let m, _) = event,
                          let dict = m as? [String: Any] else { continue }

                    let payload = (dict["payload"] as? [String: Any]) ?? dict

                    switch payload["type"] as? String {
                    case "log":
                        lock.lock()
                        lastActivity = Date()
                        lock.unlock()
                        if let msg = payload["message"] as? String {
                            await MainActor.run { onLog(msg) }
                        }
                    case "result":
                        if let data = payload["data"] as? [String: Any] {
                            resumeSuccess(data)
                        } else {
                            resumeError(FridaError.dumpFailed)
                        }
                        return
                    case "error":
                        let msg = payload["message"] as? String ?? "Unknown error"
                        resumeError(FridaError.rpcError(msg))
                        return
                    default:
                        break
                    }
                }
                resumeError(FridaError.rpcError("Event stream ended"))
            }

            Task {
                while true {
                    try? await Task.sleep(nanoseconds: 5_000_000_000) 
                    lock.lock()
                    let done = resumed
                    let elapsed = Date().timeIntervalSince(lastActivity)
                    lock.unlock()
                    if done { return }
                    if elapsed >= idleTimeout {
                        eventTask.cancel()
                        resumeError(FridaError.timeout)
                        return
                    }
                }
            }

            // Load script
            Task {
                do {
                    try await script.load()
                } catch {
                    eventTask.cancel()
                    resumeLoadError(error)
                }
            }
        }
    }

    private func executeScript(_ script: Script, onLog: @escaping (String) -> Void, timeout: UInt64 = 60) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            let lock = NSLock()

            func resumeSuccess(_ value: [String: Any]) {
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                continuation.resume(returning: value)
            }

            func resumeError(_ error: FridaError) {
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                continuation.resume(throwing: error)
            }

            func resumeLoadError(_ error: Swift.Error) {
                lock.lock()
                guard !resumed else { lock.unlock(); return }
                resumed = true
                lock.unlock()
                continuation.resume(throwing: error)
            }

            // Subscribe to events BEFORE loading
            let eventTask = Task {
                for await event in script.events {
                    guard case .message(let m, _) = event,
                          let dict = m as? [String: Any] else { continue }

                    let payload = (dict["payload"] as? [String: Any]) ?? dict

                    switch payload["type"] as? String {
                    case "log":
                        if let msg = payload["message"] as? String {
                            await MainActor.run { onLog(msg) }
                        }
                    case "result":
                        if let data = payload["data"] as? [String: Any] {
                            resumeSuccess(data)
                        } else {
                            resumeError(FridaError.dumpFailed)
                        }
                        return
                    case "error":
                        let msg = payload["message"] as? String ?? "Unknown error"
                        resumeError(FridaError.rpcError(msg))
                        return
                    default:
                        break
                    }
                }
                resumeError(FridaError.rpcError("Event stream ended"))
            }

            Task {
                try? await Task.sleep(nanoseconds: timeout * 1_000_000_000)
                eventTask.cancel()
                resumeError(FridaError.timeout)
            }

            Task {
                do {
                    try await script.load()
                } catch {
                    eventTask.cancel()
                    resumeLoadError(error)
                }
            }
        }
    }
}

struct BundleInfo {
    let appName: String
    let bundlePath: String
    let executableName: String
}

struct MemoryDumpResult {
    let dumpedRanges: Int
    let totalRanges: Int
    let dumpedBytes: Int
    let errors: Int
}

enum FridaError: LocalizedError {
    case attachFailed, timeout, dumpFailed, memoryDumpFailed, rpcError(String)

    var errorDescription: String? {
        switch self {
        case .attachFailed: "Failed to attach to process"
        case .timeout: "Operation timed out"
        case .dumpFailed: "Failed to dump executable"
        case .memoryDumpFailed: "Failed to dump memory"
        case .rpcError(let msg): "RPC error: \(msg)"
        }
    }
}
