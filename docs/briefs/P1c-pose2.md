# P1c - `glamx::pose2`

Branch `feat/glamx-pose2`. Read `docs/briefs/P1-glamx-common.md` and `docs/briefs/COMMON.md`.
Module `pose2`. The merged `packages/glamx/src/pose3.cairo` (+ tests, golden spec
`tools/refgen/specs/pose3.toml`, oracles, benches, `benches::alt::pose3`) is the direct precedent:
same structure, same naming, same fused-versus-composed benches; `packages/glamx/src/rot2.cairo`
is the rotation type.

Mirror glamx 0.3.1 `pose2.rs`: `Pose2 { rotation: Rot2, translation: Vec2 }` with public fields,
`IDENTITY`, `from_parts`, `new` (translation + angle), translation / rotation constructors,
`prepend_translation`, `append_translation`, `inverse` (conjugate rotation: no division), fused
`inv_mul`, `transform_point`, `transform_vector`, `inverse_transform_point`,
`inverse_transform_vector`, `Pose2 * Pose2` (`Mul`), named heterogeneous products with `Rot2`
(`mul_rot2`, and an extension trait for `Rot2 * Pose2` as `pose3` does), conversions from `Rot2`
and `(Vec2, Rot2)`, `to_mat3` / `from_mat3` if upstream has them (rigid-only precondition
documented), `lerp` (follow what `rot2.cairo` and `pose3.cairo` did and document), `abs_diff_eq`.

Gas: report 06 section 6.2 estimates `Pose2 * Pose2` and `inv_mul` at ~12 000 as sums of existing
entries; the fused forms must come out lower (`Rot2 * Rot2` and `mul_vec2` are 4 680 each in
`gas/rot2.snap`; `inv_mul` shares the conjugate: a sign flip inside the fused sums, not a call).
Keep every composed variant in `benches::alt::pose2` with its bench.
