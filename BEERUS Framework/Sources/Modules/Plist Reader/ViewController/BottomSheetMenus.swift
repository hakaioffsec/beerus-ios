import UIKit

class BottomSheetViewController: UIViewController {
    
    fileprivate let cellReuseIdentifier = "PlistListCellReuseIdentifier"
    private var filesCount = 0;
    private var plistsPaths: [String]
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.backgroundColor = UIColor.clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(PlistListResultCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        tableView.isUserInteractionEnabled = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setup()
    }
    
    init(plists: [String]) {
        filesCount = plists.count
        plistsPaths = plists
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup() {
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }
    
}


extension BottomSheetViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filesCount
    }
}

extension BottomSheetViewController: UITableViewDelegate {
        
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as? PlistListResultCell else {
            return PlistListResultCell.init(style: .default, reuseIdentifier: cellReuseIdentifier)
        }
        
        if (plistsPaths.count > 0) {
            cell.setupInfos(plistPath: plistsPaths[indexPath.row])
        }

        return cell
    }
    
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 55
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let cell = tableView.cellForRow(at: indexPath) as? PlistListResultCell {
            let fileText = cell.FileLabel.text
                let menuViewController = FileBottomSheet(file: fileText ?? "")
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








