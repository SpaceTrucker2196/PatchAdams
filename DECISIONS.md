# PatchAdam — decisions and refusals

Append-only. One row per decision that would otherwise be re-argued
from scratch in six weeks, and a section below carrying the reasoning.

**A refusal is a decision.** "We measured this and it does not work"
is the single most expensive thing to rediscover, and the easiest to
lose — it leaves no code behind, so nothing in the repository reminds
anyone it happened. Record refusals here with their numbers, or the
next agent will cheerfully rebuild them.

## Index

| id | date | decision | status | evidence | supersedes |
|----|------|----------|--------|----------|------------|
| D1 | 2026-10-14 | Zero third-party dependencies; own Myers/patience diff; shell out to system `git` | adopted | docs/spec.md "Stack" | — |
| D2 | 2026-10-14 | Direct notarized distribution, app not sandboxed; no App Store | provisional | docs/spec.md open questions; project.yml | — |
| D3 | 2026-10-14 | Ship the slop category list as the session default; editable per session | provisional | docs/spec.md "Category" | — |
| D4 | 2026-10-14 | Fixture bases are synthetic, rebuilt from each patch's own hunks and checked in under `Fixtures/bases/` | adopted | issue #6; `SyntheticBaseTests` | — |
| D5 | 2026-10-14 | The Markdown write-up shape is fixed from FR-32 (title, request collapsed, ranking table, findings by patch in rank order, not-flagged, rationale; blind mapping last) | adopted | issue #3 gate; `SessionModelTests.testMarkdownExportMatchesTheWriteUpShape` | — |
| D6 | 2026-10-14 | Blind mode is off for a new session, with a one-time prompt; Settings can ask again | provisional | docs/spec.md open questions; issue #5 | — |
| D7 | 2026-10-14 | One base per session; no two-base sessions | provisional | docs/spec.md open questions; `Session.base` is a single `BasePointer` | — |
| D8 | 2026-10-14 | The Markdown export includes the request text, collapsed in a `<details>` block | provisional | docs/spec.md open questions; D5 | — |

`status` is one of:

- **adopted** — in force. Change it by superseding, not editing.
- **refused** — tried, measured, rejected. The numbers live below.
- **provisional** — in force but unproven; says what would settle it.
- **superseded** — replaced. The `supersedes` column on the newer row
  points back here.

`evidence` names where the numbers are: a `PROGRESS.md` date, a
`docs/spikes/` file, a benchmark, a commit. `none` is allowed and is
itself informative — an unevidenced decision is a preference, and
saying so lets a later agent overturn it cheaply.

## D1 — zero third-party dependencies

**Decision.** `Package.swift` declares no dependencies. The line diff
is our own Myers with the patience heuristic; the word-level diff is
LCS on tokens. Git access shells out to the system `git` for
read-only subcommands rather than linking libgit2.

**Why.** The spec's stack table: no suitable Swift diff package
exists, the algorithm is small and must be tunable, and the reviewer
already has `git` installed. A dependency is also outbound surface
(SECURITY.md) and a supply-chain audit per `AGENTS.md`.

**What would change this.** A measured diff-quality or performance
gap against `git diff` that our implementation cannot close within the
non-functional budget (200 ms alignment, 1 s golden switch).

## D2 — direct notarized distribution, no sandbox

**Decision.** `project.yml` sets `com.apple.security.app-sandbox`
to false. The app spawns the user's `git` and reads arbitrary
repositories, which the App Store sandbox forbids. Distribution is a
notarized DMG.

**Why.** The spec's open question proposes exactly this. Sandboxing
would force either libgit2 (contradicts D1) or a security-scoped
bookmark dance for every base directory.

**What would change this.** An owner request for App Store
distribution. Then: libgit2 or archive-only base loading, and this
row is superseded.

## D3 — ship the slop category list

**Decision.** New sessions start with the spec's category list
(unnecessary helpers, excessive defensiveness, unnecessary machinery
or repeated work, duplicated logic or state, too many branches,
unclear code, unhelpful comments or names, code in the wrong place,
unneeded backwards compatibility, dead or unrelated code, premature
extensibility, low-value tests, other). The list is editable per
session and saved in the session file.

**Why.** The spec's open question proposes it. An empty list makes
the first finding slower and the export inconsistent across sessions.

**What would change this.** A second review team with its own
taxonomy; then an importable list format lands beside the default.

