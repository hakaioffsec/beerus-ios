import UIKit

final class HomeViewController: UIViewController {
    
    private lazy var globeImageView: UIImageView = {
        let image = UIImage(systemName: "globe")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private lazy var hackThePlanetLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.text = "Hack the planet!"
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
        view.addSubview(globeImageView)
        view.addSubview(hackThePlanetLabel)
    }
    
    func setupConstraints() {
        NSLayoutConstraint.activate([
            globeImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            globeImageView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -32),
            globeImageView.widthAnchor.constraint(equalToConstant: 52),
            globeImageView.heightAnchor.constraint(equalToConstant: 52),
            
            hackThePlanetLabel.topAnchor.constraint(equalTo: globeImageView.bottomAnchor, constant: 24),
            hackThePlanetLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hackThePlanetLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
    
    func setupAdditionalConfiguration() {
        view.backgroundColor = .black
    }
}
