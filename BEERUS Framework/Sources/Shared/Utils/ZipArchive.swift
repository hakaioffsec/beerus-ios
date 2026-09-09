import Foundation
import Compression
import zlib

enum ZipArchive {

    private static let chunkSize = 4 * 1024 * 1024 // 4MB chunks to avoid OOM

    static func create(at zipPath: URL, from sourceDir: URL, root: String = "", progress: ((Int, Int) -> Void)? = nil) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sourceDir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey]) else {
            throw ZipError.cannotEnumerate
        }

        var entries: [(url: URL, relativePath: String, isDirectory: Bool)] = []
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let relative = url.path.replacingOccurrences(of: sourceDir.path + "/", with: "")
            let fullPath = root.isEmpty ? relative : "\(root)/\(relative)"
            entries.append((url, isDir ? fullPath + "/" : fullPath, isDir))
        }

        fm.createFile(atPath: zipPath.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: zipPath.path) else {
            throw ZipError.cannotEnumerate
        }
        defer { handle.closeFile() }

        struct CDEntry {
            let nameData: Data, crc: UInt32, compressedSize: UInt32
            let uncompressedSize: UInt32, offset: UInt32, isDir: Bool, method: UInt16
        }

        var cdEntries: [CDEntry] = []

        for (i, entry) in entries.enumerated() {
            if (i + 1) % 100 == 0 || (i + 1) == entries.count {
                progress?(i + 1, entries.count)
            }

            let nameData = entry.relativePath.data(using: .utf8)!
            let offset = UInt32(handle.offsetInFile)

            if entry.isDirectory {
                handle.write(makeLocalHeader(name: nameData, crc: 0, compressedSize: 0,
                                             uncompressedSize: 0, method: 0))
                cdEntries.append(CDEntry(nameData: nameData, crc: 0, compressedSize: 0,
                                         uncompressedSize: 0, offset: offset, isDir: true, method: 0))
                continue
            }

            guard let fh = FileHandle(forReadingAtPath: entry.url.path) else { continue }
            defer { fh.closeFile() }

            // Compute CRC32 in chunks (don't load entire file)
            let crc = crc32Chunked(handle: fh)
            fh.seek(toFileOffset: 0)

            let fileSize = fh.seekToEndOfFile()
            fh.seek(toFileOffset: 0)

            // Try deflate compression for files > 512 bytes
            let (compressedData, method): (Data, UInt16)
            if fileSize > 512 {
                let deflated = deflateChunked(handle: fh)
                // Only use compression if it actually saves space
                if deflated.count < fileSize {
                    (compressedData, method) = (deflated, 8) // method 8 = deflate
                } else {
                    fh.seek(toFileOffset: 0)
                    (compressedData, method) = (readChunked(handle: fh), 0) // store
                }
            } else {
                (compressedData, method) = (readChunked(handle: fh), 0)
            }

            handle.write(makeLocalHeader(name: nameData, crc: crc,
                                          compressedSize: UInt32(compressedData.count),
                                          uncompressedSize: UInt32(fileSize), method: method))
            handle.write(compressedData)

            cdEntries.append(CDEntry(nameData: nameData, crc: crc,
                                      compressedSize: UInt32(compressedData.count),
                                      uncompressedSize: UInt32(fileSize),
                                      offset: offset, isDir: false, method: method))
        }

        let cdOffset = UInt64(handle.offsetInFile)
        cdEntries.forEach {
            handle.write(makeCentralDirEntry($0.nameData, $0.crc, $0.compressedSize,
                                              $0.uncompressedSize, $0.offset, $0.isDir, $0.method))
        }

        var eocd = Data(capacity: 22)
        eocd.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])
        eocd.append(u16: 0); eocd.append(u16: 0)
        eocd.append(u16: UInt16(cdEntries.count)); eocd.append(u16: UInt16(cdEntries.count))
        eocd.append(u32: UInt32(UInt64(handle.offsetInFile) - cdOffset))
        eocd.append(u32: UInt32(cdOffset))
        eocd.append(u16: 0)
        handle.write(eocd)
    }

    // MARK: - Chunked I/O

    private static func readChunked(handle: FileHandle) -> Data {
        var result = Data()
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            result.append(chunk)
        }
        return result
    }

    private static func crc32Chunked(handle: FileHandle) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            chunk.withUnsafeBytes { buffer in
                for byte in buffer {
                    crc ^= UInt32(byte)
                    for _ in 0..<8 {
                        crc = (crc >> 1) ^ (crc & 1 != 0 ? 0xEDB88320 : 0)
                    }
                }
            }
        }
        return ~crc
    }

    private static func deflateChunked(handle: FileHandle) -> Data {
        var result = Data()
        let bufferSize = 65536
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dstBuffer.deallocate() }

        var streamObj = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 0),
            dst_size: 0, src_ptr: UnsafeMutablePointer<UInt8>.allocate(capacity: 0),
            src_size: 0, state: nil
        )
        let initStatus = compression_stream_init(&streamObj, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
        guard initStatus == COMPRESSION_STATUS_OK else {
            handle.seek(toFileOffset: 0)
            return readChunked(handle: handle)
        }
        defer { compression_stream_destroy(&streamObj) }

        var finished = false
        while !finished {
            let chunk = handle.readData(ofLength: chunkSize)
            let isLastChunk = chunk.isEmpty

            chunk.withUnsafeBytes { rawBuffer in
                guard let baseAddr = rawBuffer.baseAddress else { return }
                let srcPtr = baseAddr.assumingMemoryBound(to: UInt8.self)
                let srcSize = rawBuffer.count

                streamObj.src_ptr = srcPtr
                streamObj.src_size = srcSize

                repeat {
                    streamObj.dst_ptr = dstBuffer
                    streamObj.dst_size = bufferSize

                    let flags: Int32 = isLastChunk ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
                    let processStatus = compression_stream_process(&streamObj, flags)

                    let produced = bufferSize - streamObj.dst_size
                    if produced > 0 {
                        result.append(dstBuffer, count: produced)
                    }

                    if processStatus == COMPRESSION_STATUS_END {
                        finished = true
                        return
                    }
                } while streamObj.src_size > 0 || (isLastChunk && !finished)
            }

            if isLastChunk { finished = true }
        }

        return result
    }

    // MARK: - ZIP Structures

    private static func makeLocalHeader(name: Data, crc: UInt32, compressedSize: UInt32,
                                        uncompressedSize: UInt32, method: UInt16) -> Data {
        var h = Data(capacity: 30 + name.count)
        h.append(contentsOf: [0x50, 0x4b, 0x03, 0x04])
        h.append(u16: 20); h.append(u16: 0); h.append(u16: method)
        h.append(u16: 0); h.append(u16: 0)
        h.append(u32: crc)
        h.append(u32: compressedSize); h.append(u32: uncompressedSize)
        h.append(u16: UInt16(name.count)); h.append(u16: 0)
        h.append(name)
        return h
    }

    private static func makeCentralDirEntry(_ name: Data, _ crc: UInt32, _ compressedSize: UInt32,
                                             _ uncompressedSize: UInt32, _ offset: UInt32,
                                             _ isDir: Bool, _ method: UInt16) -> Data {
        var cd = Data(capacity: 46 + name.count)
        cd.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])
        cd.append(u16: 20); cd.append(u16: 20)
        cd.append(u16: 0); cd.append(u16: method)
        cd.append(u16: 0); cd.append(u16: 0)
        cd.append(u32: crc)
        cd.append(u32: compressedSize); cd.append(u32: uncompressedSize)
        cd.append(u16: UInt16(name.count))
        cd.append(u16: 0); cd.append(u16: 0); cd.append(u16: 0); cd.append(u16: 0)
        cd.append(u32: isDir ? 0x10 : 0)
        cd.append(u32: offset)
        cd.append(name)
        return cd
    }
}

