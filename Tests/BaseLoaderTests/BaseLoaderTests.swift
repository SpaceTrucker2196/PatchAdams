import XCTest
@testable import BaseLoader

final class BaseLoaderTests: XCTestCase {

    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let archives = repoRoot.appendingPathComponent("Fixtures/archives")
    static let sampleFiles: [String: String] = [
        "README.md": (1...100).map { "hello world line \($0)\n" }.joined(),   // big enough that zip deflates it
        "src/main.rs": "fn main() {}\n",
        "src/raw.txt": "no newline",
    ]

    // MARK: - Directory

    func testDirectoryBaseReadsFilesAndListsThem() throws {
        let base = DirectoryBase(root: Self.repoRoot.appendingPathComponent("Fixtures/bases/rename"))
        let paths = try base.allPaths()
        XCTAssertEqual(paths.count, 4)
        for path in paths {
            let data = try XCTUnwrap(base.contents(of: path))
            XCTAssertFalse(data.isEmpty, path)
        }
        XCTAssertNil(try base.contents(of: "does/not/exist.txt"))
        XCTAssertNil(try base.contents(of: String(paths[0].split(separator: "/")[0])), "a directory is not a file")
    }

    func testDirectoryBaseRejectsEscapingPaths() {
        let base = DirectoryBase(root: Self.repoRoot.appendingPathComponent("Fixtures"))
        XCTAssertThrowsError(try base.contents(of: "../Package.swift"))
        XCTAssertThrowsError(try base.contents(of: "/etc/passwd"))
        XCTAssertThrowsError(try base.contents(of: ""))
        XCTAssertThrowsError(try base.contents(of: "a//b"))
    }

    func testDirectoryListingSkipsDotGit() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("patchadam-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".git/objects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data("ref: refs/heads/main\n".utf8).write(to: tmp.appendingPathComponent(".git/HEAD"))
        try Data("x\n".utf8).write(to: tmp.appendingPathComponent("src/a.txt"))
        try Data("y\n".utf8).write(to: tmp.appendingPathComponent("b.txt"))
        XCTAssertEqual(try DirectoryBase(root: tmp).allPaths(), ["b.txt", "src/a.txt"])
    }

    // MARK: - Git revision

    func testGitRevisionBaseReadsHeadOfThisRepository() throws {
        guard Git.version() != nil else { throw XCTSkip("git not installed") }
        let base = try GitRevisionBase(repository: Self.repoRoot, revision: "HEAD")
        XCTAssertEqual(base.commit.count, 40)
        let manifest = try XCTUnwrap(base.contents(of: "Package.swift"))
        XCTAssertTrue(String(decoding: manifest, as: UTF8.self).contains("swift-tools-version"))
        XCTAssertNil(try base.contents(of: "no/such/file.swift"))
        XCTAssertNil(try base.contents(of: "Sources"), "a tree is not a file")
        let paths = try base.allPaths()
        XCTAssertTrue(paths.contains("Package.swift"))
        XCTAssertTrue(paths.contains("Fixtures/archives/sample.zip"))
        if case .gitRevision(_, let rev, let commit) = base.origin {
            XCTAssertEqual(rev, "HEAD"); XCTAssertEqual(commit, base.commit)
        } else { XCTFail("origin") }
    }

    func testGitRevisionBaseRejectsUnknownRevision() throws {
        guard Git.version() != nil else { throw XCTSkip("git not installed") }
        XCTAssertThrowsError(try GitRevisionBase(repository: Self.repoRoot, revision: "no-such-branch-\(UUID().uuidString)"))
    }

    func testGitRunnerRefusesWritingSubcommands() {
        XCTAssertThrowsError(try Git.run(["commit", "-m", "x"], in: Self.repoRoot))
        XCTAssertThrowsError(try Git.run(["push"], in: Self.repoRoot))
        XCTAssertThrowsError(try Git.run(["fetch"], in: Self.repoRoot))
    }

    // MARK: - Archives

