#!/usr/bin/env bash
# Pre-push check: the part of the CI gate that is cheap enough to run before every push.
#
# usage: scripts/prepush.sh [<sha> [<base>]]
#   <sha>   the commit to check (default HEAD; the hook passes the pushed sha)
#   <base>  what the change is measured against (default: merge base of <sha> and origin/main)
#
# Always:        scarb fmt --check; the Python script self-tests and the cheap document /
#                generated-file checks (gas_tables, panic_coverage, gen_bounded).
# Only when their inputs changed since <base> (git diff --name-only <base>...<sha>):
#                the compile (`scarb check -p`) and the lint (`scarb lint -p --test
#                --deny-warnings`) of the touched packages AND of the workspace packages that
#                depend on them (all of them when Scarb.toml, Scarb.lock or .tool-versions
#                changed); the class size check when `consumer` is among them; the golden vectors
#                (tools/refgen) when cargo is present.
# Left to CI (scripts/check.sh and .github/workflows/ci.yml; too long for a pre-push):
#                the snforge test suites, the gas snapshots (scripts/bench.py check), `scarb doc`,
#                the refgen unit tests, the consumer cost job, the generators that need numpy /
#                mpmath (gen_trig.py, gen_exp.py).
#
# The checks run on the working tree, so the script refuses when the tree is not exactly <sha>.
# On a shared host, `scarb check|build|lint` go through the `scarb` shim (PATH), which waits on the
# heavy-build lock; this script takes that same lock once (the shim recognises a holder among its
# ancestors) so that the wait is printed apart from the work. It never bypasses the lock.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

sha_arg="${1:-HEAD}"
sha=$(git rev-parse --verify --quiet "${sha_arg}^{commit}") || {
  echo "prepush: '$sha_arg' is not a commit" >&2
  exit 1
}
head=$(git rev-parse HEAD)
dirty=$(git status --porcelain)
if [ "$head" != "$sha" ] || [ -n "$dirty" ]; then
  {
    echo "prepush: refusing to check: the working tree is not the commit being pushed."
    echo "  checked sha: $sha"
    echo "  HEAD:        $head"
    if [ -n "$dirty" ]; then
      echo "  uncommitted or untracked files:"
      echo "$dirty" | sed 's/^/    /'
    fi
    echo "Commit the changes (or remove them), and check out the commit to push, then push again."
    echo "Never use \`git stash\` (the stash stack is shared by every worktree) nor \`--no-verify\`."
  } >&2
  exit 1
fi
if [ -n "${2:-}" ]; then
  base=$(git rev-parse --verify --quiet "${2}^{commit}") || {
    echo "prepush: '$2' is not a commit" >&2
    exit 1
  }
else
  base=$(git merge-base "$sha" origin/main) || {
    echo "prepush: no merge base of $sha with origin/main (git fetch origin?)" >&2
    exit 1
  }
fi
echo "prepush: checking ${sha:0:12} against base ${base:0:12} ($(hostname))"
changed=$(git diff --name-only "$base...$sha")

t0=$(date +%s.%N)
lock_wait=0
elapsed() { awk -v a="$1" -v b="$(date +%s.%N)" 'BEGIN { printf "%.1fs", b - a }'; }
step() {
  local name=$1 s rc=0
  shift
  echo "==> $name"
  s=$(date +%s.%N)
  "$@" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "prepush: FAILED: $name ($(elapsed "$s"))" >&2
    echo "Fix it, commit, and push again. Never use --no-verify." >&2
    exit 1
  fi
  echo "    ok ($(elapsed "$s"))"
}

# 1. Unlocked, fast steps first.
step "scarb fmt --check --workspace" scarb fmt --check --workspace
step "consumer_cost.py --self-test" python3 scripts/consumer_cost.py --self-test
step "packages_table.py --self-test" python3 scripts/packages_table.py --self-test
if [ -d scripts/tests ]; then
  step "unittest scripts/tests" python3 -m unittest discover -s scripts/tests -p 'test_*.py'
fi
step "gas_tables.py --check" python3 scripts/gas_tables.py --check
step "panic_coverage.py --check" python3 scripts/panic_coverage.py --check
step "gen_bounded.py --check" python3 scripts/gen_bounded.py --check

if echo "$changed" | grep -Eq '^(tools/refgen/|packages/[^/]+/tests/golden_[^/]*\.cairo$)'; then
  if command -v cargo >/dev/null 2>&1; then
    step "refgen check (golden vectors)" \
      cargo run --quiet --locked --manifest-path tools/refgen/Cargo.toml -- check
  else
    echo "==> refgen check: cargo not found, skipped (CI runs it in the golden job)"
  fi
fi

# 2. The touched packages and the workspace packages that depend on them.
pkgs=()
for d in packages/*/; do [ -f "${d}Scarb.toml" ] && pkgs+=("$(basename "$d")"); done

declare -A touched=()
if echo "$changed" | grep -Eq '^(Scarb\.toml|Scarb\.lock|\.tool-versions)$'; then
  for p in "${pkgs[@]}"; do touched[$p]=1; done
else
  while IFS= read -r f; do
    if [[ "$f" =~ ^packages/([^/]+)/(.*\.cairo|Scarb\.toml)$ ]]; then
      p=${BASH_REMATCH[1]}
      [ -f "packages/$p/Scarb.toml" ] && touched[$p]=1
    fi
  done <<<"$changed"
fi
# Transitive closure over "depends on": q is added when its Scarb.toml names a package of the set.
grew=1
while [ "$grew" = 1 ]; do
  grew=0
  for q in "${pkgs[@]}"; do
    [ -n "${touched[$q]:-}" ] && continue
    for p in "${!touched[@]}"; do
      if grep -Eq "^${p}[[:space:]]*(\\.|=)" "packages/$q/Scarb.toml"; then
        touched[$q]=1
        grew=1
        break
      fi
    done
  done
done
todo=()
for p in "${pkgs[@]}"; do [ -n "${touched[$p]:-}" ] && todo+=("$p"); done
size_check=0
if [ -n "${touched[consumer]:-}" ] ||
  echo "$changed" | grep -Eq '^(gas/bytecode\.size|scripts/bytecode_size\.py)$'; then
  size_check=1
fi

if [ "${#todo[@]}" -eq 0 ] && [ "$size_check" = 0 ]; then
  echo "==> no Cairo source, manifest or toolchain change since the base: compile and lint skipped"
else
  # Hold the shared heavy-build lock once, and say how long it took to get it.
  lock="${HEAVY_BUILD_LOCK:-$HOME/orchestrator/heavy-build.lock}"
  if [ -d "$(dirname "$lock")" ]; then
    echo "==> waiting for the heavy-build lock ($lock)"
    s=$(date +%s.%N)
    exec {lock_fd}>>"$lock"
    flock "$lock_fd"
    lock_wait=$(elapsed "$s")
    echo "    lock wait: $lock_wait (not part of the step times below)"
  fi
  echo "packages to compile and lint: ${todo[*]:-none}"
  for p in "${todo[@]}"; do
    step "scarb check -p $p" scarb check -p "$p"
  done
  for p in "${todo[@]}"; do
    step "scarb lint -p $p --test --deny-warnings" scarb lint -p "$p" --test --deny-warnings
  done
  if [ "$size_check" = 1 ]; then
    step "bytecode_size.py check" python3 scripts/bytecode_size.py check
  fi
fi

echo "prepush: all checks passed in $(elapsed "$t0") (of which lock wait: $lock_wait)"
