# PatchAdam — roadmap

Forward direction as sized milestones. Sizes: S ≤ 1 session,
M = 1–2, L = 2–4. Each phase is gated by its checklist passing on
the fixture set (`Fixtures/patches/fixture*.patch`), not by a date.
Phases and gates come from `docs/spec.md`, "Delivery plan".

- [x] **M0** (S) — Factory scaffold: SwiftPM engines + app shell,
  `PatchModel` parser, 19 fixtures parse, `make test` green.
  2026-10-14.
- [x] **M1** (L) — Phase 1, engines: `BaseLoader`, `ApplyEngine`,
  `DiffEngine`, CLI harness, unit tests. 2026-10-14.
  - [x] Every fixture patch parses, including renames, binary stubs,
    mode changes.
  - [x] Every fixture patch applies in memory against its base with a
    per-file report. (Synthetic bases, D4; every file `clean`.)
  - [x] Line diff output matches `git diff --no-index` for 20 sampled
    file pairs. (Changed-line counts equal `--minimal`; hunk sliders
    may differ.)
  - [x] Line maps round-trip: post line → base line → post line for
    every unchanged line.
- [x] **M2** (L) — Phase 2, viewer: window, file tree, 2–4 columns,
  full-file rendering, dual gutters, scroll lock, labels with patch
  file names, request panel. 2026-10-14.
  - [x] Open a 4-patch session and read every touched file in every
    column without leaving the window. (kettle-1…18 on a merged
    synthetic base; `PatchAdam --demo`.)
  - [x] Copy a reference from a selection and get `filename
    Lstart:Lend` with the correct post-patch lines. (`--select A:10-20`
    → `brew_task.go L10:L17` on the pasteboard.)
  - [x] Scroll lock keeps the same function in view across columns
    through a 2,000-line file. (6,037-line heater_test.go, two
    columns with different line maps, both at base line 2927.)
  - [x] Each column header shows its patch file name; tab-mapping
    confusion is impossible.
- [x] **M3** (L) — Phase 3, comparison: selection alignment, status
  badges, absent notices with nearest-hunk links, comparison panel,
  golden patch mode, cross-column search. 2026-10-14.
  - [x] Select the `strip_prefix("glow-")` block in the lantern patch
    that has it; marked `absent` in the other two with a link to their
    nearest hunk in `main.rs`. (`--select C:854-856` on lantern-1…11:
    A absent, nearest `main.rs L812:L871`; B absent, nearest
    `main.rs L785:L844`.)
  - [x] Select `fn glow_schema` in any lantern column; located as
    `modified` or `exact` in the others. (`--select B:106-113`: A and
    C `modified` 0.87 via identifier `glow_schema`.)
  - [x] Set each of four columns as golden in turn; every switch
    renders in under 1 second. (`--golden A|B|C|D` on kettle-1…18:
    64 column-files in 49–59 ms each.)
  - [x] Search `tempFor(k)` across the four Go patches; grouped
    results with 60 or more hits in the patch that has them.
    (old-fixture-8, 15, 16, 17: 63 hits in 13 files, all in column A.)
- [ ] **M4** (L) — Phase 4, review workflow: findings with categories
  and severity, ranking with ties, Markdown and JSON export, session
  save/load, blind mode, manual anchor correction.
  - [ ] Review the four Go patches end to end in the app and export
    Markdown.
  - [ ] The export reproduces the ranking write-up with no hand-typed
    references.
  - [ ] Close and reopen the session; findings, pins, golden choice,
    and column order are restored.
  - [ ] One review in blind mode; the export reveals the mapping only
    at the end.
- [ ] **M5** (M) — Distribution: notarized direct download, DMG,
  Settings (font, size), first-run prompt for blind mode.
