# glamx porter tasks - shared context (read with `COMMON.md`)

You port one module of the `glamx` package of this repository (`packages/glamx`): the Cairo port of
Dimforge's glamx 0.3.1, the math layer parry and rapier are written against, on top of the merged
`glam` and `fixed` packages. Read `docs/research/06-glamx-scope.md` first (sections 2, 3.2, 6): it
lists, per item, what parry / rapier actually use, the quirks that matter in fixed point and the
design decisions. Decisions already taken by the orchestrator:

- `Pose3 = { rotation: Quat, translation: Vec3 }`, `Rot2 = { re, im }` with public fields (rapier
  reads them), `Rot3` is a type alias of `glam::Quat`, `Pose2 = { rotation: Rot2, translation: Vec2 }`.
- Naming follows glam.cairo (`Pose3Trait`/`Pose3Impl`, operator impls `Pose3Mul`; heterogeneous
  products are named methods: `mul_vec3`, `mul_rot3`...). If a glamx associated function shares
  its name with a public field (`Pose3::translation(x, y, z)`, `Pose3::rotation(axis_angle)`),
  check that the Cairo compiler accepts it; otherwise name it `from_translation` /
  `from_rotation` and document the deviation.
- Do not port what has no consumer in parry / rapier (report 06 section 6.1 "Do not port").
- f32-tuned thresholds are re-derived in raw ULPs and documented under `#### Deviations`.
- Rotations are not renormalised by composition (as upstream); document the measured norm drift
  per composition so that `rapier.cairo` knows how often to call `normalize`.

Sources: `git clone --depth 1 --branch v0.3.1 https://github.com/dimforge/glamx /tmp/glamx` (if the
tag is missing, use the default branch at the commit of "Release v0.3.1"); parry and rapier are
at `/tmp/p1/{parry,rapier}` if still present, otherwise
`git clone --depth 1 https://github.com/dimforge/parry /tmp/p1/parry` (same for rapier).

Files of a module `<m>` (strict allowlist): `packages/glamx/src/<m>.cairo`,
`packages/glamx/tests/test_<m>.cairo`, `packages/glamx/tests/golden_<m>.cairo` (refgen-generated
only; spec `package = "glamx"`), `packages/benches/tests/bench_<m>.cairo`,
`packages/benches/src/alt/<m>.cairo`, `gas/<m>.snap`, `tools/refgen/specs/<m>.toml`,
`tools/refgen/src/oracles/<m>.rs`. The refgen crate already depends on `glamx =0.3.1` (features
`f64`, `libm`, `std`): use its `DPose3` / `DRot2`-style f64 types as the oracle. New value types
(`Pose3`, `Rot2`...) are declared in the spec with the `[types.X]` layout override documented in
`tools/refgen/README.md`; a minimal `tools/refgen/src/**` fix is allowed if that mechanism falls
short (say so in the report). Do not edit `packages/glamx/src/lib.cairo`: list the re-exports you
need in the report. All stubs are already declared.
