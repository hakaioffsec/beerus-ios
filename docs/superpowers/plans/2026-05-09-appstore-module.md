# App Store Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native App Store module to BEERUS that lets users search, purchase, browse versions, and download IPAs from the App Store — all with a visual UI on-device.

**Architecture:** Swift port of ipatool's API logic. `AppStoreService` handles all HTTP calls to Apple's private APIs using URLSession + PropertyListSerialization. `AppStoreCredentialManager` stores credentials in iOS Keychain. `IPAProcessor` patches downloaded ZIPs. UI follows existing ViewCode + BaseViewController patterns. Daemon gets one new command (`INSTALL_IPA`) for root-privileged installation.

**Tech Stack:** Swift, UIKit, URLSession, PropertyListSerialization, Security.framework (Keychain), existing ZipArchive.swift

**Reference codebase:** `/Users/texugo/Documents/ipatool` — the Go implementation being ported. Read the corresponding Go files when implementing each API method.

**Important:** The BEERUS repo has unresolved merge conflicts in several files (marked with `<<<<<<<`). When modifying existing files (`TabOption.swift`, `ContainerViewController.swift`, `RootExec.swift`, `BeerusDaemon.c`), resolve the conflicts by keeping the `ae68300` (script editor) branch content, then add the App Store changes on top.

---

### Task 1: Models

**Files:**
- Create: `BEERUS Framework/Sources/Modules/AppStore/Model/AppStoreAccount.swift`
- Create: `BEERUS Framework/Sources/Modules/AppStore/Model/AppStoreApp.swift`
- Create: `BEERUS Framework/Sources/Modules/AppStore/Model/DownloadResult.swift`
- Create: `BEERUS Framework/Sources/Modules/AppStore/Model/VersionMetadata.swift`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p "BEERUS Framework/Sources/Modules/AppStore/Model"
mkdir -p "BEERUS Framework/Sources/Modules/AppStore/Service"
mkdir -p "BEERUS Framework/Sources/Modules/AppStore/View"
mkdir -p "BEERUS Framework/Sources/Modules/AppStore/ViewController"
```

- [ ] **Step 2: Create AppStoreAccount.swift**

```swift
import Foundation

struct AppStoreAccount: Codable {
    let name: String
    let email: String
    let passwordToken: String
    let directoryServicesID: String
    let storeFront: String
    let password: String
    let pod: String
}
```

- [ ] **Step 3: Create AppStoreApp.swift**

```swift
import Foundation

struct AppStoreApp: Codable {
    let id: Int64
    let bundleID: String
    let name: String
    let version: String
    let price: Double

    enum CodingKeys: String, CodingKey {
        case id = "trackId"
        case bundleID = "bundleId"
        case name = "trackName"
        case version
        case price
    }
}
```

- [ ] **Step 4: Create DownloadResult.swift**

```swift
import Foundation

struct DownloadResult {
    let destinationPath: String
    let sinfs: [SinfData]
}

struct SinfData {
    let id: Int64
    let data: Data
}

struct DownloadItemResult {
    let url: String
    let sinfs: [SinfData]
    let metadata: [String: Any]
}
```

- [ ] **Step 5: Create VersionMetadata.swift**

```swift
import Foundation

struct VersionMetadata {
    let displayVersion: String
    let releaseDate: Date
}

struct VersionListResult {
    let identifiers: [String]
    let latestID: String
}
```

- [ ] **Step 6: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/Model/"
git commit -m "feat(appstore): add data models for App Store module"
```

---

### Task 2: AppStoreCredentialManager (Keychain)

**Files:**
- Create: `BEERUS Framework/Sources/Modules/AppStore/Service/AppStoreCredentialManager.swift`

- [ ] **Step 1: Create AppStoreCredentialManager.swift**

```swift
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
```

- [ ] **Step 2: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/Service/AppStoreCredentialManager.swift"
git commit -m "feat(appstore): add keychain credential manager and error types"
```

---

### Task 3: PlistPayload helper

**Files:**
- Create: `BEERUS Framework/Sources/Modules/AppStore/Service/PlistPayload.swift`

- [ ] **Step 1: Create PlistPayload.swift**

This builds XML plist request bodies and parses plist responses — the core transport format for Apple's private APIs.

```swift
import Foundation

enum PlistPayload {

    static func encode(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: dict,
            format: .xml,
            options: 0
        )
    }

    static func decode(_ data: Data) throws -> [String: Any] {
        guard let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            throw AppStoreError.downloadFailed("invalid plist response")
        }
        return plist
    }

    static func buildLoginPayload(email: String, password: String, authCode: String,
                                   guid: String, attempt: Int) -> [String: Any] {
        var pwd = password
        if !authCode.isEmpty {
            pwd += authCode.replacingOccurrences(of: " ", with: "")
        }
        return [
            "appleId": email,
            "attempt": "\(attempt)",
            "guid": guid,
            "password": pwd,
            "rmp": "0",
            "why": "signIn"
        ]
    }

    static func buildPurchasePayload(appID: Int64, guid: String,
                                      pricingParameters: String) -> [String: Any] {
        [
            "appExtVrsId": "0",
            "hasAskedToFulfillPreorder": "true",
            "buyWithoutAuthorization": "true",
            "hasDoneAgeCheck": "true",
            "guid": guid,
            "needDiv": "0",
            "origPage": "Software-\(appID)",
            "origPageLocation": "Buy",
            "price": "0",
            "pricingParameters": pricingParameters,
            "productType": "C",
            "salableAdamId": appID
        ]
    }

    static func buildDownloadPayload(appID: Int64, guid: String,
                                      externalVersionID: String? = nil) -> [String: Any] {
        var payload: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "salableAdamId": appID
        ]
        if let vid = externalVersionID, !vid.isEmpty {
            payload["externalVersionId"] = vid
        }
        return payload
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/Service/PlistPayload.swift"
git commit -m "feat(appstore): add plist payload encoder/decoder for Apple API requests"
```

---

### Task 4: AppStoreService — Bag, Login, AccountInfo, Revoke

**Files:**
- Create: `BEERUS Framework/Sources/Modules/AppStore/Service/AppStoreService.swift`

Reference: `ipatool/pkg/appstore/appstore_bag.go`, `appstore_login.go`, `appstore_account_info.go`, `appstore_revoke.go`, `storefront.go`, `constants.go`

- [ ] **Step 1: Create AppStoreService.swift with constants, GUID, storefront map, and bag/login/accountInfo/revoke**

```swift
import Foundation
import UIKit

final class AppStoreService {

    static let shared = AppStoreService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Constants

    private let iTunesDomain = "itunes.apple.com"
    private let initDomain = "init.itunes.apple.com"
    private let buyDomain = "buy.itunes.apple.com"
    private let purchasePath = "/WebObjects/MZFinance.woa/wa/buyProduct"
    private let downloadPath = "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"

    private let failureInvalidCredentials = "-5000"
    private let failureTokenExpired = "2034"
    private let failureSignInRequired = "2042"
    private let failureLicenseNotFound = "9610"
    private let failureTempUnavailable = "2059"
    private let failureLicenseExists = "5002"
    private let failureDeviceVerification = "1008"
    private let customerMessageBadLogin = "MZFinance.BadLogin.Configurator_message"
    private let customerMessageDisabled = "Your account is disabled."
    private let customerMessageSubscription = "Subscription Required"
    private let customerMessagePasswordChanged = "Your password has changed."

    // MARK: - GUID

    private func getGUID() -> String {
        let uuid = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        return uuid.replacingOccurrences(of: "-", with: "").uppercased()
    }

    // MARK: - Storefront → Country Code

    private let storeFronts: [String: String] = [
        "AE": "143481", "AG": "143540", "AI": "143538", "AL": "143575",
        "AM": "143524", "AO": "143564", "AR": "143505", "AT": "143445",
        "AU": "143460", "AZ": "143568", "BB": "143541", "BD": "143490",
        "BE": "143446", "BG": "143526", "BH": "143559", "BM": "143542",
        "BN": "143560", "BO": "143556", "BR": "143503", "BS": "143539",
        "BW": "143525", "BY": "143565", "BZ": "143555", "CA": "143455",
        "CH": "143459", "CI": "143527", "CL": "143483", "CN": "143465",
        "CO": "143501", "CR": "143495", "CY": "143557", "CZ": "143489",
        "DE": "143443", "DK": "143458", "DM": "143545", "DO": "143508",
        "DZ": "143563", "EC": "143509", "EE": "143518", "EG": "143516",
        "ES": "143454", "FI": "143447", "FR": "143442", "GB": "143444",
        "GD": "143546", "GE": "143615", "GH": "143573", "GR": "143448",
        "GT": "143504", "GY": "143553", "HK": "143463", "HN": "143510",
        "HR": "143494", "HU": "143482", "ID": "143476", "IE": "143449",
        "IL": "143491", "IN": "143467", "IS": "143558", "IT": "143450",
        "IQ": "143617", "JM": "143511", "JO": "143528", "JP": "143462",
        "KE": "143529", "KN": "143548", "KR": "143466", "KW": "143493",
        "KY": "143544", "KZ": "143517", "LB": "143497", "LC": "143549",
        "LI": "143522", "LK": "143486", "LT": "143520", "LU": "143451",
        "LV": "143519", "MD": "143523", "MG": "143531", "MK": "143530",
        "ML": "143532", "MN": "143592", "MO": "143515", "MS": "143547",
        "MT": "143521", "MU": "143533", "MV": "143488", "MX": "143468",
        "MY": "143473", "NE": "143534", "NG": "143561", "NI": "143512",
        "NL": "143452", "NO": "143457", "NP": "143484", "NZ": "143461",
        "OM": "143562", "PA": "143485", "PE": "143507", "PH": "143474",
        "PK": "143477", "PL": "143478", "PT": "143453", "PY": "143513",
        "QA": "143498", "RO": "143487", "RS": "143500", "RU": "143469",
        "SA": "143479", "SE": "143456", "SG": "143464", "SI": "143499",
        "SK": "143496", "SN": "143535", "SR": "143554", "SV": "143506",
        "TC": "143552", "TH": "143475", "TN": "143536", "TR": "143480",
        "TT": "143551", "TW": "143470", "TZ": "143572", "UA": "143492",
        "UG": "143537", "US": "143441", "UY": "143514", "UZ": "143566",
        "VC": "143550", "VE": "143502", "VG": "143543", "VN": "143471",
        "YE": "143571", "ZA": "143472"
    ]

