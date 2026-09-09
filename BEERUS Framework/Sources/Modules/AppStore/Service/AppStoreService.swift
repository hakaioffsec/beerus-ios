import Compression
import Foundation
import UIKit

final class AppStoreService {

    static let shared = AppStoreService()

    private let userAgent = "Configurator/2.17 (Macintosh; OS X 15.2; 24C5089c) AppleWebKit/0620.1.16.11.6"

    // ponytail: shared cookie storage so auth cookies flow to purchase/download
    private let sharedCookieStorage = HTTPCookieStorage.shared

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = sharedCookieStorage
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Constants

    private let iTunesDomain = "itunes.apple.com"
    private let initDomain = "init.itunes.apple.com"
    private let buyDomain = "buy.itunes.apple.com"
    private let purchasePath = "/WebObjects/MZFinance.woa/wa/buyProduct"
    private let downloadPath = "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"
    private let defaultAuthEndpoint = "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/authenticate"

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
        // ponytail: ipatool uses MAC address format (12 uppercase hex chars)
        let uuid = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let clean = uuid.replacingOccurrences(of: "-", with: "").uppercased()
        return String(clean.prefix(12))
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
        // ponytail: ipatool sends guid param on bag request
        let guid = getGUID()
        let url = URL(string: "https://\(initDomain)/bag.xml?guid=\(guid)")!

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/xml", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppStoreError.bagFailed("unexpected status code")
        }

        let plistData = extractPlistFromXML(data) ?? data

        guard let plist = try? PlistPayload.decode(plistData) else {
            return defaultAuthEndpoint
        }

        if let urlBag = plist["urlBag"] as? [String: Any],
           let authEndpoint = urlBag["authenticateAccount"] as? String,
           !authEndpoint.isEmpty {
            return authEndpoint
        }

        return defaultAuthEndpoint
    }

    private func extractPlistFromXML(_ data: Data) -> Data? {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        guard let startRange = xml.range(of: "<plist"),
              let endRange = xml.range(of: "</plist>") else { return nil }
        let plistString = String(xml[startRange.lowerBound..<endRange.upperBound])
        return plistString.data(using: .utf8)
    }

    // MARK: - Login

    private lazy var authSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = sharedCookieStorage
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        let session = URLSession(configuration: config, delegate: AuthRedirectBlocker.shared, delegateQueue: nil)
        return session
    }()

    func login(email: String, password: String, authCode: String = "") async throws -> AppStoreAccount {
        let guid = getGUID()
        var endpoint = try await fetchBag()

        // ponytail: ipatool requires trailing slash for /native/ auth endpoints
        if endpoint.contains("/native/") && !endpoint.hasSuffix("/") {
            endpoint += "/"
        }

        var redirect: String? = nil
        var lastResponse: (data: Data, http: HTTPURLResponse)?
        var hadInvalidCredentials = false  // ponytail: track if we already got -5000

        for attempt in 1...4 {
            var url: String = redirect ?? endpoint
            redirect = nil

            // ponytail: ipatool requires trailing slash for /native/ auth endpoints
            if url.contains("/native/") && !url.hasSuffix("/") {
                url += "/"
            }

            let payload = PlistPayload.buildLoginPayload(
                email: email, password: password,
                authCode: authCode, guid: guid, attempt: attempt
            )
            // ponytail: login uses form-urlencoded body, not plist
            let body = PlistPayload.encodeFormData(payload)

            #if DEBUG
            NSLog("[AppStore] === Login Attempt %d ===", attempt)
            NSLog("[AppStore] URL: %@", url)
            NSLog("[AppStore] GUID: %@", guid)
            NSLog("[AppStore] Payload keys: %@", payload.keys.joined(separator: ", "))
            #endif

            guard let requestURL = URL(string: url) else {
                throw AppStoreError.loginFailed("invalid auth URL")
            }
            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = body

            let (data, response) = try await authSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw AppStoreError.loginFailed("invalid response")
            }

            lastResponse = (data, http)

            #if DEBUG
            NSLog("[AppStore] Status: %d", http.statusCode)
            NSLog("[AppStore] Headers: %@", http.allHeaderFields)
            #endif
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "(binary \(data.count) bytes)"
            #if DEBUG
            NSLog("[AppStore] Body preview: %@", preview)
            #endif

            if http.statusCode == 302 || http.statusCode == 301 {
                let location = http.value(forHTTPHeaderField: "Location")
                    ?? http.value(forHTTPHeaderField: "location")
                    ?? http.allHeaderFields["Location"] as? String
                    ?? http.allHeaderFields["location"] as? String
                #if DEBUG
                NSLog("[AppStore] Redirect location: %@", location ?? "NIL")
                #endif
                guard let loc = location, !loc.isEmpty else {
                    let headers = http.allHeaderFields.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                    throw AppStoreError.loginFailed("redirect \(http.statusCode) without location. Headers: \(headers.prefix(500))")
                }
                redirect = loc
                continue
            }

            if data.isEmpty || http.statusCode >= 500 {
                throw AppStoreError.loginFailed("HTTP \(http.statusCode): \(preview)")
            }

            let plist = try PlistPayload.decode(data)
            #if DEBUG
            NSLog("[AppStore] === Plist Response ===")
            NSLog("[AppStore] Keys: %@", plist.keys.joined(separator: ", "))
            for (key, value) in plist {
                let valueStr = String("\(value)".prefix(200))
                NSLog("[AppStore] %@ = %@", key, valueStr)
            }
            #endif
            let failureType = plist["failureType"] as? String ?? ""
            let customerMessage = plist["customerMessage"] as? String ?? ""
            // ponytail: always log for debugging login issues
            NSLog("[AppStore] failureType: '%@'", failureType)
            NSLog("[AppStore] customerMessage: '%@'", customerMessage)
            NSLog("[AppStore] All keys: %@", plist.keys.joined(separator: ", "))

            // ponytail: -5000 = invalid credentials, never retry more than once
            if failureType == failureInvalidCredentials {
                hadInvalidCredentials = true
                if attempt == 1 && authCode.isEmpty {
                    #if DEBUG
                    NSLog("[AppStore] Attempt 1 with -5000, retrying...")
                    #endif
                    continue
                }
                // ponytail: still -5000 on attempt 2+ = wrong password, not MFA
                throw AppStoreError.loginFailed("Invalid email or password")
            }

            // ponytail: MFA required when Apple returns auth continuation keys
            let authType = plist["authType"] as? String ?? ""
            let hasMFAIndicators = authType.lowercased().contains("hsa")
                || plist["trustedDeviceCount"] != nil
                || plist["b"] != nil  // SRP protocol
                || plist["c"] != nil
                || plist["iteration"] != nil

            if failureType.isEmpty && authCode.isEmpty && customerMessage == customerMessageBadLogin {
                if hadInvalidCredentials {
                    NSLog("[AppStore] Had -5000 before, this is invalid credentials not MFA")
                    throw AppStoreError.loginFailed("Invalid email or password")
                }
                if !hasMFAIndicators {
                    NSLog("[AppStore] No MFA indicators (authType='%@'), wrong password", authType)
                    throw AppStoreError.loginFailed("Invalid email or password")
                }
                NSLog("[AppStore] >>> MFA REQUIRED (authType='%@') - throwing authCodeRequired <<<", authType)
                throw AppStoreError.authCodeRequired
            }

            if customerMessage == customerMessageDisabled {
                throw AppStoreError.accountDisabled
            }

            if !failureType.isEmpty {
                let msg = customerMessage.isEmpty ? "something went wrong" : customerMessage
                throw AppStoreError.loginFailed(msg)
            }

            guard let passwordToken = plist["passwordToken"] as? String, !passwordToken.isEmpty else {
                throw AppStoreError.loginFailed("missing token")
            }
            // ponytail: ipatool uses DirectoryServicesID, some responses use dsPersonId
            let dsid = (plist["DirectoryServicesID"] as? String)
                ?? (plist["dsPersonId"] as? String)
                ?? (plist["directoryServicesIdentifier"] as? String)
            guard let dsid = dsid, !dsid.isEmpty else {
                throw AppStoreError.loginFailed("missing dsid")
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

        #if DEBUG
        // ponytail: log first result's icon URL for debugging gray icons
        if let first = results.first {
            NSLog("[AppStore] First result icon URL: %@", (first["artworkUrl100"] as? String) ?? "nil")
        }
        #endif

        return results.compactMap { dict in
            guard let id = dict["trackId"] as? Int64 ?? (dict["trackId"] as? Int).map(Int64.init),
                  let bundleID = dict["bundleId"] as? String,
                  let name = dict["trackName"] as? String else { return nil }
            let iconURL = dict["artworkUrl100"] as? String
                ?? dict["artworkUrl60"] as? String
                ?? dict["artworkUrl512"] as? String
            return AppStoreApp(
                id: id,
                bundleID: bundleID,
                name: name,
                version: dict["version"] as? String ?? "",
                price: dict["price"] as? Double ?? (dict["price"] as? Int).map(Double.init) ?? 0,
                iconURL: iconURL
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
            price: first["price"] as? Double ?? 0,
            iconURL: first["artworkUrl100"] as? String ?? first["artworkUrl60"] as? String
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

        let (data, response) = try await session.data(for: request)

        // ponytail: check status before parsing - redirects/errors return HTML, not plist
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "(binary)"
            throw AppStoreError.purchaseFailed("HTTP \(http.statusCode): \(preview)")
        }

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

        // ponytail: sanitize filename - remove chars that break shell commands
        let safeBundleID = app.bundleID.replacingOccurrences(of: "'", with: "")
        let safeVersion = version
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let fileName = "\(safeBundleID)_\(app.id)_\(safeVersion).ipa"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let destination = docs.appendingPathComponent(fileName).path

        // Unique per invocation so two concurrent downloads of the same bundleID/version don't race
        // on the same working file.
        let tmpPath = destination + ".\(UUID().uuidString.prefix(8)).tmp"
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
        // ponytail: ipatool requires X-Dsid header for download auth
        request.setValue(account.directoryServicesID, forHTTPHeaderField: "X-Dsid")
        request.setValue(account.storeFront, forHTTPHeaderField: "X-Apple-Store-Front")
        request.setValue(account.passwordToken, forHTTPHeaderField: "X-Token")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        // ponytail: check status before parsing - redirects/errors return HTML, not plist
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "(binary)"
            throw AppStoreError.downloadFailed("HTTP \(http.statusCode): \(preview)")
        }

        let plist = try PlistPayload.decode(data)

        let failureType = plist["failureType"] as? String ?? ""
        let customerMessage = plist["customerMessage"] as? String ?? ""

        if failureType == failureTokenExpired || failureType == failureSignInRequired
            || failureType == failureDeviceVerification {
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

    /// Reports incremental progress via URLSessionDownloadDelegate — `download(from:)` only calls back
    /// once, after the whole transfer finishes, which leaves the UI frozen at 0% for the entire download.
    private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
        private let progress: ((Int64, Int64) -> Void)?
        var continuation: CheckedContinuation<URL, Error>?
        private var didResume = false

        init(progress: ((Int64, Int64) -> Void)?) {
            self.progress = progress
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                         didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                         totalBytesExpectedToWrite: Int64) {
            progress?(totalBytesWritten, totalBytesExpectedToWrite)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                         didFinishDownloadingTo location: URL) {
            guard !didResume else { return }
            didResume = true
            // `location` is deleted as soon as this method returns, so claim it first.
            let ownedURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.moveItem(at: location, to: ownedURL)
                continuation?.resume(returning: ownedURL)
            } catch {
                continuation?.resume(throwing: error)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error, !didResume else { return }
            didResume = true
            continuation?.resume(throwing: error)
        }
    }

    private func downloadFile(from urlString: String, to path: String,
                               progress: ((Int64, Int64) -> Void)?) async throws {
        guard let url = URL(string: urlString) else {
            throw AppStoreError.downloadFailed("invalid download URL")
        }

        let delegate = DownloadProgressDelegate(progress: progress)
        let dlSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { dlSession.finishTasksAndInvalidate() }

        let tempURL: URL = try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            dlSession.downloadTask(with: url).resume()
        }

        let fileURL = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.moveItem(at: tempURL, to: fileURL)

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        progress?(fileSize, fileSize)
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
        guard let url = URL(string: urlString) else {
            throw AppStoreError.metadataFailed("invalid URL")
        }

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

        guard let cdInfo = findCentralDirectory(in: tailData, tailOffset: tailStart) else {
            throw AppStoreError.metadataFailed("cannot find ZIP central directory")
        }

        var cdReq = URLRequest(url: url)
        cdReq.httpMethod = "GET"
        cdReq.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        cdReq.setValue("bytes=\(cdInfo.offset)-\(cdInfo.offset + cdInfo.size - 1)", forHTTPHeaderField: "Range")

        let (cdData, cdResp) = try await session.data(for: cdReq)
        guard let cdHTTP = cdResp as? HTTPURLResponse, cdHTTP.statusCode == 206 else {
            throw AppStoreError.metadataFailed("failed to read central directory")
        }

        guard let plistEntry = findInfoPlistEntry(in: cdData) else {
            throw AppStoreError.metadataFailed("Info.plist not found in ZIP")
        }

        let readEnd = plistEntry.localHeaderOffset + Int64(30 + plistEntry.nameLength + plistEntry.compressedSize + 1024)
        var plistReq = URLRequest(url: url)
        plistReq.httpMethod = "GET"
        plistReq.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        plistReq.setValue("bytes=\(plistEntry.localHeaderOffset)-\(min(readEnd, totalSize - 1))", forHTTPHeaderField: "Range")

        let (plistData, plistResp) = try await session.data(for: plistReq)
        guard let plistHTTP = plistResp as? HTTPURLResponse, plistHTTP.statusCode == 206 else {
            throw AppStoreError.metadataFailed("failed to read Info.plist data")
        }

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
}

private final class AuthRedirectBlocker: NSObject, URLSessionTaskDelegate {
    static let shared = AuthRedirectBlocker()

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // ponytail: ipatool blocks redirects when current request Referer equals auth URL
        // Use currentRequest (the one being redirected FROM), not originalRequest
        let currentURL = task.currentRequest?.url?.absoluteString ?? ""
        // Block redirects from auth endpoints (buy.itunes.apple.com auth paths)
        if currentURL.contains("buy.itunes.apple.com") && currentURL.contains("/wa/authenticate") {
            completionHandler(nil)
        } else {
            completionHandler(request)
        }
    }
}

// ponytail: Data.decompress() now in ZipArchive.swift
