# Execution plan

How the port is sequenced and delegated. Status per item lives in `docs/PORTING_STATUS.md`;
design decisions in `docs/DESIGN.md`; evidence in `docs/research/`.

## Operating model

- One **orchestrator** session owns sequencing, task briefs, review, merges, the serialized files
  (`Scarb.toml`, `lib.cairo` files, `scripts/**`, `.github/**`, `docs/DESIGN.md`,
  `docs/PORTING_STATUS.md`, `CHANGELOG.md`) and the
  releases. It does not write large implementations.
- **Porter sub-agents** each own exactly one module: source + tests + benches + docs, in an
  isolated git worktree and branch (`feat/<module>`), delivered as one pull request.
- Every module file, test file and bench file already exists as an empty stub and is already
  declared in the `lib.cairo` files, and gas snapshots are one file per module
  (`gas/<module>.snap`): **parallel pull requests never touch a shared file**.
- Merge gate: CI `all-checks` green (fmt, lint, build, tests, gas snapshot check, docs) + the
  orchestrator's review of API parity, deviations and the gas table. Squash merge.
- When the optimum is unclear, the porter implements the variants (math / bitwise / loop / table),
  benches them, ships the winner and leaves the losers in `benches::alt` (DESIGN rule 9).

## Waves

Dependencies come from the glam-rs analysis (report 01 section 4). Items inside a wave are
independent and run in parallel; a wave starts when the modules it depends on are merged.

### Wave 0 - foundations (orchestrator, serialized) - DONE in the bootstrap PR
Research reports, workspace, toolchain pin, bench harness + snapshot script, CI, `AGENTS.md`,
`DESIGN.md`, this plan.

### Wave 1 - the scalar (critical path)
| id | task | depends on |
|---|---|---|
| F1 | `fixed` tier A: consts, `from_*`/`to_*`, `Add Sub Mul Div Rem Neg`, `PartialOrd`, `abs signum copysign min max clamp`, `floor ceil round trunc fract fract_gl`, `recip`, `sqrt`, `div_euclid rem_euclid`, `lerp`-family (`FloatExt`), `Zero`/`One`, bounded-int plumbing generator | - |
| F2 | `fixed::wide`: accumulator types, `dot2/3/4`, `mul_sub`, `mul_add`, `norm2/3/4`, wide-sum API for larger kernels | F1 (same agent, second PR) |
| F3 | `fixed::trig` tier B: `sin cos sin_cos tan atan2 acos asin` + coefficient generator + bit-exact Python mirror + error sweeps | F1 |
| T1 | `tools/refgen`: Rust crate pinned to glam `=0.33.8` generating golden vectors (f64 oracle, Q32.32-quantized inputs, seeded) as Cairo test data | - (parallel with F1) |

### Wave 2 - vectors (parallel, after F1+F2; `angle`/`rotate` methods need F3)
| id | task |
|---|---|
| V0 | `BVec2`, `BVec3`, `BVec4` |
| V2 | `Vec2` core (incl. `perp`, `perp_dot`, `angle_to`, `rotate`, `from_angle`) |
| V3 | `Vec3` core (incl. `cross`, `any_orthonormal_pair`; Quat-dependent methods deferred to wave 4) |
| V4 | `Vec4` core |
| VI | `IVec2/3/4` and `UVec2/3/4` (independent of `fixed`, can start in wave 1) |

### Wave 3 - matrices and quaternion (parallel)
| id | task | depends on |
|---|---|---|
| M2 | `Mat2` | V2 |
| M3 | `Mat3` (core: no `from_quat`, no `Mat4` conversions) | V2, V3 |
| M4 | `Mat4` (core) | V3, V4 |
| Q1 | `Quat` core (`mul_quat`, `mul_vec3`, `normalize`, `from_axis_angle`, `from_scaled_axis`, `to_axis_angle`, `lerp`/`nlerp`, `slerp`, `inverse`, ...) | V3, V4, F3 |
| S1 | swizzle traits for `Vec2`, `Vec3` (generated) | V2, V3, V4 |

### Wave 4 - cross-type integration (parallel)
| id | task | depends on |
|---|---|---|
| X1 | cycle-closing methods: `Vec3::rotate_*`, `Mat3/Mat4::from_quat`, `Quat::from_mat3/4`, `Mat2<->Mat3<->Mat4` conversions, TRS compose / decompose | M2-M4, Q1 |
| A2 | `Affine2` | M2, (M3 for conversions) |
| A3 | `Affine3` | M3, Q1, (M4 for conversions) |
| E1 | `EulerRot` (24 orders) and the `from_euler`/`to_euler` methods | M3, Q1 |

### Wave 5 - completion
| id | task |
|---|---|
| C1 | `camera` module (`rh`/`lh` x `view` / `proj::{opengl,vulkan,directx}`), deprecated `Mat4::perspective_*`/`look_at_*` aliases skipped |
| S2 | `Vec4` and integer swizzles |
| F4 | `fixed` tier C: `exp exp2 ln log2 powf` and the element-wise vector wrappers |
| P0 | bootstrap of the `glamx` package (manifest, stubs, CI matrix, benches dependency, refgen `glamx =0.3.1` f64 oracle): done by the orchestrator. Scope and priorities: `docs/research/06-glamx-scope.md` |
| P1a | `glamx::pose3` (+ `rot3` alias of `Quat`): `Pose3 { rotation: Quat, translation: Vec3 }`, fused `inv_mul`, `transform_point`... |
| P1b | `glamx::rot2`: `Rot2 { re, im }` |
| P1c | `glamx::pose2` (after P1b) |
| P1d | `glamx::sdp`: parry's `SdpMatrix3` / `SdpMatrix2` and the fused world-inertia kernel `R D R^T` |
| P1e | `glamx::eigen3`: `SymmetricEigen3` (setup-time only, low priority; `Svd*`, `SymmetricEigen2`, look-at are not ported: no consumer in parry / rapier) |
| X2 | `IVec*/UVec*::as_vec*` casts (gap found by the P1 research; needed by voxel code) |
| R1 | audit pass: API parity table vs glam-rs 0.33.8, optimizer pass over the top-20 hottest benches, README gas tables, `v0.1.0` tag, publish `fixed` then `glam` on scarbs.xyz |

The physics-critical path is `F1 -> F2 -> V3 -> M3 + Q1 -> A3/P1`. The 2D track
(`V2 -> M2 -> A2`) is independent and is the cheapest end-to-end slice.

## Porter brief template

Each delegation message contains: the task id and goal; the glam-rs source files to mirror
(`docs/research` clone path or URL at tag 0.33.8); the files the agent may edit (its module, its
test file, its bench file, its `gas/<module>.snap`, `benches/src/alt/<module>.cairo`); the API list; acceptance = `scripts/check.sh` green +
definition of done of `AGENTS.md`; and the report format. Agents read `AGENTS.md` and
`docs/DESIGN.md` first.

## Risks

| risk | mitigation |
|---|---|
| `core::internal::bounded_int` changes or breaks (unstable API; misuse = compiler panic) | isolated in `fixed::internal`, generated plumbing, pinned toolchain, stable fallback in `benches::alt` |
| overflow panics make a physics step unprovable (liveness) | document ranges per kernel, `try_*` variants where glam has them, engine-level bounds belong to `rapier-cairo` |
| f32-tuned epsilons meaningless at 2^-32 resolution | re-derived per call site in ULPs (DESIGN section 3) |
| bytecode growth from `inline(always)` + polynomial segments | track class size once a consumer contract exists (wave 5 audit) |
| gas numbers shift with compiler releases | snapshots are per-toolchain; bumps are dedicated PRs |
