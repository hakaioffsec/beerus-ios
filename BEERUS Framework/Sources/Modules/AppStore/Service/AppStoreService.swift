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
