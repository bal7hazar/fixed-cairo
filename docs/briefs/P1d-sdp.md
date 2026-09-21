# P1d - `glamx::sdp`: symmetric matrices and the world-inertia kernel

Branch `feat/glamx-sdp`. Read `docs/briefs/P1-glamx-common.md` and `docs/briefs/COMMON.md`.
Module `sdp`. This one is NOT in upstream glamx: it mirrors parry's `utils/sdp_matrix.rs`
(`SdpMatrix2`, `SdpMatrix3`) and the inertia code of rapier (`angular_inertia_ops.rs`) and parry
(`mass_properties.rs`), which report 06 (sections 3.4, 6.1 item 4) identifies as the per-body,
per-step matrix hot spot. The golden oracle is therefore written by hand in
`tools/refgen/src/oracles/sdp.rs` with f64 `DMat3` / `DMat2` arithmetic (and exact i128 integer
oracles wherever the Cairo result is an exactly defined fused sum).

API: `SdpMatrix3 { m11, m12, m13, m22, m23, m33 }` and `SdpMatrix2 { m11, m12, m22 }` with parry's
names: `new`, `from_sdp_matrix` (from a full `Mat3` / `Mat2`), `zero`, `identity`, `diagonal`,
`is_zero`, `add` / `sub` / `mul_scalar` (operators where homogeneous), `mul_vec` (`SdpMatrix3 *
Vec3`), `quadform` (`M^T S M` for a `Mat3`) and the `quadform3x2`-style variants parry defines,
`inverse` / `inverse_unchecked` (adjugate of the symmetric matrix, ONE shared `Recip` of the
determinant; 6 outputs instead of 9), `into_matrix` (`Mat3`), and the **world-inertia kernel**
`from_rotated_diagonal(rotation: Quat, d: Vec3) -> SdpMatrix3` = `R diag(d) R^T` computed
directly into its 6 unique entries with fused sums (one rescale per output scalar, via the
`W*`/`T*` accumulators of `fixed::wide`: each entry is a sum of three triple products
`r_ik * d_k * r_jk`), plus the variant taking a `Mat3` rotation. Report 06 estimates rapier's
literal formula at ~59 000 gas (`from_quat` 20 660 + `transpose` + 3 `mul_scalar` + `mul_mat3`
19 640): implement that literal form in `benches::alt::sdp`, bench both, and report the gain. If
a kernel shape is missing from `fixed::wide`, use the composable accumulators and list the
missing named kernel under "Escalations".

Tests: symmetry and exactness on diagonal / axis-aligned rotations (a 90-degree rotation permutes
`d` exactly), `inverse(inverse(S)) ~ S` and `S * S^-1 ~ I` in ULPs, `quadform` against the full
`Mat3` product, positive-definiteness is a documented precondition (not checked), singular panic
`'SdpMatrix3: singular'`.