    func countryCode(from storeFront: String) -> String? {
        let prefix = storeFront.split(separator: "-").first.map(String.init) ?? storeFront
        for (code, val) in storeFronts {
            if prefix == val { return code }
        }
        return nil
    }

    // MARK: - Pod URL helper

    private func buyURL(pod: String, path: String, guid: String? = nil) -> String {
        let podPrefix = pod.isEmpty ? "" : "p\(pod)-"
        var url = "https://\(podPrefix)\(buyDomain)\(path)"
        if let guid = guid {
            url += "?guid=\(guid)"
        }
        return url
    }

    // MARK: - Bag

    func fetchBag() async throws -> String {
        let guid = getGUID()
        let url = URL(string: "https://\(initDomain)/bag.xml?guid=\(guid)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppStoreError.bagFailed("unexpected status code")
        }

        let plist = try PlistPayload.decode(data)

        guard let urlBag = plist["urlBag"] as? [String: Any],
              let authEndpoint = urlBag["authenticateAccount"] as? String else {
            throw AppStoreError.bagFailed("missing authenticateAccount in bag")
        }

        return authEndpoint
    }

    // MARK: - Login

    func login(email: String, password: String, authCode: String = "") async throws -> AppStoreAccount {
        let guid = getGUID()
        let endpoint = try await fetchBag()

        var redirect: String? = nil
        var lastResponse: (data: Data, http: HTTPURLResponse)?

        for attempt in 1...4 {
            let url: String = redirect ?? endpoint
            redirect = nil

            let payload = PlistPayload.buildLoginPayload(
                email: email, password: password,
                authCode: authCode, guid: guid, attempt: attempt
            )
            let body = try PlistPayload.encode(payload)

            var request = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppStoreError.loginFailed("invalid response")
            }

            lastResponse = (data, http)

            if http.statusCode == 302 {
                guard let location = http.value(forHTTPHeaderField: "location") else {
                    throw AppStoreError.loginFailed("redirect without location")
                }
                redirect = location
                continue
            }

            let plist = try PlistPayload.decode(data)
            let failureType = plist["failureType"] as? String ?? ""
            let customerMessage = plist["customerMessage"] as? String ?? ""

            if attempt == 1 && failureType == failureInvalidCredentials {
                continue
            }

            if failureType.isEmpty && authCode.isEmpty && customerMessage == customerMessageBadLogin {
                throw AppStoreError.authCodeRequired
            }

            if customerMessage == customerMessageDisabled {
                throw AppStoreError.accountDisabled
            }

            if !failureType.isEmpty {
                let msg = customerMessage.isEmpty ? "something went wrong" : customerMessage
                throw AppStoreError.loginFailed(msg)
            }

            guard let passwordToken = plist["passwordToken"] as? String, !passwordToken.isEmpty,
                  let dsid = plist["dsPersonId"] as? String, !dsid.isEmpty else {
                throw AppStoreError.loginFailed("missing token or dsid")
            }

            let accountInfo = plist["accountInfo"] as? [String: Any] ?? [:]
            let address = accountInfo["address"] as? [String: Any] ?? [:]
            let firstName = address["firstName"] as? String ?? ""
            let lastName = address["lastName"] as? String ?? ""
            let accountEmail = (accountInfo["appleId"] as? String) ?? email

            let storeFront = http.value(forHTTPHeaderField: "X-Set-Apple-Store-Front") ?? ""
            let pod = http.value(forHTTPHeaderField: "pod") ?? ""

            let account = AppStoreAccount(
                name: [firstName, lastName].joined(separator: " ").trimmingCharacters(in: .whitespaces),
                email: accountEmail,
                passwordToken: passwordToken,
                directoryServicesID: dsid,
                storeFront: storeFront,
                password: password,
                pod: pod
            )

            try AppStoreCredentialManager.save(account)
            return account
        }

