import UIKit

protocol MenuButtonDelegate: AnyObject {
    func didTapMenuButton()
    var isMenuOpened: Bool { get }
}

class BaseViewController: UIViewController {
    
    weak var menuDelegate: MenuButtonDelegate?
    var overlayView: UIView?

    private lazy var menuButton: UIButton = {
        let button = UIButton()
        let image = UIImage(named: "menu")
        button.setImage(image, for: .normal)
        button.addTarget(self, action: #selector(didTapMenuButton), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tag = 10
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(menuButton)
        
        NSLayoutConstraint.activate([
            menuButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            menuButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
        ])
    }
    
    private func getMenuButtonImage() -> UIImage? {
        return menuDelegate?.isMenuOpened == true
        ? UIImage(systemName: "xmark")
        : UIImage(systemName: "line.3.horizontal.decrease")
    }
    
    @objc private func didTapMenuButton() {
        menuDelegate?.didTapMenuButton()
    }
    
    func setupAdditionalConfiguration() {
        view.backgroundColor = UIColor(named: "Background")
        navigationController?.navigationBar.isHidden = true
    }
}
