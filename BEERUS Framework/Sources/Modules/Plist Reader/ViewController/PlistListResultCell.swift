import UIKit



final class PlistListResultCell: UITableViewCell {
    var appInfo: AppManager.AppInfo?

    
    public lazy var FileLabel: UILabel = {
        let label = UILabel()
        label.text = ""
        label.font = UIFont.systemFont(ofSize: 14.0)
        label.lineBreakMode = .byTruncatingHead
        label.isUserInteractionEnabled = false
        return label
    }()
    
    
    public func setupInfos(plistPath: String) {
        FileLabel.text = plistPath
    }
    

    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCellView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func setupCellView() {
        selectionStyle = .none
        backgroundColor = UIColor.clear
        
        let box = UIView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.layer.borderColor = UIColor.white.cgColor
        box.layer.borderWidth = 2
        box.layer.cornerRadius = 5
        box.backgroundColor = .containerBackground
        box.isUserInteractionEnabled = true

        
        let stackView = UIStackView(arrangedSubviews: [FileLabel])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.spacing = 12
        stackView.alignment = .center
        stackView.backgroundColor = .containerBackground

        
        addSubview(box)
        box.addSubview(stackView)
        
        
        box.topAnchor.constraint(equalTo: self.topAnchor, constant: 5).isActive = true
        box.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        box.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -5).isActive = true
        box.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true

        stackView.topAnchor.constraint(equalTo: box.topAnchor).isActive = true
        stackView.leadingAnchor.constraint(equalTo: box.leadingAnchor).isActive = true
        stackView.bottomAnchor.constraint(equalTo: box.bottomAnchor).isActive = true
        stackView.trailingAnchor.constraint(equalTo: box.trailingAnchor).isActive = true
        
        NSLayoutConstraint.activate([
            FileLabel.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            FileLabel.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8)

        ])

    }
}

