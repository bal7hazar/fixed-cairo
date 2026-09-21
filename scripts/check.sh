#!/usr/bin/env bash
# Full quality gate. Must be green before any task is reported as done.
set -euo pipefail
cd "$(dirname "$0")/.."

scarb fmt --check --workspace
scarb lint --workspace --test --deny-warnings
scarb build --workspace
snforge test --workspace
python3 scripts/bench.py check
python3 scripts/api_parity.py --check
python3 scripts/gas_tables.py --check
# Golden vectors are up to date with tools/refgen (skipped when the Rust toolchain is absent; CI
# always runs it in the `golden` job).
if command -v cargo >/dev/null 2>&1; then
  cargo run --quiet --locked --manifest-path tools/refgen/Cargo.toml -- check
else
  echo "cargo not found: skipping the golden vector check"
fi
scarb doc --workspace --disable-remote-linking >/dev/null
echo "all checks passed"
