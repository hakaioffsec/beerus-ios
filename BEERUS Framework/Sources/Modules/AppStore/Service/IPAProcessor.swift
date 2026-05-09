import Foundation

enum IPAProcessor {

    static func applyPatches(metadata: [String: Any], account: AppStoreAccount,
                              sinfs: [SinfData], sourcePath: String,
                              destinationPath: String) throws {
        let sourceData = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
        let entries = try parseZipEntries(sourceData)

        let destURL = URL(fileURLWithPath: destinationPath)
        FileManager.default.createFile(atPath: destinationPath, contents: nil)
        let handle = try FileHandle(forWritingTo: destURL)
        defer { handle.closeFile() }

        var cdEntries: [CDEntry] = []

        for entry in entries {
            let offset = UInt32(handle.offsetInFile)
            handle.write(entry.localHeaderData)
            handle.write(entry.fileData)
            cdEntries.append(CDEntry(
                nameData: entry.nameData, crc: entry.crc,
                compressedSize: entry.compressedSize,
                uncompressedSize: entry.uncompressedSize,
                offset: offset, method: entry.method
            ))
        }

        var meta = metadata
        meta["apple-id"] = account.email
        meta["userName"] = account.email

        let metaPlistData = try PropertyListSerialization.data(
            fromPropertyList: meta, format: .binary, options: 0
        )
        let metaCRC = crc32(metaPlistData)
        let metaName = "iTunesMetadata.plist".data(using: .utf8)!
        let metaOffset = UInt32(handle.offsetInFile)

        handle.write(makeLocalHeader(
            name: metaName, crc: metaCRC,
            compressedSize: UInt32(metaPlistData.count),
            uncompressedSize: UInt32(metaPlistData.count), method: 0
        ))
        handle.write(metaPlistData)
        cdEntries.append(CDEntry(
            nameData: metaName, crc: metaCRC,
            compressedSize: UInt32(metaPlistData.count),
            uncompressedSize: UInt32(metaPlistData.count),
            offset: metaOffset, method: 0
        ))

        if !sinfs.isEmpty {
            let bundleName = findBundleName(in: entries)

            if let manifest = readManifestPlist(from: entries) {
                let sinfPaths = manifest["SinfPaths"] as? [String] ?? []
                for (sinf, path) in zip(sinfs, sinfPaths) {
                    let fullPath = "Payload/\(bundleName).app/\(path)"
                    writeSinfEntry(handle: handle, cdEntries: &cdEntries,
                                   path: fullPath, data: sinf.data)
                }
            } else if let info = readInfoPlist(from: entries) {
                let execName = info["CFBundleExecutable"] as? String ?? ""
                let fullPath = "Payload/\(bundleName).app/SC_Info/\(execName).sinf"
                writeSinfEntry(handle: handle, cdEntries: &cdEntries,
                               path: fullPath, data: sinfs[0].data)
            }
        }

        let cdOffset = handle.offsetInFile
        for entry in cdEntries {
            handle.write(makeCentralDirEntry(entry))
        }

        var eocd = Data(capacity: 22)
        eocd.appendZipU32(0x06054b50)
        eocd.appendZipU16(0); eocd.appendZipU16(0)
        eocd.appendZipU16(UInt16(cdEntries.count))
        eocd.appendZipU16(UInt16(cdEntries.count))
        eocd.appendZipU32(UInt32(handle.offsetInFile - cdOffset))
        eocd.appendZipU32(UInt32(cdOffset))
        eocd.appendZipU16(0)
        handle.write(eocd)
    }

    // MARK: - ZIP Parsing

    private struct ZipEntry {
        let nameData: Data
        let name: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderData: Data
        let fileData: Data
    }

