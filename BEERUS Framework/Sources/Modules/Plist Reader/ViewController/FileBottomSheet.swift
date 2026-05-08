import UIKit

class FileBottomSheet: UIViewController {
    
    fileprivate let cellReuseIdentifier = "FileBottomSheetCellReuseIdentifier"
    private var plistsValues: [String:String]
    private var plistsCount = 0
    private var fileText: String
    
    private lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.backgroundColor = UIColor.clear
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(FileBottomSheetCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        tableView.isUserInteractionEnabled = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setup()
    }
    
    func readPlist() -> [String: String] {
        var plistsValues: [String: String] = [:]
        if let dict = NSDictionary(contentsOfFile: fileText) as? [String: Any] {
           for (key, value) in dict {
               plistsValues["\(key)"] = "\(value)"
           }
        }

        return plistsValues
    }
    
    
    init(file: String) {
        self.fileText = file
        self.plistsValues = [:]
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup() {
        plistsValues = readPlist()
        plistsCount = plistsValues.count
        
        view.addSubview(tableView)
        tableView.rowHeight = UITableView.automaticDimension
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }
    
}

extension FileBottomSheet: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return plistsCount
    }
}

extension FileBottomSheet: UITableViewDelegate {
        
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as? FileBottomSheetCell else {
            return FileBottomSheetCell.init(style: .default, reuseIdentifier: cellReuseIdentifier)
        }
        
        if (plistsCount > 0) {
            cell.setupInfos(key: plistsValues.keys.sorted()[indexPath.row], value: plistsValues.values.sorted()[indexPath.row])
        }
        
        return cell
    }
}








