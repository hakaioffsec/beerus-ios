import UIKit

final class SandboxExfiltrationAppDetailViewController: UIViewController {

    var viewModel: SandboxExfiltrationAppDetailViewModel!

    private let rootView = SandboxExfiltrationAppDetailView()

    override func loadView() {
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        rootView.modeToggle.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        rootView.serverTextField.addTarget(self, action: #selector(serverAddressChanged), for: .editingChanged)
        rootView.compactButton.addTarget(self, action: #selector(compactTapped), for: .touchUpInside)
        rootView.serverTextField.delegate = self
        bindViewModel()
        viewModel.viewDidLoad()
    }

    private func bindViewModel() {
        viewModel.onAppDisplay = { [weak self] display in
            guard let self else { return }
            self.rootView.nameLabel.text = display.name
            self.rootView.bundleLabel.text = display.bundleId

            if !display.iconPath.isEmpty,
               let image = UIImage(contentsOfFile: display.iconPath) {
                self.rootView.iconImageView.image = image
            } else {
                self.rootView.iconImageView.image = UIImage(systemName: "app.fill")
            }

            if !display.hasDataContainer {
                self.rootView.compactButton.isEnabled = false
                self.rootView.compactButton.backgroundColor = UIColor(
                    red: 0.3,
                    green: 0.3,
                    blue: 0.3,
                    alpha: 1
                )
            }
        }

        viewModel.onStorageSize = { [weak self] text in
            self?.rootView.storageSizeLabel.text = text
        }

        viewModel.onServerTextField = { [weak self] text, isEnabled in
            guard let self else { return }
            self.rootView.serverTextField.text = text
            self.rootView.serverTextField.textColor = isEnabled ? .white : .lightGray
            self.rootView.serverTextField.isUserInteractionEnabled = isEnabled
        }

        viewModel.onServerTextFieldColor = { [weak self] isValid in
            self?.rootView.serverTextField.layer.borderColor = isValid
                ? UIColor.darkGray.cgColor
                : UIColor.systemRed.cgColor
        }

        viewModel.onValidation = { [weak self] showError in
            UIView.animate(withDuration: 0.2) {
                self?.rootView.validationLabel.isHidden = !showError
                self?.rootView.validationLabel.alpha = showError ? 1 : 0
            }
        }

        viewModel.onServerStatus = { [weak self] status, hidden in
            guard let self else { return }
            self.rootView.serverStatusView.isHidden = hidden
            self.rootView.serverStatusLabel.isHidden = hidden

            switch status {
            case .idle:
                self.rootView.serverCheckingIndicator.stopAnimating()
                self.rootView.serverStatusView.backgroundColor = .darkGray
                self.rootView.serverStatusLabel.text = ""
                self.rootView.serverStatusLabel.textColor = .gray

            case .checking:
                self.rootView.serverCheckingIndicator.startAnimating()
                self.rootView.serverStatusView.backgroundColor = .darkGray
                self.rootView.serverStatusLabel.text = "Checking..."
                self.rootView.serverStatusLabel.textColor = .gray

            case .online(let version):
                self.rootView.serverCheckingIndicator.stopAnimating()
                self.rootView.serverStatusView.backgroundColor = .systemGreen
                self.rootView.serverStatusLabel.text = "Online (v\(version))"
                self.rootView.serverStatusLabel.textColor = .systemGreen

            case .offline:
                self.rootView.serverCheckingIndicator.stopAnimating()
                self.rootView.serverStatusView.backgroundColor = .systemRed
                self.rootView.serverStatusLabel.text = "Offline"
                self.rootView.serverStatusLabel.textColor = .systemRed
            }
        }

        viewModel.onCompactButton = { [weak self] enabled, title in
            guard let self else { return }
            self.rootView.compactButton.isEnabled = enabled
            self.rootView.compactButton.setTitle(title, for: .normal)
            self.rootView.compactButton.backgroundColor = enabled
                ? UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
                : UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1)
        }

        viewModel.onLoading = { [weak self] isLoading in
            guard let self else { return }
            if isLoading {
                self.rootView.loadingIndicator.startAnimating()
                self.rootView.compactButton.backgroundColor = UIColor(
                    red: 0.4,
                    green: 0.1,
                    blue: 0.1,
                    alpha: 1
                )
            } else {
                self.rootView.loadingIndicator.stopAnimating()
            }
        }
    }
}

private extension SandboxExfiltrationAppDetailViewController {
    @objc func modeChanged() {
        viewModel.modeChanged(index: rootView.modeToggle.selectedSegmentIndex)
    }

    @objc func serverAddressChanged() {
        viewModel.serverAddressChanged(rootView.serverTextField.text ?? "")
    }

    @objc func compactTapped() {
        viewModel.compactTapped()
    }
}

extension SandboxExfiltrationAppDetailViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
