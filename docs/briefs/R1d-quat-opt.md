# R1d - `quat`: optimizer pass, wide `is_normalized`, flaky drift fuzz

Branch `perf/quat`. Read `docs/briefs/R1-common.md`, `docs/briefs/COMMON.md`, then
`packages/glam/src/quat.cairo` (hand-written module), pull request #26 (the shared `slerp` helper,
`gh pr view 26`) and pull request #32 (the `fixed::wide::is_unit4` kernel, `gh pr view 32`).

Files you may edit: `packages/glam/src/quat.cairo`, `packages/glam/tests/test_quat.cairo`,
`packages/glam/tests/golden_quat.cairo` (generated), `tools/refgen/specs/quat.toml`,
`tools/refgen/src/oracles/quat.rs`, `packages/benches/tests/bench_quat.cairo`,
`packages/benches/src/alt/quat.cairo`, `gas/*.snap` (yours plus any caller's that changes:
`pose3`, `euler`, `affine3`, `vec3`, `mat3`, `mat4`, `camera`...), `docs/API_PARITY.md` and
the READMEs' generated gas tables when stale, `gas/bytecode.size` if `scripts/bytecode_size.py
check` reports a change (regenerate with `python3 scripts/bytecode_size.py snapshot`).

1. **Flaky test, first.** `test_quat::fuzz_mul_quat_drift` (`#[fuzzer(runs: 128, seed: 406)]`)
   failed once in a full-workspace gate on `main` with the arguments
   `a=5900780714928847550, b=7487908446869867027, c=6315160356890705506, d=301970536359324718`
   on its first assertion `drift(q) <= 4` (before any product), then passed in a filtered run and
   in the next full gate. Replay these arguments in a plain `#[test]`: if `unit_q(d, c, b, a)`
   really drifts by more than 4 ULP, find why (`from_axis_angle` of a normalised axis has a
   documented drift bound: check it; `normalize_or` of a nearly-zero axis?) and fix either the
   helper of the test or, if the library is at fault, the library (numeric change: evidence
   required). If the arguments replay green, the fuzzer seed is not honoured across
   `snforge test --workspace` / `-p glam` and the test must be made deterministic another way
   (report what you found; do not just widen the bound).
2. **`Quat::is_normalized`** through `fixed::wide::is_unit4(x, y, z, w, 1024)` (as `Vec4`
   does since #32): total, no `'Fixed: overflow'` on long inputs, same acceptance set; boundary
   tests at `1 +- 1024` and `1 +- 1025` raw ULP and components at `Fixed::MAX` / `MIN`; doc
   updated. Check the other `length_squared`-based predicates of the module (`is_near_identity`,
   `abs_diff_eq`?) for the same panic and treat them the same way if the fix is free.
3. **The shared `slerp` helper.** #26 made `slerp` and `slerp_long` share a non-inlined body
   `slerp_impl(a, b, s, shortest)` (+1 880 gas on `slerp`, inherited by `rotate_towards` and
   `Pose3::lerp`). Measure the alternatives: `#[inline(always)]` on the helper (bytecode cost:
   `scripts/bytecode_size.py` before / after, the audit `docs/audits/R1-bytecode-size.md` says
   what a call site of `slerp` costs), a `match` on `shortest` hoisted so that the hot path has no
   branch, or two bodies generated from one macro-free template. Ship the cheapest bit-exact one;
   losers in `benches::alt::quat`.
4. **`rotate_towards` (162 720 gas, the hottest `Quat` bench)**: profile (`angle_between` =
   `acos` + `slerp` = `acos` + `sin_cos`s + divisions?): remove recomputation between the angle
   test and the interpolation (one `dot`, one `acos`, share the `Norm`s); bit-exact unless the
   numeric-change rules of `R1-common.md` are met.
5. Walk `gas/quat.snap` sorted by cost for anything out of line with its arithmetic.

Commit scope `perf(quat)` / `fix(quat)` / `test(quat)`. Pull request title `perf(quat): <what
won>`, before / after gas table, the drift finding in the body. Model trailer: the model you are.
