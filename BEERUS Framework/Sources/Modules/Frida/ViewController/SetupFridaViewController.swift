import UIKit

final class SetupFridaViewController: BaseViewController {
    
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
        let image = UIImage(named: "frida-menu-image")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
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
    
    private func createButton(for packageManager: PackageManager) -> UIButton {
        let button = UIButton()
        button.setTitle(packageManager.title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(named: "ButtonColor")
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
        label.text = "Running: Yes"
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
        var statusText = "Running: No"
        if let psOutput = Exec.command("ps", arguments: ["aux"]) {
            let psFiltered = psOutput.split(separator: "\n").filter { $0.contains("frida-server") && !$0.contains("grep") }
            let result = psFiltered.joined(separator: "\n")
            
            if !result.isEmpty {
                statusText = "Running: Yes"
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

        view.addSubview(circuitTopImageView)
        view.addSubview(circuitRightImageView)
        view.addSubview(circuitLeftImageView)
        view.addSubview(circuitLeftDownImageView)
        
        view.addSubview(fridaMenuImageView)
        view.addSubview(fridaStatusLabel)
        
        view.addSubview(stackView)

        
        PackageManager.allCases.forEach { packageManager in
            let button = createButton(for: packageManager)
            stackView.addArrangedSubview(button)
        }
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
                        
            stackView.topAnchor.constraint(equalTo: fridaStatusLabel.bottomAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
}