        throw AppStoreError.loginFailed("too many attempts")
    }

    // MARK: - Account Info

    func accountInfo() throws -> AppStoreAccount {
        guard let account = AppStoreCredentialManager.load() else {
            throw AppStoreError.loginFailed("no stored account")
        }
        return account
    }

    // MARK: - Revoke

    func revoke() {
        AppStoreCredentialManager.delete()
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/Service/AppStoreService.swift"
git commit -m "feat(appstore): add AppStoreService with bag, login, account info, revoke"
```

---

### Task 5: AppStoreService — Search, Lookup, Purchase

**Files:**
- Modify: `BEERUS Framework/Sources/Modules/AppStore/Service/AppStoreService.swift`

Reference: `ipatool/pkg/appstore/appstore_search.go`, `appstore_lookup.go`, `appstore_purchase.go`

- [ ] **Step 1: Add search, lookup, and purchase methods**

Append to `AppStoreService.swift`, inside the class, after the `revoke()` method:

```swift
    // MARK: - Search

    func search(term: String, limit: Int = 20) async throws -> [AppStoreApp] {
        let account = try accountInfo()
        guard let country = countryCode(from: account.storeFront) else {
            throw AppStoreError.searchFailed("cannot resolve country code")
        }

        var components = URLComponents(string: "https://\(iTunesDomain)/search")!
        components.queryItems = [
            URLQueryItem(name: "entity", value: "software,iPadSoftware"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "media", value: "software"),
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country)
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppStoreError.searchFailed("request failed")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let results = json["results"] as? [[String: Any]] else {
            return []
        }

        return results.compactMap { dict in
            guard let id = dict["trackId"] as? Int64 ?? (dict["trackId"] as? Int).map(Int64.init),
                  let bundleID = dict["bundleId"] as? String,
                  let name = dict["trackName"] as? String else { return nil }
            return AppStoreApp(
                id: id,
                bundleID: bundleID,
                name: name,
                version: dict["version"] as? String ?? "",
                price: dict["price"] as? Double ?? 0
            )
        }
    }

    // MARK: - Lookup

    func lookup(bundleID: String) async throws -> AppStoreApp {
        let account = try accountInfo()
        guard let country = countryCode(from: account.storeFront) else {
            throw AppStoreError.lookupFailed("cannot resolve country code")
        }

        var components = URLComponents(string: "https://\(iTunesDomain)/lookup")!
        components.queryItems = [
            URLQueryItem(name: "entity", value: "software,iPadSoftware"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "media", value: "software"),
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: country)
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppStoreError.lookupFailed("request failed")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let results = json["results"] as? [[String: Any]], let first = results.first,
              let id = first["trackId"] as? Int64 ?? (first["trackId"] as? Int).map(Int64.init),
              let bid = first["bundleId"] as? String,
              let name = first["trackName"] as? String else {
            throw AppStoreError.lookupFailed("app not found")
        }

        return AppStoreApp(
            id: id, bundleID: bid, name: name,
            version: first["version"] as? String ?? "",
            price: first["price"] as? Double ?? 0
        )
    }

    // MARK: - Purchase

    func purchase(app: AppStoreApp) async throws {
        if app.price > 0 {
            throw AppStoreError.paidAppNotSupported
        }

        let account = try accountInfo()
        let guid = getGUID()

        do {
            try await purchaseWithParams(account: account, app: app, guid: guid, pricing: "STDQ")
        } catch AppStoreError.purchaseFailed(let msg) where msg == "temporarily unavailable" {
            try await purchaseWithParams(account: account, app: app, guid: guid, pricing: "GAME")
        }
    }

    private func purchaseWithParams(account: AppStoreAccount, app: AppStoreApp,
                                     guid: String, pricing: String) async throws {
        let url = buyURL(pod: account.pod, path: purchasePath)
        let payload = PlistPayload.buildPurchasePayload(
            appID: app.id, guid: guid, pricingParameters: pricing
        )
        let body = try PlistPayload.encode(payload)

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
        request.setValue(account.directoryServicesID, forHTTPHeaderField: "iCloud-DSID")
        request.setValue(account.directoryServicesID, forHTTPHeaderField: "X-Dsid")
        request.setValue(account.storeFront, forHTTPHeaderField: "X-Apple-Store-Front")
        request.setValue(account.passwordToken, forHTTPHeaderField: "X-Token")
        request.httpBody = body

        let (data, _) = try await session.data(for: request)
        let plist = try PlistPayload.decode(data)

        let failureType = plist["failureType"] as? String ?? ""
        let customerMessage = plist["customerMessage"] as? String ?? ""

        if failureType == failureTempUnavailable {
            throw AppStoreError.purchaseFailed("temporarily unavailable")
        }
        if customerMessage == customerMessageSubscription {
            throw AppStoreError.purchaseFailed("subscription required")
        }
        if failureType == failureTokenExpired || failureType == failureSignInRequired
            || failureType == failureDeviceVerification
            || customerMessage == customerMessagePasswordChanged {
            throw AppStoreError.tokenExpired
        }
        if failureType == failureLicenseExists {
            return
        }
        if !failureType.isEmpty {
            let msg = customerMessage.isEmpty ? "something went wrong" : customerMessage
            throw AppStoreError.purchaseFailed(msg)
        }

        let docType = plist["jingleDocType"] as? String ?? ""
        let status = plist["status"] as? Int ?? -1
        if docType != "purchaseSuccess" || status != 0 {
            throw AppStoreError.purchaseFailed("unexpected response")
        }
    }
```

- [ ] **Step 2: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/Service/AppStoreService.swift"
git commit -m "feat(appstore): add search, lookup, and purchase to AppStoreService"
```

---

### Task 6: AppStoreService — Download, List Versions, Get Version Metadata

**Files:**
- Modify: `BEERUS Framework/Sources/Modules/AppStore/Service/AppStoreService.swift`

Reference: `ipatool/pkg/appstore/appstore_download.go`, `appstore_list_versions.go`, `appstore_get_version_metadata.go`, `appstore_partial_zip.go`

- [ ] **Step 1: Add download, listVersions, getVersionMetadata methods**

Append to `AppStoreService.swift`, inside the class:

```swift
    // MARK: - Download

    func download(app: AppStoreApp, externalVersionID: String? = nil,
                  progress: ((Int64, Int64) -> Void)? = nil) async throws -> DownloadResult {
        let account = try accountInfo()
        let guid = getGUID()

        let item = try await fetchDownloadItem(
            account: account, appID: app.id, guid: guid,
            externalVersionID: externalVersionID
        )

        let version: String = {
            if let v = item.metadata["bundleShortVersionString"] { return "\(v)" }
            return "unknown"
        }()

        let fileName = "\(app.bundleID)_\(app.id)_\(version).ipa"
        let ipaDir = "/var/mobile/Documents/BEERUS/IPAs"
        try FileManager.default.createDirectory(
            atPath: ipaDir, withIntermediateDirectories: true
        )
        let destination = "\(ipaDir)/\(fileName)"

        let tmpPath = destination + ".tmp"
        try await downloadFile(from: item.url, to: tmpPath, progress: progress)

        try IPAProcessor.applyPatches(
            metadata: item.metadata,
            account: account,
            sinfs: item.sinfs,
            sourcePath: tmpPath,
            destinationPath: destination
        )

        try? FileManager.default.removeItem(atPath: tmpPath)

        return DownloadResult(destinationPath: destination, sinfs: item.sinfs)
    }

    private func fetchDownloadItem(account: AppStoreAccount, appID: Int64,
                                    guid: String, externalVersionID: String?) async throws -> DownloadItemResult {
        let url = buyURL(pod: account.pod, path: downloadPath, guid: guid)
        let payload = PlistPayload.buildDownloadPayload(
            appID: appID, guid: guid, externalVersionID: externalVersionID
        )
        let body = try PlistPayload.encode(payload)

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
        request.setValue(account.directoryServicesID, forHTTPHeaderField: "iCloud-DSID")
        request.setValue(account.directoryServicesID, forHTTPHeaderField: "X-Dsid")
        request.httpBody = body

        let (data, _) = try await session.data(for: request)
        let plist = try PlistPayload.decode(data)

        let failureType = plist["failureType"] as? String ?? ""
        let customerMessage = plist["customerMessage"] as? String ?? ""

        if failureType == failureTokenExpired || failureType == failureSignInRequired
            || failureType == failureDeviceVerification || failureType == failureLicenseExists {
            throw AppStoreError.tokenExpired
        }
        if failureType == failureLicenseNotFound {
            throw AppStoreError.licenseRequired
        }
        if !failureType.isEmpty {
            let msg = customerMessage.isEmpty ? failureType : customerMessage
            throw AppStoreError.downloadFailed(msg)
        }

        guard let items = plist["songList"] as? [[String: Any]], let first = items.first,
              let downloadURL = first["URL"] as? String else {
            throw AppStoreError.downloadFailed("invalid response")
        }

        let sinfs: [SinfData] = (first["sinfs"] as? [[String: Any]] ?? []).compactMap { dict in
            guard let id = dict["id"] as? Int64 ?? (dict["id"] as? Int).map(Int64.init),
                  let data = dict["sinf"] as? Data else { return nil }
            return SinfData(id: id, data: data)
        }

        let metadata = first["metadata"] as? [String: Any] ?? [:]

        return DownloadItemResult(url: downloadURL, sinfs: sinfs, metadata: metadata)
    }

    private func downloadFile(from urlString: String, to path: String,
                               progress: ((Int64, Int64) -> Void)?) async throws {
        let url = URL(string: urlString)!
        let (asyncBytes, response) = try await session.bytes(from: url)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw AppStoreError.downloadFailed("download request failed")
        }

        let totalBytes = http.expectedContentLength
        let fileURL = URL(fileURLWithPath: path)
        FileManager.default.createFile(atPath: path, contents: nil)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { handle.closeFile() }

        var downloaded: Int64 = 0
        let bufferSize = 65536
        var buffer = Data()
        buffer.reserveCapacity(bufferSize)

        for try await byte in asyncBytes {
            buffer.append(byte)
            if buffer.count >= bufferSize {
                handle.write(buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress?(downloaded, totalBytes)
            }
        }

        if !buffer.isEmpty {
            handle.write(buffer)
            downloaded += Int64(buffer.count)
            progress?(downloaded, totalBytes)
        }
    }

    // MARK: - List Versions

    func listVersions(app: AppStoreApp) async throws -> VersionListResult {
        let account = try accountInfo()
        let guid = getGUID()

        let item = try await fetchDownloadItem(
            account: account, appID: app.id, guid: guid, externalVersionID: nil
        )

        guard let rawIDs = item.metadata["softwareVersionExternalIdentifiers"] as? [Any] else {
            throw AppStoreError.versionsFailed("no version identifiers in metadata")
        }

        let identifiers = rawIDs.map { "\($0)" }

        guard let latestID = item.metadata["softwareVersionExternalIdentifier"] else {
            throw AppStoreError.versionsFailed("no latest version in metadata")
        }

        return VersionListResult(identifiers: identifiers, latestID: "\(latestID)")
    }

    // MARK: - Get Version Metadata (partial ZIP read)

    func getVersionMetadata(app: AppStoreApp, versionID: String) async throws -> VersionMetadata {
        let account = try accountInfo()
        let guid = getGUID()

        let item = try await fetchDownloadItem(
            account: account, appID: app.id, guid: guid, externalVersionID: versionID
        )

        return try await readVersionMetadataFromRemoteIPA(url: item.url)
    }

    private func readVersionMetadataFromRemoteIPA(url urlString: String) async throws -> VersionMetadata {
        let url = URL(string: urlString)!

        // Get file size via Range request
        var sizeReq = URLRequest(url: url)
        sizeReq.httpMethod = "GET"
        sizeReq.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        sizeReq.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        let (_, sizeResp) = try await session.data(for: sizeReq)
        guard let http = sizeResp as? HTTPURLResponse, http.statusCode == 206,
              let rangeHeader = http.value(forHTTPHeaderField: "Content-Range"),
              let totalSize = parseContentRangeSize(rangeHeader) else {
            throw AppStoreError.metadataFailed("cannot determine remote file size")
        }

        // Read last 65536 bytes to find central directory (ZIP EOCD is at the end)
        let tailSize: Int64 = min(65536, totalSize)
        let tailStart = totalSize - tailSize

        var tailReq = URLRequest(url: url)
        tailReq.httpMethod = "GET"
        tailReq.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        tailReq.setValue("bytes=\(tailStart)-\(totalSize - 1)", forHTTPHeaderField: "Range")

        let (tailData, tailResp) = try await session.data(for: tailReq)
        guard let tailHTTP = tailResp as? HTTPURLResponse, tailHTTP.statusCode == 206 else {
            throw AppStoreError.metadataFailed("failed to read ZIP tail")
        }

        // Parse EOCD to find central directory
        guard let cdInfo = findCentralDirectory(in: tailData, tailOffset: tailStart) else {
            throw AppStoreError.metadataFailed("cannot find ZIP central directory")
        }

        // Read central directory
        var cdReq = URLRequest(url: url)
        cdReq.httpMethod = "GET"
        cdReq.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        cdReq.setValue("bytes=\(cdInfo.offset)-\(cdInfo.offset + cdInfo.size - 1)", forHTTPHeaderField: "Range")

        let (cdData, cdResp) = try await session.data(for: cdReq)
        guard let cdHTTP = cdResp as? HTTPURLResponse, cdHTTP.statusCode == 206 else {
            throw AppStoreError.metadataFailed("failed to read central directory")
        }

        // Find Info.plist entry in central directory
        guard let plistEntry = findInfoPlistEntry(in: cdData) else {
            throw AppStoreError.metadataFailed("Info.plist not found in ZIP")
        }

        // Read Info.plist local file header + data
        let readEnd = plistEntry.localHeaderOffset + Int64(30 + plistEntry.nameLength + plistEntry.compressedSize + 1024)
        var plistReq = URLRequest(url: url)
        plistReq.httpMethod = "GET"
        plistReq.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        plistReq.setValue("bytes=\(plistEntry.localHeaderOffset)-\(min(readEnd, totalSize - 1))", forHTTPHeaderField: "Range")

        let (plistData, plistResp) = try await session.data(for: plistReq)
        guard let plistHTTP = plistResp as? HTTPURLResponse, plistHTTP.statusCode == 206 else {
            throw AppStoreError.metadataFailed("failed to read Info.plist data")
        }

        // Skip local file header to get to actual data
        guard plistData.count > 30 else {
            throw AppStoreError.metadataFailed("Info.plist data too small")
        }

        let localNameLen = Int(plistData[26]) | (Int(plistData[27]) << 8)
        let localExtraLen = Int(plistData[28]) | (Int(plistData[29]) << 8)
        let dataStart = 30 + localNameLen + localExtraLen

        guard dataStart + plistEntry.compressedSize <= plistData.count else {
            throw AppStoreError.metadataFailed("Info.plist data truncated")
        }

        let rawPlistData = plistData.subdata(in: dataStart..<(dataStart + plistEntry.compressedSize))

        // Decompress if method == 8 (deflate)
        let infoPlistBytes: Data
        if plistEntry.method == 8 {
            guard let decompressed = rawPlistData.decompress() else {
                throw AppStoreError.metadataFailed("failed to decompress Info.plist")
            }
            infoPlistBytes = decompressed
        } else {
            infoPlistBytes = rawPlistData
        }

        guard let infoDict = try? PropertyListSerialization.propertyList(
            from: infoPlistBytes, options: [], format: nil
        ) as? [String: Any] else {
            throw AppStoreError.metadataFailed("failed to parse Info.plist")
        }

        let displayVersion: String = {
            for key in ["CFBundleShortVersionString", "bundleShortVersionString"] {
                if let v = infoDict[key] as? String, !v.isEmpty { return v }
            }
            return "unknown"
        }()

        let releaseDate: Date = {
            for key in ["releaseDate", "ReleaseDate"] {
                if let d = infoDict[key] as? Date { return d }
                if let s = infoDict[key] as? String {
                    for fmt in ["yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"] {
                        let df = DateFormatter()
                        df.dateFormat = fmt
                        if let d = df.date(from: s) { return d }
                    }
                }
            }
            return Date()
        }()

        return VersionMetadata(displayVersion: displayVersion, releaseDate: releaseDate)
    }

    // MARK: - ZIP Helpers

    private func parseContentRangeSize(_ header: String) -> Int64? {
        guard let slashIndex = header.lastIndex(of: "/") else { return nil }
        let sizeStr = header[header.index(after: slashIndex)...]
        return Int64(sizeStr)
    }

    private struct CentralDirectoryInfo {
        let offset: Int64
        let size: Int64
    }

    private func findCentralDirectory(in tailData: Data, tailOffset: Int64) -> CentralDirectoryInfo? {
        // Search for EOCD signature (0x06054b50) from end
        let sig: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        for i in stride(from: tailData.count - 22, through: 0, by: -1) {
            if tailData[i] == sig[0] && tailData[i+1] == sig[1]
                && tailData[i+2] == sig[2] && tailData[i+3] == sig[3] {
                let cdSize = Int64(tailData[i+12]) | (Int64(tailData[i+13]) << 8)
                    | (Int64(tailData[i+14]) << 16) | (Int64(tailData[i+15]) << 24)
                let cdOffset = Int64(tailData[i+16]) | (Int64(tailData[i+17]) << 8)
                    | (Int64(tailData[i+18]) << 16) | (Int64(tailData[i+19]) << 24)
                return CentralDirectoryInfo(offset: cdOffset, size: cdSize)
            }
        }
        return nil
    }

    private struct ZipEntryInfo {
        let localHeaderOffset: Int64
        let compressedSize: Int
        let method: UInt16
        let nameLength: Int
    }

    private func findInfoPlistEntry(in cdData: Data) -> ZipEntryInfo? {
        var pos = 0
        while pos + 46 <= cdData.count {
            guard cdData[pos] == 0x50, cdData[pos+1] == 0x4b,
                  cdData[pos+2] == 0x01, cdData[pos+3] == 0x02 else { break }

            let method = UInt16(cdData[pos+10]) | (UInt16(cdData[pos+11]) << 8)
            let compSize = Int(cdData[pos+20]) | (Int(cdData[pos+21]) << 8)
                | (Int(cdData[pos+22]) << 16) | (Int(cdData[pos+23]) << 24)
            let nameLen = Int(cdData[pos+28]) | (Int(cdData[pos+29]) << 8)
            let extraLen = Int(cdData[pos+30]) | (Int(cdData[pos+31]) << 8)
            let commentLen = Int(cdData[pos+32]) | (Int(cdData[pos+33]) << 8)
            let localOffset = Int64(cdData[pos+42]) | (Int64(cdData[pos+43]) << 8)
                | (Int64(cdData[pos+44]) << 16) | (Int64(cdData[pos+45]) << 24)

            let nameStart = pos + 46
            guard nameStart + nameLen <= cdData.count else { break }
            let nameData = cdData.subdata(in: nameStart..<(nameStart + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? ""

            // Match Payload/*.app/Info.plist (top-level app, not nested)
            let parts = name.split(separator: "/")
            if parts.count == 3 && parts[0] == "Payload"
                && parts[1].hasSuffix(".app") && parts[2] == "Info.plist" {
                return ZipEntryInfo(
                    localHeaderOffset: localOffset,
                    compressedSize: compSize,
                    method: method,
                    nameLength: nameLen
                )
            }

            pos = nameStart + nameLen + extraLen + commentLen
        }
        return nil
    }
```

- [ ] **Step 2: Add Data decompression extension**

Add at the bottom of `AppStoreService.swift`, outside the class:

```swift
extension Data {
    func decompress() -> Data? {
        guard !isEmpty else { return nil }
        let bufferSize = count * 4
        var result = Data()
        return withUnsafeBytes { srcBuffer -> Data? in
            guard let srcPtr = srcBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }
            let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { dstBuffer.deallocate() }

            var stream = compression_stream()
            guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                return nil
            }
            defer { compression_stream_destroy(&stream) }

            stream.src_ptr = srcPtr
            stream.src_size = count
            stream.dst_ptr = dstBuffer
            stream.dst_size = bufferSize

            while true {
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                if produced > 0 {
                    result.append(dstBuffer, count: produced)
                }
                if status == COMPRESSION_STATUS_END { break }
                if status == COMPRESSION_STATUS_ERROR { return nil }
                stream.dst_ptr = dstBuffer
                stream.dst_size = bufferSize
            }

            return result
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/Service/AppStoreService.swift"
git commit -m "feat(appstore): add download, listVersions, getVersionMetadata to AppStoreService"
```

---

### Task 7: IPAProcessor (ZIP patching + sinf replication)

**Files:**
- Create: `BEERUS Framework/Sources/Modules/AppStore/Service/IPAProcessor.swift`

Reference: `ipatool/pkg/appstore/appstore_replicate_sinf.go`, `appstore_download.go` (applyPatches, writeMetadata, replicateZip)

- [ ] **Step 1: Create IPAProcessor.swift**

```swift
import Foundation

enum IPAProcessor {

    static func applyPatches(metadata: [String: Any], account: AppStoreAccount,
                              sinfs: [SinfData], sourcePath: String,
                              destinationPath: String) throws {
        // Read source ZIP
        let sourceData = try Data(contentsOf: URL(fileURLWithPath: sourcePath))

        // Parse source ZIP entries
        let entries = try parseZipEntries(sourceData)

        // Create destination file
        let destURL = URL(fileURLWithPath: destinationPath)
        FileManager.default.createFile(atPath: destinationPath, contents: nil)
        let handle = try FileHandle(forWritingTo: destURL)
        defer { handle.closeFile() }

        struct CDEntry {
            let nameData: Data, crc: UInt32, compressedSize: UInt32
            let uncompressedSize: UInt32, offset: UInt32, method: UInt16
        }
        var cdEntries: [CDEntry] = []

        // Replicate existing entries
        for entry in entries {
            let offset = UInt32(handle.offsetInFile)
            handle.write(entry.localHeaderData)
            handle.write(entry.fileData)
            cdEntries.append(CDEntry(
                nameData: entry.nameData, crc: entry.crc,
                compressedSize: entry.compressedSize,
                uncompressedSize: entry.uncompressedSize,
                offset: offset, method: entry.method
            ))
        }

        // Add iTunesMetadata.plist
        var meta = metadata
        meta["apple-id"] = account.email
        meta["userName"] = account.email

        let metaPlistData = try PropertyListSerialization.data(
            fromPropertyList: meta, format: .binary, options: 0
        )
        let metaCRC = crc32(metaPlistData)
        let metaName = "iTunesMetadata.plist".data(using: .utf8)!
        let metaOffset = UInt32(handle.offsetInFile)

        handle.write(makeLocalHeader(
            name: metaName, crc: metaCRC,
            compressedSize: UInt32(metaPlistData.count),
            uncompressedSize: UInt32(metaPlistData.count), method: 0
        ))
        handle.write(metaPlistData)
        cdEntries.append(CDEntry(
            nameData: metaName, crc: metaCRC,
            compressedSize: UInt32(metaPlistData.count),
            uncompressedSize: UInt32(metaPlistData.count),
            offset: metaOffset, method: 0
        ))

        // Replicate sinf files
        if !sinfs.isEmpty {
            let bundleName = findBundleName(in: entries)

            if let manifest = readManifestPlist(from: entries) {
                // Use manifest sinf paths
                let sinfPaths = manifest["SinfPaths"] as? [String] ?? []
                for (sinf, path) in zip(sinfs, sinfPaths) {
                    let fullPath = "Payload/\(bundleName).app/\(path)"
                    try writeSinfEntry(handle: handle, cdEntries: &cdEntries,
                                       path: fullPath, data: sinf.data)
                }
            } else if let info = readInfoPlist(from: entries) {
                // Fall back to executable name
                let execName = info["CFBundleExecutable"] as? String ?? ""
                let fullPath = "Payload/\(bundleName).app/SC_Info/\(execName).sinf"
                try writeSinfEntry(handle: handle, cdEntries: &cdEntries,
                                   path: fullPath, data: sinfs[0].data)
            }
        }

        // Write central directory
        let cdOffset = handle.offsetInFile
        for entry in cdEntries {
            handle.write(makeCentralDirEntry(entry))
        }

        // Write EOCD
        var eocd = Data(capacity: 22)
        eocd.appendZipU32(0x06054b50)
        eocd.appendZipU16(0); eocd.appendZipU16(0)
        eocd.appendZipU16(UInt16(cdEntries.count))
        eocd.appendZipU16(UInt16(cdEntries.count))
        eocd.appendZipU32(UInt32(handle.offsetInFile - cdOffset))
        eocd.appendZipU32(UInt32(cdOffset))
        eocd.appendZipU16(0)
        handle.write(eocd)
    }

    // MARK: - ZIP Parsing

    private struct ZipEntry {
        let nameData: Data
        let name: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderData: Data
        let fileData: Data
    }

    private static func parseZipEntries(_ data: Data) throws -> [ZipEntry] {
        var entries: [ZipEntry] = []
        var pos = 0

        while pos + 30 <= data.count {
            guard data[pos] == 0x50, data[pos+1] == 0x4b,
                  data[pos+2] == 0x03, data[pos+3] == 0x04 else { break }

            let method = readU16(data, pos + 8)
            let crc = readU32(data, pos + 14)
            let compSize = readU32(data, pos + 18)
            let uncompSize = readU32(data, pos + 22)
            let nameLen = Int(readU16(data, pos + 26))
            let extraLen = Int(readU16(data, pos + 28))

            let headerSize = 30 + nameLen + extraLen
            guard pos + headerSize + Int(compSize) <= data.count else { break }

            let nameData = data.subdata(in: (pos + 30)..<(pos + 30 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? ""
            let localHeaderData = data.subdata(in: pos..<(pos + headerSize))
            let fileData = data.subdata(in: (pos + headerSize)..<(pos + headerSize + Int(compSize)))

            entries.append(ZipEntry(
                nameData: nameData, name: name, method: method,
                crc: crc, compressedSize: compSize,
                uncompressedSize: uncompSize,
                localHeaderData: localHeaderData, fileData: fileData
            ))

            pos += headerSize + Int(compSize)
        }

        return entries
    }

    private static func findBundleName(in entries: [ZipEntry]) -> String {
        for entry in entries {
            if entry.name.contains(".app/Info.plist") && !entry.name.contains("/Watch/") {
                let appComponent = entry.name.split(separator: "/")
                    .first(where: { $0.hasSuffix(".app") })
                if let app = appComponent {
                    return String(app.dropLast(4))
                }
            }
        }
        return ""
    }

    private static func readManifestPlist(from entries: [ZipEntry]) -> [String: Any]? {
        for entry in entries {
            guard entry.name.hasSuffix(".app/SC_Info/Manifest.plist") else { continue }
            let raw = entry.method == 8 ? entry.fileData.decompress() : entry.fileData
            guard let data = raw else { continue }
            return try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any]
        }
        return nil
    }

    private static func readInfoPlist(from entries: [ZipEntry]) -> [String: Any]? {
        for entry in entries {
            guard entry.name.contains(".app/Info.plist") else { continue }
            let raw = entry.method == 8 ? entry.fileData.decompress() : entry.fileData
            guard let data = raw else { continue }
            return try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any]
        }
        return nil
    }

    private static func writeSinfEntry(handle: FileHandle,
                                        cdEntries: inout [CDEntry],
                                        path: String, data: Data) throws {
        let nameData = path.data(using: .utf8)!
        let crc = crc32(data)
        let offset = UInt32(handle.offsetInFile)

        handle.write(makeLocalHeader(
            name: nameData, crc: crc,
            compressedSize: UInt32(data.count),
            uncompressedSize: UInt32(data.count), method: 0
        ))
        handle.write(data)

        struct CDEntry {
            let nameData: Data, crc: UInt32, compressedSize: UInt32
            let uncompressedSize: UInt32, offset: UInt32, method: UInt16
        }

        // Can't use the outer CDEntry type name here — just append raw
        cdEntries.append((nameData: nameData, crc: crc,
                          compressedSize: UInt32(data.count),
                          uncompressedSize: UInt32(data.count),
                          offset: offset, method: 0))
    }

    // MARK: - ZIP Structures

    private static func makeLocalHeader(name: Data, crc: UInt32, compressedSize: UInt32,
                                         uncompressedSize: UInt32, method: UInt16) -> Data {
        var h = Data(capacity: 30 + name.count)
        h.appendZipU32(0x04034b50)
        h.appendZipU16(20); h.appendZipU16(0); h.appendZipU16(method)
        h.appendZipU16(0); h.appendZipU16(0)
        h.appendZipU32(crc)
        h.appendZipU32(compressedSize); h.appendZipU32(uncompressedSize)
        h.appendZipU16(UInt16(name.count)); h.appendZipU16(0)
        h.append(name)
        return h
    }

    private struct CDEntry {
        let nameData: Data, crc: UInt32, compressedSize: UInt32
        let uncompressedSize: UInt32, offset: UInt32, method: UInt16
    }

    private static func makeCentralDirEntry(_ e: CDEntry) -> Data {
        var cd = Data(capacity: 46 + e.nameData.count)
        cd.appendZipU32(0x02014b50)
        cd.appendZipU16(20); cd.appendZipU16(20)
        cd.appendZipU16(0); cd.appendZipU16(e.method)
        cd.appendZipU16(0); cd.appendZipU16(0)
        cd.appendZipU32(e.crc)
        cd.appendZipU32(e.compressedSize); cd.appendZipU32(e.uncompressedSize)
        cd.appendZipU16(UInt16(e.nameData.count))
        cd.appendZipU16(0); cd.appendZipU16(0); cd.appendZipU16(0); cd.appendZipU16(0)
        cd.appendZipU32(0)
        cd.appendZipU32(e.offset)
        cd.append(e.nameData)
        return cd
    }

    // MARK: - Helpers

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset+1]) << 8)
            | (UInt32(data[offset+2]) << 16) | (UInt32(data[offset+3]) << 24)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 != 0 ? 0xEDB88320 : 0)
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendZipU16(_ v: UInt16) {
        var x = v.littleEndian
        append(Data(bytes: &x, count: 2))
    }
    mutating func appendZipU32(_ v: UInt32) {
        var x = v.littleEndian
        append(Data(bytes: &x, count: 4))
    }
}
```

- [ ] **Step 2: Fix CDEntry type collision in writeSinfEntry**

The `writeSinfEntry` method has a nested `CDEntry` redefinition that will shadow the outer type. Remove the inner `struct CDEntry` definition — the method already uses the outer type through the `inout` parameter:

Delete this block from inside `writeSinfEntry`:
```swift
        struct CDEntry {
            let nameData: Data, crc: UInt32, compressedSize: UInt32
            let uncompressedSize: UInt32, offset: UInt32, method: UInt16
        }
```

- [ ] **Step 3: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/Service/IPAProcessor.swift"
git commit -m "feat(appstore): add IPAProcessor for ZIP patching and sinf replication"
```

---

### Task 8: Daemon — INSTALL_IPA command

**Files:**
- Modify: `Daemon/BeerusDaemon.c`
- Modify: `BEERUS Framework/Sources/Shared/Utils/RootExec.swift`

- [ ] **Step 1: Resolve merge conflicts in BeerusDaemon.c**

Open `Daemon/BeerusDaemon.c`. For every conflict block (`<<<<<<<` ... `=======` ... `>>>>>>>`), keep the content from the `ae68300` side (between `=======` and `>>>>>>>`). Remove all conflict markers.

- [ ] **Step 2: Add install_ipa function to BeerusDaemon.c**

Add this function before `handle_client()`:

```c
static int install_ipa(const char *ipa_path, char *out, size_t out_size) {
    if (access(ipa_path, R_OK) != 0) {
        snprintf(out, out_size, "error: file not found: %s", ipa_path);
        return -1;
    }

    // Try appinst first
    char appinst_path[512];
    if (g_rootless) {
        snprintf(appinst_path, sizeof(appinst_path), "%s/usr/bin/appinst", ROOTLESS_PREFIX);
    } else {
        snprintf(appinst_path, sizeof(appinst_path), "/usr/bin/appinst");
    }

    if (access(appinst_path, X_OK) == 0) {
        char *argv[] = {appinst_path, (char *)ipa_path, NULL};
        if (run_cmd(appinst_path, argv) == 0) {
            snprintf(out, out_size, "ok: installed via appinst");
            return 0;
        }
    }

    // Fallback: extract and copy
    char tmpdir[] = "/tmp/beerus-ipa-XXXXXX";
    if (mkdtemp(tmpdir) == NULL) {
        snprintf(out, out_size, "error: failed to create temp dir");
        return -1;
    }

    // Unzip IPA
    char unzip_cmd[2048];
    snprintf(unzip_cmd, sizeof(unzip_cmd), "unzip -o -q '%s' -d '%s'", ipa_path, tmpdir);
    if (run_shell(unzip_cmd) != 0) {
        rm_rf(tmpdir);
        snprintf(out, out_size, "error: failed to extract IPA");
        return -1;
    }

    // Find .app directory
    char find_cmd[1200];
    snprintf(find_cmd, sizeof(find_cmd),
        "find '%s/Payload' -maxdepth 1 -name '*.app' -type d | head -1", tmpdir);
    char app_path[1100] = {0};
    FILE *fp = popen(find_cmd, "r");
    if (fp) {
        if (fgets(app_path, sizeof(app_path), fp)) {
            size_t len = strlen(app_path);
            if (len > 0 && app_path[len - 1] == '\n') app_path[len - 1] = '\0';
        }
        pclose(fp);
    }

    if (app_path[0] == '\0') {
        rm_rf(tmpdir);
        snprintf(out, out_size, "error: no .app found in IPA");
        return -1;
    }

    // Get app name
    char *app_name = strrchr(app_path, '/');
    app_name = app_name ? app_name + 1 : app_path;

    // Copy to Applications
    char dest[1200];
    if (g_rootless) {
        snprintf(dest, sizeof(dest), "%s/Applications/%s", ROOTLESS_PREFIX, app_name);
    } else {
        snprintf(dest, sizeof(dest), "/Applications/%s", app_name);
    }

    // Remove old version if exists
    rm_rf(dest);

    char cp_cmd[2400];
    snprintf(cp_cmd, sizeof(cp_cmd), "cp -R '%s' '%s'", app_path, dest);
    if (run_shell(cp_cmd) != 0) {
        rm_rf(tmpdir);
        snprintf(out, out_size, "error: failed to copy app");
        return -1;
    }

    // Set permissions
    char chmod_cmd[1300];
    snprintf(chmod_cmd, sizeof(chmod_cmd), "chmod -R 755 '%s'", dest);
    run_shell(chmod_cmd);

    // Run uicache
    char uicache_cmd[1300];
    snprintf(uicache_cmd, sizeof(uicache_cmd), "uicache -p '%s'", dest);
    run_shell(uicache_cmd);

    rm_rf(tmpdir);
    snprintf(out, out_size, "ok: installed %s", app_name);
    return 0;
}
```

- [ ] **Step 3: Add INSTALL_IPA handler in handle_client()**

In `handle_client()`, add this before the `WHOAMI` handler:

```c
    else if (strncmp(buf, "INSTALL_IPA ", 12) == 0) {
        install_ipa(buf + 12, out, sizeof(out));
    }
```

- [ ] **Step 4: Resolve merge conflicts in RootExec.swift and add installIPA**

Resolve any conflict markers in `RootExec.swift` (keep `ae68300` side), then add:

```swift
    static func installIPA(path: String) -> String? { send("INSTALL_IPA \(path)") }
```

Add this line right after the `uninstallFrida()` method.

- [ ] **Step 5: Commit**

```bash
git add Daemon/BeerusDaemon.c "BEERUS Framework/Sources/Shared/Utils/RootExec.swift"
git commit -m "feat(appstore): add INSTALL_IPA daemon command and RootExec wrapper"
```

---

### Task 9: UI — SearchResultCell and VersionCell

**Files:**
- Create: `BEERUS Framework/Sources/Modules/AppStore/View/SearchResultCell.swift`
- Create: `BEERUS Framework/Sources/Modules/AppStore/View/VersionCell.swift`

- [ ] **Step 1: Create SearchResultCell.swift**

```swift
import UIKit

final class SearchResultCell: UITableViewCell {

    static let identifier = "SearchResultCell"

    private let iconView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 0.15, alpha: 1)
        v.layer.cornerRadius = 12
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let nameLabel = UILabel.styled(font: AppFont.medium(14))
    private let bundleLabel = UILabel.styled(font: AppFont.regular(11), color: UIColor(white: 0.5, alpha: 1))
    private let priceLabel = UILabel.styled(font: AppFont.regular(11), color: UIColor(white: 0.6, alpha: 1))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(iconView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(bundleLabel)
        contentView.addSubview(priceLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: priceLabel.leadingAnchor, constant: -8),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

            bundleLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            bundleLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            bundleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            bundleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            priceLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            priceLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with app: AppStoreApp) {
        nameLabel.text = app.name
        bundleLabel.text = app.bundleID
        priceLabel.text = app.price == 0 ? "Free" : String(format: "$%.2f", app.price)
    }
}
```

- [ ] **Step 2: Create VersionCell.swift**

```swift
import UIKit

