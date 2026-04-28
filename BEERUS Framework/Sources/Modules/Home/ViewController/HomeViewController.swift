import UIKit

final class HomeViewController: BaseViewController {

    private lazy var leftRaysImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "ray")
        // imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.transform = CGAffineTransform(scaleX: -1, y: 1)
        return imageView
    }()

    private lazy var rightRaysImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "ray")
        // imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.transform = CGAffineTransform(scaleX: 1, y: 1) // espelha horizontalmente
        return imageView
    }()

    private lazy var beerusImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "BeerusHome")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var textContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(named: "ContainerBackground")
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.layer.cornerRadius = 18
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        return view
    }()

    private lazy var titleLabel = UILabel.styled(
        text: "BEERUS\nframework",
        font: AppFont.medium(20),
        alignment: .center,
        lines: 0
    )

    private lazy var descriptionLabel = UILabel.styled(
        text: "Developed by the Hakai Offensive Security Research Team, your all-in-one toolkit for mobile penetration testing\n≧◡≦",
        font: AppFont.medium(14),
        alignment: .center,
        lines: 0
    )

    private lazy var footerLabel = UILabel.styled(
        text: "Attack to Protect!",
        font: AppFont.regular(14),
        alignment: .center,
        lines: 0
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
    }
}

extension HomeViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(leftRaysImageView)
        view.addSubview(rightRaysImageView)
        view.addSubview(beerusImageView)
        view.addSubview(textContainerView)

        textContainerView.addSubview(titleLabel)
        textContainerView.addSubview(descriptionLabel)
        textContainerView.addSubview(footerLabel)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            // CARD
            textContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textContainerView.topAnchor.constraint(equalTo: view.topAnchor, constant: view.frame.height * 0.38),

            // FUNDO VERMELHO ESQUERDA
            leftRaysImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -8),
            leftRaysImageView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: -20),
            leftRaysImageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),
            leftRaysImageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),

            // FUNDO VERMELHO DIREITA
            rightRaysImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            rightRaysImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 20),
            rightRaysImageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),
            rightRaysImageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),

            // PERSONAGEM
            beerusImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            beerusImageView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0),
            beerusImageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            beerusImageView.heightAnchor.constraint(equalTo: beerusImageView.widthAnchor, multiplier: 1.18),

            // TÍTULO
            titleLabel.topAnchor.constraint(equalTo: textContainerView.topAnchor, constant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: textContainerView.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: textContainerView.trailingAnchor, constant: -28),

            // DESCRIÇÃO
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 26),
            descriptionLabel.leadingAnchor.constraint(equalTo: textContainerView.leadingAnchor, constant: 32),
            descriptionLabel.trailingAnchor.constraint(equalTo: textContainerView.trailingAnchor, constant: -32),

            // FOOTER
            footerLabel.centerXAnchor.constraint(equalTo: textContainerView.centerXAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
        ])
    }
}