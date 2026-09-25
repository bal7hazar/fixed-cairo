# Repository split (decided 2026-09-25)

The owner's rule is to mirror the Rust reference repository by repository. glam-rs
(`bitshifter/glam-rs`) contains `glam` only; `glamx` is its own repository at Dimforge
(`dimforge/glamx`); `f64` has no repository (it is a language primitive), and its Cairo
counterpart `fixed` is the common foundation of two independent chains
(`fixed -> glam -> glamx -> parry -> rapier` and `fixed -> simba -> nalgebra -> rapier`), so it
gets its own repository too.

| repository | packages | depends on (registry) |
|---|---|---|
| `bal7hazar/fixed-cairo` | `fixed` | - |
| `bal7hazar/glam-cairo` (this one) | `glam` | `fixed` |
| `bal7hazar/glamx-cairo` | `glamx` | `fixed`, `glam` |
| `bal7hazar/nalgebra-cairo` | `nalgebra` (its `simba` crate moves to `simba-cairo`: its orchestrator's task) | `fixed` |
| `bal7hazar/rapier-cairo` | `rapier*` (whether a `parry-cairo` is split out is its orchestrator's call) | all of the above |

## Rules

- **History**: each new repository starts from the full history of `glam-cairo` (branch cut from
  `origin/main`), then one commit removes everything that does not belong to it. `git log
  --follow` / `git blame` keep working. Tags are not copied: `v0.1.0`..`v0.3.0` stay the releases
  of `glam-cairo`, from which `fixed`, `glam`, `glamx` 0.1.0..0.3.0 were published.
- **Packages and registry**: names unchanged (`fixed`, `glam`, `glamx`); no release is needed for
  the split itself: `glam-cairo` and `glamx-cairo` pin the published `0.3.0`. The next release of
  each package is cut from its own repository (`repository` metadata updated then).
- **Tooling**: each repository carries its own copy of what its gate needs (bench harness `bb` /
  `sink`, `scripts/bench.py`, `check.sh`, `panic_coverage.py`, `deviations.py`,
  `gas_tables.py`, `bytecode_size.py` + a consumer fixture, `tools/refgen` with its own specs and
  oracles, the CI workflow), pruned to its packages. Divergence between the copies is accepted.
- **Documents**: each repository has its `AGENTS.md`, `CLAUDE.md`, `README.md`, `CHANGELOG.md`
  and `docs/DESIGN.md` (section 2 "The scalar" moves to `fixed-cairo`; `glam-cairo` keeps the
  rest and points to it; `glamx-cairo` keeps what concerns `glamx`). The orchestration documents
  (`docs/ORCHESTRATOR.md`, `HANDOFF.md`, `PLAN.md`, `PORTING_STATUS.md`, `briefs/`, `research/`,
  `audits/`) stay here: `glam-cairo` is the home of the orchestrator of the three repositories.
- **Escalations** from `nalgebra-cairo` / `rapier-cairo` about the scalar go to `fixed-cairo`.
  A `fixed` MINOR bump now means one pull request per consuming repository (as in the Rust
  ecosystem: `glamx` pins `glam ^0.33`).

## Tasks

| id | task | repository | after |
|---|---|---|---|
| S1 | extract `fixed-cairo` (history, prune, standalone gate and CI) | new | #41 |
| S2 | extract `glamx-cairo` (history, prune, depend on `fixed` / `glam` 0.3.0 from the registry) | new | #41 |
| S3 | remove `fixed` and `glamx` from `glam-cairo`, depend on `fixed` 0.3.0 from the registry | this | S1, S2 green |
