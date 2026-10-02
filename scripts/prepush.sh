#!/usr/bin/env bash
# Pre-push check: the part of the CI gate that is cheap enough to run before every push.
#
# usage: scripts/prepush.sh [<sha> [<base>]]
#   <sha>   the commit to check (default HEAD; the hook passes the pushed sha)
#   <base>  what the change is measured against (default: merge base of <sha> and origin/main)
#
# Always:        scarb fmt --check; the Python script self-tests and the cheap document /
#                generated-file checks (gas_tables, panic_coverage, gen_bounded).
# Only when their inputs changed since <base> (git diff --name-only <base>...<sha>), the heavy
# steps:         the compile (`scarb check -p`) of the touched packages AND of the workspace
#                packages that depend on them (all of them when Scarb.toml, Scarb.lock or
#                .tool-versions changed); the lint (`scarb lint -p --test --deny-warnings`) of the
#                touched packages only; the class size check when `consumer` is among the compiled
#                ones; the golden vectors (tools/refgen, no lock) when cargo is present.
# Left to CI (scripts/check.sh and .github/workflows/ci.yml; too long for a pre-push):
#                the snforge test suites, the gas snapshots (scripts/bench.py check), `scarb doc`,
#                the refgen unit tests, the consumer cost job, the generators that need numpy /
#                mpmath (gen_trig.py, gen_exp.py); and the Cairo compile when the host is busy.
#
# The checks run on the working tree, so the script refuses when the tree is not exactly <sha>.
#
# Heavy-build lock (shared host): the heavy steps run as one group under
# `flock -w 90 -E 75 ~/orchestrator/heavy-build.lock`, with the REAL scarb (the one the shim
# ~/.local/bin/scarb resolves to) and HEAVY_BUILD_LOCK_HELD=1 inside the group only. When the lock
# stays busy for 90 s the Cairo compile is left to CI and the script passes (nothing is killed).
# When HEAVY_BUILD_LOCK_HELD is set or an ancestor already holds the lock, the group runs directly;
# without a lock directory or without flock (a Mac) the steps call scarb through PATH.
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
# grep -q on a here-string, never `echo | grep -q` (pipefail + SIGPIPE would misreport a match).
changed_has() { grep -Eq "$1" <<<"$changed"; }

t0=$(date +%s.%N)
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

if changed_has '^(tools/refgen/|packages/[^/]+/tests/golden_[^/]*\.cairo$)'; then
  if command -v cargo >/dev/null 2>&1; then
    step "refgen check (golden vectors)" \
      cargo run --quiet --locked --manifest-path tools/refgen/Cargo.toml -- check
  else
    echo "==> refgen check: cargo not found, skipped (CI runs it in the golden job)"
  fi
fi

