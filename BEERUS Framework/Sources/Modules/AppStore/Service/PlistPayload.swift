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
