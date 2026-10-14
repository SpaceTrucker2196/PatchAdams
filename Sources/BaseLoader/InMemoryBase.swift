import Foundation

/// A base held entirely in memory: files handed over as bytes. Used
/// for a base reconstructed from the patches themselves (`SyntheticBase`
/// in PatchModel) and in tests.
public struct InMemoryBase: FileProvider {
    public let label: String
    private let files: [String: Data]

    public init(label: String, files: [String: Data]) {
        self.label = label
        self.files = files
    }

    public init(label: String = "in memory", texts: [String: String]) {
        self.init(label: label, files: texts.mapValues { Data($0.utf8) })
    }

    public var origin: BaseOrigin { .inMemory(label) }

    public func contents(of path: String) throws -> Data? {
        try BaseLoader.validate(path)
        return files[path]
    }

    public func allPaths() throws -> [String] { files.keys.sorted() }
}
