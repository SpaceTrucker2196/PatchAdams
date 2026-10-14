// swift-tools-version: 6.0
import PackageDescription

// PatchAdam engines. Every target here is UI-free and testable with
// `swift test`; the macOS app (project.yml → PatchAdam.xcodeproj) is a
// thin shell over these products.
//
// Dependency rules (docs/spec.md "Packages"; enforced by this manifest):
//   PatchModel       → Foundation only
//   BaseLoader       → Foundation only                    (Phase 1, not yet landed)
//   ApplyEngine      → PatchModel, BaseLoader             (Phase 1, not yet landed)
//   DiffEngine       → nothing                            (Phase 1, not yet landed)
//   AlignmentEngine  → ApplyEngine, DiffEngine            (Phase 3, not yet landed)
//   SessionModel     → PatchModel                         (Phase 4, not yet landed)
// Add a target only when its first real code lands with tests.
let package = Package(
    name: "PatchAdam",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PatchModel", targets: ["PatchModel"]),
        .executable(name: "patchadam", targets: ["patchadam"]),
    ],
    targets: [
        // Parse unified diffs into Patch / FileChange / Hunk / Line.
        .target(name: "PatchModel"),

        // Command-line harness: exercises the engines on fixture patches
        // without the app. `swift run patchadam parse <patch>...`
        .executableTarget(name: "patchadam", dependencies: ["PatchModel"]),

        .testTarget(name: "PatchModelTests", dependencies: ["PatchModel"]),
    ],
    swiftLanguageModes: [.v6]
)
