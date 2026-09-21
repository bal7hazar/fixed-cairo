# fixed

Signed Q32.32 fixed-point scalar for provable game math: `Fixed { raw: i64 }`, fused kernels that
rescale once per output (`wide`), and loop-free transcendental functions (`trig`, `exp`).
Shared by the Cairo ports of glam, nalgebra and rapier. No dependencies.

Design, rounding and overflow policy: [`docs/DESIGN.md`](../../docs/DESIGN.md).
Compatible with Cairo 2.19.4.

## The scalar (`fixed::fixed`)

```cairo
use fixed::{Fixed, FixedTrait, HALF, ONE, PI};

let a: Fixed = 3_i32.into();                 // exact, 100 gas
let b = FixedTrait::from_ratio(1, 3);        // 1/3, rounded toward zero
let c = a * b + HALF;                        // `*` floors, `+` is a native i64 add
assert!(c.abs_diff_eq(ONE + HALF, FixedTrait::from_raw(4)));
let d = (PI / a).sqrt().lerp(ONE, HALF);
```

- `value = raw / 2^32`, range `[-2^31, 2^31)`, resolution `2^-32` (`EPSILON`).
- Names mirror Rust's `f32` and glam's `FloatExt`: `abs signum copysign min max clamp floor ceil
  round trunc fract fract_gl recip sqrt div_euclid rem_euclid mul_add powi lerp inverse_lerp remap
  step saturate smoothstep move_towards abs_diff_eq`, the operators `+ - * / % -x`, their
  `*Assign` forms, `PartialOrd`, `Zero`, `One`, `Bounded`, and the `f32::consts` constants.
- Rounding (part of the API, results are bit-exact): `*`, `mul_add`, `lerp` and every fused kernel
  round toward negative infinity; `/`, `%`, `recip`, `from_ratio` round toward zero.
- Overflow, division by zero and the square root of a negative number **panic**
  (`'Fixed: overflow'`, `'Fixed: division by zero'`, `'Fixed: sqrt negative'`; the native `+`, `-`
  and unary `-` keep the corelib messages, e.g. `'i64_add Overflow'`). Nothing wraps or saturates.

## Fused kernels (`fixed::wide`)

A raw product `Fixed * Fixed` costs one step; its rescale costs a range check and a division.
Every kernel sums exact raw products and rescales **once per output scalar**:

```cairo
use fixed::wide::{RecipTrait, WideAdd, WideMul, WideNarrow, WideSub, det3, dot3, normalize3, wide_mul};

let d = dot3(ax, bx, ay, by, az, bz);                              // 1 rescale instead of 3
let cross_x = wide_mul(ay, bz).sub(wide_mul(by, az)).narrow();     // a*b - c*d
let triple = wide_mul(a, b).sub(wide_mul(c, d)).mul(e).narrow();   // (a*b - c*d) * e, exact
let (nx, ny, nz) = normalize3(x, y, z);                            // 1 sqrt + 1 division
let r = RecipTrait::new(det);                                      // divide many values by `det`
let m00 = r.mul(adj00);
```

- `W1..W16`: exact sums of up to 16 products (Q64.64). `T1..T16`: exact sums of up to 16 triple
  products (Q96.96), built with `Wn.mul(Fixed)`. The index is tracked by the type system:
  `Wn + Wm -> W(n+m)`. Additions, subtractions and negations cost one step and cannot overflow;
  only `narrow()` is range-checked.
- Named kernels: `dot2/3/4`, `dot2_add`, `dot3_add`, `mul_add`, `mul_sub`, `det3`,
  `norm2/3/4` (length as the integer square root of the raw sum of squares: no rescale, no
  underflow), `norm*_squared`, `distance2/3/4` (exact differences), `distance*_squared`,
  `normalize2/3/4`, and the `Norm` / `Recip` types behind them.

## Transcendentals (`fixed::trig`)

```cairo
use fixed::{FRAC_PI_2, Fixed, TrigTrait};

let (s, c) = angle.sin_cos();                 // one reduction, one z^2, both results
let a = y.atan2(x);                           // Rust argument order: y.atan2(x)
let half = (dot.acos_clamped()) / 2.into();   // acos of a dot product that rounding pushed past 1
let rad = 45.into::<Fixed>().to_radians();
```

