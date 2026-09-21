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
| R1 | release audit: optimizer pass, deviation review, bytecode size, `v0.1.0` (see `docs/HANDOFF.md`, briefs `docs/briefs/R1-common.md` + `R1c`..`R1i`) | inprogress | |
| R1c | optimizer pass on `glamx::eigen3` (values-only path, polish, rotation cost) | inprogress | |
| R1d | optimizer pass on `quat` (shared `slerp` helper, `rotate_towards`, wide `is_normalized`); after R1e | todo | |
| R1e | optimizer pass on `fixed::wide` + `Vec2/3/4`: `is_unit2/3/4` kernels (`is_normalized` total and ~2x cheaper), shared norm in `Vec3::rotate_towards`; single-division and `slerp` candidates measured and kept in `benches::alt` | done | #32 |
| R1f | `camera` / `Mat4::look_to_*` duplication; after R1i (bytecode evidence) | todo | |
| R1g | faster bench job: one snforge test crate per bench file (CI bench job 928 s -> 198 s, local check ~2 090 s -> 230 s, snapshots identical); `all-checks` is now bounded by `Test glam` (~16 min) | done | #33 |
| R1h | audit of every `#### Deviations` entry against DESIGN section 3 (`docs/audits/R1-deviations.md`); 8 rows added to DESIGN section 3 | done | #30 |
| R1j | `glamx::rot2`: `lerp` aligned with upstream (not normalised), `is_normalized` added (audit P0); after R1e (wide kernel) | todo | |
| R1k | panic coverage: item/branch -> `should_panic` test manifest and checker, doc template on the nine `IndexView` impls (audit P0) | todo | |
| R1l | doc-only deviation fixes, one PR per package: `Deviations: None.` on items that panic where upstream continues, stale camera module doc, non-semantic bullets moved out of `Deviations` (audit P1/P2); after the optimizer PRs | todo | |
| R1i | bytecode size of a consumer contract (`packages/consumer`, `docs/audits/R1-bytecode-size.md`): kitchen-sink class at 61.5 % of the 81 920 CASM felt limit, keep the inlining | inreview | #31 |
| R1z | `v0.1.0`: changelog, tag, GitHub release, scarbs.xyz (owner's confirmation required) | todo | |
