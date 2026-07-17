import Foundation

enum PlistPayload {

    static func encode(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: dict,
            format: .xml,
            options: 0
        )
    }

    // ponytail: login uses form-urlencoded, not plist
    // ponytail: RFC 3986 encoding - urlQueryAllowed doesn't escape + = & which corrupt form data
    private static let formSafeChars: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return cs
    }()

    static func encodeFormData(_ dict: [String: Any]) -> Data {
        dict.map { key, value in
            let k = "\(key)".addingPercentEncoding(withAllowedCharacters: formSafeChars) ?? "\(key)"
            let v = "\(value)".addingPercentEncoding(withAllowedCharacters: formSafeChars) ?? "\(value)"
            return "\(k)=\(v)"
        }.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    static func decode(_ data: Data) throws -> [String: Any] {
        let normalized = normalizePlistData(data)
        do {
            guard let plist = try PropertyListSerialization.propertyList(
                from: normalized, options: [], format: nil
            ) as? [String: Any] else {
                let preview = String(data: normalized.prefix(500), encoding: .utf8) ?? "binary"
                throw AppStoreError.downloadFailed("not a dict plist. Preview: \(preview)")
            }
            return plist
        } catch let error as AppStoreError {
            throw error
        } catch {
            let preview = String(data: normalized.prefix(500), encoding: .utf8) ?? "binary"
            throw AppStoreError.downloadFailed("plist parse error: \(error.localizedDescription). Preview: \(preview)")
        }
    }

    private static func normalizePlistData(_ data: Data) -> Data {
        guard let xml = String(data: data, encoding: .utf8) else { return data }
        if let plistRange = xml.range(of: "<plist"),
           let endRange = xml.range(of: "</plist>") {
            let plistString = String(xml[plistRange.lowerBound..<endRange.upperBound])
            if let plistData = plistString.data(using: .utf8) {
                return plistData
            }
        }
        if xml.contains("<dict>") && !xml.contains("<plist") {
            let wrapped = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\">\(xml)</plist>"
            if let wrappedData = wrapped.data(using: .utf8) {
                return wrappedData
            }
        }
        return data
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
