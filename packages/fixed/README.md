# fixed

Signed Q32.32 fixed-point scalar for provable game math: `Fixed { raw: i64 }`, fused kernels that
rescale once per output (`wide`), and loop-free transcendental functions (`trig`).
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

## Gas (Sierra gas, inlined marginal cost, see `gas/fixed.snap` and `gas/wide.snap`)

| op | gas | | kernel | gas |
|---|---:|---|---|---:|
| `+` `-` | 840 | | `dot2` / `dot3` / `dot4` | 1 880 / 2 080 / 2 280 |
| `*` | 1 680 | | `mul_sub`, `mul_add` | 1 880 |
| `/` | 3 740 | | `a * b * c` (one rescale) | 1 680 |
| `%` | 3 170 | | `det3` | 3 800 |
| `<` | 770 | | `norm3` | 3 340 |
| `sqrt` | 2 020 | | `normalize3` | 8 720 |
| `floor` / `round` | 1 310 / 2 080 | | `Recip::mul` | ~1 800 |
| `lerp` | 1 980 | | `Mat4 * Mat4` (16 x `dot4` behind a call) | 43 010 |

## Internals

All the arithmetic is written with `core::internal::bounded_int` (an unstable corelib API) and is
isolated in the private `fixed::internal` module, **generated** by
[`scripts/gen_bounded.py`](../../scripts/gen_bounded.py): every `BoundedInt` bound and every bias
constant is computed by the script (`scripts/gen_bounded.py --check` verifies that the committed
files are up to date). A stable-API implementation of `mul` and `div` is kept and benchmarked in
`benches::alt::fixed` (`mul_stable`, `div_stable`) as the fallback.