# 2. The touched packages (lint) and the workspace packages that depend on them (compile).
pkgs=()
for d in packages/*/; do [ -f "${d}Scarb.toml" ] && pkgs+=("$(basename "$d")"); done

declare -A touched=()
if changed_has '^(Scarb\.toml|Scarb\.lock|\.tool-versions)$'; then
  for p in "${pkgs[@]}"; do touched[$p]=1; done
else
  while IFS= read -r f; do
    if [[ "$f" =~ ^packages/([^/]+)/(.*\.cairo|Scarb\.toml)$ ]]; then
      p=${BASH_REMATCH[1]}
      [ -f "packages/$p/Scarb.toml" ] && touched[$p]=1
    fi
  done <<<"$changed"
fi
lint_pkgs=()
for p in "${pkgs[@]}"; do [ -n "${touched[$p]:-}" ] && lint_pkgs+=("$p"); done
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
build_pkgs=()
for p in "${pkgs[@]}"; do [ -n "${touched[$p]:-}" ] && build_pkgs+=("$p"); done
size_check=0
if [ -n "${touched[consumer]:-}" ] || changed_has '^(gas/bytecode\.size|scripts/bytecode_size\.py)$'; then
  size_check=1
fi

# The heavy steps, as one group (run under the lock, or directly).
heavy_group() {
  local p
  echo "packages to compile: ${PREPUSH_BUILD:-none}; to lint: ${PREPUSH_LINT:-none}"
  for p in $PREPUSH_BUILD; do
    step "scarb check -p $p" scarb check -p "$p"
  done
  for p in $PREPUSH_LINT; do
    step "scarb lint -p $p --test --deny-warnings" scarb lint -p "$p" --test --deny-warnings
  done
  if [ "$PREPUSH_SIZE" = 1 ]; then
    step "bytecode_size.py check" python3 scripts/bytecode_size.py check
  fi
}

lock_wait=0
left_to_ci=0
if [ "${#build_pkgs[@]}" -eq 0 ] && [ "$size_check" = 0 ]; then
  echo "==> no Cairo source, manifest or toolchain change since the base: compile and lint skipped"
else
  export PREPUSH_BUILD="${build_pkgs[*]:-}" PREPUSH_LINT="${lint_pkgs[*]:-}" PREPUSH_SIZE="$size_check"
  lock="${HEAVY_BUILD_LOCK:-$HOME/orchestrator/heavy-build.lock}"
  ancestor_holds_lock() {
    local p=$PPID
    while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
      if ls -l "/proc/$p/fd" 2>/dev/null | grep -qF -- "$lock"; then return 0; fi
      p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null) || return 1
    done
    return 1
  }
  if [ ! -d "$(dirname "$lock")" ] || ! command -v flock >/dev/null 2>&1; then
    heavy_group
  elif [ -n "${HEAVY_BUILD_LOCK_HELD:-}" ] || ancestor_holds_lock; then
    heavy_group
  else
    # The REAL scarb, as the shim resolves it, put first on PATH inside the group only.
    shim="$HOME/.local/bin/scarb"
    real=""
    if [ -f "$shim" ]; then
      real=$(sed -n 's/^real="\$HOME\/\(.*\)"$/\1/p' "$shim" | head -n 1)
      [ -n "$real" ] && real="$HOME/$real"
    fi
    [ -n "$real" ] || real="$HOME/.asdf/shims/scarb"
    if [ ! -x "$real" ]; then
      echo "prepush: real scarb not found ($real)" >&2
      exit 1
    fi
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    ln -s "$real" "$tmp/scarb"
    marker="$tmp/lock-taken"
    : >"$marker"
    export PREPUSH_MARKER="$marker" PREPUSH_REALDIR="$tmp"
    export -f heavy_group step elapsed
    echo "==> heavy-build lock ($lock), waiting up to 90 s"
    s=$(date +%s.%N)
    rc=0
    flock -w 90 -E 75 "$lock" bash -c '
      echo "lock taken after $(awk -v a="'"$s"'" -v b="$(date +%s.%N)" "BEGIN { printf \"%.1f\", b - a }") s" >"$PREPUSH_MARKER"
      export HEAVY_BUILD_LOCK_HELD=1 PATH="$PREPUSH_REALDIR:$PATH"
      heavy_group
    ' || rc=$?
    if [ "$rc" -eq 75 ] && [ ! -s "$marker" ]; then
      waited=$(awk -v a="$s" -v b="$(date +%s.%N)" 'BEGIN { printf "%d", b - a }')
      echo "heavy lock busy: Cairo compile left to CI (waited $waited s)"
      left_to_ci=1
    elif [ "$rc" -ne 0 ]; then
      exit 1
    else
      lock_wait=$(cat "$marker")
      echo "    $lock_wait (lock wait, not part of the step times above)"
    fi
  fi
fi

if [ "$left_to_ci" = 1 ]; then
  echo "prepush: passed (heavy steps left to CI) in $(elapsed "$t0")"
else
  echo "prepush: all checks passed in $(elapsed "$t0") (lock: $lock_wait)"
fi
