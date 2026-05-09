import Foundation
import Security

enum AppStoreCredentialManager {

    private static let service = "io.hakaisecurity.beerus.appstore"
    private static let accountKey = "account"

    static func save(_ account: AppStoreAccount) throws {
        let data = try JSONEncoder().encode(account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppStoreError.keychainSaveFailed(status)
        }
    }

    static func load() -> AppStoreAccount? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(AppStoreAccount.self, from: data)
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)
    }

    static var hasStoredAccount: Bool {
        load() != nil
    }
}

enum AppStoreError: LocalizedError {
    case keychainSaveFailed(OSStatus)
    case bagFailed(String)
    case loginFailed(String)
    case authCodeRequired
    case accountDisabled
    case searchFailed(String)
    case lookupFailed(String)
    case purchaseFailed(String)
    case paidAppNotSupported
    case downloadFailed(String)
    case tokenExpired
    case licenseRequired
    case versionsFailed(String)
    case metadataFailed(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .keychainSaveFailed(let s): return "Keychain save failed: \(s)"
        case .bagFailed(let m): return "Bag request failed: \(m)"
        case .loginFailed(let m): return "Login failed: \(m)"
        case .authCodeRequired: return "2FA code required"
        case .accountDisabled: return "Account is disabled"
        case .searchFailed(let m): return "Search failed: \(m)"
        case .lookupFailed(let m): return "Lookup failed: \(m)"
        case .purchaseFailed(let m): return "Purchase failed: \(m)"
        case .paidAppNotSupported: return "Paid apps are not supported"
        case .downloadFailed(let m): return "Download failed: \(m)"
        case .tokenExpired: return "Password token expired"
        case .licenseRequired: return "License required"
        case .versionsFailed(let m): return "List versions failed: \(m)"
        case .metadataFailed(let m): return "Version metadata failed: \(m)"
        case .installFailed(let m): return "Install failed: \(m)"
        }
    }
}
