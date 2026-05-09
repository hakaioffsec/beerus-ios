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
