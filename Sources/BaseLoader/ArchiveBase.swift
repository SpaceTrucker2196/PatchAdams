import Foundation

/// A `.tar`, `.tar.gz`/`.tgz` or `.zip` archive, fully read into
/// memory at open. Archives of one repository usually wrap every
/// entry in a single top-level directory (`git archive --prefix`,
/// GitHub downloads); when every entry shares one, it is stripped and
/// reported in `strippedPrefix`.
public struct ArchiveBase: FileProvider {
    public let url: URL
    public let strippedPrefix: String?
    private let files: [String: Data]

    public init(url: URL) throws {
        self.url = url.standardizedFileURL
        let data = try Data(contentsOf: url)
        let name = url.lastPathComponent.lowercased()
        var entries: [String: Data]
        if name.hasSuffix(".zip") {
            entries = try Zip.entries(data)
        } else if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") {
            entries = try Tar.entries(try Gzip.decompress(data))
        } else if name.hasSuffix(".tar") {
            entries = try Tar.entries(data)
        } else {
            throw BaseLoaderError("\(url.lastPathComponent): not a .tar, .tar.gz, .tgz or .zip archive")
        }

        // Normalise and drop anything that could escape the archive.
        entries = Dictionary(uniqueKeysWithValues: entries.compactMap { key, value in
            var path = key
            while path.hasPrefix("./") { path.removeFirst(2) }
            if path.hasPrefix("/") || path.split(separator: "/").contains("..") || path.isEmpty { return nil }
            return (path, value)
        })

        let firstComponents = Set(entries.keys.map { $0.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)[0] })
        if entries.count > 0, firstComponents.count == 1, let prefix = firstComponents.first,
           entries.keys.allSatisfy({ $0.hasPrefix(prefix + "/") }) {
            self.strippedPrefix = String(prefix)
            self.files = Dictionary(uniqueKeysWithValues: entries.map { (String($0.key.dropFirst(prefix.count + 1)), $0.value) })
        } else {
            self.strippedPrefix = nil
            self.files = entries
        }
    }

    public var origin: BaseOrigin { .archive(url) }

    public func contents(of path: String) throws -> Data? {
        try BaseLoader.validate(path)
        return files[path]
    }

    public func allPaths() throws -> [String] { files.keys.sorted() }
}

// MARK: - tar (ustar, GNU long names, pax paths)

enum Tar {
    static func entries(_ data: Data) throws -> [String: Data] {
        var out: [String: Data] = [:]
        var offset = 0
        var pendingLongName: String?
        var pendingPaxPath: String?
        let bytes = [UInt8](data)

        func field(_ start: Int, _ length: Int) -> String {
            let slice = bytes[(offset + start)..<(offset + start + length)]
            let end = slice.firstIndex(of: 0) ?? slice.endIndex
            return String(decoding: slice[slice.startIndex..<end], as: UTF8.self)
        }
        func octal(_ start: Int, _ length: Int) -> Int {
            Int(field(start, length).trimmingCharacters(in: CharacterSet(charactersIn: " \0")), radix: 8) ?? 0
        }

        while offset + 512 <= bytes.count {
            if bytes[offset..<offset + 512].allSatisfy({ $0 == 0 }) { break }   // end-of-archive blocks
            let size = octal(124, 12)
            let type = bytes[offset + 156]
            var name = field(0, 100)
            let magic = field(257, 6)
            if magic.hasPrefix("ustar") {
                let prefix = field(345, 155)
                if !prefix.isEmpty { name = prefix + "/" + name }
            }
            let dataStart = offset + 512
            let dataEnd = dataStart + size
            guard dataEnd <= bytes.count else { throw BaseLoaderError("tar: entry \(name) runs past end of archive") }
            let payload = Data(bytes[dataStart..<dataEnd])

            switch type {
            case UInt8(ascii: "L"):            // GNU long name for the next entry
                pendingLongName = String(decoding: payload.prefix { $0 != 0 }, as: UTF8.self)
            case UInt8(ascii: "x"):            // pax extended header for the next entry
                pendingPaxPath = paxPath(payload)
            case UInt8(ascii: "0"), 0, UInt8(ascii: "7"):   // regular file (incl. old-style and contiguous)
                let path = pendingPaxPath ?? pendingLongName ?? name
                out[path] = payload
                pendingLongName = nil; pendingPaxPath = nil
            default:                            // directories, links, globals: skipped
                pendingLongName = nil; pendingPaxPath = nil
            }
            offset = dataEnd + ((512 - size % 512) % 512)
        }
        return out
    }