final class VersionCell: UITableViewCell {

    static let identifier = "VersionCell"

    private let versionLabel = UILabel.styled(font: AppFont.medium(13))
    private let dateLabel = UILabel.styled(font: AppFont.regular(11), color: UIColor(white: 0.5, alpha: 1))
    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .white
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    let getButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("GET", for: .normal)
        btn.titleLabel?.font = AppFont.bold(11)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor(named: "ButtonColor")
        btn.layer.cornerRadius = 4
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    var onGetTapped: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(versionLabel)
        contentView.addSubview(dateLabel)
        contentView.addSubview(loadingIndicator)
        contentView.addSubview(getButton)

        getButton.addTarget(self, action: #selector(getTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            versionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            versionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

            dateLabel.leadingAnchor.constraint(equalTo: versionLabel.leadingAnchor),
            dateLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 2),
            dateLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10),

            loadingIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            loadingIndicator.leadingAnchor.constraint(equalTo: versionLabel.trailingAnchor, constant: 8),

            getButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            getButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            getButton.widthAnchor.constraint(equalToConstant: 52),
            getButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(versionID: String, metadata: VersionMetadata?, isLatest: Bool) {
        if let meta = metadata {
            versionLabel.text = "v\(meta.displayVersion)\(isLatest ? " • Latest" : "")"
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            dateLabel.text = formatter.string(from: meta.releaseDate)
            loadingIndicator.stopAnimating()
        } else {
            versionLabel.text = "Version \(versionID)\(isLatest ? " • Latest" : "")"
            dateLabel.text = "Loading..."
            loadingIndicator.startAnimating()
        }

        getButton.backgroundColor = isLatest ? UIColor(named: "ButtonColor") : UIColor(white: 0.2, alpha: 1)
    }

    @objc private func getTapped() {
        onGetTapped?()
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/View/"
git commit -m "feat(appstore): add SearchResultCell and VersionCell"
```

---

### Task 10: UI — AppStoreLoginViewController

**Files:**
- Create: `BEERUS Framework/Sources/Modules/AppStore/ViewController/AppStoreLoginViewController.swift`

- [ ] **Step 1: Create AppStoreLoginViewController.swift**

```swift
import UIKit

final class AppStoreLoginViewController: BaseViewController {

    var onLoginSuccess: ((AppStoreAccount) -> Void)?

    private lazy var titleLabel = UILabel.styled(
        text: "App Store", font: AppFont.bold(20), alignment: .center
    )

    private lazy var emailField: UITextField = makeField(placeholder: "Apple ID", secure: false)
    private lazy var passwordField: UITextField = makeField(placeholder: "Password", secure: true)
    private lazy var authCodeField: UITextField = {
        let f = makeField(placeholder: "2FA Code", secure: false)
        f.keyboardType = .numberPad
        f.isHidden = true
        return f
    }()

    private lazy var signInButton = UIButton.styled(
        title: "Sign In", target: self, action: #selector(signInTapped)
    )

    private lazy var statusLabel = UILabel.styled(
        text: "", font: AppFont.regular(12),
        color: UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1),
        alignment: .center, lines: 0
    )

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = .white
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
    }

    @objc private func signInTapped() {
        guard let email = emailField.text, !email.isEmpty,
              let password = passwordField.text, !password.isEmpty else {
            statusLabel.text = "Enter email and password"
            return
        }

        let authCode = authCodeField.text ?? ""
        setLoading(true)
        statusLabel.text = ""

        Task {
            do {
                let account = try await AppStoreService.shared.login(
                    email: email, password: password, authCode: authCode
                )
                await MainActor.run {
                    setLoading(false)
                    onLoginSuccess?(account)
                }
            } catch AppStoreError.authCodeRequired {
                await MainActor.run {
                    setLoading(false)
                    authCodeField.isHidden = false
                    statusLabel.text = "Enter 2FA code sent to your device"
                    statusLabel.textColor = .white
                }
            } catch {
                await MainActor.run {
                    setLoading(false)
                    statusLabel.text = error.localizedDescription
                    statusLabel.textColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
                }
            }
        }
    }

    private func setLoading(_ loading: Bool) {
        signInButton.isEnabled = !loading
        signInButton.alpha = loading ? 0.5 : 1.0
        loading ? spinner.startAnimating() : spinner.stopAnimating()
    }

    private func makeField(placeholder: String, secure: Bool) -> UITextField {
        let field = UITextField()
        field.font = AppFont.regular(14)
        field.textColor = .white
        field.tintColor = UIColor(named: "RED")
        field.isSecureTextEntry = secure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardAppearance = .dark
        field.backgroundColor = UIColor(white: 0.1, alpha: 1)
        field.layer.cornerRadius = 8
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        field.leftViewMode = .always
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(white: 0.3, alpha: 1), .font: AppFont.regular(14)]
        )
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }
}

