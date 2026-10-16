import UIKit

final class HomeView: UIView {

    private lazy var leftRaysImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "ray")
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.transform = CGAffineTransform(scaleX: -1, y: 1)
        return imageView
    }()

    private lazy var rightRaysImageView: UIImageView = {
        let imageView = UIImageView.circuit(named: "ray")
        imageView.contentMode = .scaleAspectFit
        imageView.transform = CGAffineTransform(scaleX: 1, y: 1)
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

    private var cardTopConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        cardTopConstraint.constant = bounds.height * 0.38
    }
}

extension HomeView: ViewCode {
    func buildViewHierarchy() {
        addSubview(leftRaysImageView)
        addSubview(rightRaysImageView)
        addSubview(beerusImageView)
        addSubview(textContainerView)

        textContainerView.addSubview(titleLabel)
        textContainerView.addSubview(descriptionLabel)
        textContainerView.addSubview(footerLabel)
    }

    func setupConstraints() {
        cardTopConstraint = textContainerView.topAnchor.constraint(equalTo: topAnchor)

        NSLayoutConstraint.activate([
            textContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            cardTopConstraint,

            leftRaysImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: -8),
            leftRaysImageView.leftAnchor.constraint(equalTo: leftAnchor, constant: -20),
            leftRaysImageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            leftRaysImageView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.5),

            rightRaysImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            rightRaysImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 20),
            rightRaysImageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            rightRaysImageView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.5),

            beerusImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            beerusImageView.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            beerusImageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.8),
            beerusImageView.heightAnchor.constraint(equalTo: beerusImageView.widthAnchor, multiplier: 1.18),

            titleLabel.topAnchor.constraint(equalTo: textContainerView.topAnchor, constant: 48),
            titleLabel.leadingAnchor.constraint(equalTo: textContainerView.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: textContainerView.trailingAnchor, constant: -28),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 26),
            descriptionLabel.leadingAnchor.constraint(equalTo: textContainerView.leadingAnchor, constant: 32),
            descriptionLabel.trailingAnchor.constraint(equalTo: textContainerView.trailingAnchor, constant: -32),

            footerLabel.centerXAnchor.constraint(equalTo: textContainerView.centerXAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -28),
        ])
    }
}
