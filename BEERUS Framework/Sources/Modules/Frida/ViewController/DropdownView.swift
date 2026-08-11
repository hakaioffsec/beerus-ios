//
//  DropdownView.swift
//  BEERUS Framework
//
//  Created by Daniel França Lima on 06/02/26.
//

import UIKit

final class SimpleDropdown: UIView, UITableViewDataSource, UITableViewDelegate {

    var onSelect: ((String) -> Void)?

    var itemFont: UIFont?
    var itemTextColor: UIColor?

    private let items: [String]
    private let tableView = UITableView(frame: .zero, style: .plain)

    init(items: [String]) {
        self.items = items
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        // sombra
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 6)
        layer.masksToBounds = false

        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableFooterView = UIView()
        tableView.separatorInset = .zero
        tableView.backgroundColor = .clear
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: topAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    func desiredHeight(maxRows: Int, rowHeight: CGFloat) -> CGFloat {
        let rows = min(items.count, maxRows)
        tableView.rowHeight = rowHeight
        return CGFloat(rows) * rowHeight
    }

    func show(from anchorView: UIView, in containerView: UIView, maxRows: Int = 5, rowHeight: CGFloat = 44, margin: CGFloat = 8) {
        let height = desiredHeight(maxRows: maxRows, rowHeight: rowHeight)
        let anchorFrame = anchorView.convert(anchorView.bounds, to: containerView)

        frame = CGRect(
            x: anchorFrame.minX,
            y: anchorFrame.maxY + margin,
            width: anchorFrame.width,
            height: height
        )

        if superview == nil {
            containerView.addSubview(self)
        }

        tableView.reloadData()
    }

    // MARK: UITableViewDataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = items[indexPath.row]
        cell.textLabel?.font = itemFont
        cell.textLabel?.textColor = itemTextColor
        cell.backgroundColor = .clear
        return cell
    }

    // MARK: UITableViewDelegate
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        onSelect?(items[indexPath.row])
    }
}