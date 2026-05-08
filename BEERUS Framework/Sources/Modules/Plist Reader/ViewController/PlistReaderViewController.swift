import UIKit

final class PlistReaderViewController: BaseViewController {
    var appmanager = AppManager()
    var apps: [String: AppManager.AppInfo] = [:]
    fileprivate let cellReuseIdentifier = "PlistReaderCellReuseIdentifier"
    
    private lazy var circuitTopImageView: UIImageView = {
        let image = UIImage(named: "circuit-top")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftImageView: UIImageView = {
        let image = UIImage(named: "circuit-left-2")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitRightImageView: UIImageView = {
        let image = UIImage(named: "circuit-right")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var circuitLeftDownImageView: UIImageView = {
        let image = UIImage(named: "circuit-left-down")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.backgroundColor = UIColor.clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PlistReaderResultCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        tableView.isUserInteractionEnabled = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        apps = appmanager.getApps()
    }
    
}

extension PlistReaderViewController: ViewCode {
    func buildViewHierarchy() {
        
        view.addSubview(circuitTopImageView)
        view.addSubview(circuitRightImageView)
        view.addSubview(circuitLeftImageView)
        view.addSubview(circuitLeftDownImageView)
        view.addSubview(tableView)
//        view.addSubview(appsScrollStack)
//        appsScrollStack.addSubview(appsStack)
//        createAppItems()
        
    }
    
    func setupConstraints() {
        NSLayoutConstraint.activate([
            circuitTopImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitTopImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            
            circuitRightImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitRightImageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            circuitRightImageView.widthAnchor.constraint(equalToConstant: 40),
            circuitRightImageView.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor),
            
            circuitLeftImageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            circuitLeftImageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            
            circuitLeftDownImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            circuitLeftDownImageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            
            
            
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 64),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)

            
//            appsScrollStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 64),
//            appsScrollStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
//            appsScrollStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
//            appsScrollStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
//            
//            appsStack.topAnchor.constraint(equalTo: appsScrollStack.topAnchor),
//            appsStack.bottomAnchor.constraint(equalTo: appsScrollStack.bottomAnchor),
//            appsStack.leadingAnchor.constraint(equalTo: appsScrollStack.leadingAnchor),
//            appsStack.trailingAnchor.constraint(equalTo: appsScrollStack.trailingAnchor),
//            appsStack.widthAnchor.constraint(equalTo: appsScrollStack.widthAnchor)
            
        ])
        
    }
}

extension PlistReaderViewController {
    func openPlistsMenu(in cell: PlistReaderResultCell, package: String){
        if let appInfo = apps[package] {
            let menuViewController = BottomSheetViewController(plists: appInfo.plists)
            if #available(iOS 15.0, *) {
                if let sheet = menuViewController.sheetPresentationController {
                    sheet.detents = [.large(), .large()]
                    sheet.prefersGrabberVisible = true
                }
            }
            present(menuViewController, animated: true, completion: nil)
        }
    }
}


extension PlistReaderViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return apps.count
    }
}

extension PlistReaderViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as? PlistReaderResultCell else {
            return PlistReaderResultCell.init(style: .default, reuseIdentifier: cellReuseIdentifier)
        }
        
        
        if (apps.count > 0) {
            cell.setupInfos(package: apps.keys.sorted()[indexPath.row], apps: apps)
        }
        
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 110
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let package = apps.keys.sorted()[indexPath.row]
        if let appInfo = apps[package] {
            let menuViewController = BottomSheetViewController(plists: appInfo.plists)
            if #available(iOS 15.0, *) {
                if let sheet = menuViewController.sheetPresentationController {
                    sheet.detents = [.large(), .large()]
                    sheet.prefersGrabberVisible = true
                }
            }
            present(menuViewController, animated: true, completion: nil)
        }
    }
}
