import UIKit

final class IPAExtractorView: UIView {

    private lazy var circuitTopImageView = UIImageView.circuit(named: "circuit-top")
    private lazy var circuitLeftImageView = UIImageView.circuit(named: "circuit-left")
    private lazy var circuitRightImageView = UIImageView.circuit(named: "circuit-right")
    private lazy var circuitLeftDownImageView = UIImageView.circuit(named: "circuit-left-down")

    private lazy var titleLabel = UILabel.styled(
        text: "IPA Extractor",
        font: AppFont.bold(20),
        alignment: .center
    )

    let statusLabel = UILabel.styled(
        text: "Frida: Checking...",
        font: AppFont.regular(14),
        alignment: .center
    )

    let dumpButton: UIButton = {
        let button = UIButton.styled(title: "Frida OFF")
        button.isEnabled = false
        button.alpha = 0.5
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension IPAExtractorView: ViewCode {
    func buildViewHierarchy() {
        addSubview(circuitTopImageView)
        addSubview(circuitLeftImageView)
        addSubview(circuitRightImageView)
        addSubview(circuitLeftDownImageView)
        addSubview(titleLabel)
        addSubview(statusLabel)
        addSubview(dumpButton)
    }

    func setupConstraints() {
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

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 100),

            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            dumpButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 24),
            dumpButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            dumpButton.widthAnchor.constraint(equalToConstant: 200),
            dumpButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }
}
