# Porting status

Maintained by the orchestrator after each merge. Task ids refer to `docs/PLAN.md`.
Status: `todo`, `inprogress`, `inreview`, `done`.

| id | module(s) | status | PR |
|---|---|---|---|
| W0 | research, workspace, CI, bench harness, docs | done | bootstrap |
| F1 | `fixed::fixed` tier A | done | #6 |
| F2 | `fixed::wide` fused kernels | done | #6 |
| F3 | `fixed::trig` tier B | done | #8 |
| T1 | `tools/refgen` golden vector generator | done | #3 |
| V0 | `bvec2`, `bvec3`, `bvec4` | done | #2 |
| V2 | `vec2` | done | #9 |
| V3 | `vec3` | done | #9 |
| V4 | `vec4` | done | #9 |
| VI | `ivec2/3/4`, `uvec2/3/4` | done | #5 |
| M2 | `mat2` | done | #13 |
| M3 | `mat3` | done | #13 |
| M4 | `mat4` | done | #13 |
| Q1 | `quat` | done | #12 |
| S1 | swizzles (Vec2, Vec3) | done | #10 |
| X1 | cross-type methods | done | #17 |
| A2 | `affine2` | done | #14 |
| A3 | `affine3` | done | #21 |
| E1 | `euler` | done | #15 |
| C1 | `camera` | done | #16 |
| S2 | swizzles (Vec4, integer) | done | #10 |
| F4 | `fixed` tier C (`exp`, `ln`, `powf`) | done | #18 |
| P0 | `glamx` package bootstrap + scope research (`docs/research/06-glamx-scope.md`) | done | #19 |
| P1a | `glamx::pose3`, `glamx::rot3` | done | #22 |
| P1b | `glamx::rot2` | done | #24 |
| P1c | `glamx::pose2` | done | #27 |
| P1d | `glamx::sdp` | done | #23 |
| P1e | `glamx::eigen3` | done | #29 |
| X2 | `IVec*/UVec*::as_vec*` | done | covered by the `Into<IVecN, VecN>` / `Into<UVecN, VecN>` impls (`docs/API_PARITY.md`: 0 missing) |
| R1a | API parity table (`scripts/api_parity.py`, `docs/API_PARITY.md`) | done | #20 |
| X3a | parity closure of `Vec2/3/4` (element-wise transcendentals, `step`/`smoothstep`/`saturate`, `From<BVec>`, homogeneous, `project`) | done | #25 |
| X3b | parity closure of `Quat`, `Mat3/4`, `Affine2/3`, camera views | done | #26 |
| R1b | generated gas tables in the READMEs (`scripts/gas_tables.py`, checked in CI) | done | #28 |
| R1 | release audit: optimizer pass, deviation review, bytecode size, `v0.1.0` (briefs `docs/briefs/R1-common.md` + `R1c`..`R1m`) | done | #30-#39 |
| R1c | optimizer pass on `glamx::eigen3`: metered one-rotation iterations (zero pivots free), polish-free `eigenvalues`, diagonal short-circuit: `new` -8.6 %, `eigenvalues` -15.9 %, diagonal -45.5 %; rotation order changed (numeric change, all overall worst cases improve) | done | #34 |
| R1d | optimizer pass on `quat`: `rotate_towards` 162 720 -> 129 100 gas, `slerp` back to 122 180, `is_normalized` / `is_near_identity` total and ~2x cheaper; flaky `fuzz_mul_quat_drift` fixed (test helper built quaternions 5 ULP off unit) | done | #36 |
| R1e | optimizer pass on `fixed::wide` + `Vec2/3/4`: `is_unit2/3/4` kernels (`is_normalized` total and ~2x cheaper), shared norm in `Vec3::rotate_towards`; single-division and `slerp` candidates measured and kept in `benches::alt` | done | #32 |
| R1f | `camera` / `Mat4::look_to_*` duplication | dropped | the bytecode audit (#31) shows no gain: inlined bodies are paid per call site whichever function holds them |
| R1g | faster bench job: one snforge test crate per bench file (CI bench job 928 s -> 198 s, local check ~2 090 s -> 230 s, snapshots identical); `all-checks` is now bounded by `Test glam` (~16 min) | done | #33 |
| R1h | audit of every `#### Deviations` entry against DESIGN section 3 (`docs/audits/R1-deviations.md`); 8 rows added to DESIGN section 3 | done | #30 |
| R1j | `glamx::rot2`: `lerp` aligned with upstream (not normalised, 15 330 -> 4 880 gas), `is_normalized` added (audit P0) | done | #35 |
| R1k | panic coverage: `scripts/panic_coverage.py` (item -> `should_panic` test, checked in CI), 324 tests added (372 missing pairs -> 0), doc template on the nine `IndexView` impls | done | #37 |
| R1m | follow-up of #37: the 21 allowlisted `quat` panic tests, and the 25 escalated doc gaps (documented panics that cannot happen, wrong native messages on `move_towards` / sdp); brief `docs/briefs/R1m-panic-followup.md` | done | #39 |
| R1l | doc-only deviation fixes: stale camera module doc, `Deviations: None.` replaced on items that panic where upstream continues, non-semantic bullets moved out of `Deviations` | done | #38 |
| R1i | bytecode size of a consumer contract (`packages/consumer`, `docs/audits/R1-bytecode-size.md`): kitchen-sink class at 61.5 % of the 81 920 CASM felt limit, keep the inlining; `gas/bytecode.size` checked in CI | done | #31 |
| R1z | `v0.1.0`: tag `v0.1.0` (2ac9a82) and GitHub release cut 2026-09-22; `scarb publish` of `fixed`, `glam`, `glamx` by the owner | done | [release](https://github.com/bal7hazar/glam-cairo/releases/tag/v0.1.0) |
| F5 | `fixed::wide::Acc` count-agnostic accumulator + `WideSqrt` for `W1..W16` (nalgebra-cairo escalation, 2026-09-23); release `v0.2.0` of the three packages (tag on 69c2db7, published on scarbs.xyz 2026-09-23) | done | #40, [release](https://github.com/bal7hazar/glam-cairo/releases/tag/v0.2.0) |
| F6 | correctly rounded `div_nearest` / `recip_nearest` / `RecipTrait::div_nearest` (nalgebra-cairo escalation, 2026-09-23); `/`, `recip`, `from_ratio` switched to round-half-even (Rust reference; +10.7 % on `/`, 173 benches in 18 snapshots); released `v0.3.0` (tag on e30f7e6, published on scarbs.xyz 2026-09-23) | done | #42, [release](https://github.com/bal7hazar/glam-cairo/releases/tag/v0.3.0) |
| D1 | reproducible environment for `scripts/gen_trig.py` / `gen_exp.py` (numpy / mpmath not pinned: `emit --check` depends on the numpy version; not in the gate) | todo | |
| D2 | test files over the 1 200-line budget (camera, vec2/3/4, ivec3/4; `Test glam` ~23 min in CI) | todo | |
