import UIKit

final class SandboxExfiltrationAppDetailViewController: UIViewController {

    private let appInfo: AppManager.AppInfo
    private let bundleId: String

    private var isUSBMode: Bool = true
    private var serverAddress: String = ""
    private var isAddressValid: Bool = true
    private var isServerOnline: Bool = false
    private var serverCheckTask: URLSessionDataTask?
    private var debounceTimer: Timer?

    private let addressRegex = try! NSRegularExpression(
        pattern: "^((https?://))?((localhost)|(\\d{1,3}\\.){3}\\d{1,3}|([\\dA-Za-z-]+\\.)+[A-Za-z]{2,})(:(?:[1-9]\\d{0,3}|[1-5]\\d{4}|6[0-4]\\d{3}|65[0-4]\\d{2}|655[0-2]\\d|6553[0-5]))?(\\/([\\w %&,.~\\-]+)?)*\\/?$",
        options: []
    )

    private lazy var grabberView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.gray
        view.layer.cornerRadius = 2.5
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 28
        imageView.clipsToBounds = true
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.boldSystemFont(ofSize: 18)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var bundleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .gray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var storageSizeLabel: UILabel = {
        let label = UILabel()
        label.text = "Calculating size..."
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .gray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var modeToggle: UISegmentedControl = {
        let control = UISegmentedControl(items: ["USB", "VPS"])
        control.selectedSegmentIndex = 0
        control.backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
        control.selectedSegmentTintColor = UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: UIColor.lightGray], for: .normal)
        control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private lazy var serverTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "http://192.168.1.100:8080"
        textField.textColor = .white
        textField.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1)
        textField.layer.borderColor = UIColor.darkGray.cgColor
        textField.layer.borderWidth = 1
        textField.layer.cornerRadius = 8
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        textField.rightViewMode = .always
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .URL
        textField.returnKeyType = .done
        textField.addTarget(self, action: #selector(serverAddressChanged), for: .editingChanged)
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    private lazy var validationLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = .systemRed
        label.textAlignment = .left
        label.text = "Invalid server address"
        label.isHidden = true
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var serverStatusView: UIView = {
        let view = UIView()
        view.backgroundColor = .darkGray
        view.layer.cornerRadius = 5
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var serverStatusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = .gray
        label.text = ""
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var serverCheckingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .gray
        indicator.hidesWhenStopped = true
        indicator.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var compactButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Compact", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        button.backgroundColor = UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        button.layer.cornerRadius = 8
        button.addTarget(self, action: #selector(compactTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    init(appInfo: AppManager.AppInfo, bundleId: String) {
        self.appInfo = appInfo
        self.bundleId = bundleId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        applyViewCode()
        configureAppInfo()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func configureAppInfo() {
        nameLabel.text = appInfo.name
        bundleLabel.text = bundleId

        if !appInfo.icone.isEmpty,
           let image = UIImage(contentsOfFile: appInfo.icone) {
            iconImageView.image = image
        } else {
            iconImageView.image = UIImage(systemName: "app.fill")
        }

        if appInfo.dataContainer.isEmpty {
            compactButton.isEnabled = false
            compactButton.backgroundColor = UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
        }

        updateServerTextFieldForMode()
        updateServerStatusUI(status: .idle)

        calculateStorageSize()
        serverTextField.delegate = self
    }

    @objc private func modeChanged() {
        isUSBMode = modeToggle.selectedSegmentIndex == 0

        serverCheckTask?.cancel()
        debounceTimer?.invalidate()

        UIView.animate(withDuration: 0.25) {
            self.validationLabel.isHidden = self.isUSBMode || self.isAddressValid
            self.validationLabel.alpha = (self.isUSBMode || self.isAddressValid) ? 0 : 1
        }

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

    @objc private func serverAddressChanged() {
        serverAddress = serverTextField.text ?? ""
        validateServerAddress()
        checkServerStatus()
        updateCompactButtonState()
    }

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

        UIView.animate(withDuration: 0.2) {
            self.validationLabel.isHidden = !showError
            self.validationLabel.alpha = showError ? 1 : 0
            self.serverTextField.layer.borderColor = showError
                ? UIColor.systemRed.cgColor
                : UIColor.darkGray.cgColor
        }
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
                guard let self = self else { return }

                if let error = error {
                    NSLog("[BEERUS] Server check failed: \(error.localizedDescription)")
                    self.updateServerStatusUI(status: .offline)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let data = data,
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

    private enum ServerStatus: Equatable {
        case idle
        case checking
        case online(version: String)
        case offline
    }

    private func updateServerStatusUI(status: ServerStatus) {
        let shouldHide = isUSBMode || (status == .idle && serverAddress.isEmpty)

        serverStatusView.isHidden = shouldHide
        serverStatusLabel.isHidden = shouldHide

        switch status {
        case .idle:
            isServerOnline = false
            serverCheckingIndicator.stopAnimating()
            serverStatusView.backgroundColor = .darkGray
            serverStatusLabel.text = ""
            serverStatusLabel.textColor = .gray

        case .checking:
            isServerOnline = false
            serverCheckingIndicator.startAnimating()
            serverStatusView.backgroundColor = .darkGray
            serverStatusLabel.text = "Checking..."
            serverStatusLabel.textColor = .gray

        case .online(let version):
            isServerOnline = true
            serverCheckingIndicator.stopAnimating()
            serverStatusView.backgroundColor = .systemGreen
            serverStatusLabel.text = "Online (v\(version))"
            serverStatusLabel.textColor = .systemGreen

        case .offline:
            isServerOnline = false
            serverCheckingIndicator.stopAnimating()
            serverStatusView.backgroundColor = .systemRed
            serverStatusLabel.text = "Offline"
            serverStatusLabel.textColor = .systemRed
        }

        updateCompactButtonState()
    }

    private func updateCompactButtonState() {
        let canProceed: Bool
        if isUSBMode {
            canProceed = !appInfo.dataContainer.isEmpty
        } else {
            canProceed = !appInfo.dataContainer.isEmpty && isAddressValid && !serverAddress.isEmpty && isServerOnline
        }

        compactButton.isEnabled = canProceed
        compactButton.backgroundColor = canProceed
            ? UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
            : UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
    }

    private func updateButtonTitle() {
        compactButton.setTitle(isUSBMode ? "Compact" : "Send", for: .normal)
    }

    private func updateServerTextFieldForMode() {
        if isUSBMode {
            serverTextField.text = "/tmp/{Package}.tar.gz"
            serverTextField.textColor = .lightGray
            serverTextField.isUserInteractionEnabled = false
        } else {
            serverTextField.text = serverAddress
            serverTextField.textColor = .white
            serverTextField.isUserInteractionEnabled = true
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
            guard let self = self else { return }

            let result = SandboxExfiltrationService.calculateStorageSize(for: self.bundleId)

            DispatchQueue.main.async {
                switch result {
                case .success(let size):
                    let formatted = SandboxExfiltrationService.formattedSize(size)
                    self.storageSizeLabel.text = "Storage: \(formatted)"
                case .failure:
                    self.storageSizeLabel.text = "Storage: N/A"
                }
            }
        }
    }

    @objc private func compactTapped() {
        guard !appInfo.dataContainer.isEmpty else {
            showAlert(title: "Error", message: "Data container not found for this app")
            return
        }

        compactButton.isEnabled = false
        compactButton.setTitle("", for: .normal)
        loadingIndicator.startAnimating()
        compactButton.backgroundColor = UIColor(red: 0.4, green: 0.1, blue: 0.1, alpha: 1)

        NSLog("[BEERUS] %@", appInfo.dataContainer)
        let dataContainerURL = URL(fileURLWithPath: appInfo.dataContainer)
        let timestamp = Int(Date().timeIntervalSince1970)
        let zipName = "\(bundleId)_\(timestamp).tar.gz"
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent(zipName)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

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

    private func handleUSBSuccess(zipURL: URL) {
        loadingIndicator.stopAnimating()
        compactButton.isEnabled = true
        compactButton.backgroundColor = UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        compactButton.setTitle("Done!", for: .normal)
        serverTextField.text = "/tmp/{Package}.tar.gz"
        print("[Beerus] ZIP created: \(zipURL.path)")
    }

    private func uploadToVPS(zipURL: URL) {
        let serverURL = getServerURL()
        guard let url = URL(string: serverURL) else {
            handleError(NSError(domain: "Beerus", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"]))
            return
        }

        serverTextField.isUserInteractionEnabled = false

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                let fileData = try Data(contentsOf: zipURL)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"

                let boundary = UUID().uuidString
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

                var body = Data()
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(zipURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: application/gzip\r\n\r\n".data(using: .utf8)!)
                body.append(fileData)
                body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

                request.httpBody = body

                let semaphore = DispatchSemaphore(value: 0)
                var uploadError: Error?
                var responseCode: Int = 0

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
                    self.loadingIndicator.stopAnimating()
                    self.compactButton.isEnabled = true
                    self.compactButton.backgroundColor = UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
                    self.serverTextField.isUserInteractionEnabled = true

                    if let error = uploadError {
                        self.compactButton.setTitle("Send", for: .normal)
                        self.showAlert(title: "Error", message: error.localizedDescription)
                    } else if responseCode >= 200 && responseCode < 300 {
                        self.compactButton.setTitle("Sent!", for: .normal)
                        print("[Beerus] File uploaded to: \(serverURL)")
                    } else {
                        self.compactButton.setTitle("Send", for: .normal)
                        self.showAlert(title: "Error", message: "Server returned HTTP \(responseCode)")
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
        loadingIndicator.stopAnimating()
        compactButton.isEnabled = true
        compactButton.backgroundColor = UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        compactButton.setTitle(isUSBMode ? "Compact" : "Send", for: .normal)
        showAlert(title: "Error", message: error.localizedDescription)
    }
}

// MARK: - ViewCode

extension SandboxExfiltrationAppDetailViewController: ViewCode {

    func buildViewHierarchy() {
        view.addSubview(grabberView)
        view.addSubview(iconImageView)
        view.addSubview(nameLabel)
        view.addSubview(bundleLabel)
        view.addSubview(storageSizeLabel)
        view.addSubview(modeToggle)
        view.addSubview(serverTextField)
        view.addSubview(validationLabel)
        view.addSubview(serverStatusView)
        view.addSubview(serverCheckingIndicator)
        view.addSubview(serverStatusLabel)
        view.addSubview(compactButton)
        compactButton.addSubview(loadingIndicator)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            grabberView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            grabberView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 40),
            grabberView.heightAnchor.constraint(equalToConstant: 5),

            iconImageView.topAnchor.constraint(equalTo: grabberView.bottomAnchor, constant: 24),
            iconImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),

            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            bundleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            bundleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bundleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            storageSizeLabel.topAnchor.constraint(equalTo: bundleLabel.bottomAnchor, constant: 8),
            storageSizeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            storageSizeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            modeToggle.topAnchor.constraint(equalTo: storageSizeLabel.bottomAnchor, constant: 20),
            modeToggle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            modeToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            modeToggle.heightAnchor.constraint(equalToConstant: 36),

            serverTextField.topAnchor.constraint(equalTo: modeToggle.bottomAnchor, constant: 12),
            serverTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            serverTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            serverTextField.heightAnchor.constraint(equalToConstant: 44),

            validationLabel.topAnchor.constraint(equalTo: serverTextField.bottomAnchor, constant: 4),
            validationLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            validationLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            serverStatusView.topAnchor.constraint(equalTo: serverTextField.bottomAnchor, constant: 8),
            serverStatusView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            serverStatusView.widthAnchor.constraint(equalToConstant: 10),
            serverStatusView.heightAnchor.constraint(equalToConstant: 10),

            serverCheckingIndicator.centerYAnchor.constraint(equalTo: serverStatusView.centerYAnchor),
            serverCheckingIndicator.leadingAnchor.constraint(equalTo: serverStatusView.trailingAnchor, constant: 6),

            serverStatusLabel.centerYAnchor.constraint(equalTo: serverStatusView.centerYAnchor),
            serverStatusLabel.leadingAnchor.constraint(equalTo: serverStatusView.trailingAnchor, constant: 6),
            serverStatusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            compactButton.topAnchor.constraint(equalTo: serverStatusView.bottomAnchor, constant: 16),
            compactButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            compactButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            compactButton.heightAnchor.constraint(equalToConstant: 48),

            loadingIndicator.centerXAnchor.constraint(equalTo: compactButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: compactButton.centerYAnchor)
        ])
    }
}

// MARK: - UITextFieldDelegate

extension SandboxExfiltrationAppDetailViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
