# Orchestrator handoff

For a new orchestrator session, possibly on another machine. Everything needed to continue is in
this repository; nothing depends on a previous session's scratchpad, worktrees or local memory.

## Read first, in this order

1. `AGENTS.md` (rules for every agent), `docs/ORCHESTRATOR.md` (how the orchestrator spawns and
   briefs sub-agents: local `claude -p` / `codex exec` CLIs, model choice, brief format).
2. `docs/DESIGN.md` (decisions; changing one is the orchestrator's call and is recorded there).
3. `docs/PLAN.md` (waves) and `docs/PORTING_STATUS.md` (live status, one row per task).
4. `docs/briefs/` (every brief ever given to a porter: `COMMON.md` + one file per task; reuse
   them as templates), `docs/API_PARITY.md` (generated parity table against glam-rs 0.33.8),
   `CHANGELOG.md`.
5. `docs/research/00-synthesis.md` then reports 01-06 when evidence is needed.

## Machine setup

- asdf with `scarb` and `starknet-foundry` at the versions of `.tool-versions`; Rust (`cargo`)
  for `tools/refgen`; Python 3; `gh` authenticated with push rights on this repository.
- `scripts/check.sh` is the full gate (fmt, lint, build, tests, gas snapshots, golden vectors,
  API parity, docs). It takes 10-30 minutes depending on the machine load.
- Sub-agent CLIs: `claude` (check `claude auth status`: the account used for sub-agents is
  separate from the orchestrator's) and `codex`. Models that worked: `opus` for ports with
  numerics, `sonnet` for mechanical / tooling tasks, `fable` for genuinely hard numerics,
  codex `gpt-5.6-sol` with `model_reasoning_effort=high` for standard ports.
- Reference sources are re-cloned on demand into `/tmp` (the briefs say how): glam-rs 0.33.8,
  dimforge/glamx 0.3.1, parry, rapier.

## Operating loop

1. `git fetch && gh pr list`: a green pull request left by a porter is reviewed (scope = the
   brief's allowlist, report in the PR body, gas table) and squash-merged; then the orchestrator
   alone updates re-exports (`packages/*/src/lib.cairo`), `docs/PORTING_STATUS.md`,
   `CHANGELOG.md`, and `docs/DESIGN.md` when a decision was taken, and pushes to `main`.
2. After merging a pull request that touched shared generated files (`docs/API_PARITY.md`,
   `tools/refgen/src/**`, the READMEs' gas tables), re-run the matching `--check` on `main`
   (`python3 scripts/api_parity.py --check`, `python3 scripts/gas_tables.py --check`, `cargo run
   --manifest-path tools/refgen/Cargo.toml -- check`, `cargo test --manifest-path tools/refgen/Cargo.toml`) and regenerate if stale.
3. New work: write `docs/briefs/<TASK>.md`, pre-declare any new stub in the shared `lib.cairo`
   files, push, create a worktree + branch from `origin/main`, launch the porter with a one-line
   prompt pointing at the brief and `docs/briefs/COMMON.md`.
4. Lessons already paid for: a headless agent that ends its turn while a command runs in the
   background dies (briefs say "foreground"); test crates that are too large get the CI runner
   killed (table-driven tests, line caps, 6 fuzz properties max); parallel pull requests must
   not share a file (pre-declared stubs, one gas snapshot per module); estimates written in a
   brief can be wrong, the agent's measurement wins (`Mat3::from_quat`, trig gas targets).

## What remains (see `docs/PORTING_STATUS.md` for the live state)

- Every porting task of `docs/PLAN.md` is merged as of 2026-09-21 (glam-rs 0.33.8 parity: 0
  missing item in `docs/API_PARITY.md`; `glamx`: `Rot2`, `Rot3`, `Pose2`, `Pose3`, `SdpMatrix2/3`,
  `SymmetricEigen3`). No pull request is open, no agent is running, no work is left in a local
  worktree.
- R1, the release audit:
  - optimizer pass over the hottest benches (`gas/*.snap`, headline numbers in the READMEs'
    generated tables): candidates already noted are `SymmetricEigen3` (586k gas on a generic
    matrix: skip the polish of `v3`, a values-only path for `eigenvalues`; PR #29), the
    shared non-inlined `slerp` helper (+1 880 gas, PR #26), `camera_impl::look_to_mat4_rh`
    duplicating `Mat4::look_to_rh` (PR #16), a cheaper single-division path than `Recip`
    (`project_onto`, `length_recip`, PR #9), a `norm_squared_wide` kernel so that
    `is_normalized` does not panic on long vectors (PR #9), the 15-minute CI bench job (one
    compile for the two snforge runs);
  - review of every `#### Deviations` entry against `docs/DESIGN.md` section 3, in particular
    `Rot2::lerp` (normalised here, not upstream) and the thresholds re-derived in ULPs;
  - bytecode size of a consumer contract (never measured; `inline(always)` and polynomial
    segments trade bytecode for gas);
  - `v0.1.0`: tag, GitHub release from `CHANGELOG.md`, publication on scarbs.xyz in dependency
    order (`fixed`, `glam`, `glamx`). Publishing is outward-facing: confirm with the owner first.
- Coordination with the sibling repositories: `nalgebra.cairo` appeared to define its own
  generic scalar (`simba::fixed`, `Real` trait) while this repository publishes the concrete
  `fixed` package meant to be shared (DESIGN section 2: concrete types, because
  `#[inline(always)]` is rejected on impl-generic functions). Report 06 also narrows what
  `nalgebra.cairo` is still needed for (fixed-capacity `Vec6` / `Mat6` / Jacobians and a small LU
  for multibody). Both points need the owner's decision.
