# PatchAdam — progress

In-flight state. Newest first. Each entry: date, what changed, what's
next, anything a cold agent must know that isn't in a doc yet (and a
note of which doc it should move to).

## 2026-10-14 — M2 (#2): the viewer

**Done.** The app is now a product to look at. `SessionController`
(main actor, `@Observable`) owns base, columns, selection, scroll lock,
request text; an `Engines` actor runs apply off the main actor and
hands back `AppliedPatch` values. Zones: request panel (FR-6, open on a
new session), file tree with per-patch chips, filter and tests-only
(FR-8), 2–4 columns each with label **and** patch file name in the
header (FR-4), full post-patch text with removed lines inline and a
dual base/post gutter (FR-9), scroll lock by base-line anchor (FR-10),
hide / reorder / read per column (FR-11), reduced mode above 50,000
lines, raw hunks for a failed file (FR-3). Loading: directory, archive
or git revision base, patches by picker, drop or paste (FR-1, FR-2),
and "Rebuild Base from Patches" (`SyntheticBase.merged`, D4). Copy
Reference gives `filename Lstart:Lend` from the selection (MISSION §3).
Engine additions, all unit-tested: `SyntheticBase.merged`,
`InMemoryBase`, `AppliedFile.displayLines`, `LineReference`,
`[DisplayLine].anchorBase` / `index(atOrAfterBase:)`,
`LineMap.post(atOrAfterBase:)`. 88 tests green.

**Measured.** 10,000-line file: render + full layout 198 ms (debug).
Scroll lock on a 6,037-line file: both columns at base line 2927.
First window to usable session (demo, 4 patches): well under 2 s.
Not instrumented: scrolling frame rate — by eye it is smooth; an
Instruments pass is still owed before Phase 3 adds per-line badges.

**Learned, macOS 27.** `NSRulerView`'s content layer is pane-sized and
views no longer clip to bounds, so a ruler that fills its dirty rect
paints over every neighbouring column; the gutter is a plain sibling
view now. SwiftUI's `HSplitView` pane on a secondary display can
screenshot stale through `screencapture -l`; `--shot` self-renders.

**Next.** M3 (#3): `AlignmentEngine`, selection badges, absent notices,
comparison panel, golden patch, cross-column search.

**Flagged for owner spot-check** (UI wording and shortcuts, autonomy
contract "decides and flags"): Copy Reference is ⇧⌘C (not in the
spec's table); the column actions live in a "Columns" menu with
⌘1–4, `]`/`[`, ⌘L, ⌘R, ⌥⌘T (tests only), ⌥⌘- (removed lines);
`DebugHooks` reads fixtures by `#filePath` in debug builds only.

## 2026-10-14 — M1 (#1): BaseLoader, ApplyEngine, DiffEngine

**Done.** Three engine targets, 48 new tests (76 total), CLI `apply`
and `diff`, `make harness` now applies every fixture.
- `BaseLoader`: `FileProvider` protocol; `DirectoryBase`,
  `GitRevisionBase` (resolves the revision to a commit at open;
  `rev-parse`/`ls-tree`/`cat-file` only, enforced by an allow-list),
  `ArchiveBase` (ustar + GNU long names + pax paths, gzip, zip stored
  and deflate via Foundation's `.zlib`; a single top-level prefix is
  stripped and reported). Paths with `..`, absolute or empty are
  rejected.
- `ApplyEngine`: GNU-patch-style placement — declared line plus
  running offset, then outward search, then fuzz 1 and 2 dropping
  leading/trailing context. Per file: `clean` / `fuzz(n)` / `failed`
  (post text nil, raw hunks kept) / `binary`; full post text;
  `LineMap` post↔base plus `nearestBase` for added lines; per-hunk
  `HunkPlacement` with offset and fuzz. `ApplyReport` counts.
- `DiffEngine`: linear-space Myers (middle snake), patience on top
  (unique-line LIS anchors, Myers in the gaps), tokens via the same
  Myers; `LineDiff.unifiedHunks` with `diff -u` grouping; `TokenDiff
  .similarity` for alignment.
- Gates: all 19 fixtures apply `clean` against `Fixtures/bases`; line
  maps round-trip on 10k+ unchanged lines; 20 sampled pairs match
  `git diff --no-index --minimal` on changed-line counts and our
  unified output re-applies to the post text.

**Measured.** 6,037-line Go test file with 1,778 changed lines:
patience 30 ms, Myers 90 ms, debug build, 1,778 = git's count.

**Next.** M2 (#2): the viewer. Engines hand the shell `AppliedFile`
(shared post text + `LineMap`) and `LineDiff` per file; the column
view renders from those. Open: fuzz has only rule tests — a perturbed
fixture set would exercise it on real code.

**Flagged for owner spot-check** (autonomy contract "decides and
flags"): none UI-visible. Two judgement calls inside the engine
lists: (1) hunk *count* is not part of the git gate, only changed-line
counts, because equally minimal scripts slide differently; (2) the git
gate test is the one `Process` use outside `BaseLoader` — it is the
oracle the gate names, in a test, skipped when git is missing.

## 2026-10-14 — #6: synthetic fixture bases

**Done.** `SyntheticBase` (in `PatchModel`) rebuilds the base of every
non-added, non-binary file from the patch's own hunks — context and
removed lines at their declared base numbers, numbered filler lines in
the gaps, file ends at the last hunk. `patchadam synth-base` writes a
set; `make bases` regenerates all 19 (155 files, 1.5 MB, under
`Fixtures/bases/<fixture>/`). `SyntheticBaseTests` covers the rules
(gaps, no-newline, pure insertions, renames, added/binary skipped,
overlapping hunks are an error), checks the stored set byte-for-byte
against the generator, and checks every fixture hunk is found verbatim
at its declared base offset. Decision recorded as D4. 28 tests green,
build warning-clean.

**Next.** M1 (#1) is unblocked for the apply gate: `ApplyEngine` can
apply every fixture against `Fixtures/bases/<fixture>/` and must report
every file `clean`. Fuzz needs its own perturbed fixtures. Full-repo
loading tests still need option 1 from #6 (upstream URL + SHA); that
is a separate order.

**Open, for the owner.** Unchanged: fixture licensing, spec open
questions.

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
