//
//  Requests.swift
//  BEERUS Framework
//
//  Created by Daniel França Lima on 09/02/26.
//
import Foundation

final class Requests {

    static func fetchData(
        urlTarget: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let url = URL(string: urlTarget)!

        URLSession.shared.dataTask(with: url) { data, response, error in

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode,
                  let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            let result = String(data: data, encoding: .utf8) ?? ""
            completion(.success(result))

        }.resume()
    }

    
    static func downloadFile(
        from urlTarget: String,
        fileName: String? = nil,
        destinationPath: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let url = URL(string: urlTarget) else {
            completion(.failure(URLError(.badURL)))
            return
        }

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode,
                  let tempURL = tempURL else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            do {
                let fileManager = FileManager.default
                let destinationDir = URL(fileURLWithPath: destinationPath, isDirectory: true)

                // ponytail: ensure destination directory exists
                try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)

                let finalName = fileName ?? url.lastPathComponent
                let destinationURL = destinationDir.appendingPathComponent(finalName)

                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }

                try fileManager.moveItem(at: tempURL, to: destinationURL)
                completion(.success(destinationURL))

            } catch {
                completion(.failure(error))
            }
        }

        task.resume()
    }
}