extension AppStoreLoginViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(emailField)
        view.addSubview(passwordField)
        view.addSubview(authCodeField)
        view.addSubview(signInButton)
        view.addSubview(statusLabel)
        view.addSubview(spinner)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),

            emailField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 40),
            emailField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emailField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            emailField.heightAnchor.constraint(equalToConstant: 44),

            passwordField.topAnchor.constraint(equalTo: emailField.bottomAnchor, constant: 12),
            passwordField.leadingAnchor.constraint(equalTo: emailField.leadingAnchor),
            passwordField.trailingAnchor.constraint(equalTo: emailField.trailingAnchor),
            passwordField.heightAnchor.constraint(equalToConstant: 44),

            authCodeField.topAnchor.constraint(equalTo: passwordField.bottomAnchor, constant: 12),
            authCodeField.leadingAnchor.constraint(equalTo: emailField.leadingAnchor),
            authCodeField.trailingAnchor.constraint(equalTo: emailField.trailingAnchor),
            authCodeField.heightAnchor.constraint(equalToConstant: 44),

            signInButton.topAnchor.constraint(equalTo: authCodeField.bottomAnchor, constant: 24),
            signInButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            signInButton.widthAnchor.constraint(equalToConstant: 200),
            signInButton.heightAnchor.constraint(equalToConstant: 50),

            spinner.centerYAnchor.constraint(equalTo: signInButton.centerYAnchor),
            spinner.leadingAnchor.constraint(equalTo: signInButton.trailingAnchor, constant: 12),

            statusLabel.topAnchor.constraint(equalTo: signInButton.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: emailField.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: emailField.trailingAnchor),
        ])
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/ViewController/AppStoreLoginViewController.swift"
git commit -m "feat(appstore): add login screen with 2FA support"
```

---

### Task 11: UI — AppStoreSearchViewController

**Files:**
- Create: `BEERUS Framework/Sources/Modules/AppStore/ViewController/AppStoreSearchViewController.swift`

- [ ] **Step 1: Create AppStoreSearchViewController.swift**

```swift
import UIKit

