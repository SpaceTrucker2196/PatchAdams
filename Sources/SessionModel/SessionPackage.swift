import Foundation

/// The `.patchadam` session file (spec "Persistence"; DECISIONS.md D11).
/// One file — pretty JSON holding the session and the full text of
/// every patch — so a review can be mailed, archived and reopened with
/// nothing else, and still diffs in git. Sessions saved before D11 are
/// directory packages (`session.json` plus `patches/`); `read` opens
/// both. The only place the app writes files (AGENTS.md "Forbidden APIs").
public enum SessionPackage {
    public static let fileExtension = "patchadam"
    public static let sessionFile = "session.json"
    public static let patchesDirectory = "patches"

    public struct Contents: Sendable, Hashable {
        public var session: Session
        /// Patch text by column label.
        public var patchTexts: [String: String]

        public init(session: Session, patchTexts: [String: String]) {
            self.session = session
            self.patchTexts = patchTexts
        }
    }

    public struct PackageError: Error, CustomStringConvertible, Sendable {
        public var description: String
        init(_ description: String) { self.description = description }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// The single-file form: the session and its patches, by label.
    struct Archive: Codable {
        static let formatName = "patchadam-archive"
        static let formatVersion = 1
        var format: String
        var archiveVersion: Int
        var session: Session
        var patches: [String: String]
    }

    /// Write the session as one file at `url`, replacing it atomically.
    public static func write(_ contents: Contents, to url: URL) throws {
        var session = contents.session
        session.saved = Date()
        for i in session.columns.indices {
            let label = session.columns[i].label
            guard contents.patchTexts[label] != nil else { throw PackageError("no patch text for column \(label)") }
            session.columns[i].patchFile = "\(label)-\(safeFileName(session.columns[i].sourceName))"
        }
        let archive = Archive(format: Archive.formatName, archiveVersion: Archive.formatVersion, session: session,
                              patches: contents.patchTexts.filter { label, _ in session.columns.contains { $0.label == label } })
        // A directory left by an older save at the same name would block the file.
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            try FileManager.default.removeItem(at: url)
        }
        try encoder.encode(archive).write(to: url, options: .atomic)
    }

    /// Write the pre-D11 directory package. Kept so tests can prove old
    /// sessions still open; the app never writes it.
    static func writeDirectoryPackage(_ contents: Contents, to url: URL) throws {
        var session = contents.session
        session.saved = Date()
        let fm = FileManager.default
        let patches = url.appendingPathComponent(patchesDirectory, isDirectory: true)
        try fm.createDirectory(at: patches, withIntermediateDirectories: true)
        var columns: [SessionColumn] = []
        for var column in session.columns {
            guard let text = contents.patchTexts[column.label] else {
                throw PackageError("no patch text for column \(column.label)")
            }
            column.patchFile = "\(column.label)-\(safeFileName(column.sourceName))"
            try Data(text.utf8).write(to: patches.appendingPathComponent(column.patchFile), options: .atomic)
            columns.append(column)
        }
        session.columns = columns
        try encoder.encode(session).write(to: url.appendingPathComponent(sessionFile), options: .atomic)
    }

    /// Open a session file, or a directory package saved before D11.
    public static func read(from url: URL) throws -> Contents {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw PackageError("\(url.lastPathComponent) does not exist")
        }
        if !isDirectory.boolValue {
            let archive = try decoder.decode(Archive.self, from: Data(contentsOf: url))
            guard archive.format == Archive.formatName else { throw PackageError("\(url.lastPathComponent) is not a Patch Adams session") }
            guard archive.archiveVersion <= Archive.formatVersion, archive.session.version <= Session.formatVersion else {
                throw PackageError("\(url.lastPathComponent) was saved by a newer Patch Adams")
            }
            for column in archive.session.columns where archive.patches[column.label] == nil {
                throw PackageError("\(url.lastPathComponent) has no patch text for column \(column.label)")
            }
            return Contents(session: archive.session, patchTexts: archive.patches)
        }
        let data = try Data(contentsOf: url.appendingPathComponent(sessionFile))
        let session = try decoder.decode(Session.self, from: data)
        guard session.version <= Session.formatVersion else {
            throw PackageError("session.json is version \(session.version); this build reads up to \(Session.formatVersion)")
        }
        var texts: [String: String] = [:]
        for column in session.columns {
            let file = url.appendingPathComponent(patchesDirectory).appendingPathComponent(column.patchFile)
            guard let text = String(data: try Data(contentsOf: file), encoding: .utf8) else {
                throw PackageError("\(column.patchFile) is not UTF-8")
            }
            texts[column.label] = text
        }
        return Contents(session: session, patchTexts: texts)
    }

    public static func encodeSession(_ session: Session) throws -> Data { try encoder.encode(session) }

    static func safeFileName(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:\0")
        let cleaned = name.unicodeScalars.map { bad.contains($0) ? "_" : String($0) }.joined()
        return cleaned.isEmpty ? "patch" : cleaned
    }
}
