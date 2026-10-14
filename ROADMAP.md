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
- [ ] **M2** (L) — Phase 2, viewer: window, file tree, 2–4 columns,
  full-file rendering, dual gutters, scroll lock, labels with patch
  file names, request panel.
  - [ ] Open a 4-patch session and read every touched file in every
    column without leaving the window.
  - [ ] Copy a reference from a selection and get `filename
    Lstart:Lend` with the correct post-patch lines.
  - [ ] Scroll lock keeps the same function in view across columns
    through a 2,000-line file.
  - [ ] Each column header shows its patch file name; tab-mapping
    confusion is impossible.
- [ ] **M3** (L) — Phase 3, comparison: selection alignment, status
  badges, absent notices with nearest-hunk links, comparison panel,
  golden patch mode, cross-column search.
  - [ ] Select the `strip_prefix("glow-")` block in the lantern patch
    that has it; marked `absent` in the other two with a link to their
    nearest hunk in `main.rs`.
  - [ ] Select `fn glow_schema` in any lantern column; located as
    `modified` or `exact` in the others.
  - [ ] Set each of four columns as golden in turn; every switch
    renders in under 1 second.
  - [ ] Search `tempFor(k)` across the four Go patches; grouped
    results with 60 or more hits in the patch that has them.
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
