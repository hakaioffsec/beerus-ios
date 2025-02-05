import UIKit

final class SetupFridaViewController: UIViewController {
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.numberOfLines = 0
        label.attributedText = "Add the Frida source to your Package Manager.\nTo finish the installation:\nFrida Source > All Packages > Frida > Install."
            .withBoldWords(["Frida repository", "Frida Source > All Packages > Frida > Install"])
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private func createButton(for packageManager: PackageManager) -> UIButton {
        let button = UIButton()
        button.setTitle(packageManager.title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .red
        button.layer.cornerRadius = 10
        button.isHidden = !packageManager.isInstalled
        button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        button.tag = PackageManager.allCases.firstIndex(of: packageManager) ?? 0
        return button
    }
    
    private lazy var stackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()
    
    private lazy var fridaStatusLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        checkFridaRunning()
        
        NotificationCenter.default.addObserver(self, selector: #selector(checkFridaRunning), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(checkFridaRunning), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
}

extension SetupFridaViewController {
    @objc private func buttonTapped(_ sender: UIButton) {
        let packageManager = PackageManager.allCases[sender.tag]
        packageManager.open(source: "https://build.frida.re")
    }
    
    @objc private func checkFridaRunning() {
        var statusText = "Frida Stopped"
        if let psOutput = Exec.command("ps", arguments: ["aux"]) {
            let psFiltered = psOutput.split(separator: "\n").filter { $0.contains("frida-server") && !$0.contains("grep") }
            let result = psFiltered.joined(separator: "\n")
            
            if !result.isEmpty {
                statusText = "Frida is Running"
            }
        }
        
        DispatchQueue.main.async {
            self.fridaStatusLabel.text = statusText
        }
    }
}

extension SetupFridaViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(stackView)
        view.addSubview(fridaStatusLabel)
        
        PackageManager.allCases.forEach { packageManager in
            let button = createButton(for: packageManager)
            stackView.addArrangedSubview(button)
        }
    }
    
    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            
            stackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.heightAnchor.constraint(equalToConstant: 50),
            
            fridaStatusLabel.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 24),
            fridaStatusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
    
    func setupAdditionalConfiguration() {
        view.backgroundColor = .black
    }
}