- `sin cos sin_cos tan asin acos asin_clamped acos_clamped atan atan2 to_radians to_degrees`,
  named after Rust's `f32`. `acos_clamped` / `asin_clamped` clamp the argument to `[-1, 1]` like
  glam's `acos_approx`; `acos` / `asin` panic outside it (`'Fixed: acos domain'`,
  `'Fixed: asin domain'`). `tan` panics with `'Fixed: tan overflow'` next to an odd multiple of
  `pi / 2`.
- **Loop-free**: a range reduction by a constant divisor (`DivRem`), a `match` on the reduced
  index and a minimax polynomial in Horner form. No CORDIC, no Taylor recursion, no table; the
  cost does not depend on the value of the input, only on the branch it takes.
- **Accurate**: 1.02 ULP for `sin` / `cos` over a whole turn, 0.55 inside one octant, 1.08 at
  `1000 * TAU` (the Cody-Waite tail of `pi / 4` keeps a large angle as accurate as a small one),
  3.22 ULP for `atan2`, 2.96 for `acos`. The polynomial accumulators carry 24 extra fractional
  bits and the **final rescale rounds to nearest** (the second exception to the floor rule of
  `docs/DESIGN.md` section 2, and a free one), so the error is centred on zero.
- **Exact where it matters**, by construction and not by luck: `sin(-x) = -sin(x)`,
  `cos(-x) = cos(x)`, `atan(-x) = -atan(x)`, `asin(-x) = -asin(x)`, `sin(0) = 0`, `cos(0) = 1`,
  `sin(FRAC_PI_2) = 1`, `cos(PI) = -1`, `tan(FRAC_PI_4) = 1`, `acos(1) = 0`,
  `acos(0) = FRAC_PI_2`, `acos(-1) = PI`, `asin(0) = 0`, and the four axes of `atan2`
  (`atan2(0, 0) = 0`, `atan2(y, 0) = +-FRAC_PI_2`, ...).
- The coefficients, the reduction constants and the error figures are generated by
  [`scripts/gen_trig.py`](../../scripts/gen_trig.py), which also holds a **bit-exact Python
  mirror** of every function (`gen_trig.py sweep` measures the errors, `gen_trig.py tables`
  regenerates the test vectors, `gen_trig.py check` verifies that the committed constants are up
  to date).

## Exponentials and logarithms (`fixed::exp`)

```cairo
use fixed::exp::ExpTrait;
use fixed::{Fixed, HALF, TWO};

let g = (-t / tau).exp();                     // decay factor
let db = power.log10();                       // ln, log2, log10 share one core
let r = TWO.powf(HALF);                       // sqrt(2) = exp2(0.5 * log2(2))
let steps = x.log(TWO);                       // log(self, base), Rust argument order
```

- `exp exp2 exp_m1 ln log2 log10 ln_1p log powf`, named after Rust's `f32` (`sqrt` and `powi`
  live in `FixedTrait`). `ExpTrait` is not re-exported at the crate root yet:
  `use fixed::exp::ExpTrait;`.
- **Domain**: `exp` / `exp2` panic with `'Fixed: exp overflow'` from `31 ln 2` (21.487) / `31`
  on, and return `0` below `-33 ln 2` / `-33` (the result is below half an ULP); the logarithms
  panic with `'Fixed: ln domain'` for `x <= 0`; `powf` panics with `'Fixed: powf domain'` for a
  negative base and a non-integer exponent (Rust returns NaN), accepts `0^0 = 1` and `0^n = 0`
  like Rust, and computes a negative base with an integer exponent as `(-1)^n |x|^n`.
- **Loop-free**: `exp2` is one `DivRem` (`x = k/16 + g`), one lookup in a 1 024-entry `const`
  table of `2^(k/16)` (the power of two and the segment together) and a degree-6 polynomial;
  `exp` multiplies by a 56-bit `log2(e)` and reuses it. `log2` finds the exponent with an
  unrolled binary search on constant thresholds (6 comparisons), then evaluates one of 32
  degree-4 segments in the exact 62-bit mantissa; `ln` / `log10` rescale the same accumulator.
  `powf` chains the two on the wide accumulators (`n * log2(x)` is never rounded to 32 bits).
- **Accurate**: `exp2` / `exp` within 2.02 ULP below `2^16` and `7.2e-6 * 2^-30` relative
  above; `log2` 0.75, `ln` 0.66, `log10` 0.57 ULP over the whole positive range; `powf` within
  `0.44 * 2^-30` relative for `x` in `[2^-8, 2^8]`, `n` in `[-4, 4]`.
