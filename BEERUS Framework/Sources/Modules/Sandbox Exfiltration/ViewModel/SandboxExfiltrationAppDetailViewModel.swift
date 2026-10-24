import Foundation

final class SandboxExfiltrationAppDetailViewModel {

    enum ServerStatus: Equatable {
        case idle
        case checking
        case online(version: String)
        case offline
    }

    struct AppDisplay {
        let name: String
        let bundleId: String
        let iconPath: String
        let hasDataContainer: Bool
    }

    weak var coordinator: SandboxExfiltrationCoordinator?

    private let appInfo: AppManager.AppInfo
    let bundleId: String
    private(set) var isUSBMode = true
    private var serverAddress = ""
    private(set) var isAddressValid = true
    private(set) var isServerOnline = false
    private var serverCheckTask: URLSessionDataTask?
    private var debounceTimer: Timer?

    private let addressRegex = try! NSRegularExpression(
        pattern: "^((https?://))?((localhost)|(\\d{1,3}\\.){3}\\d{1,3}|([\\dA-Za-z-]+\\.)+[A-Za-z]{2,})(:(?:[1-9]\\d{0,3}|[1-5]\\d{4}|6[0-4]\\d{3}|65[0-4]\\d{2}|655[0-2]\\d|6553[0-5]))?(\\/([\\w %&,.~\\-]+)?)*\\/?$",
        options: []
    )

    var onAppDisplay: (AppDisplay) -> Void = { _ in }
    var onStorageSize: (String) -> Void = { _ in }
    var onServerTextField: (String, Bool) -> Void = { _, _ in }
    var onServerTextFieldColor: (Bool) -> Void = { _ in }
    var onValidation: (Bool) -> Void = { _ in }
    var onServerStatus: (ServerStatus, Bool) -> Void = { _, _ in }
    var onCompactButton: (Bool, String) -> Void = { _, _ in }
    var onLoading: (Bool) -> Void = { _ in }
    var onCompactSuccess: (String) -> Void = { _ in }

    init(appInfo: AppManager.AppInfo, bundleId: String) {
        self.appInfo = appInfo
        self.bundleId = bundleId
    }

    func viewDidLoad() {
        let display = AppDisplay(
            name: appInfo.name,
            bundleId: bundleId,
            iconPath: appInfo.icone,
            hasDataContainer: !appInfo.dataContainer.isEmpty
        )
        onAppDisplay(display)
        updateServerTextFieldForMode()
        updateServerStatusUI(status: .idle)
        calculateStorageSize()
    }

    func modeChanged(index: Int) {
        isUSBMode = index == 0

        serverCheckTask?.cancel()
        debounceTimer?.invalidate()

        let showError = !isUSBMode && !isAddressValid && !serverAddress.isEmpty
        onValidation(showError)

        if isUSBMode {
            updateServerStatusUI(status: .idle)
        } else if !serverAddress.isEmpty && isAddressValid {
            checkServerStatus()
        } else {
            updateServerStatusUI(status: .idle)
        }

        updateCompactButtonState()
        updateButtonTitle()
        updateServerTextFieldForMode()
    }

    func serverAddressChanged(_ text: String) {
        serverAddress = text
        validateServerAddress()
        checkServerStatus()
        updateCompactButtonState()
    }

