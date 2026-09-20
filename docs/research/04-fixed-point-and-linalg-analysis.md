# 04 - Fixed-point and linear-algebra prior art: Cubit and Orion (static analysis)

Scope: source-reading analysis of `influenceth/cubit` and `gizatechxyz/orion`, plus a design-space
study for the scalar type of `glam.cairo` (and the future `nalgebra.cairo` / `rapier.cairo`).
No code was compiled or benchmarked for this document: every cost statement below is a
**qualitative prediction derived from the source and from the corelib** and is meant to be
confirmed (or refuted) by the separate empirical gas/step benchmark.

Sources read:

- `cubit` @ `8007a30` ("Update Cubit for Cairo 2.7"), shallow clone.
- `orion` @ `bac0b42` (last commit 2025-03-03, README-only change), shallow clone.
- Cairo corelib 2.19.4 (`~/Library/Caches/com.swmansion.scarb/registry/std/v2.19.4/core/src`),
  cross-checked against 2.8.2 / 2.11.4 / 2.12.2 / 2.13.1 / 2.15.0.

Owner's cost heuristic used throughout: **simple math (add/mul/div/mod) < bitwise (and/or/xor) < loops**.
Two refinements that come out of this analysis and matter just as much:

1. **Range checks and the 128-bit boundary.** In the Cairo VM every value is a felt; a `u32` op is
   not cheaper than a `u64` op. What costs is (i) range-checked libfuncs (overflow checks,
   comparisons, downcasts, divmod) and (ii) crossing 128 bits (`u128 x u128 -> u256`,
   `u256` division), which needs multi-limb arithmetic and "mul guarantees".
2. **Branches on sign.** A sign-magnitude representation turns every add/sub/compare into a small
   decision tree. Native integer libfuncs do the same job in one libfunc.

---

## 1. Cubit (`influenceth/cubit`)

### 1.1 Project facts

| Item | Value |
|---|---|
| License | MIT, (c) 2023 Unstoppable Games, Inc. |
| Package | `cubit` 1.4.0, `cairo-version = ">=2.7.0"`, `edition = "2023_10"` (legacy edition, no `pub` modifiers anywhere) |
| Dependencies | `starknet >= 2.7.0` (only for `StorePacking`), `cairo_test` |
| CI | `scarb test` pinned to scarb 2.7.0 |
| Status | README still says "WORK IN PROGRESS, should not be used in production". Head commit is only a toolchain bump to Cairo 2.7. No use of any post-2.7 feature (no `const fn`, no const arrays, no `BoundedInt`, no native signed ints for the representation). Treat as **low-activity / maintenance mode**. |
| Extras | JS helper package (`@influenceth/cubit`, `src/index.js`, `test/*.spec.js`) to convert to/from fixed; orphan legacy files `src/math/{lut,trig}.cairo`, `src/types/vec2.cairo` not in the module tree (`lib.cairo` only declares `f64`, `f128`, `utils`). |

Layout (duplicated almost verbatim for the two widths):

```
src/f64/   types/{fixed,vec2,vec3,vec4}.cairo  math/{ops,trig,hyp,comp,lut}.cairo  procgen/{rand,simplex3}.cairo
src/f128/  (same)
src/utils.cairo   felt_sign / felt_abs
```

### 1.2 Representation

```cairo
#[derive(Copy, Drop, Serde)]
struct Fixed { mag: u64,  sign: bool }   // f64  = Q32.32, ONE = 2^32
struct Fixed { mag: u128, sign: bool }   // f128 = Q64.64, ONE = 2^64
```

Sign-magnitude, `sign == true` means negative. Consequences:

- Two felts per scalar in memory, in `Serde` output and in calldata (a `Vec3` is 6 felts).
- **Negative zero exists.** `mul` and `div` compute `sign = a.sign ^ b.sign` without normalising,
  so `(-1) * 0 == Fixed { mag: 0, sign: true }`. `eq` compares both fields, so `-0 != +0`, and
  `lt(-0, +0)` is `true`. `neg` and `sin` guard against it (`mag == 0` checks), `add` guards only the
  opposite-sign branch (`(-0) + (-0) = -0`). This is a correctness hazard for a physics engine
  (equality with zero, `signum`, sorting for broad-phase).
- The f64 range is asymmetric with respect to a two's-complement i64: the magnitude is a full `u64`,
  so the representable range is about +/-2^32 (not +/-2^31). `new_unscaled` does `mag * ONE` with a
  checked `u64` mul.

### 1.3 Trait design

`FixedTrait` is a **non-generic trait per width** (`cubit::f64::FixedTrait`, `cubit::f128::FixedTrait`),
with one impl that simply forwards to free functions in `math::{ops,trig,hyp}`:

- constructors: `ZERO`, `ONE`, `new(mag, sign)`, `new_unscaled`, `from_felt`, `from_unscaled_felt`
- math: `abs ceil floor round sqrt exp exp2 ln log2 log10 pow`
- trig: `sin cos tan asin acos atan` + `*_fast` variants
- hyperbolic: `sinh cosh tanh asinh acosh atanh`

Operators: `Add Sub Mul Div Rem Neg`, `AddAssign/SubAssign/MulAssign/DivAssign`, `PartialEq`,
`PartialOrd`, `Zero`, `One`, `Into<Fixed, felt252>`, `TryInto<Fixed, u8..u128>`,
`Into<u8..u64 / i8..i64, Fixed>`, `TryInto<u128|u256|i128, Fixed>`, f64 <-> f128 conversions,
`PrintTrait` (legacy debug), `StorePacking<Fixed, felt252>`.

Only the comparison/assign/neg/rem impls are `#[inline(always)]`; `add/sub/mul/div` go through two
call levels (`FixedAdd::add -> ops::add -> FixedTrait::new`), leaving inlining to the compiler's
heuristic.

Constants are never `const Fixed`; they are built at each use site with
`FixedTrait::new(<raw>, <sign>)` (e.g. 10 of them in one `atan` call).

### 1.4 Algorithms, operation by operation (f64 unless noted)

