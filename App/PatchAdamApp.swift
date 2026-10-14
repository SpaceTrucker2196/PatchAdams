import SwiftUI
import PatchModel

// Patch Adam — the SwiftUI shell. One window, three zones: file tree,
// 2 to 4 patch columns with a comparison panel beneath, findings
// sidebar (docs/spec.md, "User interface"). Phase 2 fills the zones;
// until then the window states the phase so nobody mistakes the shell
// for the product.
//
// The shell never calls an engine directly: a controller owns the
// session state and hands immutable results to the views (spec,
// "Technical architecture").

@main
struct PatchAdamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
    }
}

struct ContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Patch Adam"))
                .font(.title)
            Text(String(localized: "Phase 1: engines. The viewer lands in Phase 2 (ROADMAP.md)."))
                .foregroundStyle(.secondary)
            Text(String(localized: "Harness: swift run patchadam parse <patch>…"))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
