# P1a - `glamx::pose3` (+ `glamx::rot3`)

Branch `feat/glamx-pose3`. Read `docs/briefs/P1-glamx-common.md` and `docs/briefs/COMMON.md`.
Modules `pose3` and `rot3` (allowlist of both modules).

`rot3.cairo`: `pub type Rot3 = glam::Quat;` plus whatever thin helpers glamx's `rot3.rs` adds that
parry / rapier use (check the report's counts); confirm that trait impls resolve through the alias.

`pose3.cairo`, mirroring glamx `pose3.rs` (report 06 section 6.1 item 1 and tier 2 item 6):
`IDENTITY`, `from_parts`, `new` (translation + axis-angle), translation / rotation constructors,
`prepend_translation`, `append_translation`, `inverse` (conjugate: no division), **fused**
`inv_mul`, `transform_point`, `transform_vector`, `inverse_transform_point`,
`inverse_transform_vector`, `Pose3 * Pose3` (`Mul`), `mul_rot3` / `rot3_mul_pose3`-style named
heterogeneous products, conversions from `Rot3` and `(Vec3, Rot3)`, `to_mat4` / `to_affine3`-style
conversions if upstream has them (use `Quat::from_mat3` of the linear part for `from_mat4`, not the
TRS decomposition, and document the rigid-only precondition), `lerp` as an nlerp variant (slerp
costs 122k gas: provide both if upstream has both), `abs_diff_eq`.

Numerics / gas: the estimates of report 06 section 6.2 are additive sums of existing snapshot
entries (`Pose3 * Pose3` ~22 800, `inv_mul` ~23 800, `transform_point` ~12 800,
`inverse_transform_point` ~13 800): fused implementations must come out lower. In particular
`inv_mul(a, b) = (conj(qa) * qb, conj(qa) * (tb - ta))` shares `conj(qa)`; rotating by a conjugate
quaternion is a sign flip inside the fused triple products of `Quat::mul_vec3`, not a separate
`conjugate` + call: bench the fused form against the composed one (DESIGN rule 9) and keep the
loser in `benches::alt::pose3`.
