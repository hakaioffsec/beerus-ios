import UIKit

final class HomeViewController: BaseViewController {

    private lazy var circuitTopImageView = UIImageView.circuit(named: "circuit-top")
    private lazy var circuitLeftImageView = UIImageView.circuit(named: "circuit-left")
    private lazy var circuitRightImageView = UIImageView.circuit(named: "circuit-right")
    private lazy var beerusImageView = UIImageView.circuit(named: "BeerusHome")

    private lazy var textContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(named: "ContainerBackground")
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        return view
    }()

    private lazy var titleLabel = UILabel.styled(
        text: "BEERUS\nframework", font: AppFont.medium(20), alignment: .center, lines: 0
    )
    private lazy var descriptionLabel = UILabel.styled(
        text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed vel lorem ligula. Proin faucibus dolor erat, a ultricies ligula molestie scelerisque.",
        font: AppFont.medium(14), lines: 0
    )
    private lazy var footerLabel = UILabel.styled(
        text: "If you really know, you can hack\nBSDaemon", font: AppFont.regular(14), alignment: .center, lines: 0
    )
    
    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
    }
}

extension HomeViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(circuitTopImageView)
        view.addSubview(circuitRightImageView)
        view.addSubview(circuitLeftImageView)
        view.addSubview(textContainerView)
        view.addSubview(beerusImageView)
        textContainerView.addSubview(titleLabel)
        textContainerView.addSubview(descriptionLabel)
        textContainerView.addSubview(footerLabel)
    }
    
    func setupConstraints() {
        NSLayoutConstraint.activate([
            circuitTopImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitTopImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            
            circuitRightImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitRightImageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            
            circuitLeftImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitLeftImageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                        
            textContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textContainerView.heightAnchor.constraint(equalToConstant: view.frame.height * 0.67),
            
            beerusImageView.bottomAnchor.constraint(equalTo: textContainerView.topAnchor),
            beerusImageView.centerXAnchor.constraint(equalTo: textContainerView.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: textContainerView.topAnchor, constant: 24),
            titleLabel.centerXAnchor.constraint(equalTo: textContainerView.centerXAnchor),
            
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            descriptionLabel.leadingAnchor.constraint(equalTo: textContainerView.leadingAnchor, constant: 24),
            descriptionLabel.trailingAnchor.constraint(equalTo: textContainerView.trailingAnchor, constant: -24),
            
            footerLabel.bottomAnchor.constraint(equalTo: textContainerView.bottomAnchor, constant: -24),
            footerLabel.centerXAnchor.constraint(equalTo: textContainerView.centerXAnchor),
        ])
    }


}
