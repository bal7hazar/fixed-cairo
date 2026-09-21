# F4 - `fixed` tier C: exponentials, logarithms, powers

Branch `feat/fixed-exp`. You are a PORTER agent on glam.cairo (Cairo port of glam-rs 0.33.8 on the
Q32.32 scalar `fixed::Fixed`; provable physics engine; gas/step cost is the top priority).

## Scope (strict file allowlist)

`packages/fixed/src/exp.cairo`, `packages/fixed/tests/test_exp.cairo`,
`packages/benches/tests/bench_exp.cairo`, `packages/benches/src/alt/exp.cairo`, `gas/exp.snap`,
`scripts/gen_exp.py` (new: coefficient generator + bit-exact Python mirror + error sweeps, in the
style of `scripts/gen_trig.py`), `packages/fixed/README.md` (add the section). These stub files
and their `mod` declarations already exist on `main`; do not edit `packages/fixed/src/lib.cairo`
(list the re-exports you want in the report), nor `fixed.cairo`, `wide.cairo`, `trig.cairo`.

## API

`pub trait ExpTrait` + `pub impl ExpImpl of ExpTrait` on `Fixed`, names as Rust `f32`:
`exp`, `exp2`, `exp_m1` (optional), `ln`, `log2`, `log10`, `ln_1p` (optional), `log(self, base)`,
`powf(self, n: Fixed)`, `sqrt` exists already, `cbrt` (optional). `powi` exists in `FixedTrait`.

- Domain and range: Q32.32 holds `[-2^31, 2^31)`, so `exp(x)` overflows for `x >= 31 ln 2 ~=
  21.49` (panic `'Fixed: exp overflow'`) and underflows to `0` below `-32 ln 2 ~= -22.18` (return
  `ZERO`, documented); `ln`/`log2`/`log10` panic `'Fixed: ln domain'` for `x <= 0`;
  `powf(x, n)`: `x > 0` general case `exp2(n * log2(x))`, `x == 0` -> `0` for `n > 0`, `1` for
  `n == 0`, panic otherwise; `x < 0` only for integer-valued `n` (delegate to `powi` semantics),
  panic `'Fixed: powf domain'` otherwise. Document each rule as a deviation from IEEE.
- Algorithms (loop-free): `exp2(x)`: split `x = k + f` (`floor`, one `DivRem` by `2^32`),
  `2^f` on `[0, 1)` by a minimax polynomial in Horner form on the wide accumulators (or a small
  `const` table + low-degree polynomial: bench both), then scale by `2^k` with a **`const [T; N]`
  table of powers of two** and one `DivRem`/multiplication (never `pow(2, k)` at runtime, never a
  loop); `exp(x) = exp2(x * FRAC_1_LN_2)` with a wide constant (more than 32 fractional bits, as
  `to_radians` does) or a direct reduction by `ln 2` with a Cody-Waite style two-part constant:
  bench both for precision and gas. `log2(x)`: normalize `x = m * 2^e` with `m` in `[1, 2)`: the
  exponent search is the hard part without loops or bitwise ops: evaluate (a) an unrolled binary
  search on `const` thresholds (6 comparisons for 64 bits), (b) `match`-table approaches, and ship
  the cheapest; then `log2(m)` by a polynomial (or `atanh`-style series in `(m-1)/(m+1)` with one
  shared `Recip`); `ln = log2 * LN_2`, `log10 = log2 * LOG10_2` with wide constants.
- Rounding: intermediate rescales floor; the **final** rescale rounds to nearest, as DESIGN
  section 2 allows for transcendental polynomials.
- Precision targets (max abs error in ULP, swept by the Python mirror over >= 40 001 points per
  function, generation fails above budget): `exp2`/`exp` relative error <= 4 ULP of the result
  for results below 2^16 and <= 2^-30 relative above; `log2`/`ln`/`log10` <= 4 ULP absolute on
  `[2^-32, 2^31)`; `powf` documented from its two stages. Exact identities by construction:
  `exp2(k) = 2^k` for integer `k`, `exp(0) = 1`, `log2(2^k) = k`, `ln(1) = 0`.
- Gas: report every function; expected order of magnitude 15-30k for `exp2`/`log2` under the
  `bb` protocol (compare with `gas/trig.snap`).

## Tests

`tests/test_exp.cairo`, table-driven, <= 800 lines: identities above, monotonicity spot checks,
edge cases (`EPSILON`, `MAX`, thresholds of overflow/underflow +- 1 ULP), every panic with its
exact message, <= 6 fuzz properties (`exp2(log2(x)) ~ x`, `exp(a + b) ~ exp(a) exp(b)` within a
derived tolerance, `ln` monotone...). No refgen golden file for this module (the oracle is the
Python mirror swept against high-precision references, as for `trig`).
