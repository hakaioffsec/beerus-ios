import UIKit

final class FileBottomSheetCell: UITableViewCell {
    private lazy var valueLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.text = "abacaxi"
        label.lineBreakMode = .byTruncatingHead
        label.isUserInteractionEnabled = false
        return label
    }()
    
    
    
    public func setupInfos(key: String, value: String) {
        valueLabel.text = key+": "+value
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

        
        let stackView = UIStackView(arrangedSubviews: [valueLabel])
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
            valueLabel.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            valueLabel.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            valueLabel.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8)
            
        ])

    }
}

