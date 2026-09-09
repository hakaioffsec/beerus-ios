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

    /// Shows the dropdown below `anchorView`, clamped to whatever vertical space is actually
    /// available in `containerView` — flipping above the anchor and/or shrinking (the table view
    /// scrolls internally) instead of extending the frame past the screen edge, which used to just
    /// push the bottom rows off-screen with no way to reach them.
    ///
    /// `widthAnchor`, if provided, drives the dropdown's horizontal size/position instead of
    /// `anchorView` — pass the layout container that already spans a comfortable content width
    /// (e.g. the screen's normal side margins) when `anchorView` itself is a narrow control (like
    /// one button in a row of equal-width buttons), so the list isn't squeezed into that control's
    /// own width. `anchorView` still drives the vertical (Y) position either way.
    func show(from anchorView: UIView, widthAnchor: UIView? = nil, in containerView: UIView,
              maxRows: Int = 5, rowHeight: CGFloat = 44, margin: CGFloat = 8) {
        let desired = desiredHeight(maxRows: maxRows, rowHeight: rowHeight)
        let anchorFrame = anchorView.convert(anchorView.bounds, to: containerView)
        let widthView = widthAnchor ?? anchorView
        let widthFrame = widthView.convert(widthView.bounds, to: containerView)
        let bounds = containerView.bounds
        let safeArea = containerView.safeAreaInsets

        let availableBelow = bounds.maxY - safeArea.bottom - anchorFrame.maxY - margin
        let availableAbove = anchorFrame.minY - bounds.minY - safeArea.top - margin

        let showBelow = availableBelow >= rowHeight || availableBelow >= availableAbove
        let available = max(rowHeight, showBelow ? availableBelow : availableAbove)
        let height = min(desired, available)

        let y = showBelow ? anchorFrame.maxY + margin : anchorFrame.minY - margin - height

        frame = CGRect(
            x: widthFrame.minX,
            y: y,
            width: widthFrame.width,
            height: height
        )

        if superview == nil {
            containerView.addSubview(self)
        }

        tableView.isScrollEnabled = desired > height
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