final class AppStoreSearchViewController: BaseViewController {

    private var results: [AppStoreApp] = []

    private lazy var titleLabel = UILabel.styled(
        text: "App Store", font: AppFont.bold(20), alignment: .center
    )

    private lazy var accountLabel = UILabel.styled(
        font: AppFont.regular(11), color: UIColor(white: 0.5, alpha: 1), alignment: .center
    )

    private lazy var logoutButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("Logout", for: .normal)
        btn.titleLabel?.font = AppFont.bold(11)
        btn.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(logoutTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var searchBar: UITextField = {
        let field = UITextField()
        field.font = AppFont.regular(14)
        field.textColor = .white
        field.tintColor = UIColor(named: "RED")
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.keyboardAppearance = .dark
        field.backgroundColor = UIColor(white: 0.1, alpha: 1)
        field.layer.cornerRadius = 8
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        field.leftViewMode = .always
        field.attributedPlaceholder = NSAttributedString(
            string: "Search apps...",
            attributes: [.foregroundColor: UIColor(white: 0.3, alpha: 1), .font: AppFont.regular(14)]
        )
        field.translatesAutoresizingMaskIntoConstraints = false
        field.delegate = self
        return field
    }()

    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorColor = UIColor(white: 0.15, alpha: 1)
        table.register(SearchResultCell.self, forCellReuseIdentifier: SearchResultCell.identifier)
        table.delegate = self
        table.dataSource = self
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = .white
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        updateAccountLabel()
    }

