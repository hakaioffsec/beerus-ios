import UIKit

final class ScriptEditorViewController: UIViewController {

    // MARK: - Properties

    private var script: FridaScriptModel
    private let storage = ScriptStorageService.shared
    private var hasUnsavedChanges = false

    // MARK: - UI

    private let topBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(named: "ContainerBackground")
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var backButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "chevron.left")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        btn.setImage(img, for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
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

    private lazy var moreButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "ellipsis.circle")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        btn.setImage(img, for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        return btn
    }()

    private let codeEditor = CodeEditorView()

    private let bottomBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(named: "ContainerBackground")
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var saveButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("SAVE", for: .normal)
        btn.titleLabel?.font = AppFont.bold(12)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(white: 0.18, alpha: 1)
        btn.layer.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var runButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("▶ RUN", for: .normal)
        btn.titleLabel?.font = AppFont.bold(12)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(named: "RED")
        btn.layer.cornerRadius = 8
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(runTapped), for: .touchUpInside)
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

    // MARK: - Init

    init(script: FridaScriptModel) {
        self.script = script
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(named: "Background")
        navigationController?.navigationBar.isHidden = true
        buildUI()
        loadScript()
        setupKeyboardObservers()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if hasUnsavedChanges { saveScript() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Build UI

    private func buildUI() {
        codeEditor.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(topBar)
        topBar.addSubview(backButton)
        topBar.addSubview(nameLabel)
        topBar.addSubview(unsavedDot)
        topBar.addSubview(moreButton)
        view.addSubview(codeEditor)
        view.addSubview(bottomBar)
        bottomBar.addSubview(charCountLabel)
        bottomBar.addSubview(saveButton)
        bottomBar.addSubview(runButton)

        let bottomConstraint = bottomBar.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor
        )
        bottomBarBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
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
            codeEditor.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            codeEditor.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            codeEditor.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -4),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
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

        codeEditor.onTextChange = { [weak self] text in
            self?.hasUnsavedChanges = true
            self?.unsavedDot.isHidden = false
            self?.updateCharCount(text)
        }
    }

    // MARK: - Load / Save

    private func loadScript() {
        nameLabel.text = script.name
        codeEditor.text = script.source
        updateCharCount(script.source)
    }

    @objc private func saveTapped() {
        saveScript()
        showSavedFeedback()
    }

    private func saveScript() {
        script.source = codeEditor.text
        script.updatedAt = Date()
        storage.save(script)
        hasUnsavedChanges = false
        unsavedDot.isHidden = true
    }

    private func showSavedFeedback() {
        let lbl = UILabel()
        lbl.text = "Saved ✓"
        lbl.font = AppFont.medium(12)
        lbl.textColor = UIColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)
        lbl.sizeToFit()
        lbl.center = CGPoint(x: view.center.x, y: view.safeAreaInsets.top + 70)
        view.addSubview(lbl)

        UIView.animate(withDuration: 0.8, delay: 0.5, options: []) {
            lbl.alpha = 0
            lbl.center.y -= 20
        } completion: { _ in
            lbl.removeFromSuperview()
        }
    }

    private func updateCharCount(_ text: String) {
        let lines = text.components(separatedBy: "\n").count
        charCountLabel.text = "\(text.count) chars · \(lines) lines"
    }

    // MARK: - Run

    @objc private func runTapped() {
        if hasUnsavedChanges { saveScript() }

        let console = ScriptConsoleViewController(script: script)
        navigationController?.pushViewController(console, animated: true)
    }

    // MARK: - More Menu

    @objc private func moreTapped() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.overrideUserInterfaceStyle = .dark

        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            self?.showRename()
        })

        alert.addAction(UIAlertAction(title: "Export as .js", style: .default) { [weak self] _ in
            self?.exportScript()
        })

        alert.addAction(UIAlertAction(title: "Duplicate", style: .default) { [weak self] _ in
            guard let self else { return }
            let copy = self.storage.duplicate(self.script)
            self.script = copy
            self.nameLabel.text = copy.name
        })

        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.storage.delete(self.script)
            self.navigationController?.popViewController(animated: true)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = moreButton
            pop.sourceRect = moreButton.bounds
        }
        present(alert, animated: true)
    }

    private func showRename() {
        let alert = UIAlertController(title: "Rename", message: nil, preferredStyle: .alert)
        alert.overrideUserInterfaceStyle = .dark
        alert.addTextField { [weak self] field in
            field.text = self?.script.name
            field.font = AppFont.regular(14)
        }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self,
                  let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { return }
            self.script.name = name
            self.nameLabel.text = name
            self.saveScript()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func exportScript() {
        let url = storage.exportURL(for: script)
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.overrideUserInterfaceStyle = .dark
        if let pop = activity.popoverPresentationController {
            pop.sourceView = moreButton
            pop.sourceRect = moreButton.bounds
        }
        present(activity, animated: true)
    }

    // MARK: - Back

    @objc private func backTapped() {
        if hasUnsavedChanges { saveScript() }
        navigationController?.popViewController(animated: true)
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
        let inset = frame.height - view.safeAreaInsets.bottom
        bottomBarBottomConstraint?.constant = -inset
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    @objc private func keyboardWillHide(_ notif: Notification) {
        guard let duration = notif.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        bottomBarBottomConstraint?.constant = 0
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }
}
