import UIKit

final class SetupFridaViewController: BaseViewController {

    private var dropdown: SimpleDropdown?
    private var dropdownBackdrop: UIControl?
    private var versions: [String] = []
    private var selectedVersion: String = ""
    private var versionRunning: String = ""
    private var isRunning: Bool = false
    private var startDownloading: Bool = false

    @objc private func onVersionsTap(_ sender: UIButton) {
        if dropdown != nil { hideDropdown(); return }
        showDropdown()
    }

    private func askFridaVersion(showError: Bool = false) {
        let message = showError
            ? "Invalid version. Please enter a valid Frida version."
            : "Write a version of Frida"

        Alert.showInput(
            title: "Frida Version",
            message: message,
            placeholder: "16.7.12",
            keyboardType: .decimalPad

        ) { [weak self] versionSelected in
            guard let self = self else { return }

            guard let versionSelected = versionSelected else {
                return
            }

            let trimmed = versionSelected.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty else {
                self.askFridaVersion(showError: true)
                return
            }

            Github.verifyVersion(repository: "frida/frida", version: trimmed) { [weak self] isValid in
                DispatchQueue.main.async {
                    guard let self = self else { return }

                    if isValid {
                        self.versionDropdown.setTitle(trimmed, for: .normal)
                        self.hideDropdown()
                        self.selectedVersion = trimmed
                    } else {
                        self.askFridaVersion(showError: true)
                    }
                }
            }
        }
    }