    private func updateAccountLabel() {
        if let account = try? AppStoreService.shared.accountInfo() {
            accountLabel.text = "\(account.email) ✓"
        }
    }

    private func performSearch(_ term: String) {
        spinner.startAnimating()
        Task {
            do {
                let apps = try await AppStoreService.shared.search(term: term)
                await MainActor.run {
                    spinner.stopAnimating()
                    results = apps
                    tableView.reloadData()
                }
            } catch {
                await MainActor.run {
                    spinner.stopAnimating()
                    showAlert(title: "Search Failed", message: error.localizedDescription)
                }
            }
        }
    }

    @objc private func logoutTapped() {
        AppStoreService.shared.revoke()
        let loginVC = AppStoreLoginViewController()
        loginVC.menuDelegate = menuDelegate
        loginVC.onLoginSuccess = { [weak self] _ in
            guard let self else { return }
            let searchVC = AppStoreSearchViewController()
            searchVC.menuDelegate = self.menuDelegate
            self.navigationController?.setViewControllers([searchVC], animated: true)
        }
        navigationController?.setViewControllers([loginVC], animated: true)
    }
}

extension AppStoreSearchViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let term = textField.text, !term.isEmpty else { return false }
        textField.resignFirstResponder()
        performSearch(term)
        return true
    }
}

extension AppStoreSearchViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultCell.identifier, for: indexPath) as! SearchResultCell
        cell.configure(with: results[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 64 }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let detailVC = AppDetailViewController(app: results[indexPath.row])
        detailVC.menuDelegate = menuDelegate
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

extension AppStoreSearchViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(accountLabel)
        view.addSubview(logoutButton)
        view.addSubview(searchBar)
        view.addSubview(tableView)
        view.addSubview(spinner)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            accountLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            accountLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            logoutButton.centerYAnchor.constraint(equalTo: accountLabel.centerYAnchor),
            logoutButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            searchBar.topAnchor.constraint(equalTo: accountLabel.bottomAnchor, constant: 16),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            searchBar.heightAnchor.constraint(equalToConstant: 40),

            spinner.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor, constant: -12),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/ViewController/AppStoreSearchViewController.swift"
git commit -m "feat(appstore): add search screen with results table"
```

---

### Task 12: UI — AppDetailViewController

**Files:**
- Create: `BEERUS Framework/Sources/Modules/AppStore/ViewController/AppDetailViewController.swift`

- [ ] **Step 1: Create AppDetailViewController.swift**

```swift
import UIKit

final class AppDetailViewController: BaseViewController {

    private let app: AppStoreApp

    init(app: AppStoreApp) {
        self.app = app
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private lazy var nameLabel = UILabel.styled(text: app.name, font: AppFont.bold(18), alignment: .center)
    private lazy var bundleLabel = UILabel.styled(
        text: app.bundleID, font: AppFont.regular(12),
        color: UIColor(white: 0.5, alpha: 1), alignment: .center
    )
    private lazy var versionLabel = UILabel.styled(
        text: "v\(app.version) • \(app.price == 0 ? "Free" : String(format: "$%.2f", app.price))",
        font: AppFont.regular(13), color: UIColor(white: 0.6, alpha: 1), alignment: .center
    )
    private lazy var idLabel = UILabel.styled(
        text: "App ID: \(app.id)", font: AppFont.regular(11),
        color: UIColor(white: 0.4, alpha: 1), alignment: .center
    )

    private lazy var downloadButton = UIButton.styled(
        title: "Download Latest", target: self, action: #selector(downloadTapped)
    )

    private lazy var versionsButton: UIButton = {
        let btn = UIButton.styled(
            title: "View All Versions",
            backgroundColor: UIColor(white: 0.2, alpha: 1),
            target: self, action: #selector(versionsTapped)
        )
        return btn
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
    }

    @objc private func downloadTapped() {
        let downloadVC = DownloadViewController(app: app, versionID: nil)
        downloadVC.menuDelegate = menuDelegate
        navigationController?.pushViewController(downloadVC, animated: true)
    }

    @objc private func versionsTapped() {
        let versionsVC = VersionListViewController(app: app)
        versionsVC.menuDelegate = menuDelegate
        navigationController?.pushViewController(versionsVC, animated: true)
    }
}

extension AppDetailViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(nameLabel)
        view.addSubview(bundleLabel)
        view.addSubview(versionLabel)
        view.addSubview(downloadButton)
        view.addSubview(versionsButton)
        view.addSubview(idLabel)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            bundleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            bundleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: bundleLabel.bottomAnchor, constant: 4),
            versionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            downloadButton.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 32),
            downloadButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            downloadButton.widthAnchor.constraint(equalToConstant: 220),
            downloadButton.heightAnchor.constraint(equalToConstant: 50),

            versionsButton.topAnchor.constraint(equalTo: downloadButton.bottomAnchor, constant: 12),
            versionsButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            versionsButton.widthAnchor.constraint(equalToConstant: 220),
            versionsButton.heightAnchor.constraint(equalToConstant: 50),

            idLabel.topAnchor.constraint(equalTo: versionsButton.bottomAnchor, constant: 24),
            idLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/ViewController/AppDetailViewController.swift"
git commit -m "feat(appstore): add app detail screen"
```

---

### Task 13: UI — VersionListViewController

**Files:**
- Create: `BEERUS Framework/Sources/Modules/AppStore/ViewController/VersionListViewController.swift`

- [ ] **Step 1: Create VersionListViewController.swift**

```swift
import UIKit

final class VersionListViewController: BaseViewController {

    private let app: AppStoreApp
    private var versionIDs: [String] = []
    private var latestID: String = ""
    private var metadataCache: [String: VersionMetadata] = [:]

    init(app: AppStoreApp) {
        self.app = app
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private lazy var titleLabel = UILabel.styled(
        text: "\(app.name) — Versions", font: AppFont.bold(16), alignment: .center
    )

    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.backgroundColor = .clear
        table.separatorColor = UIColor(white: 0.15, alpha: 1)
        table.register(VersionCell.self, forCellReuseIdentifier: VersionCell.identifier)
        table.delegate = self
        table.dataSource = self
        table.translatesAutoresizingMaskIntoConstraints = false
        return table
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .large)
        s.color = .white
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        loadVersions()
    }

    private func loadVersions() {
        spinner.startAnimating()
        Task {
            do {
                let result = try await AppStoreService.shared.listVersions(app: app)
                await MainActor.run {
                    spinner.stopAnimating()
                    versionIDs = result.identifiers.reversed()
                    latestID = result.latestID
                    tableView.reloadData()
                    loadMetadataProgressively()
                }
            } catch {
                await MainActor.run {
                    spinner.stopAnimating()
                    showAlert(title: "Error", message: error.localizedDescription)
                }
            }
        }
    }

    private func loadMetadataProgressively() {
        for (index, versionID) in versionIDs.enumerated() {
            Task {
                do {
                    let meta = try await AppStoreService.shared.getVersionMetadata(
                        app: app, versionID: versionID
                    )
                    await MainActor.run {
                        metadataCache[versionID] = meta
                        let indexPath = IndexPath(row: index, section: 0)
                        if tableView.indexPathsForVisibleRows?.contains(indexPath) == true {
                            tableView.reloadRows(at: [indexPath], with: .none)
                        }
                    }
                } catch {
                    // Metadata load failure is non-fatal — cell stays in loading state
                }
            }
        }
    }
}

extension VersionListViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        versionIDs.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VersionCell.identifier, for: indexPath) as! VersionCell
        let versionID = versionIDs[indexPath.row]
        let isLatest = versionID == latestID
        cell.configure(versionID: versionID, metadata: metadataCache[versionID], isLatest: isLatest)
        cell.onGetTapped = { [weak self] in
            guard let self else { return }
            let downloadVC = DownloadViewController(app: self.app, versionID: versionID)
            downloadVC.menuDelegate = self.menuDelegate
            self.navigationController?.pushViewController(downloadVC, animated: true)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 60 }
}

extension VersionListViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(titleLabel)
        view.addSubview(tableView)
        view.addSubview(spinner)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 44),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            tableView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/ViewController/VersionListViewController.swift"
git commit -m "feat(appstore): add version list screen with progressive metadata loading"
```

---

### Task 14: UI — DownloadViewController

**Files:**
- Create: `BEERUS Framework/Sources/Modules/AppStore/ViewController/DownloadViewController.swift`

- [ ] **Step 1: Create DownloadViewController.swift**

```swift
import UIKit

final class DownloadViewController: BaseViewController {

    private let app: AppStoreApp
    private let versionID: String?
    private var downloadedPath: String?

