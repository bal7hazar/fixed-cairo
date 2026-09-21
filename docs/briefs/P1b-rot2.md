# P1b - `glamx::rot2`

Branch `feat/glamx-rot2`. Read `docs/briefs/P1-glamx-common.md` and `docs/briefs/COMMON.md`.
Module `rot2`.

Mirror glamx `rot2.rs` (report 06 section 6.1 item 2, tier 2 item 6): `Rot2 { re, im }`
(unit complex number, public fields), `IDENTITY`, `from_cos_sin_unchecked`, `new` / `from_angle`
(one `sin_cos`), `angle` (`atan2(im, re)`), `cos`, `sin`, `inverse` (conjugate), `Rot2 * Rot2`
(`Mul`: two fused 2-term sums, `dot2` / `mul_sub`), `transform_vector` /
`inverse_transform_vector` (+ `mul_vec2` named method), `to_mat` (`Mat2`), `from_mat` /
`from_mat_unchecked`, `normalize`, `normalize_mut` (as `ref self`), `length`, `length_squared`,
`dot`, `lerp` (normalised), `slerp`, `angle_between`, `rotate_towards`, `from_rotation_arc`.
Skip `powf`, `is_finite` / `is_nan` (no consumer).

Numerics: `normalize` through `fixed::wide` (`normalize2`); the near-zero threshold re-derived in
ULPs; **measure and document the norm drift of `Rot2 * Rot2`** under floor rounding (report 06
section 6.5.2 estimates a shrink of up to ~2^-32 per composition): add a fuzz/table test pinning
the drift after 100 and 1 000 compositions and state the renormalisation policy in the type doc.
Gas targets: `Rot2 * Rot2` and `mul_vec2` below `Vec2::rotate` (~4 700); `new` ~ one `sin_cos`.
