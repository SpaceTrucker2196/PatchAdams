import Foundation

/// A read-only view of the base: the code every patch applies to
/// (spec FR-1). Paths are repository-relative, `/`-separated, with no
/// leading slash. Nothing here writes, executes, or reaches the
/// network (MISSION.md §1, §2).
public protocol FileProvider: Sendable {
    /// Where the base came from, for the window title and the session
    /// file's base pointer.
    var origin: BaseOrigin { get }

    /// Raw bytes of one file, or `nil` when the base has no such file.
    func contents(of path: String) throws -> Data?

    /// Every file path in the base, sorted.
    func allPaths() throws -> [String]
}

public enum BaseOrigin: Sendable, Hashable, Codable {
    case directory(URL)
    case gitRevision(repository: URL, revision: String, commit: String)
    case archive(URL)
    /// Files handed over in memory, e.g. a base rebuilt from the patches.
    case inMemory(String)

    public var description: String {
        switch self {
        case .directory(let url): return url.path
        case .gitRevision(let repo, let rev, let commit): return "\(repo.lastPathComponent)@\(rev) (\(commit.prefix(12)))"
        case .archive(let url): return url.lastPathComponent
        case .inMemory(let label): return label
        }
    }
}

public struct BaseLoaderError: Error, CustomStringConvertible, Sendable, Hashable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public enum BaseLoader {

    /// Open a base by URL: a directory (plain, or a git repository when
    /// `revision` is given), or a `.tar`, `.tar.gz`, `.tgz` or `.zip`
    /// archive.
    public static func open(_ url: URL, revision: String? = nil) throws -> any FileProvider {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw BaseLoaderError("\(url.path): no such file or directory")
        }
        if isDirectory.boolValue {
            if let revision { return try GitRevisionBase(repository: url, revision: revision) }
            return DirectoryBase(root: url)
        }
        if revision != nil { throw BaseLoaderError("\(url.path): a revision needs a git repository, not a file") }
        return try ArchiveBase(url: url)
    }

    /// Reject paths that could leave the base: absolute, empty, or
    /// containing `..` components.
    static func validate(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !parts.contains(".."), !parts.contains("") else {
            throw BaseLoaderError("invalid base path: \(path)")
        }
    }

    /// Decode file bytes the way the patch parser does: UTF-8, else
    /// Latin-1 so every byte survives.
    public static func text(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }
}
