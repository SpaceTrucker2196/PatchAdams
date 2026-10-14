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
