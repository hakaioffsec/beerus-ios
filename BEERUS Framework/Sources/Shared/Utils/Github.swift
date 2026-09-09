//
//  FridaVersions.swift
//  BEERUS Framework
//
//  Created by Daniel França Lima on 09/02/26.
//

import Foundation


final class Github {

    private struct Release: Decodable {
        let tag_name: String
        let prerelease: Bool
        let draft: Bool
    }

    /// Lists real, installable release tags — excludes drafts and pre-releases (e.g. the
    /// "<version>-barebone.<n>" CI build tags frida/frida publishes constantly, which don't ship
    /// a frida-server .deb and would just 404 the download if selected). Uses the GitHub REST API
    /// instead of scraping the releases HTML page, which broke every time GitHub tweaked markup
    /// and had no way to tell CI prerelease noise apart from real releases.
    static func getReleaseVersions(repository: String, completion: @escaping ([String]) -> Void) {
        var versions: [String] = ["Add version manually"]

        Requests.fetchData(urlTarget: "https://api.github.com/repos/\(repository)/releases?per_page=50") { result in
            switch result {
            case .success(let data):
                guard let jsonData = data.data(using: .utf8),
                      let releases = try? JSONDecoder().decode([Release].self, from: jsonData) else {
                    completion(versions)
                    return
                }

                let tags = releases
                    .filter { !$0.draft && !$0.prerelease }
                    .map { $0.tag_name }

                versions.append(contentsOf: tags)
                completion(versions)
            case .failure(let error):
                print("Error:", error)
                completion(versions)
            }
        }
    }

    static func verifyVersion(
        repository: String,
        version: String,
        completion: @escaping (Bool) -> Void
    ) {
        let encodedVersion = version.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? version
        let url = "https://api.github.com/repos/\(repository)/releases/tags/\(encodedVersion)"

        Requests.fetchData(urlTarget: url) { result in
            switch result {
            case .success(let data):
                guard let jsonData = data.data(using: .utf8),
                      let release = try? JSONDecoder().decode(Release.self, from: jsonData) else {
                    completion(false)
                    return
                }
                completion(!release.draft)

            case .failure(let error):
                print("Error:", error)
                completion(false)
            }
        }
    }

}
