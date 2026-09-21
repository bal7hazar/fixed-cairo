# A3 - `Affine3`

Branch `feat/affine3`. You are a PORTER agent on glam.cairo (Cairo port of glam-rs 0.33.8 on the
Q32.32 scalar `fixed::Fixed`; provable physics engine; gas/step cost is the top priority).
`Affine3` is the rigid/affine transform the physics engine will use most: a `Mat3` linear part
`matrix3` + a `Vec3` `translation`. Depends on `Vec3`, `Mat3`, `Mat4`, `Quat` and the X1 methods
(`Mat3::from_quat`, `Quat::from_mat3`, TRS decomposition), all merged on `main`. The merged
`packages/glam/src/affine2.cairo` (+ its tests, golden spec, benches) is the direct precedent.

## Scope (strict file allowlist)

`packages/glam/src/affine3.cairo` (hand-written), `packages/glam/tests/test_affine3.cairo`,
`packages/glam/tests/golden_affine3.cairo` (refgen-generated only),
`packages/benches/tests/bench_affine3.cairo`, `packages/benches/src/alt/affine3.cairo`,
`gas/affine3.snap`, `tools/refgen/specs/affine3.toml`, `tools/refgen/src/oracles/affine3.rs`.

## API

Mirror glam-rs `src/f32/affine3.rs` (the non-SIMD `Affine3`; `Affine3A` collapses into it; tests
in `tests/affine3.rs`): struct `Affine3 { matrix3: Mat3, translation: Vec3 }` (Copy, Drop, Serde,
PartialEq, Debug, Hash; `Default` = IDENTITY), consts `ZERO`, `IDENTITY`; `from_cols`,
`from_cols_array`, `to_cols_array`, `from_cols_array_2d`, `to_cols_array_2d`, `from_scale`,
`from_quat`, `from_axis_angle`, `from_rotation_x/y/z`, `from_translation`, `from_mat3`,
`from_mat3_translation`, `from_scale_rotation_translation`, `from_rotation_translation`,
`from_mat4`, `to_scale_rotation_translation`, `look_to_lh/rh`, `look_at_lh/rh`,
`transform_point3`, `transform_vector3`, `inverse`, `abs_diff_eq`, `Mul<Affine3>` (composition:
`matrix3 * rhs.matrix3`, `translation = matrix3 * rhs.translation + translation` with the fused
`dot3_add`), named `mul_mat4` / `Mat4` conversions (`Into<Mat4>`, `from_mat4`), and
`Quat::from_affine3` delivered as a function of this module (`quat_from_affine3`) or an extension
trait, since `quat.cairo` is not yours (document the deviation). Drop `is_finite`/`is_nan`.

Physics-oriented additions (not in glam, from Dimforge's `glamx` `Pose3`; keep them in a clearly
separated `Affine3RigidTrait` so the glam parity surface stays clean): `inverse_rigid` (for a
rotation + translation: `R^T`, `-(R^T t)`: no determinant, no division) and `inv_mul(self, rhs)`
= `self.inverse_rigid() * rhs` fused. Document the precondition (orthonormal `matrix3`).

## Numerics and gas

`inverse`: `Mat3::inverse` semantics (adjugate, ONE shared `Recip` of the determinant), then the
translation `-(inv * t)` fused; bench it against composing `Mat3::inverse` + `mul_vec3` + `neg`;
panics `'Affine3: singular'`. Composition is 9 `dot3` + 3 `dot3_add`: target about
`Mat3 * Mat3` (19 640) + `Mat3 * Vec3` (7 160) + small change; `transform_point3` about 7 800
(see `gas/mat4.snap`), `inverse_rigid` should be far below `inverse` (39 530 for the `Mat3` part).

## Tests

Table-driven; identities (`IDENTITY * a = a`, `a * a.inverse() ~ IDENTITY` in ULPs,
`inverse_rigid == inverse` within ULPs on rotations + translations, TRS round trip), exact
90-degree cases, panics, <= 6 fuzz properties (`runs: 128`); refgen golden with glam-rs
`DAffine3` oracles (products exact-integer where possible; inverse/TRS with justified tolerances).