    private static func parseZipEntries(_ data: Data) throws -> [ZipEntry] {
        var entries: [ZipEntry] = []
        var pos = 0

        while pos + 30 <= data.count {
            guard data[pos] == 0x50, data[pos+1] == 0x4b,
                  data[pos+2] == 0x03, data[pos+3] == 0x04 else { break }

            let method = readU16(data, pos + 8)
            let crc = readU32(data, pos + 14)
            let compSize = readU32(data, pos + 18)
            let uncompSize = readU32(data, pos + 22)
            let nameLen = Int(readU16(data, pos + 26))
            let extraLen = Int(readU16(data, pos + 28))

            let headerSize = 30 + nameLen + extraLen
            guard pos + headerSize + Int(compSize) <= data.count else { break }

            let nameData = data.subdata(in: (pos + 30)..<(pos + 30 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? ""
            let localHeaderData = data.subdata(in: pos..<(pos + headerSize))
            let fileData = data.subdata(in: (pos + headerSize)..<(pos + headerSize + Int(compSize)))

            entries.append(ZipEntry(
                nameData: nameData, name: name, method: method,
                crc: crc, compressedSize: compSize,
                uncompressedSize: uncompSize,
                localHeaderData: localHeaderData, fileData: fileData
            ))

            pos += headerSize + Int(compSize)
        }

        return entries
    }

    private static func findBundleName(in entries: [ZipEntry]) -> String {
        for entry in entries {
            if entry.name.contains(".app/Info.plist") && !entry.name.contains("/Watch/") {
                let appComponent = entry.name.split(separator: "/")
                    .first(where: { $0.hasSuffix(".app") })
                if let app = appComponent {
                    return String(app.dropLast(4))
                }
            }
        }
        return ""
    }

    private static func readManifestPlist(from entries: [ZipEntry]) -> [String: Any]? {
        for entry in entries {
            guard entry.name.hasSuffix(".app/SC_Info/Manifest.plist") else { continue }
            let raw = entry.method == 8 ? entry.fileData.decompress() : entry.fileData
            guard let data = raw else { continue }
            return try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any]
        }
        return nil
    }

    private static func readInfoPlist(from entries: [ZipEntry]) -> [String: Any]? {
        for entry in entries {
            guard entry.name.contains(".app/Info.plist") else { continue }
            let raw = entry.method == 8 ? entry.fileData.decompress() : entry.fileData
            guard let data = raw else { continue }
            return try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any]
        }
        return nil
    }

    private static func writeSinfEntry(handle: FileHandle,
                                        cdEntries: inout [CDEntry],
                                        path: String, data: Data) {
        let nameData = path.data(using: .utf8)!
        let crc = crc32(data)
        let offset = UInt32(handle.offsetInFile)

        handle.write(makeLocalHeader(
            name: nameData, crc: crc,
            compressedSize: UInt32(data.count),
            uncompressedSize: UInt32(data.count), method: 0
        ))
        handle.write(data)

        cdEntries.append(CDEntry(nameData: nameData, crc: crc,
                          compressedSize: UInt32(data.count),
                          uncompressedSize: UInt32(data.count),
                          offset: offset, method: 0))
    }

    // MARK: - ZIP Structures

    private static func makeLocalHeader(name: Data, crc: UInt32, compressedSize: UInt32,
                                         uncompressedSize: UInt32, method: UInt16) -> Data {
        var h = Data(capacity: 30 + name.count)
        h.appendZipU32(0x04034b50)
        h.appendZipU16(20); h.appendZipU16(0); h.appendZipU16(method)
        h.appendZipU16(0); h.appendZipU16(0)
        h.appendZipU32(crc)
        h.appendZipU32(compressedSize); h.appendZipU32(uncompressedSize)
        h.appendZipU16(UInt16(name.count)); h.appendZipU16(0)
        h.append(name)
        return h
    }

    private struct CDEntry {
        let nameData: Data, crc: UInt32, compressedSize: UInt32
        let uncompressedSize: UInt32, offset: UInt32, method: UInt16
    }

    private static func makeCentralDirEntry(_ e: CDEntry) -> Data {
        var cd = Data(capacity: 46 + e.nameData.count)
        cd.appendZipU32(0x02014b50)
        cd.appendZipU16(20); cd.appendZipU16(20)
        cd.appendZipU16(0); cd.appendZipU16(e.method)
        cd.appendZipU16(0); cd.appendZipU16(0)
        cd.appendZipU32(e.crc)
        cd.appendZipU32(e.compressedSize); cd.appendZipU32(e.uncompressedSize)
        cd.appendZipU16(UInt16(e.nameData.count))
        cd.appendZipU16(0); cd.appendZipU16(0); cd.appendZipU16(0); cd.appendZipU16(0)
        cd.appendZipU32(0)
        cd.appendZipU32(e.offset)
        cd.append(e.nameData)
        return cd
    }

    // MARK: - Helpers

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset+1]) << 8)
            | (UInt32(data[offset+2]) << 16) | (UInt32(data[offset+3]) << 24)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ (crc & 1 != 0 ? 0xEDB88320 : 0)
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendZipU16(_ v: UInt16) {
        var x = v.littleEndian
        append(Data(bytes: &x, count: 2))
    }
    mutating func appendZipU32(_ v: UInt32) {
        var x = v.littleEndian
        append(Data(bytes: &x, count: 4))
    }
}
