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
            NSLog("[Requests] Invalid URL: \(urlTarget)")
            completion(.failure(URLError(.badURL)))
            return
        }

        NSLog("[Requests] Starting download from: \(urlTarget)")
        NSLog("[Requests] Destination path: \(destinationPath)")

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in

            if let error = error {
                NSLog("[Requests] Download error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                NSLog("[Requests] No HTTP response")
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            NSLog("[Requests] HTTP status: \(httpResponse.statusCode)")

            guard 200..<300 ~= httpResponse.statusCode, let tempURL = tempURL else {
                NSLog("[Requests] Bad status or no temp file")
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            NSLog("[Requests] Temp file at: \(tempURL.path)")

            // Verifica tamanho do arquivo baixado
            if let attrs = try? FileManager.default.attributesOfItem(atPath: tempURL.path),
               let size = attrs[.size] as? Int64 {
                NSLog("[Requests] Downloaded file size: \(size) bytes")
            }

            do {
                let fileManager = FileManager.default
                let destinationDir = URL(fileURLWithPath: destinationPath, isDirectory: true)

                NSLog("[Requests] Creating directory: \(destinationDir.path)")
                try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)

                let finalName = fileName ?? url.lastPathComponent
                let destinationURL = destinationDir.appendingPathComponent(finalName)

                NSLog("[Requests] Final destination: \(destinationURL.path)")

                if fileManager.fileExists(atPath: destinationURL.path) {
                    NSLog("[Requests] Removing existing file")
                    try fileManager.removeItem(at: destinationURL)
                }

                NSLog("[Requests] Moving file...")
                try fileManager.moveItem(at: tempURL, to: destinationURL)

                NSLog("[Requests] Success! File saved at: \(destinationURL.path)")
                completion(.success(destinationURL))

            } catch {
                NSLog("[Requests] File operation error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }

        task.resume()
    }
}
