# S2 - extract `glamx-cairo`

Read `docs/SPLIT.md` first (the decisions), then `docs/briefs/R1-common.md` (foreground only, gate
under `flock`, one scarb / snforge command at a time) and `docs/briefs/COMMON.md`.

You are in a worktree of `glam-cairo` on branch `split/glamx`, cut from `origin/main`: it carries
the full history. Turn this branch into the first state of the new repository
`git@github.com:bal7hazar/glamx-cairo.git` (already created, empty), **in one commit on top of the
history** (`chore: split glamx-cairo out of glam-cairo`), then push it there as `main`:
`git remote add glamx git@github.com:bal7hazar/glamx-cairo.git && git push glamx split/glamx:main`.
**Never push this branch to `origin` (glam-cairo).** This bootstrap push to the new repository's
`main` is the one exception to "open a pull request": the repository is empty.

Keep, pruned to `glamx` (delete everything else, including `packages/fixed` and `packages/glam`):
- `packages/glamx` (unchanged source: the split must not change a single result), now depending
  on the **published** `fixed = "0.3.0"` and `glam = "0.3.0"` (registry, in
  `[workspace.dependencies]`) instead of paths;
- `packages/benches`: `harness`, `alt/{eigen3,pose2,pose3,rot2,rot3,sdp}` and the matching
  `tests/bench_*` with their `[[test]]` targets; the matching `gas/*.snap` byte-for-byte
  unchanged (a difference means the registry `fixed` / `glam` 0.3.0 differ from main: stop and
  report);
- `scripts/`: `bench.py`, `check.sh`, `gen_eigen3.py`, `panic_coverage.py`, `deviations.py`,
  `gas_tables.py` (glamx README only), `bytecode_size.py` + `packages/consumer` with the
  fixtures that use `glamx` (`Particles2d`, `Rigid3d`, `KitchenSink`; they depend on `fixed`,
  `glam` from the registry; `gas/bytecode.size` regenerated if the fixture set changes, say so),
  `agent.sh`; pruned of references to what is gone;
- `tools/refgen`: the `eigen3`, `pose2`, `pose3`, `rot2`, `sdp` specs and oracles only (it keeps
  its `glam` / `glamx` crate dependencies), goldens byte-identical;
- `.github/` (workflow for `glamx` only, `all-checks` the single required status),
  `.tool-versions`, `LICENSE`, `.gitignore`, `Scarb.toml` (`repository =
  "https://github.com/bal7hazar/glamx-cairo"`, version stays `0.3.0`), `Scarb.lock`.
- Documents: `README.md` (what `glamx` is: port of Dimforge glamx 0.3.1; install
  `glamx = "0.3.0"`; the generated gas table), `AGENTS.md` and `CLAUDE.md` (same rules, map and
  commands of this repository; the orchestrator lives in `glam-cairo`, see its
  `docs/ORCHESTRATOR.md`), `docs/DESIGN.md` = what concerns `glamx` (its row of section 1,
  the rounding exception of `eigen3`, the glamx rows of section 3, sections 4-6; point to
  `fixed-cairo` for the scalar), `CHANGELOG.md` = the `glamx` entries of glam-cairo's changelog
  under 0.1.0 / 0.2.0 / 0.3.0 with a line saying these were released from `glam-cairo`, plus an
  `[Unreleased]` entry "repository split". No research / audits / briefs / orchestration docs.

Done: the full gate of the new layout green in the foreground (`flock /tmp/glam-cairo-gate.lock
scripts/check.sh`), then push to `glamx-cairo` `main`, then wait for its CI in the foreground
until green, fixing forward with more commits pushed to `glamx-cairo` `main` if needed.
`REPORT.md` (uncommitted, in this worktree): what was kept / removed, which checks run where, the
CI result, anything that could not be made standalone. Commit trailer with your model.
