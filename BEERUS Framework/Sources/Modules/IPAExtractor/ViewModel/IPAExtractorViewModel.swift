import UIKit

final class IPAExtractorViewModel {

    struct State {
        let statusText: String
        let buttonTitle: String
        let isDumpEnabled: Bool
    }

    weak var coordinator: IPAExtractorCoordinator?

    var onState: (State) -> Void = { _ in }

    private var observers: [NSObjectProtocol] = []

    func viewDidLoad() {
        emitStatus(FridaChecker.isRunning())

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.emitStatus(FridaChecker.isRunning())
        })
        observers.append(center.addObserver(forName: FridaChecker.statusDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            FridaChecker.checkAfterDelay { running in
                self?.emitStatus(running)
            }
        })
    }

    func tappedDump() {
        coordinator?.showInstalledApps()
    }

    private func emitStatus(_ running: Bool) {
        onState(State(
            statusText: running ? "Frida: Running" : "Frida: Not Running",
            buttonTitle: running ? "Dump IPA" : "Frida OFF",
            isDumpEnabled: running
        ))
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}
