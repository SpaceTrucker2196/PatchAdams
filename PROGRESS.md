# Patch Adams — progress

In-flight state. Newest first. Each entry: date, what changed, what's
next, anything a cold agent must know that isn't in a doc yet (and a
note of which doc it should move to).

## 2026-10-21 — #8 rename, #10 zoom, #9 syntax colour

**Done.**
- **#8.** The app and repo are Patch Adams (`SpaceTrucker2196/PatchAdams`);
  Xcode project, target, scheme and bundle are `PatchAdams`. README
  rewritten as user documentation. Kept with the old spelling: the
  `.patchadam` type, bundle id, Swift package, CLI, and — found the
  hard way — the Swift module name. With module `PatchAdams` the app
  launched and idled with no window on this Mac; bisected to the module
  name (old binary fine from any path, renamed one from none, renamed
  with `PRODUCT_MODULE_NAME: PatchAdam` fine). Fixed in 1774d95.
- **#10.** View menu: Bigger ⌘=, Smaller ⌘−, Actual Size ⌘0, stepping
  the Settings font size. `--zoom N` fires the real menu items.
- **#9.** `SyntaxHighlight` target (D9) and the Spacetrucker palette.
  16 tests, 131 total. Checked on screen in a Go and a Rust file.

**Open, for the owner.** The local folder is still `~/projects/PatchAdam`:
renaming it under a running session breaks ledger attribution, so it
is the owner's move between sessions. The copy of the app opened for
the owner on 2026-10-21 is the pre-rename build; quit and reopen to get
the new one.

## 2026-10-20 — #7: a patch slot above every column

**Done.** A dashed slot sits above each column header: drop a patch
file on it, or click it to choose one. On a filled column it replaces
that column's patch and keeps the label; the findings, pins, manual
anchors and rank that pointed at the old patch go, after a
confirmation when there are findings. While a session has fewer than
four patches, an "Add a patch" slot sits to the right of the columns.
On a base rebuilt from the patches, both replace and add rebuild the
base, because the new patch can show base lines the old set did not.
`--replace B=/x.patch` and `--add /x.patch` drive it from a shell.
Checked on screen: B replaced with kettle-4 (its finding removed),
a fourth patch added as D.

