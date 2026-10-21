# PatchAdam — production metrics

One row per production order run through the converge loop
(docs/converge.md). Append-only.

| issue | commit | date | converge_iters | tests_at_ship | shipped | notes |
|------:|--------|------|---------------:|--------------:|:-------:|-------|
<!-- metrics rows appended here -->
| 6 | 0d88cb9 | 2026-10-14 | 1 | 28 | yes | synthetic fixture bases (D4); oracle green first pass; build, harness, audit clean |
| 1 | 6f70373 | 2026-10-14 | 3 | 76 | yes | M1 engines: BaseLoader, ApplyEngine, DiffEngine; pass 1 had 7 red (2 code, 5 test expectations), pass 2 green, pass 3 after cleanup |
| 2 | 34ca0f4 | 2026-10-14 | 4 | 88 | yes | M2 viewer; engine tests green on pass 2; the app needed 2 more passes on screen (text view sizing; macOS 27 ruler layer painting over the pane) |
| 3 | 7375826 | 2026-10-14 | 2 | 102 | yes | M3 comparison: AlignmentEngine, golden, search; this pass started with the app red (engine Anchor vs SwiftUI.Anchor), green after rename; prior session passes not counted |
| 4 | 4c0208e | 2026-10-14 | 2 | 115 | yes | M4 review workflow: SessionModel, findings, ranking, export, .patchadam, blind mode; engine tests red on pass 1 (3: UTC date, ISO-8601 seconds, frozen seed), green on pass 2; app built clean first time; hooks re-timed once for the golden+select race |
| 5 | 8b60321 | 2026-10-14 | 3 | 115 | yes | M5 distribution: DMG/notarize targets, Settings font, blind prompt, git detection; app build red once (Git.version namespace), green pass 2; screenshot pass 3 (welcome view self-render is blank, checked via hook log); notarization blocked on owner Developer ID cert |
| 7 | 0ca4d44 | 2026-10-20 | 2 | 115 | yes | patch slot above each column (drop or click; replace keeps label; add slot under four); built clean first pass, add-slot text trimmed after the screenshot |
| 8 | 5ac9bd9 | 2026-10-21 | 3 | 115 | yes | rename to Patch Adams + README docs + repo rename; pass 1 missed anchored project.yml lines, pass 2 display name; shipped with no window on this Mac (module rename), fixed in 1774d95 after a bisect |
| 10 | 5f49766 | 2026-10-21 | 2 | 115 | yes | View menu zoom ⌘= ⌘− ⌘0 on the Settings size; duplicate Bigger item dropped; checked via the real menu items |
| 9 | 1304d65 | 2026-10-21 | 3 | 131 | yes | syntax colour, SyntaxHighlight target (D9) + Spacetrucker palette; tests red on pass 1 (YAML overlap, generic fn), Go receiver fixed pass 3; 10k-line render 402 ms |