    init(app: AppStoreApp, versionID: String?) {
        self.app = app
        self.versionID = versionID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private lazy var nameLabel = UILabel.styled(text: app.name, font: AppFont.bold(16), alignment: .center)
    private lazy var versionLabel = UILabel.styled(
        text: versionID != nil ? "Version ID: \(versionID!)" : "Latest Version",
        font: AppFont.regular(12), color: UIColor(white: 0.5, alpha: 1), alignment: .center
    )

    private let progressBar: UIProgressView = {
        let bar = UIProgressView(progressViewStyle: .default)
        bar.progressTintColor = UIColor(named: "ButtonColor")
        bar.trackTintColor = UIColor(white: 0.2, alpha: 1)
        bar.translatesAutoresizingMaskIntoConstraints = false
        return bar
    }()

    private lazy var progressLabel = UILabel.styled(
        text: "Preparing...", font: AppFont.regular(12),
        color: UIColor(white: 0.6, alpha: 1), alignment: .center
    )

    private lazy var stepLabels: [UILabel] = {
        let steps = ["Acquiring license", "Downloading IPA", "Patching metadata", "Replicating sinf", "Ready"]
        return steps.map { UILabel.styled(text: "○ \($0)", font: AppFont.regular(12), color: UIColor(white: 0.4, alpha: 1)) }
    }()

    private lazy var actionsStack: UIStackView = {
        let installBtn = makeActionButton(title: "Install", action: #selector(installTapped))
        let shareBtn = makeActionButton(title: "Share", action: #selector(shareTapped))
        let filesBtn = makeActionButton(title: "Files", action: #selector(filesTapped))
        let stack = UIStackView(arrangedSubviews: [installBtn, shareBtn, filesBtn])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        return stack
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        applyViewCode()
        startDownload()
    }

    private func startDownload() {
        Task {
            do {
                // Step 1: Purchase
                updateStep(0, status: .inProgress)
                do {
                    try await AppStoreService.shared.purchase(app: app)
                } catch AppStoreError.purchaseFailed(let msg) where msg.contains("already") {
                    // License already exists — continue
                } catch AppStoreError.paidAppNotSupported {
                    throw AppStoreError.paidAppNotSupported
                } catch {
                    // Non-fatal for purchase — might already have license
                }
                updateStep(0, status: .done)

                // Step 2: Download
                updateStep(1, status: .inProgress)
                let result = try await AppStoreService.shared.download(
                    app: app, externalVersionID: versionID
                ) { [weak self] downloaded, total in
                    Task { @MainActor in
                        guard let self else { return }
                        let pct = total > 0 ? Float(downloaded) / Float(total) : 0
                        self.progressBar.progress = pct
                        let dlMB = Double(downloaded) / 1_048_576
                        let totalMB = Double(total) / 1_048_576
                        self.progressLabel.text = String(
                            format: "%.1f MB / %.1f MB (%.0f%%)", dlMB, totalMB, pct * 100
                        )
                    }
                }
                updateStep(1, status: .done)

                // Steps 3-4 already happened inside download()
                updateStep(2, status: .done)
                updateStep(3, status: .done)

                // Step 5: Ready
                updateStep(4, status: .done)

                await MainActor.run {
                    downloadedPath = result.destinationPath
                    progressLabel.text = "Download complete!"
                    progressBar.progress = 1.0
                    actionsStack.isHidden = false
                }

            } catch {
                await MainActor.run {
                    progressLabel.text = error.localizedDescription
                    progressLabel.textColor = UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)
                }
            }
        }
    }

    private enum StepStatus { case pending, inProgress, done }

    private func updateStep(_ index: Int, status: StepStatus) {
        Task { @MainActor in
            guard index < stepLabels.count else { return }
            let label = stepLabels[index]
            let text = String(label.text?.dropFirst(2) ?? "")
            switch status {
            case .pending:
                label.text = "○ \(text)"
                label.textColor = UIColor(white: 0.4, alpha: 1)
            case .inProgress:
                label.text = "⏳ \(text)"
                label.textColor = UIColor(named: "RED") ?? .red
            case .done:
                label.text = "✓ \(text)"
                label.textColor = UIColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 1)
            }
        }
    }

    @objc private func installTapped() {
        guard let path = downloadedPath else { return }
        progressLabel.text = "Installing..."
        Task.detached {
            let result = RootExec.installIPA(path: path)
            await MainActor.run { [weak self] in
                self?.progressLabel.text = result ?? "Install failed"
            }
        }
    }

    @objc private func shareTapped() {
        guard let path = downloadedPath else { return }
        let url = URL(fileURLWithPath: path)
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(vc, animated: true)
    }

    @objc private func filesTapped() {
        guard let path = downloadedPath else { return }
        let dir = (path as NSString).deletingLastPathComponent
        progressLabel.text = "IPA saved at:\n\(dir)"
        progressLabel.numberOfLines = 0
    }

    private func makeActionButton(title: String, action: Selector) -> UIButton {
        let btn = UIButton.styled(
            title: title, font: AppFont.bold(12),
            backgroundColor: UIColor(white: 0.2, alpha: 1),
            cornerRadius: 8, target: self, action: action
        )
        btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return btn
    }
}

extension DownloadViewController: ViewCode {
    func buildViewHierarchy() {
        view.addSubview(nameLabel)
        view.addSubview(versionLabel)
        view.addSubview(progressBar)
        view.addSubview(progressLabel)
        stepLabels.forEach { view.addSubview($0) }
        view.addSubview(actionsStack)
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            versionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            progressBar.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 32),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            progressLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 8),
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        var previous: UIView = progressLabel
        for label in stepLabels {
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: previous == progressLabel ? 24 : 6),
                label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 48),
            ])
            previous = label
        }

        NSLayoutConstraint.activate([
            actionsStack.topAnchor.constraint(equalTo: previous.bottomAnchor, constant: 32),
            actionsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            actionsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add "BEERUS Framework/Sources/Modules/AppStore/ViewController/DownloadViewController.swift"
git commit -m "feat(appstore): add download screen with progress, steps, and post-download actions"
```

---

### Task 15: Wire up — TabOption, ContainerViewController

**Files:**
- Modify: `BEERUS Framework/Sources/Shared/Enum/TabOption.swift`
- Modify: `BEERUS Framework/Sources/Main/ViewController/ContainerViewController.swift`

- [ ] **Step 1: Resolve conflicts and add .appStore to TabOption.swift**

Open `TabOption.swift`. Resolve all merge conflicts by keeping the `ae68300` content (which includes `.scriptEditor`). Then add the new `.appStore` case.

The final `TabOption` enum should be:

```swift
import UIKit

enum TabOption: String, CaseIterable {
    case home = "Home"
    case setupFrida = "Setup Frida"
    case ipaExtractor = "IPA Extractor"
    case memoryDump = "Memory Dump"
    case lldbServer = "LLDB Server"
    case proxyProfiles = "Proxy Profiles"
    case terminal = "Terminal"
    case plistReader = "Plist Reader"
    case scriptEditor = "Script Editor"
    case appStore = "App Store"

    var icon: String {
        switch self {
        case .home: return "house"
        case .setupFrida: return "frida"
        case .ipaExtractor: return "ipa-extractor"
        case .memoryDump: return "memorychip"
        case .lldbServer: return "ant.fill"
        case .proxyProfiles: return "network"
        case .terminal: return "terminal"
        case .plistReader: return "house"
        case .scriptEditor: return "scroll"
        case .appStore: return "cart.fill"
        }
    }

    var image: UIImage? {
        switch self {
        case .terminal:
            return UIImage(systemName: "terminal.fill")?
                .withRenderingMode(.alwaysTemplate)
        case .memoryDump:
            return UIImage(systemName: "memorychip")?
                .withRenderingMode(.alwaysTemplate)
        case .ipaExtractor:
            return UIImage(systemName: "arrow.down.app.fill")?
                .withRenderingMode(.alwaysTemplate)
        case .lldbServer:
            return UIImage(systemName: "ant.fill")?
                .withRenderingMode(.alwaysTemplate)
        case .proxyProfiles:
            return UIImage(systemName: "wifi")?
                .withRenderingMode(.alwaysTemplate)
        case .scriptEditor:
            return UIImage(systemName: "scroll.fill")?
                .withRenderingMode(.alwaysTemplate)
        case .appStore:
            return UIImage(systemName: "cart.fill")?
                .withRenderingMode(.alwaysTemplate)
        default:
            return UIImage(named: icon)?
                .withRenderingMode(.alwaysTemplate)
        }
    }
}
```

- [ ] **Step 2: Resolve conflicts and add appStore to ContainerViewController.swift**

Open `ContainerViewController.swift`. Resolve all merge conflicts keeping `ae68300` content (scriptEditor). Then:

Add property (after `scriptListViewController`):
```swift
    private lazy var appStoreViewController: UIViewController = {
        if AppStoreCredentialManager.hasStoredAccount {
            let vc = AppStoreSearchViewController()
            vc.menuDelegate = self
            return vc
        } else {
            let loginVC = AppStoreLoginViewController()
            loginVC.menuDelegate = self
            loginVC.onLoginSuccess = { [weak self] _ in
                guard let self else { return }
                let searchVC = AppStoreSearchViewController()
                searchVC.menuDelegate = self
                self.navController?.setViewControllers([searchVC], animated: true)
            }
            return loginVC
        }
    }()
```

Add in `setupAdditionalConfiguration()` (after `scriptListViewController.menuDelegate = self`):
```swift
        // appStoreViewController menuDelegate is set in its lazy initializer
```

Add case in `didSelect(item:)`:
```swift
        case .appStore:
            show(viewController: appStoreViewController)
```

- [ ] **Step 3: Commit**

```bash
git add "BEERUS Framework/Sources/Shared/Enum/TabOption.swift"
git add "BEERUS Framework/Sources/Main/ViewController/ContainerViewController.swift"
git commit -m "feat(appstore): wire App Store module into side menu and navigation"
```

---

### Task 16: Build verification

**Files:** None (verification only)

- [ ] **Step 1: Verify the project builds**

```bash
cd "/Users/texugo/Documents/beerus-ios-development"
xcodebuild \
  -project "BEERUS Framework.xcodeproj" \
  -scheme "BEERUS Framework" \
  -configuration Debug \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 2: Fix any compilation errors**

If build fails, read errors and fix. Common issues:
- Missing `import Compression` in `AppStoreService.swift` or `IPAProcessor.swift`
- Type mismatches between tasks (verify `CDEntry` is consistently defined)
- Merge conflict markers still present in existing files

- [ ] **Step 3: Verify daemon compiles**

```bash
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=14.0 -O2 -Wall -lproc -framework CoreFoundation Daemon/BeerusDaemon.c -o /dev/null 2>&1
```

Expected: compiles with no errors (warnings OK)

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix(appstore): resolve build errors"
```
