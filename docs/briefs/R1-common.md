# R1 - rules shared by the release-audit briefs

Read after your task brief and before `docs/briefs/COMMON.md` (which still applies in full).

- Role: **Optimizer** / **Reviewer** of `AGENTS.md`, on merged modules. `v0.1.0` is not tagged
  yet, so a numeric result may still change when the brief says so, but only with (a) the accuracy
  evidence in the pull request, (b) the item's doc comment and golden vectors updated, and (c) the
  change listed under "Numeric changes" in `REPORT.md` for the changelog. A pure gas optimization
  must be bit-exact: prove it with the existing golden vectors and tests, untouched.
- Every claim is a `gas/*.snap` delta (l2_gas **and** steps: l2_gas of branching code is the
  worst branch, steps tell which branch ran). A variant that loses stays in `benches::alt::<module>`
  with its bench (DESIGN rule 9). A candidate of the brief that does not pay off is a valid result:
  report the measurement and leave the library unchanged.
- An optimization of a function changes the snapshots of its callers in other modules. Regenerate
  **every** snapshot that `scripts/bench.py check` reports as changed (`scripts/bench.py snapshot
  bench_<module>`), commit them, and list them in the report; do not touch the source of those
  modules. Then `python3 scripts/gas_tables.py` when a README table is stale.
- Shared machine: several agents work in sibling worktrees at the same time and the `glam_tests`
  compile peaks at ~12 GB. Iterate with filtered runs (`snforge test -p <pkg> <filter>`,
  `scripts/bench.py run bench_<module>`), and run the full gate exactly like this, in the
  foreground: `flock /tmp/glam-cairo-gate.lock scripts/check.sh` (it may wait for another agent's
  gate: that is expected, do not kill it, do not bypass the lock).
- Headless session: **never** start a command in the background (no `run_in_background`, no
  "I will continue when it finishes") and never end your turn before `REPORT.md` is written: no
  notification ever arrives, the session just stops (observed again on R1g). Run everything in
  the foreground with a long timeout; for a command longer than 10 minutes, `nohup` it to a file
  and block on it with `while pgrep -f <pattern> >/dev/null; do sleep 20; done`, repeated as
  needed.
- Generated modules (`vec2/3/4`, `mat2/3/4`, integer vectors, swizzles) are edited through
  `tools/codegen/*.py` only, then regenerated (see `tools/codegen/README.md`); the generator
  and its output are both in your allowlist when the module is.
- Branch, pull request title and commit scope are given by the brief. One pull request. Never merge.
