#!/usr/bin/env bash
# Regenerates every generated source, runs the correctness tests, then the whole benchmark suite.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/gen_tables.py
python3 scripts/gen_bounded.py
python3 scripts/gen_magi.py
python3 scripts/gen_prims.py
python3 scripts/gen_fixed.py
python3 scripts/gen_trig.py > results/trig_errors.log
snforge test correctness
python3 scripts/bench.py "${1:-run}"
