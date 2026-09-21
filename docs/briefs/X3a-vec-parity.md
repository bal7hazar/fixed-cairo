# X3a - parity closure of `Vec2`, `Vec3`, `Vec4`

Branch `feat/vec-parity`. Read `docs/briefs/COMMON.md`. Close every item that
`docs/API_PARITY.md` lists as `missing` for `Vec2`, `Vec3` and `Vec4`. All dependencies are merged
(`fixed::TrigTrait`, `fixed::ExpTrait`, `FixedTrait::{step, smoothstep, saturate, sqrt}`).

Allowlist: `tools/codegen/fvec.py`, `tools/codegen/fvec_tests.py`, `tools/codegen/README.md`, the
generated `packages/glam/src/{vec2,vec3,vec4}.cairo` and `packages/glam/tests/test_{vec2,vec3,vec4}.cairo`
(edit the generator snippets, regenerate, `--check` clean; every other generated output must stay
byte-identical), `packages/glam/tests/golden_{vec2,vec3,vec4}.cairo` (refgen only),
`tools/refgen/specs/{vec2,vec3,vec4}.toml`, `tools/refgen/src/oracles/{vec2,vec3,vec4}.rs`,
`packages/benches/tests/bench_{vec2,vec3,vec4}.cairo`, `packages/benches/src/alt/{vec2,vec3,vec4}.cairo`,
`gas/{vec2,vec3,vec4}.snap`, `docs/API_PARITY.md` (generated), `scripts/api_parity.py` (rules only).

Items (mirror glam-rs 0.33.8 `src/f32/vec2.rs`, `vec3.rs`, `scalar/vec4.rs`, names exact):
- element-wise wrappers on all three types: `sin`, `cos`, `sin_cos -> (VecN, VecN)`, `exp`,
  `exp2`, `ln`, `log2`, `powf(n: Fixed)`, `sqrt`, `step(rhs)`, `smoothstep(edge0, edge1)` (check the
  exact glam signature), `saturate`. They are N independent scalar calls: `#[inline(always)]` is
  NOT appropriate for the transcendental ones (large bodies); panics are the scalar ones, listed
  in the docs. One bench per method on `Vec3` at least, all methods in the snapshot.
- `From<BVecN> for VecN` as `Into<BVecN, VecN>` (true -> 1.0, false -> 0.0), branch-free if it
  measures cheaper (bench both).
- `Vec3::from_homogeneous(Vec4)`, `Vec3::to_homogeneous()`, `Vec4::project()` (one shared `Recip`
  of `w`: three divisions), with the zero-`w` panic documented.
Tests are table-driven; the test files and golden files are near their line caps (1 200 / 1 500):
keep additions compact (one table per group; 4-6 golden cases per new function, tolerances
justified from the scalar ULP errors documented in `fixed::trig` / `fixed::exp`) and trim nothing
that exists. After the change `docs/API_PARITY.md` must show 0 `missing` for the three types.