- **Exact and monotone by construction**: `exp2(k) = 2^k`, `log2(2^k) = k`, `exp(0) = 1`,
  `ln(1) = 0`; every function is non-decreasing (the table and the final rescale of `exp2` floor,
  and every segment is sealed so that it ends at or below the start of the next one). The
  logarithms round their final rescale to nearest; `exp2` / `exp` / `powf` floor.
- Generated and mirrored bit for bit by [`scripts/gen_exp.py`](../../scripts/gen_exp.py)
  (`sweep`, `tables`, `check`), like `trig`.

## Gas

<!-- gas:begin -->

Sierra gas (`l2 gas`, what a transaction pays) and prover cost (steps, range checks) of one call, net of the test overhead (`X__op - X__base`, see [`scripts/bench.py`](../../scripts/bench.py)), measured with scarb 2.19.4, starknet-foundry 0.61.0 (`.tool-versions`). Source of truth: `gas/*.snap`; this region is generated by `scripts/gas_tables.py`, do not edit it.

### Scalar (`fixed::fixed`)

| op | l2 gas | steps | range checks |
|---|---:|---:|---:|
| `+` / `-` | 840 | 7 | 2 |
| `*` | 1 680 | 14 | 4 |
| `/` | 3 740 | 32 | 6 |
| `%` | 3 170 | 27 | 5 |
| `<` | 770 | 7 | 1 |
| `sqrt` | 2 020 | 16 | 6 |
| `recip` | 3 370 | 29 | 5 |
| `floor` | 1 310 | 11 | 3 |
| `round` | 2 080 | 18 | 4 |
| `lerp` | 1 980 | 17 | 4 |
| `smoothstep` | 8 140 | 69 | 16 |
| `powi(5)` | 22 950 | 205 | 32 |

### Fused kernels (`fixed::wide`)

| op | l2 gas | steps | range checks |
|---|---:|---:|---:|
| `dot2` | 1 880 | 16 | 4 |
| `dot3` | 2 080 | 18 | 4 |
| `dot4` | 2 280 | 20 | 4 |
| `mul_add` | 1 880 | 16 | 4 |
| `mul_sub` | 1 880 | 16 | 4 |
| `det3` | 3 800 | 34 | 4 |
| `norm3` | 3 340 | 28 | 6 |
| `distance3` | 3 640 | 31 | 6 |
| `normalize3` | 8 720 | 72 | 20 |
| `Recip::new` | 4 400 | 37 | 8 |
| `Recip::mul` | 6 820 | 57 | 14 |

### Trigonometry (`fixed::trig`)

| op | l2 gas | steps | range checks |
|---|---:|---:|---:|
| `sin` | 22 730 | 152 | 37 |
| `cos` | 22 130 | 165 | 41 |
| `sin_cos` | 31 300 | 243 | 62 |
| `tan` | 39 850 | 287 | 70 |
| `atan` | 22 150 | 154 | 35 |
| `atan2` | 28 120 | 202 | 44 |
| `asin` | 27 660 | 223 | 58 |
| `acos` | 27 390 | 215 | 56 |
| `acos_clamped` | 28 930 | 229 | 58 |
| `to_radians` | 1 680 | 14 | 4 |

### Exponentials (`fixed::exp`)

| op | l2 gas | steps | range checks |
|---|---:|---:|---:|
| `exp` | 20 840 | 168 | 43 |
| `exp2` | 19 160 | 154 | 39 |
| `exp_m1` | 21 680 | 175 | 45 |
| `ln` | 19 520 | 160 | 37 |
| `log2` | 19 520 | 160 | 37 |
| `log10` | 19 520 | 160 | 37 |
| `ln_1p` | 21 280 | 175 | 39 |
| `log` | 40 710 | 327 | 72 |
| `powf` | 47 630 | 341 | 81 |

<!-- gas:end -->

## Internals

All the arithmetic is written with `core::internal::bounded_int` (an unstable corelib API) and is
isolated in the private `fixed::internal` module, **generated** by
[`scripts/gen_bounded.py`](../../scripts/gen_bounded.py): every `BoundedInt` bound and every bias
constant is computed by the script (`scripts/gen_bounded.py --check` verifies that the committed
files are up to date). A stable-API implementation of `mul` and `div` is kept and benchmarked in
`benches::alt::fixed` (`mul_stable`, `div_stable`) as the fallback.