| Op | Algorithm | Cost drivers |
|---|---|---|
| `add` | `if a.sign == b.sign { mag+mag } else if mags equal { ZERO } else if a.mag > b.mag { a.mag-b.mag, a.sign } else { b.mag-a.mag, b.sign }` | up to 3 branches (bool eq, u64 eq, u64 `>` = range check) + one checked u64 add/sub (range check). |
| `sub` | `add(a, -b)`; `neg` itself has 2 branches (`mag == 0`, `!sign`) | `neg` branches + everything in `add`. |
| `mul` | `u128 p = WideMul(a.mag, b.mag)`; `p / ONE.into()`; `.try_into::<u64>().unwrap()`; `sign = a.sign ^ b.sign` | `u64_wide_mul` is free of range checks. The division is a **generic `u128 / u128`**: runtime `NonZero` conversion of the constant `ONE` (`'Division by 0'` branch) + `u128_safe_divmod` (the expensive 128-bit variant) + downcast (range checks) + `bool` xor. Rounding = truncation toward zero. |
| `div` | `WideMul(a.mag, ONE) / b.mag.into()`, downcast, xor sign | same as mul; division by zero panics through the corelib `'Division by 0'`. |
| `mul` (f128) | `u256 p = WideMul(u128, u128)`; `u256_safe_div_rem(p, 2^64)`; `assert(high == 0)` | `u128_guarantee_mul` + guarantee verification, then a **full u256 division** just to shift by 64 bits. By far the most expensive basic op in the library. |
| `div` (f128) | `WideMul(a.mag, ONE_u128)` -> `u256 / u256` | same: u256 division. |
| `eq/ne` | both fields compared | 2 eqs + `&&`. |
| `lt/le/gt/ge` | `if a.sign != b.sign { return sign } else { (mag != mag) && ((a.mag < b.mag) ^ a.sign) }` | branch + u64 eq + u64 `<` (range check) + xor. |
| `floor/ceil/round` | `u64_safe_divmod(mag, ONE)` then sign-dependent branches, then `new_unscaled(div)` = **checked multiply back by ONE** | 1 divmod + 1 checked mul + 2-3 branches. (`mag - rem` would avoid the multiply.) |
| `rem` | `a - floor(a / b) * b` | a full div + floor + mul + sub. Very expensive for what is a single integer `%` on raw values. |
| `sqrt` (f64) | `Sqrt::sqrt(mag.into() * ONE.into())` -> `u128_sqrt` core libfunc, result already Q32.32 | 1 checked u128 mul + **1 libfunc**, exact floor sqrt. Excellent. |
| `sqrt` (f128) | `u128_sqrt(mag)` (-> u64), then `* ONE / sqrt(ONE)` | **Loses half the fractional precision**: result is only accurate to 2^-32, not 2^-64 (a proper version needs `u256_sqrt(mag << 64)`). Also recomputes `sqrt(ONE_u128)` at runtime. |
| `exp` | `exp2(x * log2(e))` | 1 mul + `exp2`. |
| `exp2` | split int/frac with divmod; `2^int` from `lut::exp2` (if-chain, grouped by 16 then linear `==` tests); `2^frac` = degree-8 polynomial in Horner form (8 fixed muls + final mul); negative input -> `ONE / res` | 9 fixed muls (each with its own rescale division), LUT if-chain (up to ~17 comparisons), 1 extra division when negative. No loop. |
| `log2` | `a < 1` -> `-log2(1/a)` (1 division + recursion); `msb` via nested-if LUT (8-way groups then linear `<` tests, each a range check); `norm = a / 2^msb` (full fixed **division** to do a shift); degree-8 Horner polynomial on [1,2) | 1-2 fixed divisions + 9 fixed muls + ~4-12 range-checked comparisons. |
| `ln`, `log10` | constant * `log2` | +1 mul. |
| `pow` | integer exponent -> square-and-multiply **loop** (`u64_safe_divmod(n, 2)` per iteration); otherwise `exp(b * ln(a))` | loop (log2(n) iterations, 1-2 fixed muls each) or exp+ln (~20 fixed muls, 1-3 divs). |
| `sin` | reduce `mag % TWO_PI`, divmod by `PI` for the half-period sign, then **Taylor series as an 8-level recursion** `_sin_loop(a, 7, ONE)`; each level computes `a * a * acc / new_unscaled(div)` | **16 fixed muls + 8 fixed divisions + 8 checked `new_unscaled` muls + recursion overhead** (gas withdrawal per call). `a * a` is recomputed at every level. Most expensive "precise" function. |
| `cos` | `sin(HALF_PI - a)` | + 1 sub. |
| `tan` | `sin(a) / cos(a)` | two full sine evaluations + 1 div. |
| `atan` | `abs`; if `> 1` invert (`1/x`, 1 div); if `> 0.7` apply `(x - sqrt3/3) / (1 + x*sqrt3/3)` (1 mul + 1 div); degree-10 Horner polynomial (10 muls); add `pi/6` / subtract from `pi/2` | 10-11 fixed muls + 0-2 fixed divs + ~3 branches. No loop. **No `atan2`.** |
| `asin` | `atan(a / sqrt(1 - a*a))` (special-case `|a| == 1`) | 1 mul + 1 sqrt + 1 div + atan. |
| `acos` | `asin(sqrt(1 - a*a))`, mirrored for negative input | 1 mul + sqrt, then `asin` does **another** mul + sqrt + div + atan: 2 sqrt, 2-4 div, ~12 mul. |
| `sin_fast` | reduce as above, fold to [0, pi/2], `lut::sin(x)` returns `(start, low, high)` for a **256-slot** table, then linear interpolation `((x - start) / STEP) * (high - low) + low` | `slot = a / 26353589` (1 u64 div) + **binary if-tree 4 levels deep then up to 16 linear `==` tests** + 1 fixed **division** by the step (step is not a power of two, so the remainder of the slot division cannot be reused) + 1 fixed mul + 3 add/sub. Accuracy of a 256-slot lerp over [0, pi/2]: about `h^2/8 ~ 5e-6`, i.e. only ~18 of the 32 fractional bits. |
| `atan_fast` | same range reduction as `atan`, then `lut::atan` = **flat linear chain of 99 `if slot == k`** + lerp | up to 99 (avg ~50) equality tests + 1-3 fixed divs + 1-2 muls. The LUT lookup alone may cost more than the 10-mul polynomial it replaces. |
| `cos_fast/tan_fast/asin_fast/acos_fast` | same compositions as the precise versions using `sin_fast`/`atan_fast` | as above. |
| `sinh/cosh/tanh` | via `exp(a)` and `1/exp(a)` | 1 exp + 1-2 div. |
| `asinh/acosh/atanh` | `ln(a + sqrt(a*a +/- 1))`, `ln((1+a)/(1-a)) / 2` | 1 sqrt + 1 ln (+ div). |
| `comp` | `max`, `min` via `>=`/`<=` | 1 comparison tree. |

