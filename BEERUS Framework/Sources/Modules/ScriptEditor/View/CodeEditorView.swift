import UIKit

/// A code editor view with line numbers, JS syntax highlighting, accessory bar, and Frida autocomplete.
final class CodeEditorView: UIView, UITextViewDelegate, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Public

    var text: String {
        get { textView.text }
        set {
            textView.text = newValue
            applySyntaxHighlighting()
            updateLineNumbers()
        }
    }

    var onTextChange: ((String) -> Void)?

    // MARK: - UI

    private let lineNumberView: UITextView = {
        let tv = UITextView()
        tv.font = AppFont.regular(12)
        tv.textColor = UIColor(white: 0.35, alpha: 1)
        tv.backgroundColor = UIColor(white: 0.08, alpha: 1)
        tv.isEditable = false
        tv.isSelectable = false
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 4, bottom: 10, right: 2)
        tv.textContainer.lineFragmentPadding = 0
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    let textView: UITextView = {
        let tv = UITextView()
        tv.font = AppFont.regular(12)
        tv.textColor = .white
        tv.backgroundColor = .clear
        tv.autocapitalizationType = .none
        tv.autocorrectionType = .no
        tv.spellCheckingType = .no
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.smartInsertDeleteType = .no
        tv.keyboardAppearance = .dark
        tv.tintColor = UIColor(named: "RED")
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        tv.isScrollEnabled = true
        tv.showsVerticalScrollIndicator = true
        tv.indicatorStyle = .white
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()

    private let separator: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.2, alpha: 1)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Autocomplete UI

    private let autocompleteTable: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.backgroundColor = UIColor(white: 0.12, alpha: 1)
        tv.separatorColor = UIColor(white: 0.2, alpha: 1)
        tv.layer.cornerRadius = 8
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor(white: 0.25, alpha: 1).cgColor
        tv.clipsToBounds = true
        tv.isHidden = true
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.showsVerticalScrollIndicator = false
        return tv
    }()

    private var autocompleteSuggestions: [AutocompleteItem] = []
    private var autocompleteTopConstraint: NSLayoutConstraint?
    private var autocompleteLeadingConstraint: NSLayoutConstraint?

    // MARK: - Syntax colors

    private let builtinColor = UIColor(red: 0.30, green: 0.85, blue: 0.65, alpha: 1)
    private let defaultColor = UIColor.white

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(white: 0.06, alpha: 1)
        layer.cornerRadius = 12
        clipsToBounds = true

        addSubview(lineNumberView)
        addSubview(separator)
        addSubview(textView)
        addSubview(autocompleteTable)

        textView.delegate = self
        lineNumberView.isUserInteractionEnabled = false

        autocompleteTable.dataSource = self
        autocompleteTable.delegate = self
        autocompleteTable.register(UITableViewCell.self, forCellReuseIdentifier: "ac")
        autocompleteTable.rowHeight = 32

        let topC = autocompleteTable.topAnchor.constraint(equalTo: topAnchor, constant: 60)
        let leadC = autocompleteTable.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 60)
        autocompleteTopConstraint = topC
        autocompleteLeadingConstraint = leadC

        NSLayoutConstraint.activate([
            lineNumberView.topAnchor.constraint(equalTo: topAnchor),
            lineNumberView.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineNumberView.bottomAnchor.constraint(equalTo: bottomAnchor),
            lineNumberView.widthAnchor.constraint(equalToConstant: 40),

            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: lineNumberView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            topC,
            leadC,
            autocompleteTable.widthAnchor.constraint(equalToConstant: 220),
            autocompleteTable.heightAnchor.constraint(lessThanOrEqualToConstant: 160),
        ])

        buildAccessoryBar()
        updateLineNumbers()
    }

    // MARK: - Accessory bar

    private func buildAccessoryBar() {
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 40))
        bar.backgroundColor = UIColor(white: 0.1, alpha: 1)

        let keys = ["Tab", "{", "}", "(", ")", "[", "]", ";", "\"", ".", "//", "var"]
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        for key in keys {
            let btn = UIButton(type: .system)
            btn.setTitle(key, for: .normal)
            btn.titleLabel?.font = AppFont.medium(12)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = UIColor(white: 0.18, alpha: 1)
            btn.layer.cornerRadius = 5
            btn.addTarget(self, action: #selector(accessoryKeyTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(btn)
        }

        let dismiss = UIButton(type: .system)
        dismiss.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        dismiss.tintColor = UIColor(white: 0.5, alpha: 1)
        dismiss.addTarget(self, action: #selector(dismissKeyboard), for: .touchUpInside)
        dismiss.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(stack)
        bar.addSubview(dismiss)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: dismiss.leadingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: bar.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -4),

            dismiss.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            dismiss.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            dismiss.widthAnchor.constraint(equalToConstant: 32),
        ])

        textView.inputAccessoryView = bar
    }

    @objc private func accessoryKeyTapped(_ sender: UIButton) {
        guard let key = sender.title(for: .normal) else { return }
        let insertion: String
        switch key {
        case "Tab":  insertion = "    "
        case "//":   insertion = "// "
        default:     insertion = key
        }
        textView.insertText(insertion)
    }

    @objc private func dismissKeyboard() {
        textView.resignFirstResponder()
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        applySyntaxHighlighting()
        updateLineNumbers()
        updateAutocomplete()
        onTextChange?(textView.text)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        updateAutocomplete()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === textView {
            lineNumberView.contentOffset = CGPoint(x: 0, y: scrollView.contentOffset.y)
            if !autocompleteTable.isHidden {
                hideAutocomplete()
            }
        }
    }

    // MARK: - Autocomplete Logic

    /// Extract the word fragment at the cursor position.
    private func currentWordFragment() -> (word: String, range: NSRange)? {
        guard let selectedRange = textView.selectedTextRange,
              selectedRange.isEmpty else { return nil }

        let cursorOffset = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)
        let text = textView.text as NSString
        guard cursorOffset > 0 && cursorOffset <= text.length else { return nil }

        // Walk backwards to find the start of the word (including '.')
        var start = cursorOffset - 1
        while start >= 0 {
            let ch = text.character(at: start)
            guard let scalar = Unicode.Scalar(ch) else { break }
            if CharacterSet.alphanumerics.contains(scalar) || ch == UInt16(UInt8(ascii: "_")) || ch == UInt16(UInt8(ascii: "$")) || ch == UInt16(UInt8(ascii: ".")) {
                start -= 1
            } else {
                break
            }
        }
        start += 1

        let length = cursorOffset - start
        guard length >= 2 else { return nil } // need at least 2 chars

        let fragment = text.substring(with: NSRange(location: start, length: length))
        return (fragment, NSRange(location: start, length: length))
    }

    private func updateAutocomplete() {
        guard let (fragment, _) = currentWordFragment() else {
            hideAutocomplete()
            return
        }

        let query = fragment.lowercased()

        // Match against the completion dictionary
        var matches: [AutocompleteItem] = []

        // Check for dot-completion first (e.g. "Interceptor." or "ObjC.")
        if let dotIndex = fragment.lastIndex(of: ".") {
            let obj = String(fragment[fragment.startIndex..<dotIndex])
            let partial = String(fragment[fragment.index(after: dotIndex)...]).lowercased()

            if let methods = Self.dotCompletions[obj] {
                matches = methods.filter {
                    partial.isEmpty || $0.text.lowercased().hasPrefix(partial)
                }
            }
        }

        // Global completions
        if matches.isEmpty {
            matches = Self.globalCompletions.filter {
                $0.text.lowercased().hasPrefix(query) && $0.text.lowercased() != query
            }
        }

        if matches.isEmpty {
            hideAutocomplete()
            return
        }

        autocompleteSuggestions = Array(matches.prefix(5))
        autocompleteTable.reloadData()
        positionAutocomplete()
        autocompleteTable.isHidden = false
    }

    private func positionAutocomplete() {
        guard let selectedRange = textView.selectedTextRange else { return }
        let caretRect = textView.caretRect(for: selectedRange.start)
        // Convert from textView coordinates to self coordinates
        let pos = textView.convert(caretRect, to: self)

        autocompleteTopConstraint?.constant = pos.maxY + 2
        autocompleteLeadingConstraint?.constant = max(pos.minX, 48)

        // Make sure it doesn't go off screen right
        let maxLead = bounds.width - 228
        if (autocompleteLeadingConstraint?.constant ?? 0) > maxLead {
            autocompleteLeadingConstraint?.constant = maxLead
        }

        layoutIfNeeded()
    }

    private func hideAutocomplete() {
        autocompleteTable.isHidden = true
        autocompleteSuggestions = []
    }

    func insertCompletion(_ item: AutocompleteItem) {
        guard let (fragment, range) = currentWordFragment() else { return }

        let replacement: String
        if let dotIndex = fragment.lastIndex(of: ".") {
            // Only replace the part after the dot
            let prefix = String(fragment[fragment.startIndex...dotIndex])
            replacement = prefix + item.text
        } else {
            replacement = item.text
        }

        // Replace using UITextView text range
        guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
              let end = textView.position(from: start, offset: range.length),
              let textRange = textView.textRange(from: start, to: end) else { return }

        textView.replace(textRange, withText: replacement)
        hideAutocomplete()
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        autocompleteSuggestions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ac", for: indexPath)
        let item = autocompleteSuggestions[indexPath.row]

        cell.backgroundColor = UIColor(white: 0.12, alpha: 1)
        cell.selectionStyle = .none

        var config = cell.defaultContentConfiguration()
        config.text = item.text
        config.textProperties.font = AppFont.regular(12)
        config.textProperties.color = builtinColor

        config.secondaryText = item.hint
        config.secondaryTextProperties.font = AppFont.regular(10)
        config.secondaryTextProperties.color = UIColor(white: 0.4, alpha: 1)

        cell.contentConfiguration = config
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        insertCompletion(autocompleteSuggestions[indexPath.row])
    }

    // MARK: - Syntax Highlighting

    /// Flag to avoid re-entrant highlighting triggered by textStorage edits.
    private var isHighlighting = false

    // Pre-compiled patterns — built once, reused every keystroke.
    private static let syntaxRules: [(NSRegularExpression, UIColor)] = {
        func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }

        let kw = ["var","let","const","function","return","if","else","for",
                  "while","do","switch","case","break","continue","new","this",
                  "try","catch","finally","throw","typeof","instanceof","in",
                  "of","class","extends","import","export","default","null",
                  "undefined","true","false","void","async","await","yield"]
        let bi = ["Interceptor","ObjC","Java","Process","Module","Memory",
                  "NativeFunction","NativeCallback","NativePointer","ptr",
                  "console","send","recv","setTimeout","setInterval",
                  "hexdump","Stalker","ApiResolver","DebugSymbol",
                  "Instruction","Thread","Socket","File","Kernel"]

        // Order matters — later rules override earlier ones.
        let commentC  = UIColor(red: 0.40, green: 0.50, blue: 0.40, alpha: 1)
        let stringC   = UIColor(red: 0.90, green: 0.56, blue: 0.35, alpha: 1)
        let numberC   = UIColor(red: 0.82, green: 0.77, blue: 0.50, alpha: 1)
        let keywordC  = UIColor(red: 0.78, green: 0.40, blue: 0.93, alpha: 1)
        let builtinC  = UIColor(red: 0.30, green: 0.85, blue: 0.65, alpha: 1)
        let funcC     = UIColor(red: 0.35, green: 0.75, blue: 0.95, alpha: 1)

        return [
            (rx(#"//[^\n]*"#),               commentC),
            (rx(#"/\*[\s\S]*?\*/"#),          commentC),
            (rx(#""(?:[^"\\]|\\.)*""#),       stringC),
            (rx(#"'(?:[^'\\]|\\.)*'"#),       stringC),
            (rx(#"`(?:[^`\\]|\\.)*`"#),       stringC),
            (rx(#"\b\d+(\.\d+)?\b"#),         numberC),
            (rx("\\b(" + kw.joined(separator: "|") + ")\\b"), keywordC),
            (rx("\\b(" + bi.joined(separator: "|") + ")\\b"), builtinC),
            (rx(#"\b([a-zA-Z_$][\w$]*)\s*\("#), funcC),
        ]
    }()

    private func applySyntaxHighlighting() {
        guard !isHighlighting else { return }
        isHighlighting = true
        defer { isHighlighting = false }

        let text = textView.text ?? ""
        guard !text.isEmpty else { return }

        let full = NSRange(location: 0, length: (text as NSString).length)
        let storage = textView.textStorage
        let saved = (sel: textView.selectedRange, off: textView.contentOffset)

        storage.beginEditing()
        storage.setAttributes([.font: AppFont.regular(12), .foregroundColor: defaultColor], range: full)

        for (regex, color) in Self.syntaxRules {
            regex.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let r = match?.range else { return }
                storage.addAttribute(.foregroundColor, value: color, range: r)
            }
        }

        storage.endEditing()
        textView.selectedRange = saved.sel
        textView.setContentOffset(saved.off, animated: false)
    }

    // MARK: - Line Numbers

    private func updateLineNumbers() {
        let text = textView.text ?? ""
        let lines = text.components(separatedBy: "\n")
        let numbers = (1...max(lines.count, 1)).map { String($0) }.joined(separator: "\n")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: AppFont.regular(12),
            .foregroundColor: UIColor(white: 0.35, alpha: 1),
        ]
        lineNumberView.attributedText = NSAttributedString(string: numbers, attributes: attrs)
    }
}

// MARK: - Autocomplete Data

struct AutocompleteItem {
    let text: String
    let hint: String
}

extension CodeEditorView {

    static let globalCompletions: [AutocompleteItem] = [
        // Frida globals
        AutocompleteItem(text: "Interceptor", hint: "Hook functions"),
        AutocompleteItem(text: "ObjC", hint: "Objective-C runtime"),
        AutocompleteItem(text: "Java", hint: "Java/ART runtime"),
        AutocompleteItem(text: "Process", hint: "Current process"),
        AutocompleteItem(text: "Module", hint: "Loaded modules"),
        AutocompleteItem(text: "Memory", hint: "Memory ops"),
        AutocompleteItem(text: "NativeFunction", hint: "Call native func"),
        AutocompleteItem(text: "NativeCallback", hint: "Native callback"),
        AutocompleteItem(text: "NativePointer", hint: "Pointer wrapper"),
        AutocompleteItem(text: "Stalker", hint: "Code tracer"),
        AutocompleteItem(text: "ApiResolver", hint: "Find APIs"),
        AutocompleteItem(text: "DebugSymbol", hint: "Debug symbols"),
        AutocompleteItem(text: "Thread", hint: "Thread utils"),
        AutocompleteItem(text: "Kernel", hint: "Kernel access"),
        AutocompleteItem(text: "Socket", hint: "Socket listen/connect"),
        AutocompleteItem(text: "File", hint: "File read/write"),

        // Frida functions
        AutocompleteItem(text: "send(", hint: "Send message to host"),
        AutocompleteItem(text: "recv(", hint: "Receive message"),
        AutocompleteItem(text: "console.log(", hint: "Log output"),
        AutocompleteItem(text: "console.warn(", hint: "Warning output"),
        AutocompleteItem(text: "console.error(", hint: "Error output"),
        AutocompleteItem(text: "hexdump(", hint: "Hex dump memory"),
        AutocompleteItem(text: "ptr(", hint: "Create NativePointer"),
        AutocompleteItem(text: "setTimeout(", hint: "Delayed exec"),
        AutocompleteItem(text: "setInterval(", hint: "Repeated exec"),
        AutocompleteItem(text: "clearTimeout(", hint: "Cancel timeout"),
        AutocompleteItem(text: "clearInterval(", hint: "Cancel interval"),
        AutocompleteItem(text: "rpc.exports", hint: "RPC exports"),

        // JS keywords
        AutocompleteItem(text: "function", hint: "Function declaration"),
        AutocompleteItem(text: "const ", hint: "Constant"),
        AutocompleteItem(text: "return ", hint: "Return value"),
        AutocompleteItem(text: "typeof ", hint: "Type check"),
        AutocompleteItem(text: "instanceof ", hint: "Instance check"),
        AutocompleteItem(text: "undefined", hint: "Undefined value"),
        AutocompleteItem(text: "try {", hint: "Try block"),
        AutocompleteItem(text: "catch (e) {", hint: "Catch block"),
    ]

    static let dotCompletions: [String: [AutocompleteItem]] = [
        "Interceptor": [
            AutocompleteItem(text: "attach(", hint: "Hook native function"),
            AutocompleteItem(text: "detachAll()", hint: "Remove all hooks"),
            AutocompleteItem(text: "replace(", hint: "Replace implementation"),
            AutocompleteItem(text: "revert(", hint: "Revert replacement"),
        ],
        "ObjC": [
            AutocompleteItem(text: "classes", hint: "All ObjC classes"),
            AutocompleteItem(text: "protocols", hint: "All protocols"),
            AutocompleteItem(text: "Object(", hint: "Wrap ObjC handle"),
            AutocompleteItem(text: "implement(", hint: "Implement protocol"),
            AutocompleteItem(text: "registerClass(", hint: "Register new class"),
            AutocompleteItem(text: "enumerateLoadedClasses(", hint: "Iterate classes"),
            AutocompleteItem(text: "enumerateLoadedClassesSync()", hint: "List classes sync"),
            AutocompleteItem(text: "choose(", hint: "Find instances"),
            AutocompleteItem(text: "available", hint: "ObjC runtime available"),
            AutocompleteItem(text: "schedule(", hint: "Schedule on queue"),
            AutocompleteItem(text: "selector(", hint: "Get SEL pointer"),
        ],
        "Process": [
            AutocompleteItem(text: "id", hint: "Process ID"),
            AutocompleteItem(text: "arch", hint: "CPU architecture"),
            AutocompleteItem(text: "platform", hint: "OS platform"),
            AutocompleteItem(text: "pageSize", hint: "Memory page size"),
            AutocompleteItem(text: "pointerSize", hint: "Pointer size"),
            AutocompleteItem(text: "codeSigningPolicy", hint: "CS policy"),
            AutocompleteItem(text: "isDebuggerAttached()", hint: "Debugger check"),
            AutocompleteItem(text: "getCurrentThreadId()", hint: "Current thread ID"),
            AutocompleteItem(text: "enumerateThreads()", hint: "List threads"),
            AutocompleteItem(text: "findModuleByName(", hint: "Find module"),
            AutocompleteItem(text: "enumerateModules()", hint: "List modules"),
            AutocompleteItem(text: "findRangeByAddress(", hint: "Memory range at addr"),
            AutocompleteItem(text: "enumerateRanges(", hint: "List memory ranges"),
            AutocompleteItem(text: "enumerateMallocRanges(", hint: "Heap ranges"),
            AutocompleteItem(text: "setExceptionHandler(", hint: "Handle exceptions"),
        ],
        "Module": [
            AutocompleteItem(text: "findBaseAddress(", hint: "Base addr of module"),
            AutocompleteItem(text: "findExportByName(", hint: "Find export"),
            AutocompleteItem(text: "enumerateExports(", hint: "List exports"),
            AutocompleteItem(text: "enumerateImports(", hint: "List imports"),
            AutocompleteItem(text: "enumerateSymbols(", hint: "List symbols"),
            AutocompleteItem(text: "enumerateRanges(", hint: "Module ranges"),
            AutocompleteItem(text: "getBaseAddress(", hint: "Base address"),
            AutocompleteItem(text: "load(", hint: "Load module"),
        ],
        "Memory": [
            AutocompleteItem(text: "scan(", hint: "Scan memory pattern"),
            AutocompleteItem(text: "scanSync(", hint: "Scan sync"),
            AutocompleteItem(text: "alloc(", hint: "Allocate memory"),
            AutocompleteItem(text: "copy(", hint: "Copy memory"),
            AutocompleteItem(text: "protect(", hint: "Change protection"),
            AutocompleteItem(text: "patchCode(", hint: "Patch code"),
            AutocompleteItem(text: "readByteArray(", hint: "Read bytes"),
            AutocompleteItem(text: "writeByteArray(", hint: "Write bytes"),
            AutocompleteItem(text: "allocUtf8String(", hint: "Alloc UTF8 string"),
            AutocompleteItem(text: "readUtf8String(", hint: "Read UTF8"),
        ],
        "Java": [
            AutocompleteItem(text: "available", hint: "ART available"),
            AutocompleteItem(text: "perform(", hint: "Run on Java thread"),
            AutocompleteItem(text: "use(", hint: "Get Java class"),
            AutocompleteItem(text: "choose(", hint: "Find instances"),
            AutocompleteItem(text: "enumerateLoadedClasses(", hint: "List classes"),
            AutocompleteItem(text: "enumerateClassLoaders(", hint: "List class loaders"),
            AutocompleteItem(text: "cast(", hint: "Cast to type"),
            AutocompleteItem(text: "array(", hint: "Create array"),
            AutocompleteItem(text: "registerClass(", hint: "Register class"),
            AutocompleteItem(text: "deoptimizeEverything()", hint: "Deopt all"),
        ],
        "Stalker": [
            AutocompleteItem(text: "follow(", hint: "Start tracing thread"),
            AutocompleteItem(text: "unfollow(", hint: "Stop tracing"),
            AutocompleteItem(text: "exclude(", hint: "Exclude range"),
            AutocompleteItem(text: "parse(", hint: "Parse events"),
            AutocompleteItem(text: "flush()", hint: "Flush events"),
            AutocompleteItem(text: "garbageCollect()", hint: "GC stalker"),
            AutocompleteItem(text: "addCallProbe(", hint: "Add call probe"),
            AutocompleteItem(text: "removeCallProbe(", hint: "Remove probe"),
            AutocompleteItem(text: "trustThreshold", hint: "Trust threshold"),
            AutocompleteItem(text: "queueCapacity", hint: "Queue capacity"),
        ],
        "console": [
            AutocompleteItem(text: "log(", hint: "Log message"),
            AutocompleteItem(text: "warn(", hint: "Warning message"),
            AutocompleteItem(text: "error(", hint: "Error message"),
        ],
        "rpc": [
            AutocompleteItem(text: "exports", hint: "Export RPC methods"),
        ],
    ]
}
