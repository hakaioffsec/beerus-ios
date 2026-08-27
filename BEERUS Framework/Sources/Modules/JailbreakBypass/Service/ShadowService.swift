import Foundation

// MARK: - Models

struct ShadowRelease {
    let version: String
    let downloadURL: String
}

// MARK: - Service

final class ShadowService {
    static let shared = ShadowService()

    // MARK: - Constants

    private enum Constants {
        static let releasesAPI = "https://api.github.com/repos/jjolano/shadow/releases"
        static let prefsPath = "/var/mobile/Library/Preferences/me.jjolano.shadow.plist"
        static let tempDebPath = "/var/tmp/shadow.deb"
        static let tempPrefsPath = "/var/tmp/shadow_prefs.plist"
        static let dpkgPath = "/var/jb/usr/bin/dpkg"
        static let packageId = "me.jjolano.shadow"
        static let installPaths = [
            "/var/jb/Library/MobileSubstrate/DynamicLibraries/Shadow.dylib",
            "/Library/MobileSubstrate/DynamicLibraries/Shadow.dylib"
        ]
    }

    // MARK: - Properties

    private(set) var availableReleases: [ShadowRelease] = []
    private(set) var selectedRelease: ShadowRelease?

    private init() {}

    // MARK: - Public Methods

    func selectRelease(_ release: ShadowRelease) {
        selectedRelease = release
    }

    var isInstalled: Bool {
        Constants.installPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Fetch Releases

    func fetchReleases(completion: @escaping (Result<[ShadowRelease], Error>) -> Void) {
        guard let url = URL(string: Constants.releasesAPI) else {
            completion(.failure(ShadowError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(ShadowError.downloadFailed)) }
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    DispatchQueue.main.async { completion(.failure(ShadowError.parseError)) }
                    return
                }

                var releases: [ShadowRelease] = []

                for release in json {
                    guard let tagName = release["tag_name"] as? String,
                          tagName.hasPrefix("v"),
                          let assets = release["assets"] as? [[String: Any]] else { continue }

                    for asset in assets {
                        guard let name = asset["name"] as? String,
                              name.hasSuffix(".deb"),
                              name.contains("arm64"),
                              let downloadURL = asset["browser_download_url"] as? String else { continue }

                        releases.append(ShadowRelease(version: tagName, downloadURL: downloadURL))
                        break
                    }
                }

                DispatchQueue.main.async {
                    self?.availableReleases = releases
                    if self?.selectedRelease == nil, let first = releases.first {
                        self?.selectedRelease = first
                    }
                    completion(.success(releases))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    // MARK: - Install Shadow

    func install(progress: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let release = selectedRelease else {
            completion(.failure(ShadowError.installFailed("No version selected")))
            return
        }

        progress("Downloading Shadow \(release.version)...")

        guard let url = URL(string: release.downloadURL) else {
            completion(.failure(ShadowError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 120

        let task = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(ShadowError.installFailed("Download: \(error.localizedDescription)")))
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                DispatchQueue.main.async {
                    completion(.failure(ShadowError.installFailed("HTTP \(httpResponse.statusCode)")))
                }
                return
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async { completion(.failure(ShadowError.downloadFailed)) }
                return
            }

            DispatchQueue.main.async { progress("Installing...") }

            do {
                let data = try Data(contentsOf: tempURL)
                try data.write(to: URL(fileURLWithPath: Constants.tempDebPath))

                let result = RootExec.exec("\(Constants.dpkgPath) -i '\(Constants.tempDebPath)' 2>&1")
                _ = RootExec.exec("rm -f '\(Constants.tempDebPath)'")

                DispatchQueue.main.async {
                    if self.isInstalled {
                        progress("Shadow installed!")
                        completion(.success(()))
                    } else {
                        completion(.failure(ShadowError.installFailed(result ?? "dpkg failed")))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(ShadowError.installFailed(error.localizedDescription)))
                }
            }
        }
        task.resume()
    }

    // MARK: - Uninstall

    func uninstall(completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = RootExec.exec("\(Constants.dpkgPath) -r \(Constants.packageId) 2>&1")

            DispatchQueue.main.async {
                if self?.isInstalled == false {
                    completion(.success(()))
                } else {
                    completion(.failure(ShadowError.uninstallFailed(result ?? "Unknown error")))
                }
            }
        }
    }

    // MARK: - Per-App Configuration

    func getEnabledApps() -> [String] {
        guard let data = FileManager.default.contents(atPath: Constants.prefsPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let apps = plist["Apps"] as? [String: Any] else {
            return []
        }

        return apps.compactMap { bundleId, config in
            guard let config = config as? [String: Any],
                  let enabled = config["Enabled"] as? Bool,
                  enabled else { return nil }
            return bundleId
        }
    }

    func enableBypass(for bundleId: String) -> Bool {
        modifyAppConfig(bundleId: bundleId, enabled: true)
    }

    func disableBypass(for bundleId: String) -> Bool {
        modifyAppConfig(bundleId: bundleId, enabled: false)
    }

    private func modifyAppConfig(bundleId: String, enabled: Bool) -> Bool {
        var plist: [String: Any]
        if let data = FileManager.default.contents(atPath: Constants.prefsPath),
           let existing = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            plist = existing
        } else {
            plist = ["Global_Enabled": true, "Apps": [:]]
        }

        var apps = plist["Apps"] as? [String: Any] ?? [:]
        if enabled {
            apps[bundleId] = ["Enabled": true]
        } else {
            apps.removeValue(forKey: bundleId)
        }
        plist["Apps"] = apps
        plist["Global_Enabled"] = true

        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return false
        }

        do {
            try data.write(to: URL(fileURLWithPath: Constants.tempPrefsPath))
            let result = RootExec.exec("cp '\(Constants.tempPrefsPath)' '\(Constants.prefsPath)' && chmod 644 '\(Constants.prefsPath)' && chown mobile:mobile '\(Constants.prefsPath)'")
            try? FileManager.default.removeItem(atPath: Constants.tempPrefsPath)
            return result != nil
        } catch {
            return false
        }
    }

    // MARK: - Respring

    func respring() {
        _ = RootExec.exec("killall -9 SpringBoard")
    }
}

// MARK: - Errors

enum ShadowError: LocalizedError {
    case invalidURL
    case downloadFailed
    case parseError
    case installFailed(String)
    case uninstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .downloadFailed:
            return "Download failed"
        case .parseError:
            return "Failed to parse response"
        case .installFailed(let message):
            return "Install failed: \(message)"
        case .uninstallFailed(let message):
            return "Uninstall failed: \(message)"
        }
    }
}
