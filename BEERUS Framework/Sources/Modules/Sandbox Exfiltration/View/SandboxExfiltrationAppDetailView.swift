import UIKit

final class SandboxExfiltrationAppDetailView: UIView {

    private let grabberView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.gray
        view.layer.cornerRadius = 2.5
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 28
        imageView.clipsToBounds = true
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.boldSystemFont(ofSize: 18)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let bundleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .gray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let storageSizeLabel: UILabel = {
        let label = UILabel()
        label.text = "Calculating size..."
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .gray
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let modeToggle: UISegmentedControl = {
        let control = UISegmentedControl(items: ["USB", "VPS"])
        control.selectedSegmentIndex = 0
        control.backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
        control.selectedSegmentTintColor = UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        control.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: UIColor.lightGray], for: .normal)
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    let serverTextField: UITextField = {
        let textField = UITextField()
        textField.placeholder = "http://192.168.1.100:8080"
        textField.textColor = .white
        textField.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.09, alpha: 1)
        textField.layer.borderColor = UIColor.darkGray.cgColor
        textField.layer.borderWidth = 1
        textField.layer.cornerRadius = 8
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        textField.leftViewMode = .always
        textField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        textField.rightViewMode = .always
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.keyboardType = .URL
        textField.returnKeyType = .done
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }()

    let validationLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = .systemRed
        label.textAlignment = .left
        label.text = "Invalid server address"
        label.isHidden = true
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let serverStatusView: UIView = {
        let view = UIView()
        view.backgroundColor = .darkGray
        view.layer.cornerRadius = 5
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    let serverStatusLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textColor = .gray
        label.text = ""
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let serverCheckingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .gray
        indicator.hidesWhenStopped = true
        indicator.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    let compactButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Compact", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 16)
        button.backgroundColor = UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        applyViewCode()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func dismissKeyboard() {
        endEditing(true)
    }
}

extension SandboxExfiltrationAppDetailView: ViewCode {
    func buildViewHierarchy() {
        addSubview(grabberView)
        addSubview(iconImageView)
        addSubview(nameLabel)
        addSubview(bundleLabel)
        addSubview(storageSizeLabel)
        addSubview(modeToggle)
        addSubview(serverTextField)
        addSubview(validationLabel)
        addSubview(serverStatusView)
        addSubview(serverCheckingIndicator)
        addSubview(serverStatusLabel)
        addSubview(compactButton)
        compactButton.addSubview(loadingIndicator)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            grabberView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            grabberView.centerXAnchor.constraint(equalTo: centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 40),
            grabberView.heightAnchor.constraint(equalToConstant: 5),

            iconImageView.topAnchor.constraint(equalTo: grabberView.bottomAnchor, constant: 24),
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 64),
            iconImageView.heightAnchor.constraint(equalToConstant: 64),

            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            bundleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            bundleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            bundleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            storageSizeLabel.topAnchor.constraint(equalTo: bundleLabel.bottomAnchor, constant: 8),
            storageSizeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            storageSizeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            modeToggle.topAnchor.constraint(equalTo: storageSizeLabel.bottomAnchor, constant: 20),
            modeToggle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            modeToggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            modeToggle.heightAnchor.constraint(equalToConstant: 36),

            serverTextField.topAnchor.constraint(equalTo: modeToggle.bottomAnchor, constant: 12),
            serverTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            serverTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            serverTextField.heightAnchor.constraint(equalToConstant: 44),

            validationLabel.topAnchor.constraint(equalTo: serverTextField.bottomAnchor, constant: 4),
            validationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            validationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            serverStatusView.topAnchor.constraint(equalTo: serverTextField.bottomAnchor, constant: 8),
            serverStatusView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            serverStatusView.widthAnchor.constraint(equalToConstant: 10),
            serverStatusView.heightAnchor.constraint(equalToConstant: 10),

            serverCheckingIndicator.centerYAnchor.constraint(equalTo: serverStatusView.centerYAnchor),
            serverCheckingIndicator.leadingAnchor.constraint(equalTo: serverStatusView.trailingAnchor, constant: 6),

            serverStatusLabel.centerYAnchor.constraint(equalTo: serverStatusView.centerYAnchor),
            serverStatusLabel.leadingAnchor.constraint(equalTo: serverStatusView.trailingAnchor, constant: 6),
            serverStatusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            compactButton.topAnchor.constraint(equalTo: serverStatusView.bottomAnchor, constant: 16),
            compactButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            compactButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            compactButton.heightAnchor.constraint(equalToConstant: 48),

            loadingIndicator.centerXAnchor.constraint(equalTo: compactButton.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: compactButton.centerYAnchor)
        ])
    }
}
