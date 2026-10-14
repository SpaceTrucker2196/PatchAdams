import Foundation
import PatchModel

// patchadam — command-line harness for the PatchAdam engines.
// Exercises the packages on fixture patches without the app.
//
//   patchadam parse <patch>...     summarize each patch: files, kinds, +/- lines
//   patchadam hunks <patch>        list every hunk with its Lstart:Lend ranges
//   patchadam synth-base <patch> <dir>
//                                  write the patch's synthetic base files under <dir>
//                                  (Fixtures/bases; see SyntheticBase.swift, DECISIONS.md D4)

let args = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage: patchadam parse <patch>...
           patchadam hunks <patch>
           patchadam synth-base <patch> <dir>

    """.utf8))
    exit(2)
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
default:
    usage()
}

exit(failures == 0 ? 0 : 1)
