# Patch Adams: Multi-Patch Review App for macOS

Oct 14, 2026 · @Jeff Kunzelman

## Purpose and scope

Patch Adams is a native macOS app that shows two to four patches against one code base side by side, so a reviewer can find the best patch for a pull request and record why.

The current tool is a web page with one tab per implementation. The reviewer flips between tabs, holds the other patches in memory, and counts line numbers from hunk headers by hand. Patch Adams replaces that with parallel columns, a shared file tree, selection-driven cross-patch diffs, a golden-patch mode, and a findings log that exports with file and line references.

**In scope**

- Load one base revision and 2 to 4 unified-diff patches that apply to it.
- Show the patches in parallel columns, aligned by file and by hunk.
- Select text in one column and locate the matching region in the other columns. Show the differences between them. Say when a patch has no matching change.
- Mark any column as the golden patch. Show every other column as a diff against it.
- Record findings with a category, a severity, and a file:line reference. Rank the patches. Export the result.

**Out of scope**

- Running tests or builds. PatchBench reads code; it does not execute it.
- Editing patches or committing. The reviewer picks a winner; merging happens elsewhere.
- Hosting, accounts, or a server. The app works offline on local files.
- Language-aware semantic diff. Alignment is text-based with light syntax awareness (see Architecture).

## The reviewer and the job

The user is one reviewer who compares several candidate patches for the same request and must rank them on code quality, not on whether they pass.

**What the job looks like today**

The review in this chat is the model. The reviewer:

1. Reads the request and the earlier conversation to learn what was asked and what the code base already has.
2. Opens each implementation as a separate tab and reads its full diff.
3. Looks for a fixed set of problems: unnecessary helpers, duplicated logic, dead code, speculative flexibility, unclear code, misplaced code, compatibility shims nobody needs, low-value tests.
4. Writes each finding with a title, a short description, the file name, and a line range such as `pathutil.go L159:L189`.
5. Ranks the implementations, ties allowed, and explains the choices that mattered.
6. Often must answer follow-up questions: show me where X is in C, show only the unrequested feature, what would a better version look like.

**Where the web tool gets in the way**

| Pain point | Effect on the review |
| --- | --- |
| One tab per implementation | The reviewer holds three diffs in memory while reading the fourth. Comparisons are from recollection, not from the screen. |
| Line numbers only in hunk headers | Every file:line reference is counted by hand from `@@ -79,55 +79,55 @@`. Slow and error-prone. |
| Tab labels A, B, C, D do not say which patch file they hold | The reviewer had to infer the mapping from import blocks and hunk headers. |
| No cross-patch search | To see how four patches handled `generate_ree`, the reviewer opens four tabs and scrolls each. |
| No place to record findings | Findings live in a chat, a text file, or a form at the bottom of the page, detached from the code they describe. |
| Order bias | Implementations are read in tab order. The first one read sets the frame for the rest. |

**What a good reviewing experience needs**

- See the same region of every patch at the same time.
- Move by file and by region, not by patch.
- Anchor every note to a file and a line range, automatically.
- Keep the request in view while reading, so scope creep is visible.
- Compare with a reference (the golden patch) rather than from memory.
- Reduce bias: hide labels, randomize column order, review one region across all patches before judging any patch whole.

## Core concepts

Every feature in this spec uses the terms below. Use them in the UI, the code, and the export format.

