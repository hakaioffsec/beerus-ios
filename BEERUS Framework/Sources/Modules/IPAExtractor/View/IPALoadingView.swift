import UIKit

final class IPALoadingView: UIView {

    private lazy var circuitTopImageView = UIImageView.circuit(named: "circuit-top")
    private lazy var circuitLeftImageView = UIImageView.circuit(named: "circuit-left")
    private lazy var circuitRightImageView = UIImageView.circuit(named: "circuit-right")
    private lazy var circuitLeftDownImageView = UIImageView.circuit(named: "circuit-left-down")

    let cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("✕", for: .normal)
        button.titleLabel?.font = AppFont.bold(20)
        button.setTitleColor(.white, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

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
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var phaseLabel = UILabel.styled(
        text: "CHECKING",
        font: AppFont.bold(22),
        alignment: .center
    )

    private lazy var subtitleLabel = UILabel.styled(
        text: "verify frida connection",
        font: AppFont.regular(13),
        color: UIColor(white: 0.45, alpha: 1),
        alignment: .center
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

    private lazy var statusLabel = UILabel.styled(
        text: "",
        font: AppFont.regular(12),
        color: UIColor(white: 0.3, alpha: 1),
        alignment: .center
    )

    private var currentPhase: DumpPhase = .checking
    private let allPhases: [DumpPhase] = [.checking, .attaching, .loading, .dumping, .building, .complete]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        buildUI()
        updatePhase(.checking)
        startGlowPulse()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

        glowRing.layer.cornerRadius = ringSize / 2

        addSubview(circuitTopImageView)
        addSubview(circuitLeftImageView)
        addSubview(circuitRightImageView)
        addSubview(circuitLeftDownImageView)
        addSubview(cancelButton)
        addSubview(iconContainer)
        iconContainer.addSubview(glowRing)
        iconContainer.addSubview(phaseIconView)
        addSubview(phaseLabel)
        addSubview(subtitleLabel)
        addSubview(dotsStack)
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            circuitTopImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitTopImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),

            circuitRightImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitRightImageView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            circuitRightImageView.widthAnchor.constraint(equalToConstant: 40),
            circuitRightImageView.heightAnchor.constraint(equalTo: safeAreaLayoutGuide.heightAnchor),

            circuitLeftImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitLeftImageView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),

            circuitLeftDownImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            circuitLeftDownImageView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),

            cancelButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),

            iconContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -50),
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
            phaseLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: phaseLabel.bottomAnchor, constant: 6),
            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),

            dotsStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            dotsStack.centerXAnchor.constraint(equalTo: centerXAnchor),

            statusLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
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

    // MARK: - Rendering

    func updatePhase(_ phase: DumpPhase) {
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
                let dotIndex = dot.tag
                UIView.animate(withDuration: 0.3) {
                    if dotIndex < currentIndex {
                        dot.backgroundColor = green
                        dot.transform = .identity
                    } else if dotIndex == currentIndex {
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

    func updateProgress(_ current: Int, total: Int) {
        // kept for API compat — no visual element needed
    }

    func addLog(_ message: String) {
        // kept for API compat — no visual element needed
    }

    func showSuccess() {
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
            self.subtitleLabel.text = "ipa created successfully"
            self.subtitleLabel.textColor = green

            for dot in self.dotViews {
                UIView.animate(withDuration: 0.3) {
                    dot.backgroundColor = green
                    dot.transform = .identity
                }
            }

            self.statusLabel.text = ""
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

            self.statusLabel.text = "tap CLOSE to dismiss"
            self.statusLabel.textColor = UIColor(white: 0.4, alpha: 1)

            self.animatePhaseTransition()

            let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shake.timingFunction = CAMediaTimingFunction(name: .linear)
            shake.values = [-8, 8, -6, 6, -3, 3, 0]
            shake.duration = 0.4
            self.iconContainer.layer.add(shake, forKey: "shake")
        }
    }
}
