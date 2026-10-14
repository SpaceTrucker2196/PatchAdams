# PatchAdam — production metrics

One row per production order run through the converge loop
(docs/converge.md). Append-only.

| issue | commit | date | converge_iters | tests_at_ship | shipped | notes |
|------:|--------|------|---------------:|--------------:|:-------:|-------|
<!-- metrics rows appended here -->
| 6 | 0d88cb9 | 2026-10-14 | 1 | 28 | yes | synthetic fixture bases (D4); oracle green first pass; build, harness, audit clean |
| 1 | 6f70373 | 2026-10-14 | 3 | 76 | yes | M1 engines: BaseLoader, ApplyEngine, DiffEngine; pass 1 had 7 red (2 code, 5 test expectations), pass 2 green, pass 3 after cleanup |