| Term | Meaning |
| --- | --- |
| Base | The code base all patches apply to: a git revision, a directory, or a tarball. All line numbers in the "before" side refer to the base. |
| Session | One base plus 2 to 4 patches, the reviewer's findings, and the ranking. Saved as one file. |
| Patch | One unified diff (`git diff` or `git format-patch` output). Also called an implementation. Has a label (A, B, C, D) and a source file name. |
| Column | The on-screen view of one patch. Columns can be reordered, hidden, and relabeled. |
| File view | The full post-patch content of one file in one column, with added, removed, and unchanged lines marked. Not just the hunks. |
| Hunk | One contiguous change in a patch, as in the diff format. |
| Region | A reviewer-selected span of lines in one column. The unit of cross-patch comparison. |
| Anchor | The matching span for a region in another column, found by the alignment engine. An anchor has a confidence score and a status: `exact`, `moved`, `modified`, or `absent`. |
| Golden patch | The column currently chosen as the reference. All other columns render as a diff against it instead of against the base. Any column can be golden; only one at a time. |
| Finding | A reviewer note tied to one patch, one file, and a line range. Has a title, a description, a category, and a severity. |
| Category | A fixed list the reviewer picks from. The default list is the slop list used in this chat: unnecessary helpers, excessive defensiveness, unnecessary machinery or repeated work, duplicated logic or state, too many branches, unclear code, unhelpful comments or names, code in the wrong place, unneeded backwards compatibility, dead or unrelated code, premature extensibility, low-value tests, other. The list is editable per session. |
| Ranking | An ordered list of patches with ties allowed, plus a free-text rationale. |

**Line reference format**

The app writes references as `filename Lstart:Lend`, using the file name only, not the repository path, and the post-patch line numbers of that column. Example: `downloader.go L50:L62`. When a finding spans the removed side, the reference carries a minus prefix: `downloader.go -L88:L95`.

## Functional requirements

Requirements are numbered FR-n and grouped by feature. "Must" items are required for the first release. "Should" items follow.

**Loading a session**

- FR-1 (must) Open a base from a local git repository at a chosen revision, from a plain directory, or from a `.tar`/`.zip` archive.
- FR-2 (must) Add 2 to 4 patch files by file picker, by drag and drop onto the window, or by paste. Accept `git diff` and `git format-patch` output, including binary and rename headers.
- FR-3 (must) Apply each patch to the base in memory (not on disk) and report, per patch, which files applied cleanly, with fuzz, or failed. A failed file stays visible with its raw hunks and a warning.
- FR-4 (must) Show the patch source file name next to its label (A, B, C, D) everywhere a label appears. Confusing which label is which patch must not be possible.
- FR-5 (should) Load a session file that restores base, patches, column order, golden choice, findings, and ranking.
- FR-6 (should) Accept an optional request text (the task prompt) and show it in a collapsible panel. The reviewer judges scope against it.

**Column layout**

- FR-7 (must) Show 2, 3, or 4 columns side by side, each with its own vertical scroll. Equal widths by default; dividers are draggable.
- FR-8 (must) A shared file tree on the left lists every file touched by any patch. Each file row shows a chip per patch: changed, added, deleted, unchanged, or failed. Selecting a file opens it in every column at once.
- FR-9 (must) Each column shows the full post-patch file, with added lines, removed lines (collapsible), and unchanged context. A gutter shows base line numbers and post-patch line numbers.
- FR-10 (must) Scroll lock: when on, scrolling one column scrolls the others to the aligned position (by anchor, not by raw line number). Off by default for a column that failed to apply.
- FR-11 (must) A column can be hidden or re-ordered by drag. Hidden columns keep their findings.
- FR-12 (should) Blind mode: labels show as 1, 2, 3, 4 in a shuffled order until the reviewer turns it off. The true mapping is revealed on export.

**Selection alignment (cross-patch diff)**

- FR-13 (must) The reviewer selects a region (a line range) in one column. The app locates the matching region in every other column and highlights it.
- FR-14 (must) Each located region shows a status badge: `exact` (same text), `modified` (same place, different text), `moved` (same text, different place), or `absent` (no match above the confidence threshold).
- FR-15 (must) For `absent`, the column shows an inline notice at the position where the region would fall: "No matching change in B. Nearest hunk: downloader.go L94:L101." The notice is a link.
- FR-16 (must) A comparison panel below the columns shows the selected region against each located region as a word-level diff. One pane per other column.
- FR-17 (must) The reviewer can pin a selection. Pinned selections stay highlighted while the reviewer scrolls and are listed in a sidebar for return.
- FR-18 (should) The reviewer can adjust a located region by hand (drag its edges) when the engine chose wrong. The correction is remembered for the session.
- FR-19 (should) Search across all columns at once. Results group by file, then by column, with line references.

