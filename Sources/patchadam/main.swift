import Foundation
import PatchModel
import BaseLoader
import ApplyEngine
import DiffEngine

// patchadam — command-line harness for the Patch Adams engines.
// Exercises the packages on fixture patches without the app.
//
//   patchadam parse <patch>...     summarize each patch: files, kinds, +/- lines
//   patchadam hunks <patch>        list every hunk with its Lstart:Lend ranges
//   patchadam synth-base <patch> <dir>
//                                  write the patch's synthetic base files under <dir>
//                                  (Fixtures/bases; see SyntheticBase.swift, DECISIONS.md D4)
//   patchadam apply <base> <patch>...
//                                  apply each patch to the base in memory; per-file report.
//                                  <base> is a directory, a .tar/.tar.gz/.tgz/.zip, or
//                                  <repo>@<revision>. Exit 1 if any file failed.
//   patchadam diff [--myers] <a> <b>
//                                  unified line diff of two files

let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: patchadam parse <patch>...
           patchadam hunks <patch>
           patchadam synth-base <patch> <dir>
           patchadam apply <base|repo@rev> <patch>...
           patchadam diff [--myers] <a> <b>

    """.utf8))
    exit(2)
}

/// `<dir>`, `<archive>`, or `<repo>@<revision>`.
func openBase(_ spec: String) throws -> any FileProvider {
    if let at = spec.lastIndex(of: "@"), !FileManager.default.fileExists(atPath: spec) {
        let repo = String(spec[..<at]), rev = String(spec[spec.index(after: at)...])
        return try BaseLoader.open(URL(fileURLWithPath: repo), revision: rev)
    }
    return try BaseLoader.open(URL(fileURLWithPath: spec))
}

guard let command = args.first else { usage() }
let paths = Array(args.dropFirst())
guard !paths.isEmpty else { usage() }

var failures = 0

switch command {
case "parse":
    for path in paths {
        do {
            let patch = try UnifiedDiffParser.parse(contentsOf: URL(fileURLWithPath: path))
            let counts = patch.lineCounts
            let name = (path as NSString).lastPathComponent
            print("\(name): \(patch.files.count) files, +\(counts.added) -\(counts.removed)")
            if let subject = patch.mailHeader?.subject { print("  subject: \(subject)") }
            for file in patch.files {
                let c = file.lineCounts
                var tag = file.kind.rawValue
                if file.isBinary { tag += " binary" }
                if let s = file.similarity { tag += " \(s)%" }
                let rename = file.kind == .renamed || file.kind == .copied
                    ? " (from \(file.oldPath ?? "?"))" : ""
                print("  \(tag.padding(toLength: 16, withPad: " ", startingAt: 0)) \(file.path)\(rename)  \(file.hunks.count) hunks +\(c.added) -\(c.removed)")
            }
        } catch {
            failures += 1
            FileHandle.standardError.write(Data("\(path): \(error)\n".utf8))
        }
    }
case "hunks":
    guard paths.count == 1 else { usage() }
    do {
        let patch = try UnifiedDiffParser.parse(contentsOf: URL(fileURLWithPath: paths[0]))
        for file in patch.files {
            print(file.path)
            for hunk in file.hunks {
                let old = hunk.oldRange.map { "-L\($0.lowerBound):L\($0.upperBound)" } ?? "-L\(hunk.oldStart):L\(hunk.oldStart - 1)"
                let new = hunk.newRange.map { "L\($0.lowerBound):L\($0.upperBound)" } ?? "L\(hunk.newStart):L\(hunk.newStart - 1)"
                print("  \(file.fileName) \(new)   base \(old)   \(hunk.sectionHeading ?? "")")
            }
        }
    } catch {
        failures += 1
        FileHandle.standardError.write(Data("\(paths[0]): \(error)\n".utf8))
    }
case "synth-base":
    // The one place the harness writes files: regenerating the fixture
    // base set. Engines never write (AGENTS.md "Forbidden APIs").
    guard paths.count == 2 else { usage() }
    do {
        let patch = try UnifiedDiffParser.parse(contentsOf: URL(fileURLWithPath: paths[0]))
        let root = URL(fileURLWithPath: paths[1])
        let files = try SyntheticBase.files(for: patch)
        for file in files {
            let url = root.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.text.utf8).write(to: url)
        }
        print("\((paths[0] as NSString).lastPathComponent): \(files.count) base files → \(paths[1])")
    } catch {
        failures += 1
        FileHandle.standardError.write(Data("\(paths[0]): \(error)\n".utf8))
    }
case "apply":
    guard paths.count >= 2 else { usage() }
    do {
        let base = try openBase(paths[0])
        print("base: \(base.origin.description)")
        for path in paths.dropFirst() {
            let patch = try UnifiedDiffParser.parse(contentsOf: URL(fileURLWithPath: path))
            let applied = ApplyEngine.apply(patch, to: base)
            let name = (path as NSString).lastPathComponent
            print("\(name): \(applied.report.summary)")
            for file in applied.files {
                var detail = ""
                if case .failed(let reason) = file.status { detail = "  " + reason }
                let moved = file.hunks.filter { $0.offset != 0 || $0.fuzz > 0 }
                if !moved.isEmpty {
                    detail += "  " + moved.map { "h\($0.index + 1)" + ($0.offset != 0 ? " offset \($0.offset)" : "") + ($0.fuzz > 0 ? " fuzz \($0.fuzz)" : "") }.joined(separator: ", ")
                }
                print("  \(file.status.label.padding(toLength: 8, withPad: " ", startingAt: 0)) \(file.path)\(detail)")
            }
            if applied.report.failed > 0 { failures += 1 }
        }
    } catch {
        failures += 1
        FileHandle.standardError.write(Data("apply: \(error)\n".utf8))
    }
case "diff":
    var rest = paths
    var algorithm = DiffEngine.Algorithm.patience
    if rest.first == "--myers" { algorithm = .myers; rest.removeFirst() }
    guard rest.count == 2 else { usage() }
    do {
        let a = BaseLoader.text(from: try Data(contentsOf: URL(fileURLWithPath: rest[0])))
        let b = BaseLoader.text(from: try Data(contentsOf: URL(fileURLWithPath: rest[1])))
        let la = DiffEngine.splitLines(a), lb = DiffEngine.splitLines(b)
        let diff = DiffEngine.lines(la, lb, algorithm: algorithm)
        print(diff.unified(a: la, b: lb, aName: "a/" + rest[0], bName: "b/" + rest[1]), terminator: "")
    } catch {
        failures += 1
        FileHandle.standardError.write(Data("diff: \(error)\n".utf8))
    }
default:
    usage()
}

exit(failures == 0 ? 0 : 1)