    func testTarArchiveStripsItsSinglePrefix() throws {
        try assertSample(ArchiveBase(url: Self.archives.appendingPathComponent("sample.tar")))
    }

    func testGzippedTarArchive() throws {
        try assertSample(ArchiveBase(url: Self.archives.appendingPathComponent("sample.tar.gz")))
    }

    func testZipArchiveDeflated() throws {
        try assertSample(ArchiveBase(url: Self.archives.appendingPathComponent("sample.zip")))
    }

    func testZipArchiveStored() throws {
        try assertSample(ArchiveBase(url: Self.archives.appendingPathComponent("sample-stored.zip")))
    }

    private func assertSample(_ base: ArchiveBase, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(base.strippedPrefix, "sample-1.0", file: file, line: line)
        XCTAssertEqual(try base.allPaths(), Self.sampleFiles.keys.sorted(), file: file, line: line)
        for (path, text) in Self.sampleFiles {
            XCTAssertEqual(try base.contents(of: path), Data(text.utf8), path, file: file, line: line)
        }
        XCTAssertNil(try base.contents(of: "missing"), file: file, line: line)
        XCTAssertThrowsError(try base.contents(of: "../x"), file: file, line: line)
    }

    func testUnknownArchiveExtensionIsAnError() {
        XCTAssertThrowsError(try ArchiveBase(url: Self.repoRoot.appendingPathComponent("Package.swift")))
    }

    func testTarWithoutCommonPrefixKeepsPaths() throws {
        // Build a two-entry ustar in memory: "a.txt" and "dir/b.txt".
        func entry(_ name: String, _ body: String) -> Data {
            var header = [UInt8](repeating: 0, count: 512)
            let nameBytes = Array(name.utf8); header.replaceSubrange(0..<nameBytes.count, with: nameBytes)
            let size = Array(String(format: "%011o", body.utf8.count).utf8); header.replaceSubrange(124..<135, with: size)
            header[156] = UInt8(ascii: "0")
            header.replaceSubrange(257..<263, with: Array("ustar\0".utf8))
            header.replaceSubrange(148..<156, with: Array("        ".utf8))
            let checksum = header.reduce(0) { $0 + Int($1) }
            header.replaceSubrange(148..<155, with: Array(String(format: "%06o\0", checksum).utf8))
            var data = Data(header)
            data.append(Data(body.utf8))
            let pad = (512 - body.utf8.count % 512) % 512
            data.append(Data(repeating: 0, count: pad))
            return data
        }
        var tar = entry("a.txt", "A\n")
        tar.append(entry("dir/b.txt", "B\n"))
        tar.append(Data(repeating: 0, count: 1024))
        let files = try Tar.entries(tar)
        XCTAssertEqual(files, ["a.txt": Data("A\n".utf8), "dir/b.txt": Data("B\n".utf8)])
    }

    // MARK: - Dispatcher

    func testOpenDispatchesOnKind() throws {
        XCTAssertTrue(try BaseLoader.open(Self.archives) is DirectoryBase)
        XCTAssertTrue(try BaseLoader.open(Self.archives.appendingPathComponent("sample.zip")) is ArchiveBase)
        if Git.version() != nil {
            XCTAssertTrue(try BaseLoader.open(Self.repoRoot, revision: "HEAD") is GitRevisionBase)
        }
        XCTAssertThrowsError(try BaseLoader.open(Self.archives.appendingPathComponent("sample.zip"), revision: "HEAD"))
        XCTAssertThrowsError(try BaseLoader.open(Self.repoRoot.appendingPathComponent("nope")))
    }

    func testTextDecodingFallsBackToLatin1() {
        XCTAssertEqual(BaseLoader.text(from: Data("héllo".utf8)), "héllo")
        let latin1 = Data([0x68, 0xE9, 0x6C])   // "hél" in ISO-8859-1, invalid UTF-8
        XCTAssertEqual(BaseLoader.text(from: latin1).count, 3)
    }
}
