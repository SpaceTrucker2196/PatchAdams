#!/bin/sh
set -eu
# Write every case and check it with the Python validator.
for case in basic glow-i16 glow-i32 glow-i64; do
  cargo run -q -- "$case" "out/$case.glow"
  python3 tools/py/glow_validate.py "out/$case.glow"
