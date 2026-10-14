// swift-tools-version: 6.0
import PackageDescription

// PatchAdam engines. Every target here is UI-free and testable with
// `swift test`; the macOS app (project.yml → PatchAdam.xcodeproj) is a
// thin shell over these products.
//
// Dependency rules (docs/spec.md "Packages"; enforced by this manifest):
//   PatchModel       → Foundation only
//   BaseLoader       → Foundation only
//   ApplyEngine      → PatchModel, BaseLoader
//   DiffEngine       → nothing
//   AlignmentEngine  → ApplyEngine, DiffEngine            (Phase 3, not yet landed)
//   SessionModel     → PatchModel                         (Phase 4, not yet landed)
// Add a target only when its first real code lands with tests.
let package = Package(
    name: "PatchAdam",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PatchModel", targets: ["PatchModel"]),
        .library(name: "BaseLoader", targets: ["BaseLoader"]),
        .library(name: "ApplyEngine", targets: ["ApplyEngine"]),
        .library(name: "DiffEngine", targets: ["DiffEngine"]),
        .executable(name: "patchadam", targets: ["patchadam"]),
    ],
    targets: [
        // Parse unified diffs into Patch / FileChange / Hunk / Line.
        .target(name: "PatchModel"),

        // Read-only base provider: directory, git revision, archive (FR-1).
        // The only target that may spawn `git`.
        .target(name: "BaseLoader"),

        // Apply a Patch to a base in memory with fuzz; post text, line
        // map, per-file report (FR-3).
        .target(name: "ApplyEngine", dependencies: ["PatchModel", "BaseLoader"]),

        // Myers + patience line diff, Myers token diff. No imports.
        .target(name: "DiffEngine"),

        // Command-line harness: exercises the engines on fixture patches
        // without the app. `swift run patchadam parse <patch>...`
        .executableTarget(name: "patchadam", dependencies: ["PatchModel", "BaseLoader", "ApplyEngine", "DiffEngine"]),

        .testTarget(name: "PatchModelTests", dependencies: ["PatchModel"]),
        .testTarget(name: "BaseLoaderTests", dependencies: ["BaseLoader"]),
        .testTarget(name: "ApplyEngineTests", dependencies: ["ApplyEngine", "PatchModel", "BaseLoader"]),
        .testTarget(name: "DiffEngineTests", dependencies: ["DiffEngine", "ApplyEngine", "PatchModel", "BaseLoader"]),
    ],
    swiftLanguageModes: [.v6]
)
