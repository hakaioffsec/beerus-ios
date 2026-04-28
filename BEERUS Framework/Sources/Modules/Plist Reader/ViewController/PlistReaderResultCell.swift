//
//  SearchResultCell.swift
//  AppStoreClone
//
//  Created by Kelvin Montini on 02/08/21.
//

import UIKit


final class PlistReaderResultCell: UITableViewCell {
    var appInfo: AppManager.AppInfo?
    
    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.backgroundColor = UIColor.clear
        imageView.layer.cornerRadius = 20
        imageView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 64).isActive = true
        return imageView
    }()
    
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.text = "APP NAME"
        label.isUserInteractionEnabled = false
        return label
    }()
    
    private lazy var packageLabel: UILabel = {
        let label = UILabel()
        label.text = "Photo & Video"
        label.isUserInteractionEnabled = false
        return label
    }()
    
    private lazy var ratingsLabel: UILabel = {
        let label = UILabel()
        label.text = "Plist Files: 0"
        label.isUserInteractionEnabled = false
        return label
    }()
    
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCellView()
    }
    
    public func setupInfos(package: String, apps: [String: AppManager.AppInfo]) {
        packageLabel.text = package
        if let app = apps[package] {
            nameLabel.text = app.name
            iconImageView.image = UIImage(contentsOfFile: app.icone)
            ratingsLabel.text = "Plist Files: "+String(app.plists.count)
            appInfo = app
        }

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
        //        box.layer.name = name
        box.layer.borderWidth = 2
        box.layer.cornerRadius = 5
        box.backgroundColor = .containerBackground
        box.isUserInteractionEnabled = true

        let labelsStackView = UIStackView(arrangedSubviews: [nameLabel, packageLabel, ratingsLabel])
        labelsStackView.axis = .vertical
        
        let stackView = UIStackView(arrangedSubviews: [iconImageView, labelsStackView])
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
            iconImageView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 16),
            
        ])
    }
}