## D4 — synthetic fixture bases

**Decision.** The 19 fixture patches came without their base
revisions. For the Phase 1 apply gate the base of every modified,
renamed, copied or deleted file is rebuilt from the patch itself:
context and removed lines sit at their declared base line numbers,
gaps between hunks hold a filler line (`~ synthetic base line N ~`),
and the file ends at the last hunk's last base line. The generator is
`SyntheticBase` in `PatchModel`; `make bases` writes the set to
`Fixtures/bases/<fixture>/<path>`, and `SyntheticBaseTests` fails the
oracle when the stored set drifts from the generator's output.
Added and binary files have no base file.

**Why.** Issue #6 weighed two options. Fetching the upstream repos at
recorded SHAs needs the network at fixture-fetch time and leaves the
gate depending on third-party hosts staying put. The synthetic set is
offline, deterministic, in-tree, and every hunk applies at its exact
offset, so a clean apply is a hard expectation rather than a hope.
155 files, 1.5 MB.

**What it does not give.** Lines outside any hunk are filler, not the
real file, and nothing after the last hunk exists. So the synthetic
set cannot exercise fuzz, cross-file context, or whole-repository
loading. Fuzz needs separate, deliberately perturbed fixtures; full
repository loading (FR-1 git revisions) needs option 1 — upstream URL
plus base SHA per fixture, fetched into a cache outside the repo —
which stays open as a later production order.

**What would change this.** Clearance to vendor the upstream base
trees (the fixtures are third-party code, PROGRESS.md "Open"), or a
measured gap where the apply engine behaves differently on real bases
than on synthetic ones.

## D5 — the Markdown write-up shape

**Decision.** `MarkdownExport` (in `SessionModel`) renders: an H1 with
the session name; a one-line count; the request text collapsed in a
`<details>` block; `## Ranking` as a table of rank, label and patch
file name (rows in rank order, ties in display order, unranked last);
`## Findings` with one H3 per patch in rank order, each finding a
bullet `**severity · category** — title \`ref\`` followed by the
description, the "Request asks for this" answer when it is not
"unclear", and the note; `## Not flagged` for the deliberate passes;
`## Rationale`. In blind mode the body shows the shuffled numbers,
file names are withheld, and `## Mapping` comes last (FR-12). The
test holds the exact text.

**Why.** FR-32 says the export must match "the write-ups in this
chat" so it pastes into the review form unchanged. Those write-ups
are not in the repository — the spec was carried over without them —
so the shape had to be fixed from the requirement's own list (mapping
table, findings grouped by patch with `filename Lstart:Lend`
references, rationale) plus the open question's proposed answer on the
request text (yes, collapsed). Every reference is generated from a
selection; the test asserts no reference in the export is absent from
the findings.

**What would change this.** The owner pasting one of the original
write-ups into `docs/`. Then the renderer follows it and the test's
expected text changes with it; nothing else moves.

## D6 — blind mode off by default, asked once

**Decision.** A new session opens with letter labels. The first time a
session has a base and two patches, the app asks "Review blind?" once.
The answer is remembered in UserDefaults (`blindPromptShown`), and a
Settings toggle can bring the question back. A reopened session never
asks; it keeps the blind state it was saved with (MISSION.md §8).

**Why.** The spec's open question proposes exactly this. Blind mode
reduces order bias, but forcing it on surprises a reviewer who needs
the file names, for example to match a ticket.

**What would change this.** A review team that wants every review
blind. Then the default flips and the prompt asks the other way.

## D7 — one base per session

**Decision.** A session has one base. `Session.base` is a single
`BasePointer`; every column applies against it.

**Why.** The spec's open question proposes it. Alignment maps regions
through base line numbers (spec "Alignment algorithm", step 1); two
bases would need a base-to-base line map first, and no fixture needs
one.

**What would change this.** A real review where the patches were made
against different revisions. Then a base-to-base diff becomes the
first step of alignment.

## D8 — the request text is in the export, collapsed

**Decision.** The Markdown export carries the request text in a
`<details><summary>Request</summary>` block under the title (D5).

**Why.** The spec's open question proposes it. Findings are judged
against the request, so a reader of the write-up needs it, but it
should not push the ranking off the first screen.

**What would change this.** A review form that rejects HTML in
Markdown. Then the request moves under a plain `## Request` heading.