enum ZipError: LocalizedError {
    case cannotEnumerate
    case invalidZip
    case extractFailed(String)
    var errorDescription: String? {
        switch self {
        case .cannotEnumerate: return "Cannot enumerate directory"
        case .invalidZip: return "Invalid ZIP file"
        case .extractFailed(let msg): return "Extract failed: \(msg)"
        }
    }
}

// MARK: - ZIP Extraction (Streaming)

extension ZipArchive {

    /// Extract ZIP streaming from FileHandle - avoids loading entire file into memory
    static func extract(from zipPath: String, to destDir: String) throws {
        let fm = FileManager.default
        guard let handle = FileHandle(forReadingAtPath: zipPath) else {
            throw ZipError.invalidZip
        }
        defer { handle.closeFile() }

        try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)

        // ponytail: stream ZIP entries, never load entire file
        while true {
            let headerData = handle.readData(ofLength: 30)
            guard headerData.count == 30 else { break }

            // Check local file header signature
            guard headerData[0] == 0x50, headerData[1] == 0x4b,
                  headerData[2] == 0x03, headerData[3] == 0x04 else { break }

            let gpFlag = readU16(headerData, 6)
            let method = readU16(headerData, 8)
            let compSize = Int(readU32(headerData, 18))
            let uncompSize = Int(readU32(headerData, 22))
            let nameLen = Int(readU16(headerData, 26))
            let extraLen = Int(readU16(headerData, 28))

            let nameData = handle.readData(ofLength: nameLen)
            _ = handle.readData(ofLength: extraLen) // skip extra field

            guard let name = String(data: nameData, encoding: .utf8), !name.isEmpty else {
                // Skip unknown entry - need sizes to seek past
                if compSize > 0 {
                    handle.seek(toFileOffset: handle.offsetInFile + UInt64(compSize))
                }
                continue
            }

            // ponytail: Data descriptor (bit 3) means sizes follow data, not in header
            // For now skip these - rare in IPAs. Add when encountering one that needs it.
            let hasDataDescriptor = (gpFlag & 0x08) != 0
            if hasDataDescriptor && compSize == 0 {
                throw ZipError.extractFailed("Data descriptor not supported for \(name)")
            }

            let fullPath = (destDir as NSString).appendingPathComponent(name)

            // Reject zip-slip entries (e.g. "../../etc/x") that would resolve outside destDir.
            let standardizedFull = (fullPath as NSString).standardizingPath
            let standardizedDest = (destDir as NSString).standardizingPath
            guard standardizedFull == standardizedDest || standardizedFull.hasPrefix(standardizedDest + "/") else {
                throw ZipError.extractFailed("unsafe path in zip entry: \(name)")
            }

            if name.hasSuffix("/") {
                try fm.createDirectory(atPath: fullPath, withIntermediateDirectories: true)
                continue
            }

            let dir = (fullPath as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

            let content: Data
            if method == 8 {
                // Deflate - read compressed data and decompress with libz
                let compressedData = handle.readData(ofLength: compSize)
                guard let decompressed = compressedData.inflateRaw(expectedSize: uncompSize) else {
                    throw ZipError.extractFailed("decompress failed for \(name)")
                }
                content = decompressed
            } else if method == 0 {
                // Stored - read directly
                content = handle.readData(ofLength: compSize)
            } else {
                throw ZipError.extractFailed("Unsupported compression method \(method) for \(name)")
            }

            try content.write(to: URL(fileURLWithPath: fullPath))
        }
    }

