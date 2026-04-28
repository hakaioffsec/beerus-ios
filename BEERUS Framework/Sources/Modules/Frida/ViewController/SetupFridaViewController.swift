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
            keyboardType: .phonePad

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
        
        let btnFrame = versionDropdown.convert(versionDropdown.bounds, to: window)
        let width = btnFrame.width
        let height = dd.desiredHeight(maxRows: 6, rowHeight: 44)

        dd.frame = CGRect(x: btnFrame.minX, y: btnFrame.maxY + 6, width: width, height: height)
        window.addSubview(dd)
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
    
    @objc private func ToggleFrida(_ sender: UIButton) {
        
        if (FileManager.default.fileExists(atPath: BeerusStrings.fridaDaemonPath)) {
            buttonStart.isEnabled = false
            if (isRunning) {
                RootExec.shellAwait("launchctl unload \(BeerusStrings.fridaDaemonPath)") {_ in
                    DispatchQueue.main.async {
                        self.buttonStart.isEnabled = true
                    }
                }
            } else {
                if (selectedVersion == versionRunning) {
                    RootExec.shellAwait("launchctl load \(BeerusStrings.fridaDaemonPath)") {_ in
                        DispatchQueue.main.async {
                            self.buttonStart.isEnabled = true
                        }
                    }
                } else {
                    startDownloading = true
                    buttonStart.isEnabled = false

                    if let deviceArch = Exec.command(BeerusStrings.dpkgBin, arguments: ["--print-architecture"], findPath: false) {
                        let deviceArchCleanOut = deviceArch.trimmingCharacters(in: .whitespacesAndNewlines)
            
                        if !deviceArchCleanOut.isEmpty {
                            Requests.downloadFile(
                                from: "https://github.com/frida/frida/releases/download/\(selectedVersion)/frida_\(selectedVersion)_\(deviceArchCleanOut).deb",
                                fileName: "frida-server.deb",
                                destinationPath: BeerusStrings.tmp
                            ) { result in
                                switch result {
                                case .success(let url):
                                    RootExec.shellAwait("dpkg -i \(BeerusStrings.tmp)frida-server.deb") {result in
                                        DispatchQueue.main.async {
                                            self.startDownloading = false
                                            self.buttonStart.isEnabled = true
                                            self.checkFridaRunning()
                                        }
                                    }
                                case .failure(let error):
                                    DispatchQueue.main.async {
                                        self.startDownloading = false
                                        self.buttonStart.isEnabled = true
                                        self.checkFridaRunning()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            checkFridaRunning()
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        checkFridaRunning()
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

extension SetupFridaViewController {

    @objc private func checkFridaRunning() {
        var statusText = "Status: Stopped"
        var versionText = "Version: None"
        var toggleFridaText = "Start Frida"
        
        
        if (startDownloading) {
            statusText = "Status: Downloading"
        } else {
            if let psOutput = Exec.command("ps", arguments: ["aux"]) {
                let psFiltered = psOutput.split(separator: "\n").filter { $0.contains("frida-server") && !$0.contains("grep") }
                let result = psFiltered.joined(separator: "\n")
                
                if !result.isEmpty {
                    statusText = "Status: Running"
                    toggleFridaText = "Stop Frida"
                    isRunning = true
                } else {
                    isRunning = false
                }
                
            }
        }
        
        if let psOutput = Exec.command(BeerusStrings.fridaServerPath, arguments: ["--version"], findPath: false) {
            let cleanOutput = psOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !cleanOutput.isEmpty {
                versionText = "Version: "+cleanOutput
                versionRunning = cleanOutput
                if (selectedVersion == "") {
                    selectedVersion = cleanOutput
                }
            }
        }
        
        if (versions == []) {
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
                        
            fridaMenuImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -32),
            fridaMenuImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: -8),
            
            fridaVersionLabel.topAnchor.constraint(equalTo: fridaMenuImageView.bottomAnchor, constant: 24),
            fridaVersionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            fridaStatusLabel.topAnchor.constraint(equalTo: fridaVersionLabel.bottomAnchor, constant: 24),
            fridaStatusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                        
            stackView.topAnchor.constraint(equalTo: fridaStatusLabel.bottomAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
}