    private func showDropdown() {
        guard let window = view.window ?? UIApplication.shared.windows.first else { return }

        let backdrop = UIControl(frame: window.bounds)
        backdrop.backgroundColor = .clear
        backdrop.addTarget(self, action: #selector(onBackdropTap), for: .touchUpInside)
        window.addSubview(backdrop)
        dropdownBackdrop = backdrop

        let dd = SimpleDropdown(items: versions)
        dd.backgroundColor = versionDropdown.backgroundColor ?? .white
        dd.layer.cornerRadius = versionDropdown.layer.cornerRadius

        dd.itemFont = versionDropdown.titleLabel?.font
        dd.itemTextColor = versionDropdown.titleColor(for: .normal)

        dd.onSelect = { [weak self] value in
            if (value == "Add version manually") {
                self?.askFridaVersion(showError: false)
            } else {
                self?.versionDropdown.setTitle(value, for: .normal)
                self?.hideDropdown()
                self?.selectedVersion = value
            }

        }

        dd.show(
            from: versionDropdown,
            widthAnchor: stackView,
            in: window,
            maxRows: 6,
            rowHeight: 44
        )

        dropdown = dd
    }

    @objc private func onBackdropTap() {
        hideDropdown()
    }

    private func hideDropdown() {
        dropdown?.removeFromSuperview()
        dropdown = nil

        dropdownBackdrop?.removeFromSuperview()
        dropdownBackdrop = nil
    }

    // MARK: - Frida Helpers

    private func fridaDaemonExists() -> Bool {
        let result = RootExec.shell("test -f \(BeerusStrings.fridaDaemonPath) && echo 1")
        return result.output.contains("1")
    }

    private func showDownloadProgress(_ text: String, fraction: Float) {
        downloadProgressLabel.isHidden = false
        downloadProgressBar.isHidden = false
        downloadProgressLabel.text = text
        downloadProgressBar.setProgress(fraction, animated: true)
    }

    private func hideDownloadProgress() {
        downloadProgressLabel.isHidden = true
        downloadProgressBar.isHidden = true
        downloadProgressBar.setProgress(0, animated: false)
    }

    @objc private func ToggleFrida(_ sender: UIButton) {
        buttonStart.isEnabled = false

        if isRunning {
            // Stop Frida
            if fridaDaemonExists() {
                RootExec.shellAwait("\(BeerusStrings.launchctlBin) bootout system \(BeerusStrings.fridaDaemonPath)") { _ in
                    DispatchQueue.main.async {
                        self.buttonStart.isEnabled = true
                        self.checkFridaRunning()
                    }
                }
            } else {
                RootExec.shellAwait("killall frida-server") { _ in
                    DispatchQueue.main.async {
                        self.buttonStart.isEnabled = true
                        self.checkFridaRunning()
                    }
                }
            }
        } else if !versionRunning.isEmpty && selectedVersion == versionRunning && fridaDaemonExists() {
            // Start existing version (já instalado)
            RootExec.shellAwait("\(BeerusStrings.launchctlBin) bootstrap system \(BeerusStrings.fridaDaemonPath)") { _ in
                DispatchQueue.main.async {
                    self.buttonStart.isEnabled = true
                    self.checkFridaRunning()
                }
            }
        } else if !selectedVersion.isEmpty {
            // Download and install new version
            startDownloading = true
            checkFridaRunning()
            DispatchQueue.main.async { self.showDownloadProgress("Detecting device architecture...", fraction: 0.02) }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }

                // Obtém arquitetura via dpkg
                let archResult = RootExec.shell("\(BeerusStrings.dpkgBin) --print-architecture")
                let arch = archResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !arch.isEmpty else {
                    DispatchQueue.main.async {
                        self.startDownloading = false
                        self.buttonStart.isEnabled = true
                        self.checkFridaRunning()
                        self.hideDownloadProgress()
                        Alert.show(title: "Error", message: "Could not detect device architecture")
                    }
                    return
                }

                let debFileName = "frida-server.deb"
                let downloadURL = "https://github.com/frida/frida/releases/download/\(self.selectedVersion)/frida_\(self.selectedVersion)_\(arch).deb"
                let appTmpDir = NSTemporaryDirectory()
                let systemDebPath = BeerusStrings.tmp + debFileName

                NSLog("[Frida] Architecture: \(arch)")
                NSLog("[Frida] Downloading from: \(downloadURL)")
                NSLog("[Frida] App tmp: \(appTmpDir)")
                NSLog("[Frida] System tmp: \(BeerusStrings.tmp)")

                // Baixa para o tmp do app (sandbox permite)
                Requests.downloadFile(
                    from: downloadURL,
                    fileName: debFileName,
                    destinationPath: appTmpDir,
                    progress: { downloaded, total in
                        DispatchQueue.main.async {
                            let pct = total > 0 ? Double(downloaded) / Double(total) : 0
                            let dlMB = Double(downloaded) / 1_048_576
                            let totalMB = Double(total) / 1_048_576
                            let text = total > 0
                                ? String(format: "%.1f / %.1f MB · %.0f%%", dlMB, totalMB, pct * 100)
                                : "Downloading..."
                            // Download itself is 0-80% of the bar; copy + install fill the rest.
                            self.showDownloadProgress(text, fraction: 0.05 + Float(pct) * 0.75)
                        }
                    }
                ) { result in
                    switch result {
                    case .success(let fileURL):
                        NSLog("[Frida] Download success: \(fileURL.path)")

                        // Verifica tamanho do arquivo
                        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
                        NSLog("[Frida] File size: \(fileSize) bytes")

                        if fileSize < 1000 {
                            DispatchQueue.main.async {
                                self.startDownloading = false
                                self.buttonStart.isEnabled = true
                                self.checkFridaRunning()
                                self.hideDownloadProgress()
                                Alert.show(title: "Download Failed", message: "File is too small or empty")
                            }
                            return
                        }

                        DispatchQueue.main.async {
                            self.showDownloadProgress("Copying to system...", fraction: 0.85)
                        }

                        // Copia para o tmp do sistema via daemon
                        let copyResult = RootExec.shell("cp '\(fileURL.path)' '\(systemDebPath)'")
                        NSLog("[Frida] Copy result: \(copyResult.output), exit: \(copyResult.exitCode)")

                        if copyResult.exitCode != 0 {
                            DispatchQueue.main.async {
                                self.startDownloading = false
                                self.buttonStart.isEnabled = true
                                self.checkFridaRunning()
                                self.hideDownloadProgress()
                                Alert.show(title: "Install Failed", message: "Failed to copy to system tmp")
                            }
                            return
                        }

                        DispatchQueue.main.async {
                            self.showDownloadProgress("Installing frida-server...", fraction: 0.95)
                        }

                        // Instala usando o daemon
                        if let response = RootExec.installFrida(from: systemDebPath) {
                            NSLog("[Frida] Install response: \(response)")

                            // Limpa arquivo temporário
                            // _ = RootExec.shell("rm -f '\(systemDebPath)'")

                            DispatchQueue.main.async {
                                self.startDownloading = false
                                self.buttonStart.isEnabled = true
                                if response.hasPrefix("ok:") {
                                    self.showDownloadProgress("Installed!", fraction: 1.0)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                        self.hideDownloadProgress()
                                    }
                                } else {
                                    self.hideDownloadProgress()
                                    Alert.show(title: "Install Failed", message: response)
                                }
                                self.checkFridaRunning()
                            }
                        } else {
                            DispatchQueue.main.async {
                                self.startDownloading = false
                                self.buttonStart.isEnabled = true
                                self.checkFridaRunning()
                                self.hideDownloadProgress()
                                Alert.show(title: "Install Failed", message: "Daemon not responding")
                            }
                        }
                    case .failure(let error):
                        NSLog("[Frida] Download failed: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.startDownloading = false
                            self.buttonStart.isEnabled = true
                            self.checkFridaRunning()
                            self.hideDownloadProgress()
                            Alert.show(title: "Download Failed", message: error.localizedDescription)
                        }
                    }
                }
            }
        } else {
            // Nenhuma versão selecionada
            buttonStart.isEnabled = true
            Alert.show(title: "Error", message: "Select a Frida version first")
        }
    }









    private lazy var circuitTopImageView: UIImageView = {
        let image = UIImage(named: "circuit-top")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftImageView: UIImageView = {
        let image = UIImage(named: "circuit-left-2")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitRightImageView: UIImageView = {
        let image = UIImage(named: "circuit-right")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftDownImageView: UIImageView = {
        let image = UIImage(named: "circuit-left-down")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()


    private lazy var fridaMenuImageView: UIImageView = {
        let iv = UIImageView.circuit(named: "frida-menu-image")
        iv.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        return iv
    }()

        private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Frida Setup"
        label.font = UIFont(name: "IBM Plex Mono Bold", size: 20)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.tintColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var versionDropdown: UIButton = {
        let button = UIButton()
        button.setTitle("Versions", for: .normal)
        button.setTitleColor(.RED, for: .normal)
        button.backgroundColor = UIColor(named: "ButtonColorWhite")
        button.layer.cornerRadius = 10
        button.titleLabel?.font = UIFont(name: "IBM Plex Mono Bold", size: 15)
        button.addTarget(self, action: #selector(onVersionsTap(_:)), for: .touchUpInside)
        return button
    }()


    private lazy var buttonStart: UIButton = {
        let button = UIButton()
        button.setTitle("Start Frida", for: .normal)
        button.setTitleColor(.RED, for: .normal)
        button.backgroundColor = UIColor(named: "ButtonColorWhite")
        button.layer.cornerRadius = 10
        button.titleLabel?.font = UIFont(name: "IBM Plex Mono Bold", size: 15)
        button.addTarget(self, action: #selector(ToggleFrida(_:)), for: .touchUpInside)
        return button
    }()



    private lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private lazy var fridaVersionLabel: UILabel = {
        let label = UILabel()
        label.text = "Version: None"
        label.font = UIFont(name: "IBM Plex Mono Bold", size: 20)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.tintColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var fridaStatusLabel: UILabel = {
        let label = UILabel()
        label.text = "Status: Stopped"
        label.font = UIFont(name: "IBM Plex Mono Bold", size: 20)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.tintColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var downloadProgressLabel: UILabel = {
        let label = UILabel()
        label.font = AppFont.regular(13)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.tintColor = .white
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private lazy var downloadProgressBar: UIProgressView = {
        let bar = UIProgressView(progressViewStyle: .default)
        bar.progressTintColor = .RED
        bar.trackTintColor = UIColor.white.withAlphaComponent(0.15)
        bar.layer.cornerRadius = 3
        bar.clipsToBounds = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.isHidden = true
        return bar
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        checkFridaRunning()
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

extension SetupFridaViewController {

    @objc private func checkFridaRunning() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            var statusText = "Status: Stopped"
            var versionText = "Version: None"
            var toggleFridaText = "Start Frida"

            if self.startDownloading {
                statusText = "Status: Downloading"
            } else {
                let psResult = RootExec.shell("ps aux | grep frida-server | grep -v grep")
                if psResult.exitCode == 0 && !psResult.output.isEmpty {
                    statusText = "Status: Running"
                    toggleFridaText = "Stop Frida"
                    self.isRunning = true
                } else {
                    self.isRunning = false
                }
            }

            let versionResult = RootExec.shell("\(BeerusStrings.fridaServerPath) --version")
            let cleanOutput = versionResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

            // Verifica se é uma versão válida (formato: X.X.X) e não uma mensagem de erro
            let isValidVersion = versionResult.exitCode == 0
                && !cleanOutput.isEmpty
                && !cleanOutput.contains("sh:")
                && !cleanOutput.contains("not found")
                && cleanOutput.range(of: #"^\d+\.\d+\.\d+"#, options: .regularExpression) != nil

            if isValidVersion {
                versionText = "Version: " + cleanOutput
                self.versionRunning = cleanOutput
                if self.selectedVersion.isEmpty {
                    self.selectedVersion = cleanOutput
                }
            }

            if self.versions.isEmpty {
                Github.getReleaseVersions(repository: "frida/frida") { resultVersions in
                    self.versions = resultVersions
                }
            }

            DispatchQueue.main.async {
                self.fridaStatusLabel.text = statusText
                self.fridaVersionLabel.text = versionText
                self.buttonStart.setTitle(toggleFridaText, for: .normal)
            }
        }
    }
}

extension SetupFridaViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(titleLabel)

        view.addSubview(circuitTopImageView)
        view.addSubview(circuitRightImageView)
        view.addSubview(circuitLeftImageView)
        view.addSubview(circuitLeftDownImageView)

        view.addSubview(fridaMenuImageView)
        view.addSubview(fridaVersionLabel)
        view.addSubview(fridaStatusLabel)

        view.addSubview(stackView)

        stackView.addArrangedSubview(versionDropdown)
        stackView.addArrangedSubview(buttonStart)

        view.addSubview(downloadProgressLabel)
        view.addSubview(downloadProgressBar)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            circuitTopImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitTopImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),

            circuitRightImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitRightImageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            circuitRightImageView.widthAnchor.constraint(equalToConstant: 40),
            circuitRightImageView.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor),

            circuitLeftImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitLeftImageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),

            circuitLeftDownImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            circuitLeftDownImageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),

            fridaMenuImageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 32),
            fridaMenuImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: -8),

            fridaVersionLabel.topAnchor.constraint(equalTo: fridaMenuImageView.bottomAnchor, constant: 24),
            fridaVersionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            fridaStatusLabel.topAnchor.constraint(equalTo: fridaVersionLabel.bottomAnchor, constant: 24),
            fridaStatusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            stackView.topAnchor.constraint(equalTo: fridaStatusLabel.bottomAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.heightAnchor.constraint(equalToConstant: 50),

            downloadProgressLabel.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 20),
            downloadProgressLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            downloadProgressLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            downloadProgressBar.topAnchor.constraint(equalTo: downloadProgressLabel.bottomAnchor, constant: 8),
            downloadProgressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            downloadProgressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            downloadProgressBar.heightAnchor.constraint(equalToConstant: 6),
        ])
    }
}