LUT implementation note: all tables are **code, not data**: nested `if` trees returning tuples
(`lut.cairo` is 1331 lines for f64, 1550 for f128, 389 `return (...)` statements in f64). That costs
both steps (comparisons, several of them range-checked `<`) and **bytecode size** (each entry
compiles to several felts of CASM; this matters for Starknet class-size limits).

### 1.5 Vector types

`Vec2`, `Vec3`, `Vec4` exist for both widths (`struct Vec3 { x: Fixed, y: Fixed, z: Fixed }`,
`Copy, Drop, Serde`): `new`, `splat`, `abs`, `dot`, `cross` (Vec3), `floor`, `norm`, scalar
`add/sub/mul/div/rem`, component-wise `Add Sub Mul Div Rem`. No `normalize`, `length_squared`,
`lerp`, `min/max`, no matrices, no quaternions. `dot` rescales after **every** product
(3 divisions by ONE for a Vec3), `norm = sqrt(dot(a, a))` (3 rescales + 1 multiply-back inside
sqrt). They are a small convenience layer for Influence's procedural generation (`simplex3`), far
from glam's surface.

### 1.6 Packing / storage

`StorePacking<Fixed, felt252>`: `pack = mag + sign * 2^64` (f64) or `+ sign * 2^128` (f128);
`unpack` = `u128` (resp. `u256`) div-rem by `2^64` (`2^128`). One storage slot per scalar, but the
f128 unpack does a u256 division. A `Vec3` still occupies 3 slots (no vector-level packing).
This impl is why the whole library depends on `starknet`.

### 1.7 Tests and gas tracking

- Inline `#[cfg(test)] mod tests` per file; helpers `assert_precise` (absolute, default 1e-7 =
  430 raw units for f64) and `assert_relative`; several trig tests relax to 1e-5.
- Gas is **not measured**: tests only carry `#[available_gas(N)]` upper bounds, chosen loosely
  (most common values: 1,000,000 x38, 10,000,000 x30, 5,000,000 x10 ... up to 1,000,000,000 for
  the `procgen::rand` distribution tests). No snapshot, no regression tracking, no step counts.
- JS spec files test only the JS conversion helpers.

### 1.8 Cost-driver summary for Cubit

1. Sign-magnitude branching in add/sub/compare/neg/floor/ceil.
2. Generic division for every rescale (`/ ONE.into()` with runtime `NonZero` check and the
   128-bit divmod variant), one per multiplication - never amortised across a dot product.
3. u256 arithmetic for every f128 mul/div.
4. `sin`: recursion with 8 divisions; `tan`: two sines; `acos`: two square roots.
5. If-tree LUTs (linear 99-way chain for `atan`), plus a non-power-of-two step forcing an extra
   fixed-point division in the interpolation.
6. Constants rebuilt through constructor calls; `new_unscaled` uses checked multiplications.
7. Felt conversions (`from_felt` uses `u256` comparison against `HALF_PRIME` to get the sign) -
   only on construction paths, but expensive there.

What is good and worth keeping as ideas: `u128_sqrt` for Q32.32 sqrt (single libfunc, exact),
Horner-form polynomials with no loops for `exp2/log2/atan`, the `exp = exp2(x*log2 e)` /
`ln = ln2 * log2` reductions, and the absolute/relative precision test helpers.

---

## 2. Orion (`gizatechxyz/orion`)

### 2.1 Project facts

| Item | Value |
|---|---|
| License | MIT, (c) 2023 Auditless Limited (template notice; project by Giza) |
| Package | `orion` 0.2.5, **`cairo-version = "2.5.3"`**, `.tool-versions` scarb 2.6.4, edition 2023_10 |
| Dependencies | alexandria (`merkle_tree`, `data_structures`, `sorting`) pinned to a git rev; **`cubit` pinned to git rev `6275608`** |
| Status | Last commit 2025-03-03 and README-only. Effectively **unmaintained** and pinned to a two-year-old compiler; will not build on Cairo 2.11+ without porting. |

### 2.2 Numbers module

- `numbers/fixed_point/core.cairo`: **generic** `trait FixedTrait<T, MAG>` (1147 lines, mostly doc
  comments). Same function list as Cubit plus `HALF`, `MAX`, `sign`, `erf`, and IEEE-like
  sentinels `NaN`, `INF`, `POS_INF`, `NEG_INF`, `is_nan`, `is_inf`, ...
- `numbers.cairo`: `trait NumberTrait<T, MAG>` (3495 lines, ~786 method bodies) implemented for
  every fixed type **and** `i8..i128`, `u32`, `complex64`, so tensors can be generic over "number".
  Pure boilerplate; also contains hand-rolled `Div` for signed ints (casting through `felt252` and
  `u128`) because corelib 2.5.3 had no signed division.

Implementations:

| Type | Struct | Origin |
|---|---|---|
| `FP8x23` | `{ mag: u32, sign: bool }`, ONE = 2^23 | Cubit code re-scaled by hand |
| `FP16x16` | `{ mag: u32, sign: bool }`, ONE = 2^16 | Cubit code re-scaled by hand |
| `FP8x23W`, `FP16x16W` | same Q format, **`mag: u64`** ("wide") | copy of the above with wider magnitude so ML accumulations do not overflow; mul uses `u64_wide_mul -> u128` |
| `FP32x32` | `use cubit::f64::Fixed as FP32x32` | **thin wrapper over Cubit f64** |
| `FP64x64` | `use cubit::f128::types::Fixed as FP64x64` | **thin wrapper over Cubit f128** |

