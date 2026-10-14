# PatchAdam — token / cost ledger

Append-only. Rows are produced by `~/.claude/billing/ledger.py
--append` after each substantive commit. Never hand-author, estimate,
or rewrite rows. If the script can't produce a row, stop and surface
it. If it finds no transcripts, pass `--session-cwd <dir>` with the
directory the session was launched from. Energy estimate for the
whole ledger: `ledger.py --energy-total`.

| commit | date | model(s) | input | output | cache_read | cache_write | cost_usd | summary |
|--------|------|----------|------:|-------:|-----------:|------------:|---------:|---------|
<!-- ledger rows appended here -->
| 25cabcc | 2026-10-14T17:21:22Z | claude-fable-5-1 | 1352 | 118576 | 5325396 | 362878 | 14.5312 | M0 scaffold from DF_Template; first row, --since session start, cwd ~/projects |
| e05f229 | 2026-10-14T17:47:12Z | claude-fable-5-1 | 1382 | 67110 | 4012923 | 350572 | 11.3840 | #6 synthetic fixture bases (D4), 0d88cb9 |