**Golden patch**

- FR-20 (must) Any column can be set as golden from its header or by keyboard. Exactly one golden at a time, or none.
- FR-21 (must) With a golden patch set, every other column renders its diff against the golden patch's post-patch files instead of against the base. The golden column itself renders against the base.
- FR-22 (must) The file tree chips update to show, per column, whether the file differs from golden.
- FR-23 (must) Switching golden is instant and reversible. Findings are not affected.
- FR-24 (should) A summary bar shows, per column, the count of files and lines that differ from golden.

**Findings**

- FR-25 (must) From any selection, the reviewer adds a finding. The app prefills the patch label, file name, and line range in the reference format.
- FR-26 (must) A finding has: title, description, category (from the session's list), severity (trivial, minor, material, blocking), and the reference. All but description are required.
- FR-27 (must) Findings appear as gutter markers in the column they belong to and in a findings list that can be filtered by patch, file, category, and severity.
- FR-28 (must) Clicking a finding scrolls its column to the reference and, when cross-patch alignment is on, locates the same region in the other columns.
- FR-29 (should) A finding can be copied to the other columns as a template ("same issue in C?"), which prefills the located region and leaves the reviewer to confirm.
- FR-30 (should) Findings can be tagged "not flagged" to record a deliberate pass, so the export shows what was considered and rejected.

**Ranking and export**

- FR-31 (must) A ranking panel lists the patches. The reviewer assigns a rank 1 to 4, ties allowed, and writes a rationale.
- FR-32 (must) Export to Markdown with: the mapping table (label, patch file name, rank), findings grouped by patch with `filename Lstart:Lend` references, and the rationale. The format must match the write-ups in this chat so it pastes into the review form unchanged.
- FR-33 (must) Export to JSON with the same data plus anchors and confidence scores, for tooling.
- FR-34 (should) Copy a single finding or a single reference to the clipboard in the reference format.
- FR-35 (should) Save and reopen the session file (see FR-5).

## Reviewer workflow and best practices

The app should guide a reviewer through the same sequence a careful human review follows, and make the shortcuts that cause bad reviews hard to take.

**The intended sequence**

1. Read the request first. The request panel (FR-6) is open on a new session until the reviewer closes it. Scope creep is only visible when the scope is in view.
2. Scan the file tree. Which files does each patch touch? A patch that touches files the others do not is the first place to look for unrelated or speculative edits.
3. Review one file at a time across all columns, not one patch at a time across all files. Region-by-region comparison keeps the judgment relative, which is the whole point of a comparative review.
4. Pick a provisional golden patch early, usually the one that looks cleanest after step 3, and read the others as diffs against it. Differences from the cleanest version are where the slop is.
5. Record findings as they are seen, each with a reference. Do not batch them for later; the line numbers will be wrong.
6. Rank last, with the findings list filtered by severity in front of the reviewer.

**Practices the app enforces or encourages**

| Practice | How the app supports it |
| --- | --- |
| Judge relative to the request, not to taste | Request panel pinned; a finding form field "Does the request ask for this?" with yes / no / unclear. |
| Reduce order bias | Blind mode (FR-12); columns open in shuffled order for a new session. |
| Compare like with like | Selection alignment (FR-13 to FR-16) shows the same region across patches. The absent notice (FR-15) makes a missing change explicit rather than silent. |
| Keep references exact | References are generated from the selection, never typed. |
| Separate quality from correctness | Severity labels are quality labels. The finding form has no "is this a bug" field. A free-text note field exists for a correctness concern the reviewer wants to park. |
| Record what was considered and passed | "Not flagged" findings (FR-30) appear in the export under their own heading. |
| Check tests as code | Test files appear in the file tree like any other file, with a filter to show only tests. |
| Avoid reviewer fatigue | A session timer in the status bar; a per-column "read" checkbox so the reviewer knows what has been covered. |

**Anti-patterns the design avoids**

- A single long scrolling page that hides which column the reviewer is in.
- Counting on memory for cross-patch comparison.
- A findings form detached from the code.
- Labels that can be confused with the underlying patch file.

## User interface

One window, three zones: a file tree on the left, 2 to 4 patch columns in the middle with a comparison panel beneath them, and a findings sidebar on the right. The layout below shows a session with four patches, B set as golden, and one region selected in B.

&#91;embedded content: main window · 4 columns, golden B, one selection located\]

Green marks an exact match, amber a modified one, and a dashed red box marks a column with no matching change. The comparison panel repeats the verdict per column and links to the nearest hunk when there is no match.

**Zones**

| Zone | Contents | Notes |
| --- | --- | --- |
| Toolbar | Request panel toggle, session name, blind-mode switch, current golden patch, export | Golden switch is a segmented control with one segment per column plus "none". |
| File tree | Every file any patch touches, with per-patch status chips; filter box; tests-only filter | Selecting a file loads it in all columns. Keyboard: up/down to move, return to open. |
| Columns | Label and patch file name in the header; full post-patch file; dual line-number gutter; finding markers; located-region badges | Header shows a star when golden. Column menu: hide, move left, move right, set golden, mark as read. |
| Comparison panel | One pane per non-selected column, each a word-level diff of the selected region against the located region | Collapsible. Pane header carries the status badge and, for `absent`, the nearest-hunk link. |
| Findings sidebar | Findings list with filters; ranking block; export buttons | Clicking a finding jumps all columns. |

**Keyboard**

| Keys | Action |
| --- | --- |
| ⌘1 to ⌘4 | Focus column 1 to 4 |
| ⌘⇧1 to ⌘⇧4 | Set column 1 to 4 as golden; press again to clear |
| ⌘L | Toggle scroll lock |
| ⌘F | Search all columns |
| ⌘N | New finding from the current selection |
| ⌘P | Pin the current selection |
| ⌘⌥B | Toggle blind mode |
| \] and \[ | Next and previous hunk in the focused column |
| } and { | Next and previous finding in the focused column |
| ⌘E | Export Markdown |

**Accessibility**

- Every status conveyed by colour is also conveyed by a word (`exact`, `modified`, `moved`, `absent`).
- Column contents are real text views, so VoiceOver reads them and the system find-and-select works.
- All actions are reachable from the menu bar and by keyboard. Minimum type size follows the system setting.
- Light and dark appearance follow the system. Diff colours are tested against both.

## Technical architecture

The app is a SwiftUI shell around AppKit text views, with all patch, diff, and alignment work in plain Swift packages that have no UI dependency and can be tested on their own.

&#91;embedded content: architecture · shell, controller, 6 engines, 2 stores\]

The shell never calls an engine directly. The controller owns the session state, fans work out to the engines on a background actor, and hands immutable results back to the views.

**Stack**

| Layer | Choice | Reason |
| --- | --- | --- |
| Platform | macOS 14 or later, Swift 6, Xcode 16 | Strict concurrency and `Observable` without compatibility shims. |
| Shell | SwiftUI for window, toolbar, sidebars, panels, settings | Fast to build; declarative state fits the session model. |
| Code views | AppKit `NSTextView` wrapped in `NSViewRepresentable`, one per column | SwiftUI `Text` cannot handle 10,000-line files with per-line attributes, gutters, and precise selection. |
| Git access | Shell out to the system `git` for `show`, `ls-tree`, `cat-file`; no libgit2 | Zero dependencies, matches what the reviewer already has installed. Archives and directories go through Foundation. |
| Diff engine | Own implementation of Myers with the patience heuristic for lines; LCS on tokens for the word-level panel | No suitable Swift package exists; the algorithm is small and must be tunable. |
| Persistence | A `.patchadam` directory package: `session.json` plus copies of the patch files and a pointer to the base | Readable, diffable, survives moving the base repository. |

**Packages**

| Package | Responsibility | Depends on |
| --- | --- | --- |
| `PatchModel` | Parse unified diffs into `Patch`, `FileChange`, `Hunk`, `Line`. Handle renames, binary stubs, mode changes. | Foundation |
| `BaseLoader` | Produce a read-only file provider for a git revision, a directory, or an archive. | Foundation |
| `ApplyEngine` | Apply a `Patch` to the base in memory, with fuzz. Produce per-file post-patch text, a line map (post line to base line), and an apply report. | `PatchModel`, `BaseLoader` |
| `DiffEngine` | Line diff and token diff between any two texts. Used for base-vs-patch, golden-vs-patch, and the comparison panel. | none |
| `AlignmentEngine` | Locate a region from one column in another column. Returns an anchor with status and confidence. | `ApplyEngine`, `DiffEngine` |
| `SessionModel` | `Session`, `Finding`, `Ranking`, `Pin`, `ManualAnchor`; Codable; export to Markdown and JSON. | `PatchModel` |
| `PatchAdamsApp` | SwiftUI shell, AppKit column views, view models. | all of the above |

**Alignment algorithm**

Given a region R (a line range in column X, file F), find its anchor in column Y:

1. Map R to base line numbers through X's line map. Lines that exist only in X (added lines) carry the base line of their nearest context line.
2. Map those base lines forward through Y's line map to a candidate range in Y.
3. Compare the text of R with the candidate range after whitespace normalization. Identical: `exact`. Different: `modified`, with the token diff cached for the panel.
4. If step 2 yields no candidate (Y did not touch that part of F, or F is absent in Y), search all of F in Y for the best token-similarity window of R's length. Similarity 0.6 or higher: `moved`. Below: `absent`.
5. When R contains a declaration (function, method, type, struct, const), search Y for the same identifier first. An identifier hit outranks a positional hit.
6. For `absent`, report the nearest hunk in Y by base line distance, so the UI can offer a jump target.

The reviewer can override any anchor by hand (FR-18). Overrides are stored as `ManualAnchor` and take precedence on reload.

**Golden rendering**

With golden G set, each other column Y shows `DiffEngine.lines(G.post(F), Y.post(F))` instead of `DiffEngine.lines(base(F), Y.post(F))`. Results are cached per (F, Y, G) and invalidated when G changes. The file tree chips are derived from the same cache.

**Concurrency**

Apply, diff, and alignment run on a background actor. The UI shows a per-column progress state and never blocks on them. Results are immutable value types handed back to the main actor.

## Non-functional requirements

The app must stay responsive on the patch sizes seen in this chat (up to about 2,500 changed lines across 15 files per patch) and degrade gracefully well beyond that.

| Area | Requirement |
| --- | --- |
| Startup | A session with 4 patches of 2,500 lines each opens to a usable window in under 2 seconds on an M1 MacBook Air. Apply and diff may continue in the background. |
| Scrolling | 60 frames per second in every column with a 10,000-line file open. Syntax colouring may lag by one frame; diff colouring may not. |
| Alignment | Locating a region in three other columns returns in under 200 milliseconds for files under 5,000 lines. Above that, show a progress state; never block input. |
| Golden switch | Re-rendering all columns against a new golden patch completes in under 1 second for the sizes above, from cache where possible. |
| Memory | Under 500 MB resident for the sizes above. Post-patch file contents are shared, not copied per view. |
| Offline | No network access at any time. No telemetry. |
| Privacy | Patch and base contents never leave the machine. Session files contain only what the reviewer loaded plus their own notes. |
| Determinism | The same session file opens to the same column order, golden choice, and anchors every time. Blind-mode shuffles are seeded and stored. |
| Large or odd patches | Binary files show a stub. Files over 50,000 lines open in a reduced mode (hunks only, no full file). Patches that fail to apply stay loadable. |
| Fonts and sizing | Monospace font and size follow the reviewer's choice in Settings. Default is the system monospace at 12 points. |
| Localization | English only for the first release. All user-facing strings go through `String(localized:)` from day one. |

## Delivery plan

Four phases, each gated by a review task that the build must pass before the next phase starts. The fixture set is invented (DECISIONS.md D10): four Go `kettle` patches, three Rust `lantern` patches with tooling in five other languages, and three small patches for parser edge cases. No review or customer code is used.

&#91;embedded content: roadmap · 4 phases, 3 gates, 1 finish line\]

No dates are set. Each phase ends when its gate passes on the fixture set, not on a calendar.

**Phase 1: Engines**

Build `PatchModel`, `BaseLoader`, `ApplyEngine`, `DiffEngine` as packages with a command-line harness and unit tests.

- [ ] Every fixture patch parses, including renames, binary stubs, and mode changes.
- [ ] Every fixture patch applies in memory against its base with a per-file report.
- [ ] Line diff output matches `git diff --no-index` for 20 sampled file pairs.
- [ ] Line maps round-trip: post line to base line to post line for every unchanged line.

**Phase 2: Viewer**

Window, file tree, 2 to 4 columns, full-file rendering, dual gutters, scroll lock, labels with patch file names, request panel.

- [ ] Open a 4-patch session and read every touched file in every column without leaving the window.
- [ ] Copy a reference from a selection and get `filename Lstart:Lend` with the correct post-patch lines.
- [ ] Scroll lock keeps the same function in view across columns while scrolling through a 2,000-line file.
- [ ] The tab-mapping confusion is impossible: each column header shows its patch file name.

**Phase 3: Comparison**

Selection alignment, status badges, absent notices with nearest-hunk links, comparison panel, golden patch mode, cross-column search.

- [ ] Select the `strip_prefix("glow-")` block in the lantern patch that has it; the app marks it `absent` in the other two and links to their nearest hunk in `main.rs`.
- [ ] Select `fn glow_schema` in any lantern column; the app locates it as `modified` or `exact` in the others.
- [ ] Set each of four columns as golden in turn; every switch renders in under 1 second.
- [ ] Search `tempFor(k)` across the four Go patches and get a grouped result list with 60 or more hits in the patch that has them.

**Phase 4: Review workflow**

Findings with categories and severity, ranking with ties, Markdown and JSON export, session save and load, blind mode, manual anchor correction.

- [ ] Review the four Go patches end to end in the app and export Markdown.
- [ ] The export reproduces the ranking write-up from this chat with no hand-typed references.
- [ ] Close and reopen the session; findings, pins, golden choice, and column order are restored.
- [ ] Run one review in blind mode; the export reveals the mapping only at the end.

## Risks, open questions, and non-goals

The largest risk is alignment quality: a located region that is wrong is worse than one that is missing, because the reviewer trusts it.

**Risks**

| Risk | Effect | Mitigation |
| --- | --- | --- |
| Alignment picks a plausible but wrong region | Reviewer compares the wrong code and records a false finding | Show the confidence score; default to `absent` below 0.6; make manual correction one drag (FR-18); log corrections to tune the threshold. |
| Patches that restructure a file (B's renames in the lantern set) defeat positional alignment | Many `absent` results in a column that did change the code | Identifier-first search (algorithm step 5); fall back to token similarity across the whole file. |
| `NSTextView` performance with per-line attributes on very large files | Scroll stutter, slow golden switch | Reduced mode above 50,000 lines; attribute runs computed off the main actor; measure in Phase 2 before adding features. |
| Shelling out to `git` differs by version or missing install | Base fails to load | Detect `git` at launch, show the version, and fall back to directory and archive loading. |
| Reviewer trusts the app's diff over the raw patch | A parser bug hides a change | Raw-hunk view always available per file; apply report shown per patch. |

**Open questions**

- [ ] Should the category list ship with the slop categories from this chat, or start empty and let the reviewer import a list? Default proposed: ship the list, allow edit.
- [ ] Should blind mode be on by default for new sessions? Proposed: off, with a one-time prompt.
- [ ] Is a two-base session (patches against different base revisions) needed? Proposed: no; one base per session.
- [ ] Should the Markdown export include the request text? Proposed: yes, collapsed under a heading.
- [ ] Is App Store distribution wanted, which limits shelling out to `git`? Proposed: direct distribution, notarized.

**Non-goals**

- Running, building, or testing the patched code.
- Editing patches, cherry-picking hunks, or producing a merged result.
- Collaboration, comments shared between reviewers, or a server.
- Replacing the review form: the export pastes into whatever form the team uses.
- Language servers or semantic analysis beyond identifier matching.
