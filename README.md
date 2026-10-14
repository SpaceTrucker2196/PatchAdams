# Patch Adam

A native macOS app that shows two to four patches against one code
base side by side, so a reviewer can find the best patch for a pull
request and record why.

Parallel columns aligned by file and hunk. Select a region in one
column and the app locates it in the others: `exact`, `modified`,
`moved`, or `absent` with a link to the nearest hunk. Mark any column
as the golden patch and read the rest as diffs against it. Findings
carry generated `filename Lstart:Lend` references and export as
Markdown and JSON.

- Spec: [`docs/spec.md`](docs/spec.md)
- Charter and invariants: [`MISSION.md`](MISSION.md)
- Build and test: [`FACTORY.md`](FACTORY.md) — `make test`, `make build`
- Phases and gates: [`ROADMAP.md`](ROADMAP.md)

This repository runs as a dark factory: mission, conventions, tests,
and the autonomy boundary live in-tree (`docs/dark-factory.md`).
Production orders are GitHub issues; `/converge <n>` ships one.

```
make test      # engines: swift test --enable-code-coverage
make build     # app: xcodegen + xcodebuild, warnings are errors
make harness   # swift run patchadam parse Fixtures/patches/*.patch
```

Requires macOS 14+, Xcode 16+ (Swift 6), and `xcodegen` for the app
target. The engines build with `swift` alone and have no
dependencies.
