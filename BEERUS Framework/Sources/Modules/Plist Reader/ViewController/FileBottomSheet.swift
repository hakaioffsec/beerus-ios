import UIKit

class FileBottomSheet: UIViewController {
    
    fileprivate let cellReuseIdentifier = "FileBottomSheetCellReuseIdentifier"
    private var plistEntries: [(key: String, value: String)]
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
    
    func readPlist() -> [(key: String, value: String)] {
        var plistsValues: [String: String] = [:]
        if let dict = NSDictionary(contentsOfFile: fileText) as? [String: Any] {
           for (key, value) in dict {
               plistsValues["\(key)"] = "\(value)"
           }
        }

        return plistsValues.sorted { $0.key < $1.key }
    }


    init(file: String) {
        self.fileText = file
        self.plistEntries = []
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup() {
        plistEntries = readPlist()

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
        return plistEntries.count
    }
}

extension FileBottomSheet: UITableViewDelegate {

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as? FileBottomSheetCell else {
            return FileBottomSheetCell.init(style: .default, reuseIdentifier: cellReuseIdentifier)
        }

        let entry = plistEntries[indexPath.row]
        cell.setupInfos(key: entry.key, value: entry.value)

        return cell
    }
}








