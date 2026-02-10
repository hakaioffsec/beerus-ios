import Foundation

struct FridaRelease: Decodable {
    let tagName: String
    let name: String
    let publishedAt: String
    let prerelease: Bool
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let size: Int
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case size
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case publishedAt = "published_at"
        case prerelease
        case assets
    }

    /// The version string without the leading tag (e.g. "16.5.2")
    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    /// Formatted publish date
    var formattedDate: String {
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: publishedAt) else { return publishedAt }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }

    /// Filter assets matching the current device architecture (iOS)
    func assets(for arch: String) -> [Asset] {
        assets.filter {
            $0.name.contains("ios-\(arch)") ||
            $0.name.contains("ios_\(arch)") ||
            $0.name.contains("iphoneos-\(arch)")
        }
    }

    /// Find the best frida-server asset for the given architecture.
    /// Prefers the .deb package (iphoneos) since standalone ios binaries aren't published.
    func fridaServerAsset(for arch: String) -> Asset? {
        let matching = assets(for: arch)
        // .deb package: frida_VERSION_iphoneos-arm64.deb
        if let deb = matching.first(where: { $0.name.hasSuffix(".deb") && $0.name.hasPrefix("frida_") }) {
            return deb
        }
        // Fallback: standalone frida-server binary (other platforms)
        return matching.first(where: { $0.name.contains("frida-server") })
    }
}

enum FridaGitHubService {

    private static let releasesURL = "https://api.github.com/repos/frida/frida/releases"

    /// Downloads a Frida asset to a temporary file, reporting progress.
    /// Returns the local file path on success.
    static func downloadAsset(
        _ asset: FridaRelease.Asset,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) -> FridaDownloadTask {
        let task = FridaDownloadTask()
        guard let url = URL(string: asset.browserDownloadURL) else {
            completion(.failure(ServiceError.invalidURL))
            return task
        }

        let delegate = DownloadDelegate(
            expectedSize: Int64(asset.size),
            progress: progress,
            completion: completion
        )
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let downloadTask = session.downloadTask(with: url)
        task.urlTask = downloadTask
        downloadTask.resume()
        return task
    }

    static func fetchReleases(completion: @escaping (Result<[FridaRelease], Error>) -> Void) {
        guard let url = URL(string: releasesURL) else {
            completion(.failure(ServiceError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(ServiceError.noData))
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                completion(.failure(ServiceError.httpError(httpResponse.statusCode)))
                return
            }

            do {
                let releases = try JSONDecoder().decode([FridaRelease].self, from: data)
                completion(.success(releases))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    enum ServiceError: LocalizedError {
        case invalidURL
        case noData
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .noData: return "No data received"
            case .httpError(let code): return "HTTP error \(code)"
            }
        }
    }
}

// MARK: - Download Task Handle

final class FridaDownloadTask {
    var urlTask: URLSessionDownloadTask?

    func cancel() {
        urlTask?.cancel()
    }
}

// MARK: - Download Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let expectedSize: Int64
    private let progressHandler: (Double) -> Void
    private let completionHandler: (Result<String, Error>) -> Void

    init(expectedSize: Int64,
         progress: @escaping (Double) -> Void,
         completion: @escaping (Result<String, Error>) -> Void) {
        self.expectedSize = expectedSize
        self.progressHandler = progress
        self.completionHandler = completion
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Move from temp to a persistent temp location (URLSession deletes the file after this returns)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(downloadTask.response?.suggestedFilename ?? "frida-server.xz")

        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            completionHandler(.success(dest.path))
        } catch {
            completionHandler(.failure(error))
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        guard total > 0 else { return }
        progressHandler(Double(totalBytesWritten) / Double(total))
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            completionHandler(.failure(error))
            session.finishTasksAndInvalidate()
        }
    }
}
