import Foundation
import Frida

final class SpawnGateService {
    static let shared = SpawnGateService()

    private var device: Device?
    private var gatingTask: Task<Void, Never>?
    private var isRunning = false
    private let deviceManager = DeviceManager()

    var onLog: ((String) -> Void)?
    var onStatusChange: ((Bool) -> Void)?

    private init() {}

    // MARK: - Public

    var isActive: Bool { isRunning }

    func start() async throws {
        guard !isRunning else { return }

        log("Starting spawn gating...")

        do {
            device = try await deviceManager.addRemoteDevice(address: "localhost")
            guard let device else { throw SpawnGateError.deviceNotAvailable }

            try await device.enableSpawnGating()
            isRunning = true
            onStatusChange?(true)
            log("Spawn gating enabled")

            gatingTask = Task { [weak self] in
                await self?.pollPendingSpawns()
            }
        } catch {
            isRunning = false
            onStatusChange?(false)
            log("Failed to enable spawn gating: \(error.localizedDescription)")
            throw error
        }
    }

    func stop() async {
        guard isRunning else { return }

        log("Stopping spawn gating...")

        isRunning = false
        gatingTask?.cancel()
        gatingTask = nil

        do {
            try await device?.disableSpawnGating()
        } catch {
            log("Error disabling spawn gating: \(error.localizedDescription)")
        }

        onStatusChange?(false)
        log("Spawn gating stopped")
    }

    // MARK: - Private

    private func pollPendingSpawns() async {
        guard let device else { return }

        while isRunning {
            do {
                let spawns = try await device.enumeratePendingSpawn()

                for spawn in spawns {
                    guard isRunning else { break }
                    await injectBypassAndResume(device: device, spawn: spawn)
                }

                // Poll interval
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            } catch {
                if isRunning {
                    log("Poll error: \(error.localizedDescription)")
                }
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms backoff
            }
        }
    }

    private func injectBypassAndResume(device: Device, spawn: SpawnDetails) async {
        let pid = spawn.pid
        let identifier = spawn.identifier ?? "pid:\(pid)"

        log("Spawn: \(identifier)")

        do {
            // Timeout: 5 seconds max for entire injection
            try await withTimeout(5) { [self] in
                let session = try await device.attach(to: pid)
                let script = try await session.createScript(JBBypassScript.source)
                try await script.load()
                self.log("Injected: \(identifier)")
            }
        } catch {
            log("Injection failed for \(identifier): \(error.localizedDescription)")
        }

        // ALWAYS resume - fail-open pattern
        do {
            try await device.resume(pid)
        } catch {
            log("Resume failed for \(identifier): \(error.localizedDescription)")
        }
    }

    private func withTimeout<T>(_ seconds: Double, _ op: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SpawnGateError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    private func log(_ message: String) {
        let formatted = "[SpawnGate] \(message)"
        print(formatted)
        Task { @MainActor in
            onLog?(formatted)
        }
    }
}

enum SpawnGateError: LocalizedError {
    case timeout
    case deviceNotAvailable

    var errorDescription: String? {
        switch self {
        case .timeout: "Operation timed out"
        case .deviceNotAvailable: "Frida device not available"
        }
    }
}
