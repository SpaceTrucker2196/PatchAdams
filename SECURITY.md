# Patch Adams — security

## Threat model

The app reads other people's code: candidate patches and a base
repository that may be proprietary, and the reviewer's own findings
and rankings. It must keep all of it on the machine (MISSION.md §2)
and must never execute any of it (MISSION.md §1). The attacker of
interest is a patch crafted to exploit the reader: a malformed diff
that crashes or misleads the parser, a path like `../../.ssh/id_rsa`
in a header, a binary payload, or a 50,000-line file meant to hang
the UI. Defences: strict parsing with line-numbered errors, paths are
keys into an in-memory provider and never joined to the file system,
binary stubs, reduced mode above 50,000 lines, and the raw-hunk view
that always shows what the parser saw (MISSION.md §5).

## Outbound surface (frozen)

Every network destination, credential, and external process this
repo touches. Adding to this list is a stops-and-asks
(docs/dark-factory.md §4).

- **`github.com`** — `git push` / `git fetch` over SSH and `gh`
  (issues, releases, Pages) from the factory tooling only. The app
  itself opens no connection.
- **System `git`** — `BaseLoader` (Phase 1) spawns the user's `git`
  for read-only subcommands: `rev-parse`, `show`, `ls-tree`,
  `cat-file`. No other subprocess, anywhere.
- **Credentials** — none. The app holds no tokens, keys, or accounts.

## The harness (enforced, not promised)

The list above is an inventory. `.claude/settings.json` is what makes it
bite. Two layers, both shipped with the operating system, so a
zero-dependency shop adds nothing:

**Default-deny egress.** `sandbox.network.allowedDomains` starts EMPTY,
which means a sandboxed command reaches nothing. `github.com` is copied from the
frozen list above into it. Adding one here is the
same stops-and-asks as adding one there — they are one decision written
twice, and they must not drift.

**Kernel-enforced confinement.** `sandbox.enabled` is true, so commands
run under Seatbelt on macOS and bubblewrap/seccomp on Linux.

One layer does NOT ship here, because a project settings file cannot
set it: `sandbox.network.strictAllowlist`. Claude Code ignores that key
in `.claude/settings.json` by design — a checked-in file must not be
able to weaken or assert policy. Without it an unlisted host PROMPTS
instead of being refused outright. Set it in `~/.claude/settings.json`,
or in managed settings, and the refusal becomes deterministic.

## The command allowlist, and what it is not

`.claude/settings.json` names the git subcommands a run needs and
nothing else. A DENYLIST was considered and rejected: a list that blocks
shell metacharacters and permits `git` permits everything, because
`git -c core.hooksPath=...` is arbitrary execution. Two independent
teams demonstrated that exact bypass against two different agents in
August 2026.

**Pattern matching is not a security boundary, and this file must not
be read as one.** `git push *` matches `git push --receive-pack=...`,
which is how researchers reached remote code execution through Claude
Code's own published workflow: the bash validator stripped quoted
content before inspecting the command. That is why `push` sits under
`ask` rather than `allow`, and why the sandbox above is the control
that actually holds. The allowlist reduces the surface. The harness
contains what gets through it.

## The workflow audit

`make audit` (`tools/audit-workflows.sh`) checks this factory's own
GitHub Actions against the three lab findings. Zero dependencies —
grep and awk — because a check that needs installing is a check that
stops being run. It looks for:

1. **A write-scoped token on an attacker-controlled trigger.** The
   Google ADK finding: content in a pull request reached a
   low-privilege triage agent, which posted a comment, which triggered
   a maintainer-gated workflow, which inherited issue and
   pull-request write scope. A maintainer gate is worth nothing if a
   lower-privilege agent can trigger it. A missing `permissions:`
   block counts, because the run then inherits the repository default.
2. **`pull_request_target` at all.** It runs with the base
   repository's secrets against the pull request's code.
3. **A workflow that writes an instruction file.** The static half of
   the Codex finding.

It is green today: `pages.yml` triggers on `push` and writes nothing.
A red here is a regression, not noise.

**What it cannot check, said plainly rather than left to silence:**
whether two agent passes share a writable checkout at RUNTIME. That
depends on what the agent does, not on what the YAML says. Read any
multi-pass workflow by hand.

Findings and citations: SpaceTrucker2196/DF_Template#1.
