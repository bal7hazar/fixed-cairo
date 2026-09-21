# R1e - optimizer pass on `fixed::wide` and `Vec2/3/4`

Branch `perf/vec-wide`. Read `docs/briefs/R1-common.md`, `docs/briefs/COMMON.md`, then
`packages/fixed/src/wide.cairo`, `tools/codegen/README.md`, `tools/codegen/fvec.py` and the body of
pull request #9 (`gh pr view 9`: the measurements that chose the current formulations).

Files you may edit: `packages/fixed/src/wide.cairo`, `packages/fixed/tests/test_wide.cairo`,
`packages/benches/tests/bench_wide.cairo`, `packages/benches/src/alt/wide.cairo`,
`tools/codegen/fvec.py`, `tools/codegen/fvec_tests.py` and their generated outputs for `vec2`,
`vec3`, `vec4` (`packages/glam/src/vec{2,3,4}.cairo`, `packages/glam/tests/test_vec{2,3,4}.cairo`,
`packages/benches/tests/bench_vec{2,3,4}.cairo`, `packages/benches/src/alt/vec{2,3,4}.cairo`),
`tools/refgen/specs/vec{2,3,4}.toml`, `tools/refgen/src/oracles/vec{2,3,4}.rs`, the generated
golden files of those modules, `gas/*.snap` (yours, plus any caller's snapshot that changes),
`docs/API_PARITY.md` and the READMEs' generated gas tables when stale. `quat.cairo`,
`pose3.cairo` and every other module are out of scope (another task adopts your kernel there:
list in the report what they should call).

Work items:
1. **`is_normalized` must not panic on long vectors** (behaviour fix, numeric results of valid
   inputs unchanged). Today `VecN::is_normalized` is `length_squared(self).abs_diff_eq(ONE, 1024
   raw)`, and `length_squared` panics `'Fixed: overflow'` once `|v| >= 2^15.5`: a predicate that
   panics on a vector that is obviously not normalized. Add to `fixed::wide` the kernel(s) that
   compare the **wide** sum of squares (Q64.64, no rescale, no narrowing panic) with `1 +- eps`,
   e.g. `norm2/3/4_squared_wide(..) -> W2/W3/W4` plus a comparison helper, or a direct
   `is_unit2/3/4(x, y, z, eps)`; pick the API that stays consistent with the existing `Norm` /
   `norm*_wide` family and that `Quat` and `Pose3` can reuse. The accepted set must be exactly the
   current one for inputs that do not overflow today (same threshold semantics, prove it in tests
   at the boundary raw values), it must be no more expensive than today (it should be cheaper: one
   rescale less), and the panic disappears (test the former panic inputs, including components at
   `Fixed::MAX` / `MIN`). Full doc template, tests, `X__base` / `X__op` benches in `bench_wide`.
2. **Single division** (`project_onto`, `reject_from`, `length_recip`, `div_scalar` with one
   use...): pull request #9 measured that `Recip` loses below two divisions and shipped the plain
   `/`. Look for a cheaper or more accurate single-division formulation: e.g. a fused
   `dot(a, b) / dot(b, b)` on the wide sums (one rescale instead of two, no intermediate
   truncation; mind the >64-bit operands rule of DESIGN 4.6: measure), `length_recip` from the
   wide norm instead of `length().recip()`. Ship only what wins; if a result changes (better
   rounding), it is a numeric change: justify it in ULPs against the f64 oracle.
3. **`Vec3::slerp` (138 050 gas), `Vec3::rotate_towards` (109 970), `Vec2::rotate_towards`,
   `angle_between`**: the hottest `Vec*` benches after the element-wise transcendentals. Profile
   where the gas goes (how many `acos` / `sin_cos` / `sqrt` / divisions per call, whether a `Norm`
   or a `sin_cos` is computed twice, whether a large body is `#[inline(always)]` into another
   one) and remove recomputation. Bit-exact unless item 2's rules are met.
4. Walk the rest of `gas/vec{2,3,4}.snap` and `gas/wide.snap` sorted by cost and flag anything
   whose cost is out of line with its arithmetic (compare with the scalar costs of
   `gas/fixed.snap`): fix what is cheap to fix, list the rest.

Commit scope `perf(vec)` / `feat(wide)`. Pull request title
`perf(vec): <what won>`, body with the before/after gas table. Model trailer: the model you are.
