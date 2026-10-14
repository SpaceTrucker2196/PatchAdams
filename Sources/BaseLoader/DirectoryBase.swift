import Foundation

/// A plain directory on disk, read file by file on demand.
public struct DirectoryBase: FileProvider {
    public let root: URL

    public init(root: URL) { self.root = root.standardizedFileURL }

    public var origin: BaseOrigin { .directory(root) }

    public func contents(of path: String) throws -> Data? {
        try BaseLoader.validate(path)
        let url = root.appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    public func allPaths() throws -> [String] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw BaseLoaderError("\(root.path): cannot enumerate")
        }
        var out: [String] = []
        let prefix = root.path + "/"
        for case let url as URL in walker {
            if url.lastPathComponent == ".git" { walker.skipDescendants(); continue }
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            out.append(String(path.dropFirst(prefix.count)))
        }
        return out.sorted()
    }
}