    private static func readU16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}

// MARK: - Raw Deflate Decompression via libz

extension Data {
    /// Decompress raw deflate (RFC 1951) using libz inflateInit2 with -MAX_WBITS
    /// ponytail: Apple's Compression framework cannot decode raw deflate - it only supports zlib-wrapped.
    /// libz with negative windowBits (-15) enables raw deflate mode.
    func inflateRaw(expectedSize: Int? = nil) -> Data? {
        guard !isEmpty else { return nil }

        var stream = z_stream()

        let result = withUnsafeBytes { (srcBuffer: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcBuffer.baseAddress else { return nil }

            stream.next_in = UnsafeMutablePointer(mutating: srcBase.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(srcBuffer.count)

            // -15 = raw deflate (no zlib/gzip header). Negative windowBits = raw mode.
            // ponytail: this is THE fix - Apple's COMPRESSION_ZLIB cannot do this
            let initResult = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initResult == Z_OK else { return nil }

            defer { inflateEnd(&stream) }

            // Use expected size if available, else estimate
            var outputSize = expectedSize ?? Swift.max(count * 4, 1024)
            var output = Data(count: outputSize)

            while true {
                let inflateResult = output.withUnsafeMutableBytes { (dstBuffer: UnsafeMutableRawBufferPointer) -> Int32 in
                    guard let dstBase = dstBuffer.baseAddress else { return Z_MEM_ERROR }

                    stream.next_out = dstBase.assumingMemoryBound(to: Bytef.self).advanced(by: Int(stream.total_out))
                    stream.avail_out = uInt(dstBuffer.count - Int(stream.total_out))

                    return inflate(&stream, Z_NO_FLUSH)
                }

                if inflateResult == Z_STREAM_END {
                    output.count = Int(stream.total_out)
                    return output
                }

                if inflateResult == Z_BUF_ERROR || (inflateResult == Z_OK && stream.avail_out == 0) {
                    // Need more output space
                    outputSize *= 2
                    output.count = outputSize
                    continue
                }

                if inflateResult != Z_OK {
                    return nil
                }
            }
        }

        return result
    }

    /// Legacy decompress - calls inflateRaw for compatibility
    func decompress() -> Data? {
        return inflateRaw()
    }
}

private extension Data {
    mutating func append(u16 v: UInt16) {
        var x = v.littleEndian
        append(Data(bytes: &x, count: 2))
    }

    mutating func append(u32 v: UInt32) {
        var x = v.littleEndian
        append(Data(bytes: &x, count: 4))
    }
}
