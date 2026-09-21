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
| P1a | `glamx::pose3`, `glamx::rot3` | todo | |
| P1b | `glamx::rot2` | todo | |
| P1c | `glamx::pose2` | todo | |
| P1d | `glamx::sdp` | todo | |
| P1e | `glamx::eigen3` | todo | |
| X2 | `IVec*/UVec*::as_vec*` | todo | |
| R1a | API parity table (`scripts/api_parity.py`, `docs/API_PARITY.md`) | done | #20 |
| X3 | parity closure: the items still `missing` in `docs/API_PARITY.md` | todo | |
| R1 | audit, optimizer pass, `v0.1.0` | todo | |
