#!/usr/bin/env bash
# Full quality gate. Must be green before any task is reported as done.
set -euo pipefail
cd "$(dirname "$0")/.."

scarb fmt --check --workspace
scarb lint --workspace --test --deny-warnings
scarb build --workspace
snforge test --workspace
python3 scripts/bench.py check
scarb doc --workspace --disable-remote-linking >/dev/null
echo "all checks passed"
