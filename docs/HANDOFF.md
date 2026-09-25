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

- Every porting task of `docs/PLAN.md` and the R1 release audit are merged as of 2026-09-22
  (glam-rs 0.33.8 parity: 0 missing item; `glamx`: `Rot2`, `Rot3`, `Pose2`, `Pose3`,
  `SdpMatrix2/3`, `SymmetricEigen3`; audits in `docs/audits/`: deviations, bytecode size, panic
  coverage; checkers `scripts/{deviations,panic_coverage,bytecode_size}.py`). `CHANGELOG.md` is
  frozen at `0.1.0`.
- `v0.1.0`: the tag and the GitHub release are cut by the orchestrator with the owner's
  go-ahead; `scarb publish -p fixed`, then `glam`, then `glamx` (each depends on the previous
  one being on the registry) need the owner's scarbs.xyz token (`SCARB_REGISTRY_AUTH_TOKEN`),
  which the orchestrator never handles.
- Known debt, not blocking: six test files exceed the 1 200-line budget (camera, vec2/3/4,
  ivec3/4; `Test glam` ~23 min in CI); splitting them into `test_<m>_panics.cairo` needs the
  orchestrator-owned `tests/lib.cairo`. The appendix of `docs/audits/R1-deviations.md` is a
  snapshot of 2026-09-21 (not gated).
- Next: whatever the sibling repositories escalate (missing `fixed` kernels get added here with
  their bench and snapshot; any numeric change is a MINOR bump, DESIGN section 6). Coordination
  decision taken on 2026-09-22: `nalgebra-cairo` keeps its `simba` trait layer and drops its
  duplicate Q32.32 scalar in favour of `fixed` pinned on `v0.1.0` (the Rust model: one primitive
  scalar, simba is traits only).
- Operational lessons of the R1 session (all recorded in `docs/ORCHESTRATOR.md`): launch agents
  as systemd user units (`scripts/agent.sh`), never as children of the session; Sonnet agents
  end their turn on background commands despite the written rule, so the launch prompt itself
  must say "foreground only"; a shared machine at full CPU gets agents OOM-killed, resume them
  with their context rather than relaunching; `gh pr merge --delete-branch` fails on the agent's
  untracked `REPORT.md`, archive it and remove the worktree by hand.
