//
//  FridaVersions.swift
//  BEERUS Framework
//
//  Created by Daniel França Lima on 09/02/26.
//

import Foundation


final class Github {

    static func getReleaseVersions(repository: String, completion: @escaping ([String]) -> Void) {
        var versions: [String] = ["Add version manually"]
        
        Requests.fetchData(urlTarget: "https://github.com/\(repository)/releases?page=1") { result in
            switch result {
            case .success(let data):
                print(data)
                
                let result = data
                    .components(separatedBy: .newlines)
                    .filter { $0.contains("\(repository)/tree/") }
                
                for version in result {
                    
                    if let range = version.range(of: "\(repository)/tree/") {
                        let start = range.upperBound
                        let rest = version[start...]
                        
                        if let end = rest.firstIndex(of: "\"") {
                            let version = String(rest[..<end])
                            versions.append(version)
                        }
                    }
                }
                
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
        let url = "https://github.com/\(repository)/tree/\(encodedVersion)"

        Requests.fetchData(urlTarget: url) { result in
            switch result {
            case .success(let data):
                let isValid = data.contains("\(repository) at \(version)")
                completion(isValid)

            case .failure(let error):
                print("Error:", error)
                completion(false)
            }
        }
    }

}
