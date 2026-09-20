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
| X1 | cross-type methods | inprogress | worktree `cli-x1`, branch `feat/x1`, uncommitted |
| A2 | `affine2` | done | #14 |
| A3 | `affine3` | todo | |
| E1 | `euler` | done | #15 |
| C1 | `camera` | inprogress | worktree `cli-camera`, branch `feat/camera`, uncommitted |
| S2 | swizzles (Vec4, integer) | done | #10 |
| F4 | `fixed` tier C (`exp`, `ln`, `powf`) | todo | |
| P1 | physics extensions (`Rot2`, `Pose2`, `Pose3`) | todo | |
| R1 | audit, optimizer pass, `v0.1.0` | todo | |

## Resume notes (2026-09-20 19:40, graceful shutdown)

- #15 (`feat/euler`) merged at 19:48 with its re-exports.
- X1 and C1 agents were still working when the machine was shut down: their files are on disk in
  `.claude/worktrees/cli-x1` and `cli-camera` and snapshotted as ungated `wip(...)` commits on
  `origin/feat/x1` and `origin/feat/camera` (squash them into the real commit before the PR); resume with `claude --continue -p "<finish: run
  scripts/check.sh in the foreground, commit, push, open the PR, write REPORT.md>"` from the
  worktree, or restart from `docs/ORCHESTRATOR.md` briefs (`scratchpad/prompts/*.md` are
  session-local and may be gone).
- Not started: A3 `affine3` (depends on X1 for `Mat3::from_quat`), F4 tier C, P1 physics
  extensions, R1 audit / v0.1.0. After A3 + X1 land, `Quat::from_affine3` closes the last cycle.
- Re-exports so far: BVec*, IVec*, UVec*, Vec2/3/4, swizzles, Quat, Mat2/3/4, Affine2.
