import UIKit

final class DownloadViewController: BaseViewController {

    private let app: AppStoreApp
    private let versionID: String?
    private var downloadedPath: String?

    // ponytail: haptic feedback for success/error
    private let successFeedback = UINotificationFeedbackGenerator()
    private let errorFeedback = UINotificationFeedbackGenerator()
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    init(app: AppStoreApp, versionID: String?) {
        self.app = app
        self.versionID = versionID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI Elements

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.backgroundColor = UIColor(white: 0.15, alpha: 1)
        iv.layer.cornerRadius = 20
        iv.clipsToBounds = true
        iv.contentMode = .scaleAspectFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private lazy var nameLabel = UILabel.styled(text: app.name, font: AppFont.bold(18), alignment: .center)

    private lazy var bundleLabel = UILabel.styled(
        text: app.bundleID,
        font: AppFont.regular(11), color: UIColor(white: 0.5, alpha: 1), alignment: .center
    )

    private lazy var versionBadge: UIView = {
        let container = UIView()
        container.backgroundColor = UIColor(named: "RED")?.withAlphaComponent(0.2) ?? UIColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 0.2)
        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel.styled(
            text: versionID != nil ? "Specific Version" : "Latest Version",
            font: AppFont.bold(10), color: UIColor(named: "RED") ?? .red, alignment: .center
        )
        label.tag = 100
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
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
        text: "Preparing download...", font: AppFont.medium(12),
        color: .white, alignment: .center
    )

