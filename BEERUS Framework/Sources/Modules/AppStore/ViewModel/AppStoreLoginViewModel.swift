import Foundation

final class AppStoreLoginViewModel {

    enum StatusStyle { case info, error, muted }

    weak var coordinator: AppStoreCoordinator?

    private static let emailHistoryKey = "AppStoreEmailHistory"

    private var mfaTimer: Timer?
    private var mfaTimeoutDate: Date?
    private var pendingEmail: String?
    private var pendingPassword: String?

    private var emailSuggestions: [String] = []
    private(set) var filteredSuggestions: [String] = []

    var onLoading: (Bool) -> Void = { _ in }
    var onStatus: (String, StatusStyle) -> Void = { _, _ in }
    var onShowMFA: (String) -> Void = { _ in }
    var onHideMFA: () -> Void = {}
    var onMFATimer: (String) -> Void = { _ in }
    var onSuggestionsChanged: () -> Void = {}

    var mfaCommand: String { "echo \"CODE\" > \(MFAFileWatcher.filePath)" }

    func viewDidLoad() {
        emailSuggestions = UserDefaults.standard.stringArray(forKey: Self.emailHistoryKey) ?? []
    }

    func numberOfSuggestions() -> Int { filteredSuggestions.count }
    func suggestion(at index: Int) -> String { filteredSuggestions[index] }

    func emailChanged(_ text: String?) {
        guard let text, !text.isEmpty else {
            filteredSuggestions = []
            onSuggestionsChanged()
            return
        }
        filteredSuggestions = emailSuggestions.filter {
            $0.lowercased().contains(text.lowercased()) && $0 != text
        }
        onSuggestionsChanged()
    }

    func signIn(email: String?, password: String?) {
        guard let email, !email.isEmpty, let password, !password.isEmpty else {
            onStatus("Enter email and password", .error)
            return
        }
        attemptLogin(email: email, password: password, authCode: "")
    }

    func cancelMFA() {
        stopMFAPolling()
        onHideMFA()
        pendingEmail = nil
        pendingPassword = nil
        onStatus("Login cancelado", .muted)
    }

    deinit {
        stopMFAPolling()
    }

    private func attemptLogin(email: String, password: String, authCode: String) {
        onLoading(true)
        onStatus("Connecting to App Store...", .info)

        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await AppStoreService.shared.login(email: email, password: password, authCode: authCode)
                await MainActor.run {
                    self.onLoading(false)
                    self.stopMFAPolling()
                    self.saveEmailToHistory(email)
                    self.coordinator?.loginSucceeded()
                }
            } catch AppStoreError.authCodeRequired {
                await MainActor.run {
                    self.onLoading(false)
                    self.pendingEmail = email
                    self.pendingPassword = password
                    self.onShowMFA(self.mfaCommand)
                    self.startMFAPolling()
                }
            } catch {
                await MainActor.run {
                    self.onLoading(false)
                    self.stopMFAPolling()
                    self.onHideMFA()
                    self.onStatus(error.localizedDescription, .error)
                }
            }
        }
    }

    private func startMFAPolling() {
        MFAFileWatcher.clear()
        mfaTimeoutDate = Date().addingTimeInterval(300)
        mfaTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkMFAFile()
        }
    }

    private func stopMFAPolling() {
        mfaTimer?.invalidate()
        mfaTimer = nil
        mfaTimeoutDate = nil
        MFAFileWatcher.clear()
    }

    private func checkMFAFile() {
        if let timeout = mfaTimeoutDate {
            let remaining = timeout.timeIntervalSinceNow
            if remaining <= 0 {
                stopMFAPolling()
                onHideMFA()
                onStatus("Timeout - código MFA expirou", .error)
                return
            }
            let mins = Int(remaining) / 60
            let secs = Int(remaining) % 60
            onMFATimer(String(format: "Expira em %d:%02d", mins, secs))
        }

        guard let code = MFAFileWatcher.read() else { return }

        MFAFileWatcher.clear()
        stopMFAPolling()
        onHideMFA()

        guard let email = pendingEmail, let password = pendingPassword else { return }
        attemptLogin(email: email, password: password, authCode: code)
    }

    private func saveEmailToHistory(_ email: String) {
        var history = emailSuggestions
        history.removeAll { $0.lowercased() == email.lowercased() }
        history.insert(email, at: 0)
        if history.count > 5 { history = Array(history.prefix(5)) }
        emailSuggestions = history
        UserDefaults.standard.set(history, forKey: Self.emailHistoryKey)
    }
}
