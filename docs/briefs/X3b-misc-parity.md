# X3b - parity closure of `Quat`, `Mat3`, `Mat4`, `Affine2`, `Affine3`, `camera::*::view`

Branch `feat/misc-parity`. Read `docs/briefs/COMMON.md`. Close every item that
`docs/API_PARITY.md` lists as `missing` outside of `Vec2/3/4` (another agent owns those).

Allowlist: `packages/glam/src/{quat,affine2,affine3}.cairo`, `packages/glam/src/camera/**`,
`tools/codegen/fmat.py` + `fmat_tests.py` and the generated `packages/glam/src/{mat3,mat4}.cairo`,
`packages/glam/tests/test_{mat3,mat4}.cairo` (generator edits only, other outputs byte-identical),
`packages/glam/tests/test_{quat,affine2,affine3,camera}.cairo`, the matching `golden_*.cairo`
(refgen only) with their `tools/refgen/specs/*.toml` and `tools/refgen/src/oracles/*.rs`, the
matching `packages/benches/tests/bench_*.cairo`, `packages/benches/src/alt/*.cairo`,
`gas/*.snap`, `docs/API_PARITY.md` (generated), `scripts/api_parity.py` (rules only).

Items (glam-rs 0.33.8 names and semantics):
- `Quat`: `AddAssign<Quat>`, `SubAssign<Quat>`, `MulAssign<Quat>`, `MulAssign<Fixed>`,
  `DivAssign<Fixed>` (core `ops::*Assign` traits, delegating to the existing fused methods),
  `slerp_long` (glam's long-path variant of `slerp`: share the code of `slerp`, no duplication of
  the large body: a private helper taking the shortest-path flag), `from_affine3(a: Affine3)`
  (= `from_mat3(a.matrix3)` with glam's precondition documented; `affine3.cairo` currently ships
  a `quat_from_affine3`-style helper: keep it as a thin alias or remove it, and document).
- `Mat3`: `MulAssign<Affine2>`; `Mat4`: `Mul<Affine3>` as the named `mul_affine3` and
  `MulAssign<Affine3>`; `Affine3`: `Mul<Mat4>` is already the named `mul_mat4`: add the missing
  rename rule in `scripts/api_parity.py` instead of new code. Heterogeneous `Mul` cannot be a
  core operator (DESIGN section 3): named methods + rename rules.
- `Affine2::to_scale_angle_translation() -> (Vec2, Fixed, Vec2)` (glam's algorithm: determinant
  sign, column lengths, `atan2`).
- `camera::{rh,lh}::view`: `look_at_affine3`, `look_to_affine3`, `look_at_quat`, `look_to_quat`
  (mirror `src/camera/*/view.rs`; reuse the shared look-to kernel of `camera_impl`).
Tests table-driven and compact (files are near their caps), golden entries with justified
tolerances, a bench for every new arithmetic function. After the change `docs/API_PARITY.md`
must show 0 `missing` for these types. If another pull request regenerated
`docs/API_PARITY.md` on `main` in the meantime, rebase and regenerate rather than hand-merging.