**Owner spot-check.** Slot wording ("Drop a patch to replace A · or
click", "Add a patch") and the replace confirmation.

## 2026-10-14 — M5 (#5): distribution

**Done.** `make release` / `make dmg` / `make notarize` (FACTORY.md
"Release"): hardened runtime on, Release build signed with `SIGN`,
compressed DMG with an Applications link, notarytool submit + staple
with the App Store Connect key already on this Mac. Ad-hoc DMG built
(2.3 MB), mounted, and its app launched. Settings window: code font
(any fixed-pitch family) and size 9–24, default system monospace
12 pt; `CodeStyle.font` reads UserDefaults and the column content key
carries the font so a change re-renders at once. One-time "Review
blind?" prompt on a new session (not on reopen), with a Settings
toggle to ask again. `git --version` at launch; the welcome view shows
it or says the Git Revision base is off. `MARKETING_VERSION` 0.5.0.

**Blocked, owner.** Notarization itself. This Mac has Apple Development
and Apple Distribution identities only; a notarized DMG needs a
*Developer ID Application* certificate, which only the Apple Developer
account holder can create. Once it is in the keychain:
`make dmg notarize SIGN='Developer ID Application: river.io llc (U3Z59VXPUB)'`.

**Next.** No production order open. Candidates: real-base fixture
loading (D4 "what it does not give"), fuzz fixtures, the original
write-ups for D5.

**Owner spot-check.** Settings layout and the prompt wording.
`hdiutil create` prints a deprecation notice on macOS 27 (it still
works); `diskutil image create` is the successor when it bites.

## 2026-10-14 — M4 (#4): review workflow

**Done.** `SessionModel` target (PatchModel only, no UI): `Session`,
`Finding` (title, description, category, severity, generated
reference, "does the request ask for this", not-flagged, parked
correctness note, anchors with confidence), `Ranking` (ties allowed),
`SessionPin`, `ManualAnchor`, `BlindMode` (seeded SplitMix64 shuffle,
frozen by test), `BasePointer`; `SessionPackage` writes and reads the
`.patchadam` directory (`session.json` + `patches/<label>-<name>`);
`MarkdownExport` (D5) and `JSONExport`. App: findings sidebar with
filters by patch, file, category, severity; ⌘N finding sheet prefilled
from the selection; gutter markers by severity; `}` `{` walk findings;
"Same issue in C?" templates (FR-29); ranking block with rationale;
Copy Markdown, Export Markdown (⌘E), Export JSON; Save / Save As /
Open Session (`.patchadam` is a registered package type); blind mode
(⌘⌥B) numbers the columns in a seeded shuffle and hides file names;
manual anchor (FR-18) as "Use selection as anchor" in a comparison
pane, stored and winning over the engine on reload. Session timer in
the status bar. 13 engine tests; 115 total. All four M4 gates driven
on screen (ROADMAP.md has the numbers).

**Next.** M5 (#5): DMG, notarization, Settings (font), one-time
blind-mode prompt, `git` detection at launch.

**Owner spot-check (autonomy contract, "decides and flags").**
- FR-18 says "drag its edges". Shipped as: select the right lines in
  the other column, then "Use selection as anchor" in its comparison
  pane. One selection and one click; no new gesture on the text view.
- Export writes (`Data.write` to the URL from the save panel) are read
  as part of "session save" under AGENTS.md's FileManager rule; the
  only other writer is `SessionPackage`.
- Shortcuts: ⌘S / ⇧⌘S save, ⌘⌥O open session, ⌘E / ⇧⌘E / ⌘⌥E export,
  ⌘N finding, ⌘⌥B blind, `}` `{` findings.

**Open, for the owner.** The original chat write-ups behind FR-32 are
not in the repo (D5). Unchanged: fixture licensing, spec open questions
not yet adopted (two-base session: no).

## 2026-10-14 — M3 (#3): comparison

**Done.** `AlignmentEngine` target (ApplyEngine + DiffEngine, no UI):
`AlignmentEngine.locate` runs the spec's alignment steps over display
lines in a shared reference frame (base lines, or the golden column's
post lines) — declared identifier first (step 5 outranks position),
then the same reference span, then the best token-similarity window
anywhere in the file (`moved` at 0.6 or above), else `absent` at the
place the region would fall with the nearest hunk. `GoldenRenderer`
diffs a column's post text against the golden column's. The engine's
anchor type is `RegionAnchor` (the spec's "Anchor" — SwiftUI already
owns that name; the app build was red on the ambiguity at the start of
this pass). App: status badges per column, absent notice with a
nearest-hunk jump, word-level comparison panel, pins panel (⌘P),
golden picker (⇧⌘1–4) with a per-column differs summary and a cache
keyed (file, column, golden), cross-column search (⌘F) grouped by file
then column. 14 engine tests cover the rules and all four M3 gates on
the fixtures; the gates were also driven on screen through
`DebugHooks` (`--golden`, `--search`, `--pin`, anchors logged after
`--select`) and the numbers are in ROADMAP.md.

**Next.** M4 (#4): `SessionModel` — findings with categories, ranking,
Markdown/JSON export, session save, blind mode. Manual anchor
correction (FR-18) is not in this pass: its `ManualAnchor` record is
part of `SessionModel` (AGENTS.md), so the drag lands with M4.

**Owner spot-check (autonomy contract, "decides and flags").** UI
wording and shortcuts: badge text `exact / modified / moved / absent`
with a percent, the absent notice "No matching change in X. Nearest
hunk: file Lstart:Lend", ⌘F search, ⌘P pin, ⇧⌘1–4 golden.

**Open, for the owner.** Unchanged: fixture licensing, spec open
questions.

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
