import Foundation
import UIKit

final class HomeViewController: BaseViewController {
    
    private lazy var circuitTopImageView: UIImageView = {
        let image = UIImage(named: "circuit-top")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftImageView: UIImageView = {
        let image = UIImage(named: "circuit-left")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitRightImageView: UIImageView = {
        let image = UIImage(named: "circuit-right")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    
    private lazy var textContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(named: "ContainerBackground")
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        return view
    }()

    private lazy var beerusImageView: UIImageView = {
        let image = UIImage(named: "BeerusHome")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont(name: "IBM Plex Mono Medium", size: 20)
        label.text = "BEERUS\nframework"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.tintColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont(name: "IBM Plex Mono Medium", size: 14)
        label.text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed vel lorem ligula. Proin faucibus dolor erat, a ultricies ligula molestie scelerisque."
        label.lineBreakMode = .byWordWrapping
        label.numberOfLines = 0
        label.tintColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private lazy var footerLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont(name: "IBM Plex Mono", size: 14)
        label.text = "If you really know, you can hack\nBSDaemon"
        label.textAlignment = .center
        label.tintColor = .white
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
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