    /// `path=` record of a pax header: `<len> path=<value>\n`.
    private static func paxPath(_ payload: Data) -> String? {
        let text = String(decoding: payload, as: UTF8.self)
        for record in text.split(separator: "\n") {
            guard let space = record.firstIndex(of: " ") else { continue }
            let body = record[record.index(after: space)...]
            if body.hasPrefix("path=") { return String(body.dropFirst(5)) }
        }
        return nil
    }
}

// MARK: - zip (stored and deflate, no zip64)

enum Zip {
    static func entries(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }

        // End of central directory: signature 0x06054b50, scanned from the end.
        guard bytes.count >= 22 else { throw BaseLoaderError("zip: too short") }
        var eocd = -1
        var i = bytes.count - 22
        let floor = max(0, bytes.count - 22 - 65535)
        while i >= floor {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4b, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw BaseLoaderError("zip: no end-of-central-directory record") }
        let entryCount = u16(eocd + 10)
        let cdOffset = u32(eocd + 16)
        if entryCount == 0xFFFF || cdOffset == 0xFFFF_FFFF { throw BaseLoaderError("zip: zip64 archives are not supported") }

        var out: [String: Data] = [:]
        var p = cdOffset
        for _ in 0..<entryCount {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4b50 else { throw BaseLoaderError("zip: bad central directory entry") }
            let method = u16(p + 10)
            let compressedSize = u32(p + 20)
            let uncompressedSize = u32(p + 24)
            let nameLength = u16(p + 28)
            let extraLength = u16(p + 30)
            let commentLength = u16(p + 32)
            let localOffset = u32(p + 42)
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            p += 46 + nameLength + extraLength + commentLength

            if name.hasSuffix("/") { continue }    // directory entry
            guard localOffset + 30 <= bytes.count, u32(localOffset) == 0x0403_4b50 else {
                throw BaseLoaderError("zip: bad local header for \(name)")
            }
            let dataStart = localOffset + 30 + u16(localOffset + 26) + u16(localOffset + 28)
            guard dataStart + compressedSize <= bytes.count else { throw BaseLoaderError("zip: \(name) runs past end of archive") }
            let raw = Data(bytes[dataStart..<dataStart + compressedSize])
            switch method {
            case 0:
                out[name] = raw
            case 8:
                let inflated = try Deflate.inflate(raw, expectedSize: uncompressedSize)
                out[name] = inflated
            default:
                throw BaseLoaderError("zip: \(name) uses unsupported compression method \(method)")
            }
        }
        return out
    }
}

// MARK: - gzip wrapper around raw deflate

enum Gzip {
    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else {
            throw BaseLoaderError("gzip: not a gzip stream")
        }
        let flags = bytes[3]
        var p = 10
        if flags & 0x04 != 0 {                   // FEXTRA
            let len = Int(bytes[p]) | Int(bytes[p + 1]) << 8
            p += 2 + len
        }
        if flags & 0x08 != 0 { while p < bytes.count, bytes[p] != 0 { p += 1 }; p += 1 }   // FNAME
        if flags & 0x10 != 0 { while p < bytes.count, bytes[p] != 0 { p += 1 }; p += 1 }   // FCOMMENT
        if flags & 0x02 != 0 { p += 2 }                                                     // FHCRC
        guard p < bytes.count - 8 else { throw BaseLoaderError("gzip: truncated header") }
        let isize = Int(bytes[bytes.count - 4]) | Int(bytes[bytes.count - 3]) << 8
            | Int(bytes[bytes.count - 2]) << 16 | Int(bytes[bytes.count - 1]) << 24
        return try Deflate.inflate(Data(bytes[p..<(bytes.count - 8)]), expectedSize: isize)
    }
}

enum Deflate {
    /// Raw DEFLATE via Foundation's Compression bridge (`.zlib` there
    /// means raw deflate, no zlib header).
    static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        do {
            let out = try (data as NSData).decompressed(using: .zlib) as Data
            if expectedSize > 0, out.count != expectedSize {
                throw BaseLoaderError("deflate: expected \(expectedSize) bytes, got \(out.count)")
            }
            return out
        } catch let error as BaseLoaderError {
            throw error
        } catch {
            throw BaseLoaderError("deflate: \(error.localizedDescription)")
        }
    }
}