    func compactTapped() {
        guard !appInfo.dataContainer.isEmpty else {
            coordinator?.showError(
                title: "Error",
                message: "Data container not found for this app"
            )
            return
        }

        onLoading(true)
        onCompactButton(false, "")

        let dataContainerURL = URL(fileURLWithPath: appInfo.dataContainer)
        let timestamp = Int(Date().timeIntervalSince1970)
        let zipName = "\(bundleId)_\(timestamp).tar.gz"
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(zipName)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let result = SandboxExfiltrationService.compactDirectory(
                at: dataContainerURL,
                to: zipURL,
                rootName: self.bundleId,
                progress: nil
            )

            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    if self.isUSBMode {
                        self.handleUSBSuccess(zipURL: url)
                    } else {
                        self.uploadToVPS(zipURL: url)
                    }
                case .failure(let error):
                    self.handleError(error)
                }
            }
        }
    }

    // MARK: - Private

    private func validateServerAddress() {
        guard !serverAddress.isEmpty else {
            isAddressValid = true
            updateValidationUI()
            return
        }

        let range = NSRange(location: 0, length: serverAddress.utf16.count)
        isAddressValid = addressRegex.firstMatch(in: serverAddress, options: [], range: range) != nil
        updateValidationUI()
    }

    private func updateValidationUI() {
        let showError = !isUSBMode && !isAddressValid && !serverAddress.isEmpty
        onValidation(showError)
        onServerTextFieldColor(!showError)
    }

    private func checkServerStatus() {
        serverCheckTask?.cancel()
        debounceTimer?.invalidate()

        guard !serverAddress.isEmpty && isAddressValid else {
            updateServerStatusUI(status: .idle)
            return
        }

        updateServerStatusUI(status: .checking)

        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.performServerCheck()
        }
    }

    private func performServerCheck() {
        let baseURL = getServerURL()
        guard let url = URL(string: "\(baseURL)/check") else {
            updateServerStatusUI(status: .offline)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        serverCheckTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if error != nil {
                    self.updateServerStatusUI(status: .offline)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let app = json["app"] as? String,
                      app == "Beerus Server" else {
                    self.updateServerStatusUI(status: .offline)
                    return
                }

                let version = json["version"] as? String ?? "?"
                self.updateServerStatusUI(status: .online(version: version))
            }
        }
        serverCheckTask?.resume()
    }

    private func updateServerStatusUI(status: ServerStatus) {
        let shouldHide = isUSBMode || (status == .idle && serverAddress.isEmpty)

        switch status {
        case .idle, .checking:
            isServerOnline = false
        case .online:
            isServerOnline = true
        case .offline:
            isServerOnline = false
        }

        onServerStatus(status, shouldHide)
        updateCompactButtonState()
    }

    private func updateCompactButtonState() {
        let canProceed: Bool
        if isUSBMode {
            canProceed = !appInfo.dataContainer.isEmpty
        } else {
            canProceed = !appInfo.dataContainer.isEmpty
                && isAddressValid
                && !serverAddress.isEmpty
                && isServerOnline
        }
        onCompactButton(canProceed, isUSBMode ? "Compact" : "Send")
    }

    private func updateButtonTitle() {
        onCompactButton(true, isUSBMode ? "Compact" : "Send")
    }

    private func updateServerTextFieldForMode() {
        if isUSBMode {
            onServerTextField("/tmp/{Package}.tar.gz", false)
            onServerTextFieldColor(true)
        } else {
            onServerTextField(serverAddress, true)
            onServerTextFieldColor(true)
        }
    }

    private func getServerURL() -> String {
        let address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.hasPrefix("http://") || address.hasPrefix("https://") {
            return address
        }
        return "http://\(address)"
    }

    private func calculateStorageSize() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let result = SandboxExfiltrationService.calculateStorageSize(for: self.bundleId)

            DispatchQueue.main.async {
                switch result {
                case .success(let size):
                    let formatted = SandboxExfiltrationService.formattedSize(size)
                    self.onStorageSize("Storage: \(formatted)")
                case .failure:
                    self.onStorageSize("Storage: N/A")
                }
            }
        }
    }

    private func handleUSBSuccess(zipURL: URL) {
        onLoading(false)
        onCompactButton(true, "Done!")
        onServerTextField("/tmp/{Package}.tar.gz", false)
    }

    private func uploadToVPS(zipURL: URL) {
        let serverURL = getServerURL()
        guard let url = URL(string: serverURL) else {
            handleError(NSError(
                domain: "Beerus",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"]
            ))
            return
        }

        onServerTextField(serverAddress, false)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            do {
                let fileData = try Data(contentsOf: zipURL)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"

                let boundary = UUID().uuidString
                request.setValue(
                    "multipart/form-data; boundary=\(boundary)",
                    forHTTPHeaderField: "Content-Type"
                )

                var body = Data()
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(zipURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/gzip\r\n\r\n".data(using: .utf8)!)
                body.append(fileData)
                body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

                request.httpBody = body

                let semaphore = DispatchSemaphore(value: 0)
                var uploadError: Error?
                var responseCode = 0

                let task = URLSession.shared.dataTask(with: request) { _, response, error in
                    uploadError = error
                    if let httpResponse = response as? HTTPURLResponse {
                        responseCode = httpResponse.statusCode
                    }
                    semaphore.signal()
                }
                task.resume()
                semaphore.wait()

                DispatchQueue.main.async {
                    self.onLoading(false)
                    self.onServerTextField(self.serverAddress, true)

                    if let error = uploadError {
                        self.onCompactButton(true, "Send")
                        self.coordinator?.showError(title: "Error", message: error.localizedDescription)
                    } else if responseCode >= 200 && responseCode < 300 {
                        self.onCompactButton(true, "Sent!")
                    } else {
                        self.onCompactButton(true, "Send")
                        self.coordinator?.showError(title: "Error", message: "Server returned HTTP \(responseCode)")
                    }

                    try? FileManager.default.removeItem(at: zipURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.handleError(error)
                }
            }
        }
    }

    private func handleError(_ error: Error) {
        onLoading(false)
        onCompactButton(true, isUSBMode ? "Compact" : "Send")
        coordinator?.showError(title: "Error", message: error.localizedDescription)
    }
}
