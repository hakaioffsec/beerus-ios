import Foundation

struct VersionMetadata {
    let displayVersion: String
    let releaseDate: Date
}

struct VersionListResult {
    let identifiers: [String]
    let latestID: String
}
