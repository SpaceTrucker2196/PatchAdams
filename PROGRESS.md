# PatchAdam — progress

In-flight state. Newest first. Each entry: date, what changed, what's
next, anything a cold agent must know that isn't in a doc yet (and a
note of which doc it should move to).

## 2026-10-14 — M0: factory scaffold from DF_Template

**Done.** Repo created from `DF_Template` (Track B, fresh). Spec
landed at `docs/spec.md`; 19 fixture patches at
`Fixtures/patches/fixture*.patch`. SwiftPM package with `PatchModel`
(strict unified-diff parser: `diff --git`, extended headers, renames,
binary stubs, mode changes, `format-patch` mail wrapper, `\ No
newline`), a `patchadam` CLI harness (`parse`, `hunks`), and 19
XCTest cases — every fixture parses with the grep-measured file count,
hunk counts validated, line numbers round-trip. Oracle green; app
shell builds warning-clean (xcodegen + xcodebuild). `MISSION.md`,
`FACTORY.md`, `AGENTS.md`, `SECURITY.md`, autonomy contract,
`ROADMAP.md` M0–M5, `DECISIONS.md` D1–D3 written.

**Next.** M1 (Phase 1 engines): `BaseLoader` (git revision,
directory, archive), `ApplyEngine` (in-memory apply with fuzz, line
map, report), `DiffEngine` (Myers + patience, token LCS). Fixture
bases are not in the repo yet — the fixture patches came without
their base revisions; M1's apply gate needs them (see "Open").

**Open, for the owner.**
- Fixture bases: the spec's Phase 1 gate applies every fixture against
  its base. The patches reference upstream repos (ledgerlib, glowmap,
  a sample Go module, …) but no base commit is recorded. Either
  record base URLs + SHAs per fixture, or build a synthetic base set
  for the gate.
- The spec's open questions (category list, blind-mode default,
  Markdown export of the request text, App Store) carry proposed
  answers; D2 and D3 adopt the App Store and category ones
  provisionally.
- Fixture licensing: the 19 patches are third-party code. The repo is
  private; keep it so, or replace the fixtures before opening it.

**Not in a doc yet.** Swift 6.4's coverage artifact path
(`.build/out/Products/Debug/codecov/`) differs from the template's
assumption — recorded in `FACTORY.md` "Code visualization".
