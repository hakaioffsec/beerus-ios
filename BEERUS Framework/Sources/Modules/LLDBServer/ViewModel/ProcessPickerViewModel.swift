import Foundation

final class ProcessPickerViewModel {

    var onReload: () -> Void = {}

    private let service: LLDBServerService
    private let onSelect: (DeviceProcess) -> Void
    private var allProcesses: [DeviceProcess] = []
    private var filtered: [DeviceProcess] = []

    init(service: LLDBServerService, onSelect: @escaping (DeviceProcess) -> Void) {
        self.service = service
        self.onSelect = onSelect
    }

    func viewDidLoad() {
        load()
    }

    func numberOfRows() -> Int { filtered.count }

    func process(at index: Int) -> DeviceProcess { filtered[index] }

    func filter(_ query: String) {
        let lowered = query.lowercased()
        filtered = lowered.isEmpty ? allProcesses : allProcesses.filter {
            $0.name.lowercased().contains(lowered) || $0.pid.contains(lowered)
        }
        onReload()
    }

    func selectProcess(at index: Int) {
        onSelect(filtered[index])
    }

    private func load() {
        let service = self.service
        Task {
            let procs = await Task.detached(priority: .userInitiated) { service.listProcesses() }.value
            await MainActor.run {
                self.allProcesses = procs
                self.filtered = procs
                self.onReload()
            }
        }
    }
}
