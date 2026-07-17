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
