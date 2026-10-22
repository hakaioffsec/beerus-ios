import UIKit

final class DownloadView: UIView {

    var onShare: () -> Void = {}
    var onFiles: () -> Void = {}
    var onRetry: () -> Void = {}

    private let successFeedback = UINotificationFeedbackGenerator()
    private let errorFeedback = UINotificationFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.backgroundColor = UIColor(white: 0.15, alpha: 1)
        iv.layer.cornerRadius = 20
        iv.clipsToBounds = true
        iv.contentMode = .scaleAspectFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let nameLabel = UILabel.styled(font: AppFont.bold(18), alignment: .center)

    private let bundleLabel = UILabel.styled(
        font: AppFont.regular(11),
        color: UIColor(white: 0.5, alpha: 1),
        alignment: .center
    )

    private lazy var versionBadgeLabel = UILabel.styled(
        font: AppFont.bold(10),
        color: UIColor(named: "RED") ?? .red,
        alignment: .center
    )

    private lazy var versionBadge: UIView = {
        let container = UIView()
        container.backgroundColor = UIColor(named: "RED")?.withAlphaComponent(0.2) ?? UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.2)
        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(versionBadgeLabel)
        NSLayoutConstraint.activate([
            versionBadgeLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            versionBadgeLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            versionBadgeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            versionBadgeLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])
        return container
    }()

    private let progressContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.08, alpha: 1)
        v.layer.cornerRadius = 12
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let progressBar: UIProgressView = {
        let bar = UIProgressView(progressViewStyle: .default)
        bar.progressTintColor = UIColor(named: "RED") ?? .red
        bar.trackTintColor = UIColor(white: 0.2, alpha: 1)
        bar.layer.cornerRadius = 4
        bar.clipsToBounds = true
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private lazy var progressLabel = UILabel.styled(
        text: "Preparing download...",
        font: AppFont.medium(12),
        color: .white,
        alignment: .center
    )

    private let stepTitles = ["Acquiring license", "Downloading IPA", "Patching metadata", "Applying signatures", "Complete"]

    private lazy var stepLabels: [UILabel] = stepTitles.map {
        UILabel.styled(text: $0, font: AppFont.regular(13), color: UIColor(white: 0.4, alpha: 1))
    }

    private lazy var actionsStack: UIStackView = {
        let shareBtn = makeActionButton(title: "Share", icon: "square.and.arrow.up", action: #selector(shareTapped))
        let filesBtn = makeActionButton(title: "Files", icon: "folder", action: #selector(filesTapped))
        let stack = UIStackView(arrangedSubviews: [shareBtn, filesBtn])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Rendering

    func configure(name: String, bundle: String, isSpecificVersion: Bool) {
        nameLabel.text = name
        bundleLabel.text = bundle
        versionBadgeLabel.text = isSpecificVersion ? "Specific Version" : "Latest Version"
    }

    func setIcon(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        iconImageView.alpha = 0
        iconImageView.image = image
        UIView.animate(withDuration: 0.3) { self.iconImageView.alpha = 1 }
    }

    func setProgress(_ pct: Float, text: String) {
        progressBar.setProgress(pct, animated: true)
        progressLabel.text = text
    }

    func setStep(_ index: Int, status: DownloadViewModel.StepStatus) {
        guard index < stepLabels.count else { return }
        let label = stepLabels[index]
        switch status {
        case .pending:
            label.textColor = UIColor(white: 0.4, alpha: 1)
            label.font = AppFont.regular(13)
        case .inProgress:
            label.textColor = UIColor(named: "RED") ?? .red
            label.font = AppFont.bold(13)
        case .done:
            label.textColor = UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1)
            label.font = AppFont.medium(13)
        }
    }

    func showComplete() {
        progressLabel.text = "Download complete!"
        progressBar.setProgress(1.0, animated: true)
        successFeedback.notificationOccurred(.success)
        showActionsAnimated()
    }

    func showError(_ message: String) {
        errorFeedback.notificationOccurred(.error)
        progressLabel.text = message
        progressLabel.textColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)

        let retryBtn = makeActionButton(title: "Retry", icon: "arrow.clockwise", action: #selector(retryTapped))
        actionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actionsStack.addArrangedSubview(retryBtn)
        showActionsAnimated()
    }

    func prepareForRetry() {
        impactFeedback.impactOccurred()
        actionsStack.isHidden = true
        progressLabel.textColor = .white
        progressBar.setProgress(0, animated: true)
        stepLabels.forEach {
            $0.textColor = UIColor(white: 0.4, alpha: 1)
            $0.font = AppFont.regular(13)
        }
    }

    private func showActionsAnimated() {
        actionsStack.alpha = 0
        actionsStack.isHidden = false
        UIView.animate(withDuration: 0.3) { self.actionsStack.alpha = 1 }
    }

    private func makeActionButton(title: String, icon: String, action: Selector) -> UIButton {
        let btn = UIButton(type: .system)
        btn.setTitle(" \(title)", for: .normal)
        btn.setImage(UIImage(systemName: icon), for: .normal)
        btn.titleLabel?.font = AppFont.bold(13)
        btn.tintColor = .white
        btn.backgroundColor = UIColor(white: 0.15, alpha: 1)
        btn.layer.cornerRadius = 10
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: action, for: .touchUpInside)
        btn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return btn
    }

    @objc private func shareTapped() { onShare() }
    @objc private func filesTapped() { onFiles() }
    @objc private func retryTapped() { onRetry() }
}

extension DownloadView: ViewCode {
    func buildViewHierarchy() {
        addSubview(iconImageView)
        addSubview(nameLabel)
        addSubview(bundleLabel)
        addSubview(versionBadge)
        addSubview(progressContainer)
        progressContainer.addSubview(progressBar)
        progressContainer.addSubview(progressLabel)
        stepLabels.forEach { addSubview($0) }
        addSubview(actionsStack)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 40),
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 80),
            iconImageView.heightAnchor.constraint(equalToConstant: 80),

            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            bundleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            bundleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            versionBadge.topAnchor.constraint(equalTo: bundleLabel.bottomAnchor, constant: 12),
            versionBadge.centerXAnchor.constraint(equalTo: centerXAnchor),

            progressContainer.topAnchor.constraint(equalTo: versionBadge.bottomAnchor, constant: 24),
            progressContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            progressContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            progressBar.topAnchor.constraint(equalTo: progressContainer.topAnchor, constant: 16),
            progressBar.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor, constant: 16),
            progressBar.trailingAnchor.constraint(equalTo: progressContainer.trailingAnchor, constant: -16),
            progressBar.heightAnchor.constraint(equalToConstant: 8),

            progressLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 12),
            progressLabel.centerXAnchor.constraint(equalTo: progressContainer.centerXAnchor),
            progressLabel.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor, constant: -16),
        ])

        var previous: UIView = progressContainer
        for label in stepLabels {
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: previous == progressContainer ? 20 : 8),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            ])
            previous = label
        }

        NSLayoutConstraint.activate([
            actionsStack.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: 28),
            actionsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            actionsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])
    }
}
