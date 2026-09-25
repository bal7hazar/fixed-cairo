# Design

Decisions that every module must follow. Evidence lives in `docs/research/` (reports 01-05);
this file only records the conclusions. Changing anything here is a breaking change and is decided
by the orchestrator, never by a porting sub-agent.

## 1. Scope

`glam-cairo` (named `glam.cairo` until 2026-09; the dated documents under `docs/research/`,
`docs/audits/`, `docs/briefs/` and the past `CHANGELOG.md` entries keep that name) ports
[glam-rs](https://github.com/bitshifter/glam-rs) **0.33.8** to pure Cairo
(no `starknet` dependency). It is the base layer of a provable game physics stack; the sibling
repositories `nalgebra-cairo` and `rapier-cairo` consume the published packages:

| package | role |
|---|---|
| `fixed` | the signed Q32.32 scalar, its fused kernels and its transcendental functions. Zero dependencies. |
| `glam` | `Vec2/3/4`, `Mat2/3/4`, `Quat`, `Affine2/3`, `BVec*`, `IVec*`, `UVec*`, `EulerRot`, swizzles, camera |
| `glamx` | physics-oriented extensions mirroring Dimforge's `glamx` 0.3.1 (what parry and rapier are written against): `Rot2`, `Rot3 = Quat`, `Pose2`, `Pose3`, `SdpMatrix2/3`, `SymmetricEigen3`. Separate package so that `glam` stays a clean glam-rs parity surface and `glam_tests` does not pay for it |
| `benches` | unpublished: gas/step benchmarks and the losing alternative implementations |

Type mapping from glam-rs (one scalar, so the f32/f64/SIMD/aligned variants collapse):

| glam-rs | glam-cairo |
|---|---|
| `Vec2`, `DVec2` | `Vec2` |
| `Vec3`, `Vec3A`, `DVec3` | `Vec3` |
| `Vec4`, `DVec4` | `Vec4` |
| `Mat2/DMat2`, `Mat3/Mat3A/DMat3`, `Mat4/DMat4` | `Mat2`, `Mat3`, `Mat4` |
| `Quat`, `DQuat` | `Quat` |
| `Affine2/DAffine2`, `Affine3A/Affine3/DAffine3` | `Affine2`, `Affine3` |
| `BVec2/3/4` (+`A` variants) | `BVec2`, `BVec3`, `BVec4` |
| `IVec*` / `UVec*` (i32 / u32) | `IVec2/3/4`, `UVec2/3/4` |
| other integer widths (i8, i16, i64, u8, u16, u64, usize) | not ported (add on demand) |
| `EulerRot`, swizzle traits, `camera` | ported (Vec4 swizzles and camera last) |
| SIMD, `bytemuck`, `serde`, `rand`, `mint`, `NAN`/`INFINITY`, `is_nan`, `is_finite` | dropped |

## 2. The scalar: `fixed::Fixed`

```cairo
#[derive(Copy, Drop, Serde, PartialEq, Debug, Default, Hash)]
pub struct Fixed { pub raw: i64 }   // value = raw / 2^32
```

- **Format**: signed Q32.32 in a native two's-complement `i64`. Range `[-2^31, 2^31)`,
  resolution `2^-32 ~= 2.3e-10`. One felt per value, a unique zero, native `Serde`/`Hash`/storage.
- **Why** (report 05): add/sub/compare are one native libfunc each (840 / 770 gas vs 4 050 / 3 110
  for cubit's sign-magnitude); every operand is <= 64 bits so every product fits 128 bits, below
  the cost cliff of `u128` multiplication (5.7x) and `u256` (25x). Q16.16 costs the same as Q32.32
  and overflows `length_squared` at |v| = 181; Q64.64 costs 2.4x on `mul`.
- **Rejected**: sign-magnitude structs (cubit, orion), `u256` intermediates, Q64.64, biased
  unsigned. A `felt252`-backed scalar is 12-19 % cheaper on kernels and 8x cheaper on `add`, but
  loses the static "always a valid i64" invariant at every trust boundary; it is kept as a
  documented alternative (report 05 section 3.4) should profiling of the physics step justify it.
- **Rounding**: **floor** (toward negative infinity) for every rescale: `mul`, fused kernels,
  polynomial evaluation. It is what the branch-free bias trick `((p + 2^k) div 2^32) - 2^(k-32)`
  yields for free. Division follows the Rust reference (`f64 /`): `Fixed / Fixed`, `recip` and
  `from_ratio` round to nearest, ties to even, and are exact whenever the quotient is
  representable (since 0.3.0, #42; 4 140 gas vs 3 740 for the former truncation, which DESIGN
  used to prefer for cost: the owner's rule "mirror the reference" wins). `div_nearest` /
  `recip_nearest` are the same functions under explicit names, and `wide::RecipNearest` shares a
  divisor with the same bits. `rem` is the exact truncated remainder (Rust's float `%`) and
  `div_euclid` / `rem_euclid` are euclidean, as in Rust. Multiplication and the fused kernels
  still floor: `f64 *` rounds to nearest, and aligning them is an open question (it would change
  every result of the library). One deliberate exception:
  `wide::RecipTrait::mul` (the shared-division kernel behind `normalize*` and `inverse`) rounds
  to nearest, ties toward +infinity, at no extra cost, so that `x / d` is exact whenever the
  quotient is representable (`normalize` of an axis-aligned vector is exactly `+-1`). Second
  exception: the **final** rescale of a transcendental polynomial (`fixed::trig`) rounds to
  nearest (symmetric error of about +-1 ULP instead of one-sided `[-2, 0]`, `cos(2^-32) = 1`,
  <= 300 gas); intermediate rescales still floor. `exp2` / `exp` / `powf` (`fixed::exp`) keep
  a floor final rescale: with round-to-nearest the generator found 1 ULP descents at segment
  junctions, and monotonicity is worth more than the 1 ULP gained; the logarithms round to
  nearest. Third exception: the Jacobi rotations of `glamx::eigen3` round to nearest (one-sided
  floor errors accumulate over ~12 rotations: residual 14.0 -> 6.7 ULP measured). `sqrt` and `norm*` return the floor of the
  exact root. Rounding is part of the API: results are bit-exact
  and any change is a MINOR version bump.
- **Overflow**: panics (native `i64` checks and the final `downcast` of each kernel). Never wraps,
  never saturates. Panic messages are short strings, e.g. `'Fixed: overflow'`.
- **Arithmetic internals**: `core::internal::bounded_int` behind
  `#[feature("bounded-int-utils")]`, isolated in `fixed::internal` and never exposed. It is an
  unstable corelib API: the toolchain is pinned, the plumbing (type aliases and helper impls with
  computed bounds) is generated by a script, and a stable-API variant (1.8x the `mul` cost) stays
  in `benches::alt` as the fallback.
- **Concrete type, no generic scalar**: `#[inline(always)]` is rejected on functions with impl
  generic parameters (E2143) and a non-inlined panicking call costs ~2 000 gas, i.e. as much as a
  `mul`. glam-rs itself is monomorphic (generated from templates). All geometry types are written
  against `Fixed` directly.

### 2.1 Fused kernels (`fixed::wide`)

The single largest win (7x on `Mat4 * Mat4` vs cubit): multiply raw values into Q64.64 products
(1 step, no range check), **sum the raw products, rescale once per output scalar**.

- `dot2/3/4`, `dot2/3_add`, `mul_sub` (`a*b - c*d`, the cross-product/determinant building
  block), `mul_add`, `det3`, `norm*`, `distance*`, `normalize*`, the shared square root `Norm`
  (one `sqrt` for `length` + `normalize` + `try_normalize`), the shared division `Recip` (divide
  an adjugate once) and the typed accumulators `W1..W16` (sums of raw products, Q64.64) /
  `T1..T16` (sums of triple products, Q96.96) with `add/sub/neg/mul/lift/narrow` are public API
  of `fixed`: `glam`, `nalgebra` and `rapier` kernels must be written against them, never as
  chains of `Fixed * Fixed` (measured: `dot3` 2 080 fused vs 7 540 unfused gas). Bounds are
  tracked by the type system; `narrow` is the only range check; 16 terms is the ceiling
  (narrow a partial sum and re-lift beyond that); quadruple products do not fit a felt.
- `length = u128_sqrt(x^2 + y^2 + z^2)` on the **raw** sum: no rescale, no precision loss, and
  `length_squared` underflow for tiny vectors disappears from `length`/`normalize`.
- Rule of thumb: one rescale (`div_rem` by `2^32`) per output component, zero per intermediate.

### 2.2 Transcendentals (`fixed::trig`, later `fixed::exp`)

Loop-free: constant-divisor range reduction (`DivRem` by a constant, with a Cody-Waite tail so
that 1 000 turns still cost ~2 ULP), then a minimax polynomial in Horner form on wide
accumulators, coefficients as constants. Report 05 section 4 measured the prototype with
**constant inputs** (`sin` 18 420, `sin_cos` 28 060, `atan2` 22 420, `acos` 25 740 gas): those
numbers are roughly half of what the repository's black-boxed protocol reports for the same
algorithm; the baseline is `gas/trig.snap`, not report 05. Coefficients are
generated by a checked-in script which also emits a bit-exact Python mirror used for error sweeps.
LUT + lerp variants (12 680 gas, 1.2e-7) are optional and named `*_fast`. No CORDIC, no Taylor
recursion.

Tiers: **A** arithmetic, comparisons, rounding, `sqrt`, fused kernels; **B** `sin`, `cos`,
`sin_cos`, `tan`, `atan2`, `acos`, `asin`; **C** (deferred, no internal consumer in glam) `exp`,
`exp2`, `ln`, `log2`, `powf`.

## 3. Semantics that differ from glam-rs

Every deviation is also documented on the item under `#### Deviations`.

| topic | glam-rs (f32) | glam-cairo |
|---|---|---|
| NaN / infinity | propagate | do not exist; the operation panics instead |
| overflow | infinity | panic (`'Fixed: overflow'` or native i64 message) |
| `normalize` of zero | NaN vector | panics `'VecN: normalize zero'`; `try_normalize` / `normalize_or_zero` as in glam |
| `recip`, division by zero | infinity | panic |
| `signum(0)` | `+1.0` | `+1` (kept: `angle_to` and `any_orthonormal_*` rely on it) |
| epsilon thresholds (`is_normalized` 2e-4, slerp `1 - 1e-6`, `1e-8`, ...) | tuned for f32 | re-derived per call site, expressed in raw ULPs, listed in the item doc |
| `abs_diff_eq`, `Eq`, `Hash` | approximate only | `abs_diff_eq` kept; exact `PartialEq`/`Hash` also meaningful |
| `try_inverse` / `inverse` | `det == 0` | divide the adjugate **once** by the determinant; singular = `det == 0` raw |
| `Vec * scalar` operators | `Mul<f32> for Vec3` | core `Mul<T>` is homogeneous: named methods `mul_scalar`, `div_scalar` (+ heterogeneous `MulAssign`) |
| `round`, `fract`, `%` on negatives | IEEE | `round` = half away from zero as in Rust; `fract = x - trunc(x)`, `fract_gl = x - floor(x)`; `rem` truncated, `rem_euclid` euclidean |
| `as_*` casts | saturating | `Fixed -> i32/u32` panics when out of range |
| `glam_assert!` (opt-in debug asserts) | feature flag | not checked (document the precondition) unless the check is free |
| `acos_approx` | degree-7 approximation | the precise `fixed::trig::acos` (7.6e-10) |
| algebraic reassociation | rounds after each f32 operation | products are accumulated by `fixed::wide` and rescaled once per output: an equivalent formula may differ bitwise from a line-by-line float port |
| interpolation | `lerp` is `a*(1-t) + b*t`; glamx `Rot2::lerp` is not normalised | `Fixed` / vector `lerp` is `a + (b-a)*t` (exact at both ends, one rescale). A same-name rotation `lerp` keeps the upstream semantics: normalisation is spelled `lerp(..).normalize()` or `nlerp` where upstream has it |
| small-distance snap | `move_towards` snaps below `1e-4` | only a distance of exactly zero raw is snapped: every non-zero Q32.32 distance is resolved |
| camera validation | `glam_assert!` on positive near / far; other invalid inputs flow to IEEE values | projection constructors always check positive near / far, `0 < fov < PI`, non-zero aspect and non-zero denominators, and panic with the documented messages (no NaN to return; the checks are cheap next to a `sin_cos`) |
| integer-vector overflow | depends on debug / release and on the operation order | plain operators panic; fused helpers range-check the final result only, so an out-of-range intermediate is accepted when the result fits |
| alternative algorithms | platform libm, glamx closed forms | the deterministic transcendentals of `fixed` and the scaled Jacobi solver of `glamx::eigen3` are public numeric choices; the measured error bounds live on the items |
| API surface | inherent methods, reference / iterator / `Display` / `Deref` glue | extension traits to import, named heterogeneous operations, pass by value, derived `Debug`; every omission or addition is listed on the type |
| unchecked preconditions and degenerate inputs | feature-gated assertions | out-of-contract results are unspecified but deterministic: a degenerate input either flows through (`Affine2::to_scale_angle_translation` returns a zero scale) or reaches a mandatory division and panics (`Mat4` / `Affine3::to_scale_rotation_translation`); the item says which |

The `#### Deviations` section of an item is semantic only: gas notes, inlining choices and
"exact" parity statements do not belong there. The audit of all 1 179 documented items before
`v0.1.0` is `docs/audits/R1-deviations.md` (inventory: `python3 scripts/deviations.py`; the
appendix of the audit is a snapshot of its date, it is deliberately not part of the gate).

## 4. Code conventions

Naming mirrors glam-rs exactly (modules, types, methods). `pub trait Vec3Trait` +
`pub impl Vec3Impl of Vec3Trait`; operator impls `Vec3Add`, `Vec3Neg`, ...; conversions
`Vec2IntoVec3`; panic messages `'<Type>: <reason>'` (<= 31 chars).

Hard rules (each one is backed by a measurement in report 05 section 6 / report 03 R1-R12):

1. Value types are `#[derive(Copy, Drop, Serde, PartialEq, Debug, Default, Hash)]` structs of
   named scalar fields with `pub` fields, passed **by value**. No `Array`, `Span`, `Felt252Dict`
   or loop in any fixed-size math (a `Span`+loop `Mat3*Mat3` is 9.2x the unrolled one).
2. Products go through the fused kernels of `fixed::wide`: one rescale per output scalar.
3. `#[inline(always)]` on every scalar operator, constructor, accessor and kernel helper. Public
   kernels are the only call boundaries. Large bodies (`Mat4::inverse`, `slerp`) are not inlined.
   Any inlining decision on a hot path is backed by a snapshot delta. Bytecode is the price
   (`docs/audits/R1-bytecode-size.md`, #31): an inlined item is paid at every call site (51 CASM
   felts for `Fixed * Fixed`, ~900 for `Mat4::mul_mat4`, ~1 100 for a camera `perspective`), a
   non-inlined one once per class (`powf` 9.3k); a kitchen-sink contract of 22 entry points sits
   at 62 % of the 81 920-felt class limit. The library does not ship non-inlined twins: a
   consumer short of bytecode wraps the call site in its own `#[inline(never)]` function
   (+15 to +42 % gas on that call), which is possible in that direction only; the compiler's
   `inlining-strategy` is left at its default (`avoid` costs +177 % gas). `gas/bytecode.size`
   tracks the fixture sizes in CI.
4. No bitwise operators. Masks and shifts are `DivRem` by a constant power of two
   (`NonZero` const). Never `pow(2, n)` at runtime.
5. Tables are `const [T; N]` + `.span()` (1 270 gas, size independent); dispatch is `match` on a
   small integer (2 370). Never if-chains.
6. Stay <= 64-bit operands. No `u128` multiplication, no `u256`, no `felt252 -> int` conversion
   in hot paths unless measured.
7. Plain panicking operators only: `wrapping_*` / `checked_*` / `saturating_*` are slower.
8. One `DivRem::div_rem` instead of `/` and `%`. Do not recompute derived values.
9. When the cheapest formulation is not obvious, implement the candidates (math / bitwise / loop /
   table), bench them all, keep the winner in the library and the losers in `benches::alt` with
   their benches, so the comparison stays reproducible across compiler upgrades.
10. No stubbed success: an unported function does not exist.

Re-exports: `glam/src/lib.cairo` re-exports types and traits only (`pub use vec3::{Vec3, Vec3Trait};`).
The glam-rs constructor functions (`vec3(x, y, z)`, `bvec3(..)`) share their module's name, and
in Cairo a root re-export of the function shadows the module (`glam::vec3::Vec3` stops resolving):
import them from their module (`use glam::vec3::vec3;`).

Gas accounting note (measured on `eigen3`, #34): inside a function Sierra gas is charged for the
most expensive branch whichever one runs (a skipped Jacobi rotation still cost its 38 040 gas),
while steps count what ran; only the iterations of a loop are metered as they execute. So a
cheap early-out saves steps, not gas, unless it is the exit condition of a `while`; and benches
of branching functions carry several inputs (`_first` / `_last` ...) mainly for the steps and
for the cases where the compiler does redeposit the gas of the cheaper branch.

Doc template (every public item):

```cairo
/// Computes the dot product of `self` and `rhs`.
///
/// Mirrors `glam::Vec3::dot`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
```

## 5. Tests and gas tracking

- Correctness tests: `packages/<pkg>/tests/test_<module>.cairo`. Golden vectors come from glam-rs
  (`=0.33.8`, f64 `D*` types as the oracle, inputs quantized to Q32.32 first) via the generator in
  `tools/refgen`; tolerances are budgeted in raw ULPs and justified (0 for exact ops, ~`dim` ULP
  for dot / matrix products, relative to the determinant for inverses). Plus edge cases, seeded
  fuzz properties (`#[fuzzer(runs: 256, seed: ...)]`) and `#[should_panic(expected: ...)]` with
  the exact message for every panic path.
- Benchmarks: `packages/benches/tests/bench_<module>.cairo`. A bench `X` is a pair of tests
  `X__base` / `X__op` with the same prelude; inputs go through `bb`, results through `sink`
  (`#[inline(never)]`), otherwise the compiler constant-folds the work down to the empty-test
  floor (13 620 gas). **Every public function of `fixed` and every non-trivial public function of
  `glam` has a bench.**
- `scripts/bench.py snapshot` writes `gas/<module>.snap` (l2_gas = Sierra gas, the north star;
  steps, range checks and bitwise cells, the prover's cost). `scripts/bench.py check` fails on any
  difference; CI runs it, so every gas change is a reviewable diff in the pull request.
- `scripts/check.sh` = fmt + lint (`--deny-warnings`) + build + tests + snapshot check + docs.

## 6. Versioning

Pre-1.0. PATCH: fixes/perf with identical API **and identical numeric results**. MINOR: any API
change or any change of a numeric result (downstream determinism depends on bit-exact outputs).
Siblings pin a tag: `{ git = "https://github.com/bal7hazar/glam-cairo", tag = "vX.Y.Z" }`, never
a branch. Compiler bumps are dedicated pull requests that regenerate every snapshot.
