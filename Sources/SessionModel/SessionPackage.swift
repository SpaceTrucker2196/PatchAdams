import Foundation

/// The `.patchadam` directory package (spec "Persistence"): `session.json`
/// plus a copy of every patch, so the review survives moving the base
/// repository and is diffable in git. The only place the app writes
/// files (AGENTS.md "Forbidden APIs").
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

    /// Write the package at `url` (created or replaced in place). Patch
    /// copies are named `<label>-<sourceName>` so two patches with the
    /// same file name cannot collide.
    public static func write(_ contents: Contents, to url: URL) throws {
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

    public static func read(from url: URL) throws -> Contents {
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
