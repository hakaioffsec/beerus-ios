import UIKit

// MARK: - App Fonts

enum AppFont {
    static func regular(_ size: CGFloat) -> UIFont {
        UIFont(name: "IBM Plex Mono", size: size) ?? .systemFont(ofSize: size)
    }

    static func medium(_ size: CGFloat) -> UIFont {
        UIFont(name: "IBM Plex Mono Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    }

    static func bold(_ size: CGFloat) -> UIFont {
        UIFont(name: "IBM Plex Mono Bold", size: size) ?? .boldSystemFont(ofSize: size)
    }
}

// MARK: - UILabel Factory

extension UILabel {
    static func styled(
        text: String? = nil,
        font: UIFont = AppFont.regular(14),
        color: UIColor = .white,
        alignment: NSTextAlignment = .natural,
        lines: Int = 1
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.textAlignment = alignment
        label.numberOfLines = lines
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}

// MARK: - UIButton Factory

extension UIButton {
    static func styled(
        title: String,
        font: UIFont = AppFont.bold(14),
        backgroundColor: UIColor? = UIColor(named: "ButtonColor"),
        cornerRadius: CGFloat = 10,
        target: Any? = nil,
        action: Selector? = nil
    ) -> UIButton {
        let button = UIButton()
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = font
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = cornerRadius
        button.translatesAutoresizingMaskIntoConstraints = false
        if let target, let action {
            button.addTarget(target, action: action, for: .touchUpInside)
        }
        return button
    }
}

// MARK: - UIImageView Factory

extension UIImageView {
    static func circuit(named name: String) -> UIImageView {
        let imageView = UIImageView(image: UIImage(named: name))
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }
}

