import Foundation

/// A git revision, read through the system `git`. The only `Process`
/// use in the code base, and only read-only subcommands: `rev-parse`,
/// `ls-tree`, `cat-file` (AGENTS.md). The revision is resolved to a
/// commit once, at open, so the base cannot drift under a session.
public struct GitRevisionBase: FileProvider {
    public let repository: URL
    public let revision: String
    /// Full commit hash `revision` resolved to at open time.
    public let commit: String

    public init(repository: URL, revision: String) throws {
        self.repository = repository.standardizedFileURL
        self.revision = revision
        let result = try Git.run(["rev-parse", "--verify", "--end-of-options", "\(revision)^{commit}"], in: self.repository)
        guard result.status == 0, let sha = String(data: result.stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), sha.count == 40 else {
            throw BaseLoaderError("\(revision): not a commit in \(self.repository.path) — \(result.stderrText)")
        }
        self.commit = sha
    }

    public var origin: BaseOrigin { .gitRevision(repository: repository, revision: revision, commit: commit) }

    public func contents(of path: String) throws -> Data? {
        try BaseLoader.validate(path)
        let result = try Git.run(["cat-file", "blob", "\(commit):\(path)"], in: repository)
        if result.status != 0 {
            // Missing path or a directory: both mean "no such file".
            let err = result.stderrText
            if err.contains("does not exist") || err.contains("exists on disk, but not in")
                || err.contains("Not a valid object name") || err.contains("is a tree") || err.contains("bad file") {
                return nil
            }
            throw BaseLoaderError("git cat-file \(path): \(err)")
        }
        return result.stdout
    }

    public func allPaths() throws -> [String] {
        let result = try Git.run(["ls-tree", "-r", "-z", "--name-only", commit], in: repository)
        guard result.status == 0 else { throw BaseLoaderError("git ls-tree: \(result.stderrText)") }
        return result.stdout.split(separator: 0).compactMap { String(data: Data($0), encoding: .utf8) }.sorted()
    }
}

/// Runs `git` with read-only subcommands. Deliberately small: there is
/// no general "run a command" helper in this code base.
public enum Git {
    public static let allowedSubcommands: Set<String> = ["rev-parse", "ls-tree", "cat-file", "--version"]

    public struct Result: Sendable {
        public var status: Int32
        public var stdout: Data
        public var stderr: Data
        public var stderrText: String { String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    }

    /// `git --version`, or `nil` when git is not installed (spec risk
    /// "Shelling out to git differs by version or missing install").
    public static func version() -> String? {
        guard let r = try? run(["--version"], in: nil), r.status == 0 else { return nil }
        return String(data: r.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func run(_ arguments: [String], in directory: URL?) throws -> Result {
        guard let sub = arguments.first, allowedSubcommands.contains(sub) else {
            throw BaseLoaderError("git subcommand not allowed: \(arguments.first ?? "")")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + (directory.map { ["-C", $0.path] } ?? []) + arguments
        // No pager, no prompts, no config surprises.
        var env = ProcessInfo.processInfo.environment
        env["GIT_PAGER"] = "cat"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw BaseLoaderError("cannot run git: \(error.localizedDescription)")
        }
        // Read both pipes to EOF before waiting, or a large blob deadlocks.
        let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
        let stderrData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, stdout: stdoutData, stderr: stderrData)
    }
}
