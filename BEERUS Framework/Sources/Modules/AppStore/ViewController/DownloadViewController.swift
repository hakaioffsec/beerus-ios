import UIKit

final class DownloadViewController: BaseViewController {

    private let app: AppStoreApp
    private let versionID: String?
    private var downloadedPath: String?

    init(app: AppStoreApp, versionID: String?) {
        self.app = app
        self.versionID = versionID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private lazy var nameLabel = UILabel.styled(text: app.name, font: AppFont.bold(16), alignment: .center)
    private lazy var versionLabel = UILabel.styled(
        text: versionID != nil ? "Version ID: \(versionID!)" : "Latest Version",
        font: AppFont.regular(12), color: UIColor(white: 0.5, alpha: 1), alignment: .center
    )

    private let progressBar: UIProgressView = {
        let bar = UIProgressView(progressViewStyle: .default)
        bar.progressTintColor = UIColor(named: "ButtonColor")
        bar.trackTintColor = UIColor(white: 0.2, alpha: 1)
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private lazy var progressLabel = UILabel.styled(
        text: "Preparing...", font: AppFont.regular(12),
        color: UIColor(white: 0.6, alpha: 1), alignment: .center
    )

    private lazy var stepLabels: [UILabel] = {
        let steps = ["Acquiring license", "Downloading IPA", "Patching metadata", "Replicating sinf", "Ready"]
        return steps.map { UILabel.styled(text: "○ \($0)", font: AppFont.regular(12), color: UIColor(white: 0.4, alpha: 1)) }
    }()

    private lazy var actionsStack: UIStackView = {
        let installBtn = makeActionButton(title: "Install", action: #selector(installTapped))
        let shareBtn = makeActionButton(title: "Share", action: #selector(shareTapped))
        let filesBtn = makeActionButton(title: "Files", action: #selector(filesTapped))
        let stack = UIStackView(arrangedSubviews: [installBtn, shareBtn, filesBtn])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        return stack
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        startDownload()
    }

    private func startDownload() {
        Task {
            do {
                updateStep(0, status: .inProgress)
                do {
                    try await AppStoreService.shared.purchase(app: app)
                } catch AppStoreError.purchaseFailed(let msg) where msg.contains("already") {
                } catch AppStoreError.paidAppNotSupported {
                    throw AppStoreError.paidAppNotSupported
                } catch {
                }
                updateStep(0, status: .done)

                updateStep(1, status: .inProgress)
                let result = try await AppStoreService.shared.download(
                    app: app, externalVersionID: versionID
                ) { [weak self] downloaded, total in
                    Task { @MainActor in
                        guard let self else { return }
                        let pct = total > 0 ? Float(downloaded) / Float(total) : 0
                        self.progressBar.progress = pct
                        let dlMB = Double(downloaded) / 1_048_576
                        let totalMB = Double(total) / 1_048_576
                        self.progressLabel.text = String(
                            format: "%.1f MB / %.1f MB (%.0f%%)", dlMB, totalMB, pct * 100
                        )
                    }
                }
                updateStep(1, status: .done)

                updateStep(2, status: .done)
                updateStep(3, status: .done)

                updateStep(4, status: .done)

                await MainActor.run {
                    downloadedPath = result.destinationPath
                    progressLabel.text = "Download complete!"
                    progressBar.progress = 1.0
                    actionsStack.isHidden = false
                }

            } catch {
                await MainActor.run {
                    progressLabel.text = error.localizedDescription
                    progressLabel.textColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
                }
            }
        }
    }

    private enum StepStatus { case pending, inProgress, done }

    private func updateStep(_ index: Int, status: StepStatus) {
        Task { @MainActor in
            guard index < stepLabels.count else { return }
            let label = stepLabels[index]
            let text = String(label.text?.dropFirst(2) ?? "")
            switch status {
            case .pending:
                label.text = "○ \(text)"
                label.textColor = UIColor(white: 0.4, alpha: 1)
            case .inProgress:
                label.text = "⏳ \(text)"
                label.textColor = UIColor(named: "RED") ?? .red
            case .done:
                label.text = "✓ \(text)"
                label.textColor = UIColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 1)
            }
        }
    }

    @objc private func installTapped() {
        guard let path = downloadedPath else { return }
        progressLabel.text = "Installing..."
        Task.detached {
            let result = RootExec.installIPA(path: path)
            await MainActor.run { [weak self] in
                self?.progressLabel.text = result ?? "Install failed"
            }
        }
    }

    @objc private func shareTapped() {
        guard let path = downloadedPath else { return }
        let url = URL(fileURLWithPath: path)
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(vc, animated: true)
    }

    @objc private func filesTapped() {
        guard let path = downloadedPath else { return }
        let dir = (path as NSString).deletingLastPathComponent
        progressLabel.text = "IPA saved at:\n\(dir)"
        progressLabel.numberOfLines = 0
    }

    private func makeActionButton(title: String, action: Selector) -> UIButton {
        let btn = UIButton.styled(
            title: title, font: AppFont.bold(12),
            backgroundColor: UIColor(white: 0.2, alpha: 1),
            cornerRadius: 8, target: self, action: action
        )
        btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return btn
    }
}

extension DownloadViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(nameLabel)
        view.addSubview(versionLabel)
        view.addSubview(progressBar)
        view.addSubview(progressLabel)
        stepLabels.forEach { view.addSubview($0) }
        view.addSubview(actionsStack)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            versionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            progressBar.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 32),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            progressLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 8),
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        var previous: UIView = progressLabel
        for label in stepLabels {
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: previous == progressLabel ? 24 : 6),
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 48),
            ])
            previous = label
        }

        NSLayoutConstraint.activate([
            actionsStack.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: 32),
            actionsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            actionsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }
}