    private lazy var stepLabels: [UILabel] = {
        let steps = ["Acquiring license", "Downloading IPA", "Patching metadata", "Applying signatures", "Complete"]
        return steps.map { text in
            let label = UILabel.styled(text: text, font: AppFont.regular(13), color: UIColor(white: 0.4, alpha: 1))
            return label
        }
    }()

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

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        loadIcon()
        startDownload()
    }

    private func loadIcon() {
        guard let urlString = app.iconURL, let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                // ponytail: fade-in animation for icon
                self?.iconImageView.alpha = 0
                self?.iconImageView.image = image
                UIView.animate(withDuration: 0.3) {
                    self?.iconImageView.alpha = 1
                }
            }
        }.resume()
    }

    // MARK: - Download

    private func startDownload() {
        Task { [weak self] in
            guard let self else { return }
            do {
                updateStep(0, status: .inProgress)
                do {
                    try await AppStoreService.shared.purchase(app: self.app)
                } catch AppStoreError.purchaseFailed(let msg) where msg.contains("already") {
                } catch AppStoreError.paidAppNotSupported {
                    throw AppStoreError.paidAppNotSupported
                } catch {
                    throw error
                }
                updateStep(0, status: .done)

                updateStep(1, status: .inProgress)
                let result = try await AppStoreService.shared.download(
                    app: self.app, externalVersionID: self.versionID
                ) { [weak self] downloaded, total in
                    Task { @MainActor in
                        guard let self else { return }
                        let pct = total > 0 ? Float(downloaded) / Float(total) : 0
                        // ponytail: animated progress update
                        self.progressBar.setProgress(pct, animated: true)
                        let dlMB = Double(downloaded) / 1_048_576
                        let totalMB = Double(total) / 1_048_576
                        self.progressLabel.text = String(
                            format: "%.1f MB / %.1f MB (%.0f%%)", dlMB, totalMB, pct * 100
                        )
                    }
                }
                updateStep(1, status: .done)

                // ponytail: patching steps with brief delay so user sees progress
                updateStep(2, status: .inProgress)
                try? await Task.sleep(nanoseconds: 200_000_000)
                updateStep(2, status: .done)

                updateStep(3, status: .inProgress)
                try? await Task.sleep(nanoseconds: 200_000_000)
                updateStep(3, status: .done)

                updateStep(4, status: .done)

                await MainActor.run {
                    self.downloadedPath = result.destinationPath
                    self.progressLabel.text = "Download complete!"
                    self.progressBar.setProgress(1.0, animated: true)
                    self.successFeedback.notificationOccurred(.success)
                    self.showActionsAnimated()
                }

            } catch AppStoreError.tokenExpired {
                await MainActor.run {
                    self.handleTokenExpired()
                }
            } catch {
                await MainActor.run {
                    self.errorFeedback.notificationOccurred(.error)
                    self.progressLabel.text = self.friendlyError(error)
                    self.progressLabel.textColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
                    self.showRetryButton()
                }
            }
        }
    }

    // ponytail: map errors to user-friendly messages
    private func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("paid") || msg.contains("purchase") {
            return "Paid apps require purchase on device"
        }
        if msg.contains("network") || msg.contains("connection") || msg.contains("timed out") {
            return "Connection failed. Check your internet and try again."
        }
        if msg.contains("license") || msg.contains("already") {
            return "License already acquired"
        }
        return error.localizedDescription
    }

    private func showActionsAnimated() {
        actionsStack.alpha = 0
        actionsStack.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.actionsStack.alpha = 1
        }
    }

    private func handleTokenExpired() {
        AppStoreService.shared.revoke()
        let alert = UIAlertController(
            title: "Session Expired",
            message: "Your login has expired. Please sign in again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self else { return }
            let nav = self.navigationController
            let delegate = self.menuDelegate
            let loginVC = AppStoreLoginViewController()
            loginVC.menuDelegate = delegate
            loginVC.onLoginSuccess = { _ in
                let searchVC = AppStoreSearchViewController()
                searchVC.menuDelegate = delegate
                nav?.setViewControllers([searchVC], animated: true)
            }
            nav?.setViewControllers([loginVC], animated: true)
        })
        present(alert, animated: true)
    }

    private func showRetryButton() {
        let retryBtn = makeActionButton(title: "Retry", icon: "arrow.clockwise", action: #selector(retryTapped))
        actionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        actionsStack.addArrangedSubview(retryBtn)
        showActionsAnimated()
    }

    @objc private func retryTapped() {
        impactFeedback.impactOccurred()
        actionsStack.isHidden = true
        progressLabel.textColor = .white
        progressBar.setProgress(0, animated: true)
        stepLabels.forEach { label in
            label.textColor = UIColor(white: 0.4, alpha: 1)
            label.font = AppFont.regular(13)
        }
        startDownload()
    }

    private enum StepStatus { case pending, inProgress, done }

    // ponytail: status via color+weight, no bracket symbols
    private func updateStep(_ index: Int, status: StepStatus) {
        Task { @MainActor in
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
    }

    // MARK: - Actions

    @objc private func shareTapped() {
        guard let path = downloadedPath else { return }
        let url = URL(fileURLWithPath: path)
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(vc, animated: true)
    }

    @objc private func filesTapped() {
        guard let path = downloadedPath else { return }
        let dir = (path as NSString).deletingLastPathComponent
        let alert = UIAlertController(title: "IPA Location", message: dir, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
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
}

extension DownloadViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(iconImageView)
        view.addSubview(nameLabel)
        view.addSubview(bundleLabel)
        view.addSubview(versionBadge)
        view.addSubview(progressContainer)
        progressContainer.addSubview(progressBar)
        progressContainer.addSubview(progressLabel)
        stepLabels.forEach { view.addSubview($0) }
        view.addSubview(actionsStack)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            iconImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 80),
            iconImageView.heightAnchor.constraint(equalToConstant: 80),

            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 16),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            bundleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            bundleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            versionBadge.topAnchor.constraint(equalTo: bundleLabel.bottomAnchor, constant: 12),
            versionBadge.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            progressContainer.topAnchor.constraint(equalTo: versionBadge.bottomAnchor, constant: 24),
            progressContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            progressContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

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
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            ])
            previous = label
        }

        NSLayoutConstraint.activate([
            actionsStack.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: 28),
            actionsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            actionsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }
}
