import UIKit

final class PlistReaderView: UIView {

    static let cellReuseIdentifier = "PlistReaderCellReuseIdentifier"

    private lazy var circuitTopImageView = UIImageView.circuit(named: "circuit-top")
    private lazy var circuitLeftImageView = UIImageView.circuit(named: "circuit-left-2")
    private lazy var circuitRightImageView = UIImageView.circuit(named: "circuit-right")
    private lazy var circuitLeftDownImageView = UIImageView.circuit(named: "circuit-left-down")

    let tableView: UITableView = {
        let tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.backgroundColor = UIColor.clear
        tableView.register(PlistReaderResultCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        tableView.isUserInteractionEnabled = true
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        applyViewCode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension PlistReaderView: ViewCode {
    func buildViewHierarchy() {
        addSubview(circuitTopImageView)
        addSubview(circuitRightImageView)
        addSubview(circuitLeftImageView)
        addSubview(circuitLeftDownImageView)
        addSubview(tableView)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            circuitTopImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitTopImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),

            circuitRightImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitRightImageView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            circuitRightImageView.widthAnchor.constraint(equalToConstant: 40),
            circuitRightImageView.heightAnchor.constraint(equalTo: safeAreaLayoutGuide.heightAnchor),

            circuitLeftImageView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            circuitLeftImageView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),

            circuitLeftDownImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            circuitLeftDownImageView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),

            tableView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 64),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }
}
