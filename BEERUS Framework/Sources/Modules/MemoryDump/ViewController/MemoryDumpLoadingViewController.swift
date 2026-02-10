import UIKit

final class MemoryDumpLoadingViewController: UIViewController {

    // MARK: - UI

    private let iconContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let phaseIconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = UIColor(named: "RED")
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let glowRing: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.layer.borderColor = UIColor(named: "RED")?.cgColor ?? UIColor.red.cgColor
        v.layer.borderWidth = 2
        v.layer.cornerRadius = 50
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var phaseLabel = UILabel.styled(
        text: "CONNECTING", font: AppFont.bold(22), alignment: .center
    )

    private lazy var subtitleLabel = UILabel.styled(
        text: "checking frida server", font: AppFont.regular(13),
        color: UIColor(white: 0.45, alpha: 1), alignment: .center
    )

    private var dotViews: [UIView] = []
    private let dotsStack: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.spacing = 12
        s.alignment = .center
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("✕", for: .normal)
        button.titleLabel?.font = AppFont.bold(20)
        button.setTitleColor(.white, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Properties

    var onCancel: (() -> Void)?
    private var currentPhase: MemoryDumpPhase = .connecting

    private let allPhases: [MemoryDumpPhase] = [.connecting, .attaching, .dumping, .packaging, .complete]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "Background")
        buildUI()
        updatePhase(.connecting)
        startGlowPulse()
    }

    // MARK: - Build UI

    private func buildUI() {
        let ringSize: CGFloat = 100

        for (i, phase) in allPhases.enumerated() {
            if phase == .complete { continue }
            let dot = UIView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.backgroundColor = UIColor(white: 0.2, alpha: 1)
            dot.layer.cornerRadius = 4
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 8),
                dot.heightAnchor.constraint(equalToConstant: 8),
            ])
            dot.tag = i
            dotViews.append(dot)
            dotsStack.addArrangedSubview(dot)
        }

        view.addSubview(cancelButton)
        view.addSubview(iconContainer)
        iconContainer.addSubview(glowRing)
        iconContainer.addSubview(phaseIconView)
        view.addSubview(phaseLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(dotsStack)

        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),

            iconContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            iconContainer.widthAnchor.constraint(equalToConstant: ringSize),
            iconContainer.heightAnchor.constraint(equalToConstant: ringSize),

            glowRing.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            glowRing.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            glowRing.widthAnchor.constraint(equalToConstant: ringSize),
            glowRing.heightAnchor.constraint(equalToConstant: ringSize),

            phaseIconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            phaseIconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            phaseIconView.widthAnchor.constraint(equalToConstant: 36),
            phaseIconView.heightAnchor.constraint(equalToConstant: 36),

            phaseLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 28),
            phaseLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: phaseLabel.bottomAnchor, constant: 6),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),

            dotsStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            dotsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    // MARK: - Animations

    private func startGlowPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowRing.layer.add(pulse, forKey: "pulse")
    }

    private func stopGlowPulse() {
        glowRing.layer.removeAnimation(forKey: "pulse")
        glowRing.layer.opacity = 1.0
    }

    private func animatePhaseTransition() {
        phaseIconView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        phaseIconView.alpha = 0
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.7,
                       initialSpringVelocity: 0.5) {
            self.phaseIconView.transform = .identity
            self.phaseIconView.alpha = 1
        }
        phaseLabel.alpha = 0
        subtitleLabel.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.phaseLabel.alpha = 1
            self.subtitleLabel.alpha = 1
        }
    }

    // MARK: - Public

    func updatePhase(_ phase: MemoryDumpPhase) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentPhase = phase

            self.phaseIconView.image = UIImage(systemName: phase.icon)?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 36, weight: .medium))
            self.phaseLabel.text = phase.title
            self.subtitleLabel.text = phase.subtitle

            guard let currentIndex = self.allPhases.firstIndex(of: phase) else { return }
            let red = UIColor(named: "RED") ?? .red
            let green = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)

            for dot in self.dotViews {
                UIView.animate(withDuration: 0.3) {
                    if dot.tag < currentIndex {
                        dot.backgroundColor = green
                        dot.transform = .identity
                    } else if dot.tag == currentIndex {
                        dot.backgroundColor = red
                        dot.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
                    } else {
                        dot.backgroundColor = UIColor(white: 0.2, alpha: 1)
                        dot.transform = .identity
                    }
                }
            }
            self.animatePhaseTransition()
        }
    }

    func addLog(_ message: String) {
        // No-op — minimal UI
    }

    func showSuccess(message: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopGlowPulse()

            let green = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
            self.glowRing.layer.borderColor = green.cgColor
            self.phaseIconView.tintColor = green
            self.phaseIconView.image = UIImage(systemName: "checkmark.seal.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 36, weight: .medium))
            self.phaseLabel.text = "COMPLETE"
            self.phaseLabel.textColor = green
            self.subtitleLabel.text = message
            self.subtitleLabel.textColor = green

            for dot in self.dotViews {
                UIView.animate(withDuration: 0.3) {
                    dot.backgroundColor = green
                    dot.transform = .identity
                }
            }
            self.animatePhaseTransition()

            UIView.animate(withDuration: 0.2, animations: {
                self.glowRing.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            }) { _ in
                UIView.animate(withDuration: 0.15) {
                    self.glowRing.transform = .identity
                }
            }
        }
    }

    func showError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopGlowPulse()

            let red = UIColor(named: "RED") ?? .red
            self.glowRing.layer.borderColor = red.cgColor
            self.phaseIconView.tintColor = red
            self.phaseIconView.image = UIImage(systemName: "xmark.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 36, weight: .medium))
            self.phaseLabel.text = "ERROR"
            self.phaseLabel.textColor = red
            self.subtitleLabel.text = error.localizedDescription
            self.subtitleLabel.textColor = red

            self.cancelButton.setTitle("CLOSE", for: .normal)
            self.cancelButton.titleLabel?.font = AppFont.bold(14)

            self.animatePhaseTransition()

            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.timingFunction = CAMediaTimingFunction(name: .linear)
            shake.values = [-8, 8, -6, 6, -3, 3, 0]
            shake.duration = 0.4
            self.iconContainer.layer.add(shake, forKey: "shake")
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true) {
            self.onCancel?()
        }
    }
}

// MARK: - MemoryDumpPhase

enum MemoryDumpPhase: Equatable {
    case connecting, attaching, dumping, packaging, complete

    var title: String {
        switch self {
        case .connecting: "CONNECTING"
        case .attaching: "ATTACHING"
        case .dumping: "DUMPING"
        case .packaging: "PACKAGING"
        case .complete: "COMPLETE"
        }
    }

    var subtitle: String {
        switch self {
        case .connecting: "checking frida server"
        case .attaching: "attach to target process"
        case .dumping: "reading memory regions"
        case .packaging: "creating zip archive"
        case .complete: "done"
        }
    }

    var icon: String {
        switch self {
        case .connecting: "magnifyingglass"
        case .attaching: "link"
        case .dumping: "memorychip"
        case .packaging: "archivebox"
        case .complete: "checkmark.seal"
        }
    }
}
