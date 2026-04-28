import Foundation

struct ProxyProfile: Codable, Equatable {
    let name: String
    let proxy: String
    var isEnabled: Bool
}

final class ProxyProfilesStorage {
    static let shared = ProxyProfilesStorage()

    private init() {}

    private var fileURL: URL {
        let fileManager = FileManager.default
        let appSupport = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let folder = appSupport.appendingPathComponent("BeerusFramework", isDirectory: true)

        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        return folder.appendingPathComponent("proxy_profiles.json")
    }

    func fetchProfiles() -> [ProxyProfile] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }

        return (try? JSONDecoder().decode([ProxyProfile].self, from: data)) ?? []
    }

    func saveProfiles(_ profiles: [ProxyProfile]) {
        if let data = try? JSONEncoder().encode(profiles) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    @discardableResult
    func addProfile(name: String, proxy: String) -> Bool {
        var profiles = fetchProfiles()

        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let proxy = proxy.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !proxy.isEmpty else { return false }

        if profiles.contains(where: { $0.name.lowercased() == name.lowercased() }) {
            return false
        }

        profiles.append(
            ProxyProfile(
                name: name,
                proxy: proxy,
                isEnabled: false
            )
        )

        saveProfiles(profiles)
        return true
    }

    func deleteProfile(named name: String) {
        var profiles = fetchProfiles()
        profiles.removeAll { $0.name == name }
        saveProfiles(profiles)
    }

    func setProfileEnabled(named name: String, enabled: Bool) {
        var profiles = fetchProfiles()

        for index in profiles.indices {
            if profiles[index].name == name {
                profiles[index].isEnabled = enabled
            } else if enabled {
                profiles[index].isEnabled = false
            }
        }

        saveProfiles(profiles)
    }

    func disableAllProfiles() {
        var profiles = fetchProfiles()

        for index in profiles.indices {
            profiles[index].isEnabled = false
        }

        saveProfiles(profiles)
    }
}