import UIKit

final class SetupFridaView: UIView {

    var onSelectVersion: (String) -> Void = { _ in }
    var onAddManually: () -> Void = {}

    private var versions: [String] = []
    private var dropdown: SimpleDropdown?
    private var dropdownBackdrop: UIControl?

    private lazy var circuitTopImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "circuit-top"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "circuit-left-2"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitRightImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "circuit-right"))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftDownImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "circuit-left-down"))
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

    let versionDropdown: UIButton = {
        let button = UIButton()
        button.setTitle("Versions", for: .normal)
        button.setTitleColor(.RED, for: .normal)
        button.backgroundColor = UIColor(named: "ButtonColorWhite")
        button.layer.cornerRadius = 10
        button.titleLabel?.font = UIFont(name: "IBM Plex Mono Bold", size: 15)
        return button
    }()

    let buttonStart: UIButton = {
        let button = UIButton()
        button.setTitle("Start Frida", for: .normal)
        button.setTitleColor(.RED, for: .normal)
        button.backgroundColor = UIColor(named: "ButtonColorWhite")
        button.layer.cornerRadius = 10
        button.titleLabel?.font = UIFont(name: "IBM Plex Mono Bold", size: 15)
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()
        versionDropdown.addTarget(self, action: #selector(onVersionsTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    func setVersions(_ versions: [String]) {
        self.versions = versions
    }

    func setSelectedVersionTitle(_ title: String) {
        versionDropdown.setTitle(title, for: .normal)
    }

    func setStatus(statusText: String, versionText: String, startTitle: String) {
        fridaStatusLabel.text = statusText
        fridaVersionLabel.text = versionText
        buttonStart.setTitle(startTitle, for: .normal)
    }

    func setStartEnabled(_ enabled: Bool) {
        buttonStart.isEnabled = enabled
    }

    func showProgress(_ text: String, fraction: Float) {
        downloadProgressLabel.isHidden = false
        downloadProgressBar.isHidden = false
        downloadProgressLabel.text = text
        downloadProgressBar.setProgress(fraction, animated: true)
    }

    func hideProgress() {
        downloadProgressLabel.isHidden = true
        downloadProgressBar.isHidden = true
        downloadProgressBar.setProgress(0, animated: false)
    }

    func dismissDropdown() {
        hideDropdown()
    }

    // MARK: - Dropdown

    @objc private func onVersionsTap() {
        if dropdown != nil {
            hideDropdown()
            return
        }
        showDropdown()
    }

    private func showDropdown() {
        guard let window = self.window
            ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows.first
        else { return }

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
            guard let self else { return }
            if value == "Add version manually" {
                self.onAddManually()
            } else {
                self.versionDropdown.setTitle(value, for: .normal)
                self.hideDropdown()
                self.onSelectVersion(value)
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
}

extension SetupFridaView: ViewCode {
    func buildViewHierarchy() {
        addSubview(titleLabel)

        addSubview(circuitTopImageView)
        addSubview(circuitRightImageView)
        addSubview(circuitLeftImageView)
        addSubview(circuitLeftDownImageView)

        addSubview(fridaMenuImageView)
        addSubview(fridaVersionLabel)
        addSubview(fridaStatusLabel)

        addSubview(stackView)
        stackView.addArrangedSubview(versionDropdown)
        stackView.addArrangedSubview(buttonStart)

        addSubview(downloadProgressLabel)
        addSubview(downloadProgressBar)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

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

            fridaMenuImageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 32),
            fridaMenuImageView.centerXAnchor.constraint(equalTo: centerXAnchor, constant: -8),

            fridaVersionLabel.topAnchor.constraint(equalTo: fridaMenuImageView.bottomAnchor, constant: 24),
            fridaVersionLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            fridaStatusLabel.topAnchor.constraint(equalTo: fridaVersionLabel.bottomAnchor, constant: 24),
            fridaStatusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            stackView.topAnchor.constraint(equalTo: fridaStatusLabel.bottomAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            stackView.heightAnchor.constraint(equalToConstant: 50),

            downloadProgressLabel.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 20),
            downloadProgressLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            downloadProgressLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            downloadProgressBar.topAnchor.constraint(equalTo: downloadProgressLabel.bottomAnchor, constant: 8),
            downloadProgressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            downloadProgressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            downloadProgressBar.heightAnchor.constraint(equalToConstant: 6),
        ])
    }
}
