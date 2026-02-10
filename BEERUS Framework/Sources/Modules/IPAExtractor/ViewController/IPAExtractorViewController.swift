import UIKit

final class IPAExtractorViewController: BaseViewController {

    private lazy var circuitTopImageView = UIImageView.circuit(named: "circuit-top")
    private lazy var circuitLeftImageView = UIImageView.circuit(named: "circuit-left")
    private lazy var circuitRightImageView = UIImageView.circuit(named: "circuit-right")
    private lazy var circuitLeftDownImageView = UIImageView.circuit(named: "circuit-left-down")

    private lazy var titleLabel = UILabel.styled(
        text: "IPA Extractor", font: AppFont.bold(20), alignment: .center
    )
    private lazy var statusLabel = UILabel.styled(
        text: "Frida: Checking...", font: AppFont.regular(14), alignment: .center
    )
    private lazy var dumpButton: UIButton = {
        let button = UIButton.styled(title: "Frida OFF", target: self, action: #selector(dumpButtonTapped))
        button.isEnabled = false
        button.alpha = 0.5
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        checkFridaStatus()

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(checkFridaStatus), name: UIApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(fridaStatusDidChange), name: FridaChecker.statusDidChangeNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func fridaStatusDidChange() {
        FridaChecker.checkAfterDelay { [weak self] running in
            self?.updateUI(fridaRunning: running)
        }
    }

    @objc private func checkFridaStatus() {
        updateUI(fridaRunning: FridaChecker.isRunning())
    }

    private func updateUI(fridaRunning: Bool) {
        statusLabel.text = fridaRunning ? "Frida: Running" : "Frida: Not Running"
        dumpButton.setTitle(fridaRunning ? "Dump IPA" : "Frida OFF", for: .normal)
        dumpButton.isEnabled = fridaRunning
        dumpButton.alpha = fridaRunning ? 1.0 : 0.5
    }

    @objc private func dumpButtonTapped() {
        let appsViewController = InstalledAppsViewController()
        appsViewController.menuDelegate = menuDelegate
        navigationController?.pushViewController(appsViewController, animated: true)
    }
}

extension IPAExtractorViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(circuitTopImageView)
        view.addSubview(circuitLeftImageView)
        view.addSubview(circuitRightImageView)
        view.addSubview(circuitLeftDownImageView)
        view.addSubview(titleLabel)
        view.addSubview(statusLabel)
        view.addSubview(dumpButton)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
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

            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            dumpButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            dumpButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dumpButton.widthAnchor.constraint(equalToConstant: 200),
            dumpButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
}
