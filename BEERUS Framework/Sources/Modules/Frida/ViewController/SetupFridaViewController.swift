import UIKit

final class SetupFridaViewController: BaseViewController {

    private lazy var circuitTopImageView = UIImageView.circuit(named: "circuit-top")
    private lazy var circuitLeftImageView = UIImageView.circuit(named: "circuit-left-2")
    private lazy var circuitRightImageView = UIImageView.circuit(named: "circuit-right")
    private lazy var circuitLeftDownImageView = UIImageView.circuit(named: "circuit-left-down")

    private lazy var fridaMenuImageView: UIImageView = {
        let iv = UIImageView.circuit(named: "frida-menu-image")
        iv.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        return iv
    }()

    private lazy var titleLabel = UILabel.styled(
        text: "Frida Setup", font: AppFont.bold(20), alignment: .center, lines: 0
    )
    private lazy var fridaStatusLabel = UILabel.styled(
        text: "Running: ...", font: AppFont.bold(20), alignment: .center, lines: 0
    )
    private lazy var downloadFridaButton = UIButton.styled(
        title: "Download Frida", target: self, action: #selector(downloadFridaTapped)
    )
    private lazy var restartFridaButton = UIButton.styled(
        title: "Restart Frida Server", target: self, action: #selector(restartFridaTapped)
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        checkFridaRunning()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(checkFridaRunning), name: UIApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(checkFridaRunning), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(fridaStatusDidChange), name: FridaChecker.statusDidChangeNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

extension SetupFridaViewController {
    @objc private func downloadFridaTapped() {
        let versionsVC = FridaVersionsViewController()
        versionsVC.modalPresentationStyle = .pageSheet
        present(versionsVC, animated: true)
    }

    @objc private func checkFridaRunning() {
        fridaStatusLabel.text = FridaChecker.isRunning() ? "Running: Yes" : "Running: No"
    }

    @objc private func fridaStatusDidChange() {
        FridaChecker.checkAfterDelay { [weak self] running in
            self?.fridaStatusLabel.text = running ? "Running: Yes" : "Running: No"
        }
    }

    @objc private func restartFridaTapped() {
        guard RootExec.isAvailable else {
            showAlert(title: "Daemon Offline", message: "The beerus daemon is not running. Make sure it is installed and started.")
            return
        }

        restartFridaButton.isEnabled = false
        restartFridaButton.setTitle("Restarting...", for: .normal)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = RootExec.restartFrida()
            sleep(2)
            let success = result?.hasPrefix("ok") == true

            DispatchQueue.main.async {
                self?.restartFridaButton.isEnabled = true
                self?.restartFridaButton.setTitle("Restart Frida Server", for: .normal)
                self?.checkFridaRunning()

                if success {
                    FridaChecker.notifyStatusChanged()
                } else {
                    self?.showAlert(title: "Restart Failed", message: result ?? "No response from daemon")
                }
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
        view.addSubview(fridaStatusLabel)
        view.addSubview(restartFridaButton)
        view.addSubview(downloadFridaButton)
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
            
            fridaStatusLabel.topAnchor.constraint(equalTo: fridaMenuImageView.bottomAnchor, constant: 24),
            fridaStatusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            restartFridaButton.topAnchor.constraint(equalTo: fridaStatusLabel.bottomAnchor, constant: 16),
            restartFridaButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            restartFridaButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            restartFridaButton.heightAnchor.constraint(equalToConstant: 50),

            downloadFridaButton.topAnchor.constraint(equalTo: restartFridaButton.bottomAnchor, constant: 16),
            downloadFridaButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            downloadFridaButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            downloadFridaButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
}
