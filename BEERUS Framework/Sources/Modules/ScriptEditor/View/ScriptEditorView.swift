import UIKit

final class ScriptEditorView: UIView {

    private let topBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(named: "ContainerBackground")
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    let backButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "chevron.left")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        btn.setImage(img, for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = AppFont.bold(14)
        l.textColor = .white
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let unsavedDot: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(named: "RED")
        v.layer.cornerRadius = 4
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    let moreButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "ellipsis.circle")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let codeEditor = CodeEditorView()

    private let bottomBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(named: "ContainerBackground")
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    let saveButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("SAVE", for: .normal)
        btn.titleLabel?.font = AppFont.bold(12)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(white: 0.18, alpha: 1)
        btn.layer.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    let runButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("▶ RUN", for: .normal)
        btn.titleLabel?.font = AppFont.bold(12)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(named: "RED")
        btn.layer.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let charCountLabel: UILabel = {
        let l = UILabel()
        l.font = AppFont.regular(10)
        l.textColor = UIColor(white: 0.35, alpha: 1)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private var bottomBarBottomConstraint: NSLayoutConstraint?

    var onTextChange: ((String) -> Void)? {
        get { codeEditor.onTextChange }
        set { codeEditor.onTextChange = newValue }
    }

    var codeText: String { codeEditor.text }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(named: "Background")
        codeEditor.translatesAutoresizingMaskIntoConstraints = false
        buildUI()
        setupKeyboardObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public

    func setName(_ name: String) {
        nameLabel.text = name
    }

    func setCode(_ source: String) {
        codeEditor.text = source
    }

    func setUnsaved(_ unsaved: Bool) {
        unsavedDot.isHidden = !unsaved
    }

    func setCharCount(_ text: String) {
        charCountLabel.text = text
    }

    func showSavedFeedback() {
        let lbl = UILabel()
        lbl.text = "Saved ✓"
        lbl.font = AppFont.medium(12)
        lbl.textColor = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
        lbl.sizeToFit()
        lbl.center = CGPoint(x: center.x, y: safeAreaInsets.top + 70)
        addSubview(lbl)

        UIView.animate(withDuration: 0.8, delay: 0.5, options: []) {
            lbl.alpha = 0
            lbl.center.y -= 20
        } completion: { _ in
            lbl.removeFromSuperview()
        }
    }

    // MARK: - Build

    private func buildUI() {
        addSubview(topBar)
        topBar.addSubview(backButton)
        topBar.addSubview(nameLabel)
        topBar.addSubview(unsavedDot)
        topBar.addSubview(moreButton)
        addSubview(codeEditor)
        addSubview(bottomBar)
        bottomBar.addSubview(charCountLabel)
        bottomBar.addSubview(saveButton)
        bottomBar.addSubview(runButton)

        let bottomConstraint = bottomBar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        bottomBarBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 48),

            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 12),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 36),
            backButton.heightAnchor.constraint(equalToConstant: 36),

            nameLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -4),

            unsavedDot.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            unsavedDot.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            unsavedDot.widthAnchor.constraint(equalToConstant: 8),
            unsavedDot.heightAnchor.constraint(equalToConstant: 8),

            moreButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -12),
            moreButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 36),
            moreButton.heightAnchor.constraint(equalToConstant: 36),

            codeEditor.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 4),
            codeEditor.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            codeEditor.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            codeEditor.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -4),

            bottomBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 52),
            bottomConstraint,

            charCountLabel.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 16),
            charCountLabel.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),

            saveButton.trailingAnchor.constraint(equalTo: runButton.leadingAnchor, constant: -8),
            saveButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            saveButton.widthAnchor.constraint(equalToConstant: 64),
            saveButton.heightAnchor.constraint(equalToConstant: 34),

            runButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -16),
            runButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            runButton.widthAnchor.constraint(equalToConstant: 80),
            runButton.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    // MARK: - Keyboard

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil
        )
    }

    @objc private func keyboardWillShow(_ notif: Notification) {
        guard let frame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notif.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        let inset = frame.height - safeAreaInsets.bottom
        bottomBarBottomConstraint?.constant = -inset
        UIView.animate(withDuration: duration) { self.layoutIfNeeded() }
    }

    @objc private func keyboardWillHide(_ notif: Notification) {
        guard let duration = notif.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        bottomBarBottomConstraint?.constant = 0
        UIView.animate(withDuration: duration) { self.layoutIfNeeded() }
    }
}
