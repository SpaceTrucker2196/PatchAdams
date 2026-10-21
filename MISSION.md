# Patch Adams — mission

## What this is

Patch Adams is a native macOS app for one reviewer who must compare two
to four candidate patches against the same code base and pick the
best one for a pull request, with a written record of why. It shows
the patches in parallel columns aligned by file and hunk, locates the
same region across patches, lets any column be the golden reference,
and keeps findings anchored to `filename Lstart:Lend` references that
export as Markdown and JSON. It replaces a web page with one tab per
patch, where comparison happens from memory and line numbers are
counted by hand from hunk headers. Full spec: `docs/spec.md`.

## Sacred invariants (do not cross)

Numbered, testable where possible. An agent that finds itself about
to violate one stops and asks.

1. **Reads code, never runs it.** No target, test, or feature
   executes, builds, or installs patched code. Apply is in memory.
2. **Nothing leaves the machine.** No network access at any time, no
   telemetry. Patch and base contents stay local; a session file holds
   only what the reviewer loaded plus their own notes.
3. **References are generated, never typed.** Every `filename
   Lstart:Lend` the app writes comes from a selection through the line
   map. A hand-typed reference is a bug.
4. **A wrong anchor is worse than a missing one.** Alignment below
   0.6 confidence reports `absent`, with the confidence shown. The
   reviewer can override any anchor by one drag, and the override wins
   on reload.
5. **The raw patch is always one click away.** A per-file raw-hunk
   view and a per-patch apply report exist in every build, so a parser
   bug cannot hide a change.
6. **Label and patch file name appear together, everywhere.** Blind
   mode may hide the mapping; nothing else may.
7. **Engines have no UI dependency.** Every package under `Sources/`
   except the app shell imports Foundation at most, and is tested by
   `swift test` alone. The shell never calls an engine directly.
8. **Same session file, same picture.** Column order, golden choice,
   anchors, and blind-mode shuffle (seeded, stored) are deterministic
   on reopen.

## Non-goals

- Running, building, or testing the patched code.
- Editing patches, cherry-picking hunks, or producing a merged result.
- Collaboration, shared comments, hosting, accounts, or a server.
- Replacing the review form: the export pastes into whatever form the
  team uses.
- Language servers or semantic analysis beyond identifier matching.
- Localization beyond English in the first release (strings still go
  through `String(localized:)` from day one).