Differences vs Cubit:

- Same sign-magnitude struct and the same algorithms line for line: `add` decision tree,
  `mul = wide_mul / ONE` + downcast, `sqrt = u64_sqrt(mag * ONE)`, Taylor `_sin_loop(a, 7, ONE)`,
  degree-10 `atan` polynomial (coefficients re-quantised to 16 bits, one even dropped to 0),
  degree-7 `exp2`, `msb`/`exp2` if-tree LUTs, 256-slot `sin` LUT, ~100-slot `atan` LUT, plus an
  `erf` LUT.
- **`sin/cos/tan/asin/acos/atan` default to the `_fast` LUT variants** in the trait impls
  (`fn sin(self) { trig::sin_fast(self) }`), for both the native FP16x16/FP8x23 and the
  Cubit-backed FP32x32. Precision is therefore ~1e-5 at best regardless of the Q format.
- **NaN is encoded as negative zero** (`FP16x16 { mag: 0, sign: true }`), INF as `mag = u32::MAX`.
  Combined with the un-normalised `sign = a.sign ^ b.sign` in `mul`, **`(-x) * 0` yields NaN**.
  This is a genuine semantic bug source and a good illustration of why negative zero must not
  exist in our scalar.
- `comp` adds logical/bitwise ops on fixed values (`xor`, `or`, `and`, `where`, `bitwise_and`...,
  the latter using the Bitwise builtin on `mag`).
- 8.23 / 16.16 formats are ML-oriented (small dynamic range, weights in [-1, 1]); they are of
  little interest for physics.

### 2.3 Tensors and linear algebra

```cairo
#[derive(Copy, Drop)]
struct Tensor<T> { shape: Span<usize>, data: Span<T> }
```

- Dynamic rank and shape, row-major flat data; all indexing goes through
  `ravel_index` / `unravel_index` / `stride`, each a loop that pops a `Span` and often **allocates
  an `Array` per call**.
- Element-wise `add/sub/mul/div` (`tensor/math/arithmetic.cairo`): for each output element, the
  code calls `unravel_index` (allocates an index array), `broadcast_index_mapping` twice, then two
  bounds-checked `Span` indexings, then appends to a result `Array`. A 3-component vector add
  that is 3 libfunc calls on a struct becomes three loop iterations with several nested loops and
  allocations each - easily two orders of magnitude more steps.
- `linalg/`: only **`matmul`, `transpose`, `trilu`**. `matmul` supports 1-D/2-D only: textbook
  triple `while` loop, `sum += *mat1[i*n+k] * *mat2[k*p+j]` with index arithmetic and bounds-checked
  indexing at each step, result appended to an `Array`, shapes rebuilt via helper loops
  (`prepare_shape_for_matmul`, `adjust_output_shape_after_matmul`). Each fixed-point product is
  rescaled individually. `gemm` (`nn/functional/gemm.cairo`) = optional transposes (full copies)
  + `matmul` + `mul_by_scalar` + broadcast add.
- **No determinant, no inverse, no cross product, no norms/normalisation helpers beyond
  `reduce_l2`, no quaternions, no decompositions.**
- `operators/matrix.cairo`: `MutMatrix<T>` backed by `NullableVec<T>` =
  `Felt252Dict<Nullable<T>>`. Every element access is a dictionary access (dict entry + later
  squash cost) plus `Box` allocation. Only used for ML helpers (argmax, softmax, sigmoid,
  matrix-vector product).

Why this is the wrong shape for us:

1. Loops: every loop iteration in Cairo pays gas-withdrawal + branch bookkeeping; for N in {2,3,4}
   fully unrolled struct code avoids all of it.
2. `Span` indexing is bounds-checked (range check + pointer arithmetic) and index arithmetic
   (`i*n+k`) is itself checked `u32` math.
3. Results are built with `Array::append`; shapes are heap data too.
4. Generic code over `T, MAG` with 6-8 impl parameters per function inhibits inlining and bloats
   Sierra.
5. No opportunity for fused operations (single rescale per dot product, see 3.4).

### 2.4 Orion tests / gas

`#[available_gas]` bounds only (same coarse style as Cubit); `tests/performance` holds
quantize/dequantize operator tests, not benchmarks. No usable performance data.

---

## 3. Design space for our scalar

### 3.1 What the corelib gives us (verified in corelib 2.19.4; signed `DivRem` already in 2.8.2)

Native `i8 i16 i32 i64 i128`:

- `Add`, `Sub` -> single libfunc `iN_overflowing_add_impl/sub_impl` (1 range-check based libfunc,
  3-way result InRange/Underflow/Overflow, panics otherwise). Also `Checked*`, `Saturating*`,
  `Overflowing*`, `Wrapping*` add/sub.
- `Neg` (panics on MIN), `PartialEq` (`iN_eq`, no range check), `PartialOrd` via **`iN_diff`
  (one libfunc)**.
- `Mul`: `i64` = `i64_wide_mul(lhs, rhs).try_into().expect(..)`. **`i8..i64_wide_mul` take no
  implicits at all** (no range check: the result type is wide enough by construction), so a widening
  multiply is essentially one felt multiplication. `WideMul` is implemented for `i8..i64` but
  **not for `i128`**; `I128Mul` exists but is sign-split + `u128_wide_mul` + two downcasts.
- `Div`, `Rem`, `DivRem` for all signed types (`signed_div_rem`): truncated (Rust) semantics,
  implemented as a 4-way branch on the operand signs via `BoundedInt` `constrain`, then an unsigned
  `bounded_int::div_rem`, then negate/upcast (and a downcast in the neg/neg case for `MIN / -1`).
- `Serde` (one felt, felt252-based), `StorePacking<i64|i128, felt252>` (one slot; negative values
  are stored as `P - |x|`), `BitSize`, `Bounded`, `Default`, `NumericLiteral` (negative literals in
  `const` items work), `TryInto` to/from felt252 and between integer types (`upcast`/`downcast`).
- `core::internal::bounded_int` (`BoundedInt<MIN, MAX>`, `AddHelper`, `SubHelper`, `MulHelper`,
  `DivRemHelper`, `ConstrainHelper`, `NegateHelper`, `TrimMin/Max`) is `pub` behind
  `#[feature("bounded-int-utils")]` ("improper usage is likely to cause compiler crashes, use with
  caution"). `bounded_int_add/sub/mul` are **not range-checked** (the bounds are tracked in the
  type); only `div_rem`, `constrain`, `trim` and `downcast` use the range-check builtin.
- `Sqrt`: `u8..u128` plus `u256_sqrt`; `u64_sqrt -> u32`, `u128_sqrt -> u64` are single libfuncs.
- Const data: `const TABLE: [u64; N] = [...]` + `.span()` (`span_from_tuple`, present since at least
  2.8) gives **O(1) table lookups from the program's const segment** - this replaces Cubit's
  if-tree LUTs entirely.
- `const fn` exists from 2.11 on (54 occurrences in 2.11.4's `integer.cairo`, 109 in 2.19.4), and
  struct-valued `const` items are supported, so `const PI: Fixed = Fixed { raw: 13493037705 };`
  is fine.

### 3.2 Candidate representations

(a) `struct { mag: u64, sign: bool }` (Cubit) -
(b) newtype over native `i64` / `i128` holding the raw two's-complement value -
(c) `felt252`-backed value (signed interpretation around 0 / P) -
(d) single unsigned integer with a bias (`u64` storing `x + 2^63`).

| Criterion | (a) sign-magnitude | (b) native `i64` | (c) `felt252` | (d) biased `u64` |
|---|---|---|---|---|
| add / sub | decision tree: 2-3 branches + 1 checked op; `sub` adds `neg` branches | **1 libfunc** (`i64_overflowing_add_impl`) | 1 felt op, **no overflow detection** | checked add then checked sub of the bias (2 range-checked ops), or felt math + downcast |
| mul (incl. rescale) | `u64_wide_mul` + generic u128 divmod + downcast + bool xor; truncates toward zero | `i64_wide_mul` (free) + rescale. Naive `i128 / ONE` pays the 4-way signed `DivRem`; the **bias trick** (3.3) makes it branch-free: felt add, one divmod by a constant, felt sub, one downcast | felt mul is 1 step, but rescaling needs an integer view: convert to a bounded int (range checks), divmod, convert back. The conversion is the cost, so nothing is gained over (b) | un-bias both operands first, then as (b), then re-bias |
| div | `wide_mul(mag, ONE)` + u128 divmod + downcast + xor | `a * ONE` as i128 (free) then signed `DivRem` by a runtime divisor: sign branches are unavoidable here (or take abs values first, same thing). Comparable to (a) | same problem as mul | worse |
| comparison | branch + eq + range-checked `<` + xor | **1 libfunc** (`i64_diff`) | needs normalisation to a bounded int first (several range checks; Cubit's `felt_sign` even goes through `u256`) | 1 libfunc (unsigned compare) |
| equality / zero test | 2 field compares, **-0 != +0 hazard** | 1 `i64_eq`, unique zero | 1 felt compare, unique zero | 1 compare, zero is `2^63` |
| overflow behaviour | panics via checked `u64` ops / `unwrap` (messages are generic `Option::unwrap failed`) | panics with typed messages (`'i64_add Overflow'`); `Checked/Saturating/Wrapping` variants available for free | **silent wrap modulo P** - unacceptable for a provable physics engine: a wrapped value is still a valid proof | panics |
| range-check usage | highest (compare + op per add; divmod + downcast per mul) | lowest for add/sub/cmp; same order as (a) for mul/div | none for add/mul, heavy whenever a value must be interpreted | a bit higher than (b) |
| memory / Serde | **2 felts** per scalar (Vec3 = 6, Mat4 = 32) | **1 felt** (Vec3 = 3, Mat4 = 16); halves calldata and struct copy traffic | 1 felt | 1 felt |
| storage | custom `StorePacking` (1 slot) | built-in `StorePacking<i64, felt252>`; a custom vector-level packing can put a whole `Vec3` (3 x 64 bits) in **one** slot, with 0.0 mapping to raw 0 if two's-complement packing is used | 1 slot | trivially packable, but **uninitialised storage (0) decodes to -2^31**, a nasty default in Starknet |
| operator traits / ergonomics | all operator traits must be hand written; constants are `{mag, sign}` pairs | newtype needs hand-written `Add/Sub/Mul/Div/Rem/Neg/PartialOrd` but each is a one-liner over `i64`; `derive(PartialEq, Serde, Copy, Drop, Default, Hash)` just works | everything by hand; no type safety | everything by hand; unreadable literals |
| const-evaluability | `const X: Fixed = Fixed { mag: .., sign: .. }` works | `const X: Fixed = Fixed { raw: -123 }` works; raw consts may use const integer expressions | works | works but constants are opaque (`2^63 + ...`) |
| sqrt | direct on `mag` | 1 conversion to unsigned (checks non-negativity at the same time) then same libfunc | conversion needed | un-bias first |
| abs / signum / floor | trivial on fields (`abs` = clear flag) | `abs` needs a sign test (`i64_diff` against 0 or `constrain`), floor is natural with the bias trick | expensive | moderate |

A single-field struct is free at runtime: Sierra `struct_construct`/`struct_deconstruct` of a
one-member struct compile to no CASM instructions, so `struct Fixed { raw: i64 }` costs the same as
a bare `i64`. A newtype is mandatory anyway because `Mul<i64>` already exists with integer semantics.

**Verdict.** (b) wins on every axis that matters for us except `abs` and the rescale-after-multiply
detail, which 3.3 addresses. (c) is rejected as a public type (silent wrap, expensive comparisons)
but **felt252 is the right type for internal accumulators** (3.4). (d) has no advantage over (b)
once (b) is packed with an offset at storage time, and its non-zero zero is dangerous. (a) is what
both reference libraries do and is the main structural reason they are slow on add/sub/compare and
fat in memory.

### 3.3 The rescale after a multiplication (the hot path)

For Q32.32 in `i64`: `p = a.raw * b.raw` fits in `i128` (|p| <= 2^126). We need `p / 2^32`.

Options, from worst to best (predicted):

1. `(WideMul::wide_mul(a, b) / ONE_I128).try_into().unwrap()`: generic signed `DivRem`
   (constrain lhs, **constrain the constant rhs at runtime**, unsigned div_rem, negate) + runtime
   `NonZero` check + downcast. Truncation toward zero. Likely *slower* than Cubit's unsigned path.
2. Sign-split by hand (abs values, unsigned `u128` divmod by a `NonZero` **constant**, re-apply
   sign): Cubit-equivalent cost, still branches.
3. **Bias trick (branch-free, floor or round-to-nearest for free):**
   `q = ((p + 2^127 [+ 2^31]) div 2^32) - 2^95`.
   With `BoundedInt`: `bounded_int_add(p, UnitInt<2^127 + 2^31>)` (no range check) ->
   `bounded_int_div_rem(_, NonZero<UnitInt<2^32>>)` (range-checked; the constant, small divisor
   lets the compiler pick the cheap divmod variant since `q * d` cannot wrap the field) ->
   `bounded_int_sub(q, UnitInt<2^95>)` (no range check) -> `downcast` to `i64` (range check;
   this is the overflow detection). No sign branch, no xor, no negative zero, and the rounding mode
   is chosen by the bias constant at zero extra cost. The same effect is reachable without the
   unstable feature by doing the additions in `felt252` and converting to `u128` for a
   `u128_safe_divmod` by a `const NonZero<u128>`, at the price of one extra conversion.

Rounding mode is a **specification decision** (determinism is guaranteed either way, since all of
this is integer arithmetic): floor (`>>` semantics, the convention of most fixed-point game
engines and the easiest to mirror off-chain in Rust/TS with an arithmetic shift), truncation
(Cubit; symmetric, `(-a)*b == -(a*b)`), or round-half-up (best accuracy, slightly better energy
behaviour in integrators). Recommendation: **floor**, documented, with a bit-exact Rust/TS mirror
for clients; keep the constant in one place so it can be switched to round-to-nearest if the
benchmark shows simulation drift.

### 3.4 Lazy rescale / fused operations (largest structural win, independent of cubit/orion)

Both reference libraries rescale after *each* multiplication. In Cairo, `felt252` add and mul are
the cheapest operations that exist (no range check) and a felt has 252 bits of headroom, so raw
products (<= 2^126 in magnitude) can be **summed un-rescaled**, then rescaled **once**:

- `dot(a, b)` for Vec3: 3 felt muls + 2 felt adds + **1** rescale (instead of 3).
- `cross`: 6 muls, 3 rescales (instead of 6). `Mat3 * Vec3`: 3 rescales (instead of 9).
  `Mat4 * Mat4`: 16 (instead of 64). `i64 -> felt252` conversion is a no-op.
- `length(v) = u128_sqrt(x^2 + y^2 + z^2)` on the **un-rescaled** sum: the sum of raw squares is a
  Q64.64 value and its integer square root is *directly* the Q32.32 result. **Zero rescales, zero
  precision loss**, 1 conversion to `u128` + 1 libfunc. (Cubit: 3 rescales, then a multiply by
  `ONE`, then sqrt.) The sum fits `u128` for Vec2/Vec3 (3 * 2^126 < 2^128); Vec4 needs a checked
  conversion.
- Overflow is still detected, at the single final downcast. The bias for the final rescale must
  account for the number of accumulated terms (constant per call site).

This suggests exposing a small internal "wide accumulator" API in the scalar package
(`wide_mul(a, b) -> Wide`, `Wide + Wide`, `Wide::narrow() -> Fixed`, `Wide::sqrt() -> Fixed`) and
writing all glam kernels against it.

### 3.5 Precision choice

| Format | Container | Range | Resolution | mul intermediate | Notes |
|---|---|---|---|---|---|
| Q16.16 | `i32` | +/-32768 | 1.5e-5 | `i64` | `|v|^2` overflows for `|v| > 181`. Angular/impulse quantities in a solver lose too many bits. No step advantage: a 32-bit op costs the same VM steps as a 64-bit one. |
| **Q32.32** | **`i64`** | **+/-2.1e9** | **2.3e-10** | **`i128` (fits one range-check word, < 2^128)** | `|v|^2` fine up to `|v| ~ 46000`; comparable to f32 precision near 1.0 and *better* than f32 far from the origin (uniform resolution). Sweet spot. |
| Q64.64 | `i128` | +/-9.2e18 | 5.4e-20 | **`u256`/`u512`** | every mul = `u128_guarantee_mul` + verification, every rescale/div = u256 division; no native `i128` `WideMul`. Predict **5-10x** the cost of Q32.32 per mul/div. Only justified for accumulators or very long-running integrations. |

Intermediate splits in the same `i64` container (Q40.24, Q48.16) cost exactly the same as Q32.32 and
are a pure range/precision trade; keeping the fractional bit count as a single constant makes this a
later tuning knob. **Recommendation: Q32.32 in `i64`** as the only scalar initially
(`type Real = Fixed`), mirroring how rapier switches `Real` between f32 and f64.

Determinism: integer-only arithmetic is bit-exact on every prover/VM/sequencer. What must be
specified and frozen: rounding of mul/div, the exact polynomial coefficients and evaluation order of
every transcendental, table contents, and overflow policy (panic = transaction/proof failure, never
wrap). A reference mirror (Rust `i64`/`i128`) with shared test vectors is the way to guarantee
client-side prediction matches on-chain results.

---

## 4. Transcendental functions: algorithm families and predictions

Cost unit below: "fmul" = one fixed-point multiply including its rescale (the dominant unit),
"fdiv" = one fixed-point division (predicted ~1.5-2x an fmul because the divisor is not constant).
Q32.32 resolution is 2.3e-10; "full precision" means error within a few raw units.

| Function | Cubit / Orion | Alternatives | Recommendation (predicted cost / precision) |
|---|---|---|---|
| `sqrt` | core `u128_sqrt(raw << 32)` | Newton iterations (loop or unrolled, each an fdiv): strictly worse | **Keep the libfunc**: ~1 conversion + 1 libfunc, exact floor. Add `Wide::sqrt` (3.4) for lengths. `rsqrt`/`normalize`: 1 sqrt + 1 fdiv then N fmul (reciprocal once) rather than N fdiv. |
| `sin`, `cos` | precise: 8-level Taylor recursion, 16 fmul + 8 fdiv (~1e-9); fast: 256-slot if-tree LUT + lerp, ~1 div + ~12 compares + 1 fdiv + 1 fmul (~5e-6) | (i) odd/even **minimax polynomial in Horner form**, `x^2` computed once; (ii) const-array LUT + lerp with power-of-two step; (iii) CORDIC | **(i)**: range-reduce with one `u64` divmod by `HALF_PI` (quadrant + remainder), fold to [-pi/4, pi/4], evaluate sin (degree 9, 5 coeffs) or cos (degree 8-10): **~6 fmul, no fdiv, no loop, ~1e-10**. That is roughly 4-5x cheaper than Cubit's precise `sin` and both cheaper and ~4 orders of magnitude more precise than its `sin_fast`. Provide **`sin_cos`** sharing reduction and `x^2` (glam needs both for rotations). (ii) with `const [i64; 2^k + 1]` and step `2^-k`: 1 divmod (gives slot *and* fraction) + 2 O(1) lookups + 1 fmul; cheapest, but error `h^2/8`: 5e-6 @256, 3e-7 @1024, 2e-8 @4096 entries, paid in bytecode size. Offer as an optional `fast` module if benchmarks justify it. |
| `tan` | `sin/cos` = 2 full sines + 1 fdiv | dedicated rational/odd polynomial near 0 | `sin_cos` + 1 fdiv (~13 fmul-equivalents). Rare in physics. |
| `atan` | degree-10 Horner + up to 2 fdiv range reductions (~1e-7..1e-9); fast: 99-way linear if-chain + lerp | odd minimax polynomial on [0,1]; piecewise polynomials selected by comparison (coefficients in a const array); CORDIC vectoring mode | see `atan2` |
| **`atan2`** | **absent in both libraries** | - | `z = min(|x|,|y|) / max(|x|,|y|)` (1 fdiv, 1 compare), polynomial on [0,1], then octant fix-up with 2-3 compares and constant adds. `atan` converges slowly on [0,1] (singularities at +/-i): an odd polynomial needs ~8 coefficients for ~1e-6 and ~12 for ~1e-9. Better: **piecewise** (2-4 segments, degree 5-7 each, coefficients from a const array) -> **~6-8 fmul + 1 fdiv, ~1e-9**; or one Cubit-style argument reduction (extra fdiv) + 6-7 coefficient odd polynomial. `atan(x) = atan2(x, ONE)`. Coefficients must be regenerated (Remez) for our format. |
| `asin`, `acos` | `asin = atan(a / sqrt(1 - a^2))`: fmul + sqrt + fdiv + atan; `acos = asin(sqrt(1 - a^2))`: **2 sqrt, 2-4 fdiv, ~12 fmul** | **`acos(x) = sqrt(1 - x) * P(x)`** on [0,1] (Abramowitz-Stegun 4.4.45/46 family; degree 7 gives ~2e-8, re-fitted minimax degree 8-10 reaches ~1e-9), `asin = pi/2 - acos`, reflection for negative x | **1 sqrt (libfunc) + ~8-10 fmul, no fdiv, no loop.** Exploits the fact that sqrt is unusually cheap in Cairo. Accurate at the endpoints where the `atan` formulation degrades (division by ~0). glam uses `acos` in `angle_between` and quaternion slerp, so this one matters. |
| `exp` | `exp2(x * log2 e)`: int part from if-chain LUT, frac part degree-8 Horner; ~10 fmul (+1 fdiv if negative) | same scheme with const-array (or arithmetic) `2^n`, negative handled by shifting the *other way* (divide by `2^n` via constant table of divisors, or `2^(frac)` with `frac` made positive by flooring) so no fdiv | ~9-10 fmul, ~1e-9. Low priority for physics (damping uses constants or `powi`). |
| `ln`, `log2` | msb via if-tree (4-12 range-checked compares) + fdiv normalisation + degree-8 Horner; fdiv + recursion for `a < 1` | msb by 6-step binary search on comparisons (no CLZ in Cairo); normalise by multiplying with a table constant (or divmod by const-table `NonZero` power of two) rather than fdiv; handle `a < 1` by the same normalisation with negative exponent (no reciprocal) | ~9 fmul + 6 compares + 1 divmod. Low priority. Iterative squaring `log2` (one fmul per output bit = a 32-iteration loop) is strictly worse. |
| `pow` | integer: square-and-multiply loop; else `exp(b * ln a)` | `powi(n)` with the loop (or unrolled for small constant n); `powf` via exp/ln | same; ~20 fmul for `powf`. Provide `powi` separately; avoid the `rem == 0` runtime dispatch. |
| CORDIC (general) | not used | 32 iterations for 32 bits; each iteration needs 2 shifts (= **2 divmods** in Cairo, there is no shift instruction), 3 add/sub and a sign branch, inside a loop | **Reject.** By the owner's heuristic it is the worst family: a loop *and* division-as-shift per iteration; predicted >10x the polynomial approach. |
| Bitwise tricks | Orion `bitwise_*` only | masks/shifts via `&`, `|` | Avoid: the Bitwise builtin is costlier than divmod by a constant power of two, which yields the same information (`q`, `r`). |

General implementation rules for these functions: Horner form, **no loops/recursion**, `const`
coefficients (`const C5: Fixed = Fixed { raw: .. }`), constant `NonZero` divisors, const-array tables
instead of if-trees, argument reduction with a single integer divmod on the raw value, and a
generator script (Python/mpmath Remez) checked into the repo so coefficients are reproducible.

---

## 5. Recommendation

### 5.1 Reuse vs reimplement

License compatibility: Cubit and Orion are both **MIT**, same as our repository. Copying code or
constants is allowed provided their copyright notices are retained (e.g. in a `NOTICE`/third-party
section or file header). So the constraint is technical, not legal.

- **Do not depend on either package.** Cubit: sign-magnitude type baked into every signature,
  legacy edition, hard `starknet` dependency, 2.7-era idioms, WIP/low activity. Orion: pinned to
  Cairo 2.5.3, unmaintained, drags alexandria + an old Cubit rev, tensor model fundamentally
  unsuited to fixed-size math.
- **Reuse as ideas / reference material (from Cubit):** `u128_sqrt` formulation of Q32.32 sqrt;
  the `exp2`/`log2` decomposition; Horner-form loop-free polynomials; `assert_precise` /
  `assert_relative` test-helper pattern and their numeric test vectors (useful as cross-checks);
  the `atan` range-reduction identities. If polynomial coefficient sets are copied as a stopgap,
  keep the MIT notice - but they should be **regenerated** for our rounding mode and target error.
- **Reuse nothing from Orion's linalg.** The only relevant operators (`matmul`, `gemm`,
  `transpose`) are generic textbook loops over `Span`s; there is no determinant, inverse, cross,
  quaternion or decomposition code. Orion is mainly valuable as a catalogue of pitfalls:
  NaN-as-negative-zero, LUT-by-default trig with ~1e-5 precision, 3.5k-line `NumberTrait`
  boilerplate, dict-backed matrices.
- **Reimplement:** the scalar type, all arithmetic, all transcendentals (section 4), and of course
  all of glam's types as plain `Copy` structs with fully unrolled component code.

### 5.2 Proposed scalar

```cairo
// package `fixed` (name TBD), pure Cairo, no starknet dependency by default
#[derive(Copy, Drop, Serde, PartialEq, Default, Hash, Debug)]
pub struct Fixed { raw: i64 }          // Q32.32, two's complement, unique zero

pub const FRAC_BITS: u8 = 32;
pub const ONE: Fixed = Fixed { raw: 0x1_0000_0000 };
pub const PI:  Fixed = Fixed { raw: 13493037705 };   // etc.

pub type Real = Fixed;                 // single switch point, as in rapier
```

- add/sub/neg/compare delegate to the native `i64` libfuncs (panic on overflow; expose
  `checked_*`, `saturating_*`, `wrapping_*` for the rare solver spots that want them).
- mul/div/rescale use the branch-free bias technique of 3.3 (floor rounding, frozen in the spec),
  isolated in one internal module so the `BoundedInt` (unstable feature) implementation can be
  swapped for a `felt252`/`u128` one without touching callers. Both variants should be benchmarked.
- internal `Wide` accumulator (felt252- or i128-backed) for fused kernels: `wide_mul`, `+`,
  `narrow()`, `sqrt()` (3.4). glam kernels (`dot`, `cross`, `length`, mat*vec, mat*mat, quat mul)
  are written against it.
- no NaN/Inf: division by zero and overflow panic. glam's `is_nan`/`is_finite` are omitted or
  constant.
- constructors: `from_raw`, `from_int(i32)`, `const` items for literals, `to_int` (floor),
  `TryInto`/`Into` for integer types; a small script to turn decimal literals into raw constants.
- storage: optional module/feature providing `StorePacking` (scalar: built-in `i64` packing already
  suffices; vectors: two's-complement offset packing, `Vec3` in one slot, zero-initialised storage
  decodes to the zero vector). Keeps the core package free of `starknet`.

### 5.3 Trait design

- **Concrete first.** glam-rs itself is concrete per scalar (`Vec3` = f32, `DVec3` = f64, generated
  from templates), and Cairo generics with many impl parameters hurt inlining, Sierra size and
  compile time (both reference libraries show the boilerplate explosion: Cubit duplicates every
  file per width, Orion adds a 3.5k-line `NumberTrait`). Write `Vec2/3/4`, `Mat2/3/4`, `Quat`,
  `Affine*` directly against `Fixed`.
- Standard operator traits on `Fixed`: `Add Sub Mul Div Rem Neg`, `AddAssign SubAssign MulAssign
  DivAssign` (`core::ops`), `PartialOrd`, `Zero`, `One`, `Bounded`, `Display/Debug`.
- One inherent-style trait `FixedTrait` (or `#[generate_trait] impl`) for math, mirroring Rust's
  `f32` method names so glam code ports mechanically: `abs signum floor ceil round trunc fract
  min max clamp sqrt rsqrt recip mul_add powi powf exp ln sin cos sin_cos tan asin acos atan atan2
  rem_euclid lerp`. Small functions `#[inline(always)]`; polynomial bodies left out-of-line
  to keep bytecode size under control.
- If a second width ever becomes necessary, introduce a thin `Real` trait then; until then the
  `type Real = Fixed` alias is the abstraction boundary shared by the three libraries.

### 5.4 Packaging

**Yes, the scalar should be its own package**, consumed by `glam.cairo`, `nalgebra.cairo` and
`rapier.cairo`:

- it is the one type all three must agree on bit-for-bit (rounding mode, constants, function
  approximations): a single versioned source of truth is a determinism requirement, not only
  a convenience;
- it has a different release cadence and test style (exhaustive numeric test vectors, precision
  sweeps, step-count regression snapshots) from the geometry code;
- it can stay dependency-free (no `starknet`), with storage packing as an opt-in feature/module;
- a Scarb workspace can host it next to glam initially (`crates/fixed`, `crates/glam`) and it can be
  split into its own repository / published to the Scarb registry once the API settles.

### 5.5 Items to hand to the benchmark agent for validation

1. `Fixed{i64}` vs Cubit `Fixed{mag,sign}`: add, sub, lt, eq, mul, div (expect large wins on
   add/sub/compare, parity or modest win on mul/div).
2. Rescale variants: naive `i128 /`, sign-split unsigned, `BoundedInt` bias trick, `felt252`+`u128`
   bias trick; constant `NonZero` vs runtime `.into()` divisor.
3. Fused `dot`/`length`/`mat3*vec3` (single rescale, `u128_sqrt` of the raw sum) vs per-product
   rescale.
4. Cubit `sin` (Taylor recursion) vs `sin_fast` (if-tree LUT) vs a 5-coefficient Horner polynomial
   vs const-array LUT + lerp; same for `atan`/`atan_fast` (99-way chain) and the
   `sqrt(1-x) * P(x)` `acos`.
5. Q64.64 (`u256` path) vs Q32.32 mul/div to quantify the 128-bit boundary.
6. Orion `Tensor` add/matmul on 3- and 4-element data vs struct-based unrolled code (expected
   one to two orders of magnitude).
