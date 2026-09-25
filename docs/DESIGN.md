# Design

Decisions that every change to `fixed` must follow. The evidence lives in the research reports
of [`glam-cairo`](https://github.com/bal7hazar/glam-cairo) (`docs/research/`, reports 01-05,
cited below as "report NN"), where this package was designed and released up to 0.3.0; this file
only records the conclusions. Changing anything here is a breaking change and is decided by the
orchestrator (it lives in `glam-cairo`, see its `docs/ORCHESTRATOR.md`), never by a sub-agent.

## 1. Scope

`fixed-cairo` is the common foundation of two independent Cairo chains
(`fixed -> glam -> glamx -> parry -> rapier` and `fixed -> simba -> nalgebra -> rapier`). It has
no counterpart repository in Rust: `f64` is a language primitive. It was split out of
`glam-cairo` on 2026-09-25 (`glam-cairo` `docs/SPLIT.md`) with its full history.

| package | role |
|---|---|
| `fixed` | the signed Q32.32 scalar, its fused kernels and its transcendental functions. Zero dependencies. Published. |
| `benches` | unpublished: gas/step benchmarks and the losing alternative implementations |
| `consumer` | unpublished: a Starknet contract fixture that tracks the compiled class size (`gas/bytecode.size`) |

Names mirror Rust's `f32` / `f64` and glam's `FloatExt`; the fused kernels mirror the shapes of
the glam-rs functions they serve (`dot3` for `Vec3::dot`, `det3` for `Mat3::determinant`).
Escalations about the scalar from `glam-cairo`, `glamx-cairo`, `nalgebra-cairo` and
`rapier-cairo` come here. A MINOR bump of `fixed` means one pull request per consuming
repository.

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
  representable (since 0.3.0, glam-cairo #42; 4 140 gas vs 3 740 for the former truncation,
  which DESIGN used to prefer for cost: the owner's rule "mirror the reference" wins).
  `div_nearest` / `recip_nearest` are the same functions under explicit names, and
  `wide::RecipNearest` shares a divisor with the same bits. `rem` is the exact truncated
  remainder (Rust's float `%`) and `div_euclid` / `rem_euclid` are euclidean, as in Rust.
  Multiplication and the fused kernels still floor: `f64 *` rounds to nearest, and aligning them
  is an open question (it would change every result of every consumer). One deliberate
  exception: `wide::RecipTrait::mul` (the shared-division kernel behind `normalize*` and
  `inverse` in `glam`) rounds to nearest, ties toward +infinity, at no extra cost, so that
  `x / d` is exact whenever the quotient is representable (`normalize` of an axis-aligned vector
  is exactly `+-1`). Second exception: the **final** rescale of a transcendental polynomial
  (`fixed::trig`) rounds to nearest (symmetric error of about +-1 ULP instead of one-sided
  `[-2, 0]`, `cos(2^-32) = 1`, <= 300 gas); intermediate rescales still floor. `exp2` / `exp` /
  `powf` (`fixed::exp`) keep a floor final rescale: with round-to-nearest the generator found
  1 ULP descents at segment junctions, and monotonicity is worth more than the 1 ULP gained; the
  logarithms round to nearest. (Consumers may round differently in their own kernels: the Jacobi
  rotations of `glamx::eigen3` round to nearest.) `sqrt` and `norm*` return the floor of the
  exact root. Rounding is part of the API: results are bit-exact and any change is a MINOR
  version bump.
- **Overflow**: panics (native `i64` checks and the final `downcast` of each kernel). Never wraps,
  never saturates. Panic messages are short strings, e.g. `'Fixed: overflow'`.
- **Arithmetic internals**: `core::internal::bounded_int` behind
  `#[feature("bounded-int-utils")]`, isolated in `fixed::internal` and never exposed. It is an
  unstable corelib API: the toolchain is pinned, the plumbing (type aliases and helper impls with
  computed bounds) is generated by a script (`scripts/gen_bounded.py`), and a stable-API variant
  (1.8x the `mul` cost) stays in `benches::alt` as the fallback.
- **Concrete type, no generic scalar**: `#[inline(always)]` is rejected on functions with impl
  generic parameters (E2143) and a non-inlined panicking call costs ~2 000 gas, i.e. as much as a
  `mul`. glam-rs itself is monomorphic (generated from templates). Consumers write their
  geometry types against `Fixed` directly.

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
- A consumer that needs a kernel which does not exist asks for it here (escalation); it does not
  emulate it with chains of `Fixed * Fixed`.

### 2.2 Transcendentals (`fixed::trig`, `fixed::exp`)

Loop-free: constant-divisor range reduction (`DivRem` by a constant, with a Cody-Waite tail so
that 1 000 turns still cost ~2 ULP), then a minimax polynomial in Horner form on wide
accumulators, coefficients as constants. Report 05 section 4 measured the prototype with
**constant inputs** (`sin` 18 420, `sin_cos` 28 060, `atan2` 22 420, `acos` 25 740 gas): those
numbers are roughly half of what the repository's black-boxed protocol reports for the same
algorithm; the baseline is `gas/trig.snap`, not report 05. Coefficients are generated by a
checked-in script (`scripts/gen_trig.py`, `scripts/gen_exp.py`) which also emits a bit-exact
Python mirror used for error sweeps. LUT + lerp variants (12 680 gas, 1.2e-7) are optional and
named `*_fast`. No CORDIC, no Taylor recursion.

Tiers: **A** arithmetic, comparisons, rounding, `sqrt`, fused kernels; **B** `sin`, `cos`,
`sin_cos`, `tan`, `atan2`, `acos`, `asin`; **C** `exp`, `exp2`, `ln`, `log2`, `log10`, `ln_1p`,
`log`, `powf`.

## 3. Semantics that differ from Rust's `f32` / `f64`

Every deviation is also documented on the item under `#### Deviations`.

| topic | Rust float | `fixed` |
|---|---|---|
| NaN / infinity | propagate | do not exist; the operation panics instead |
| overflow | infinity | panic (`'Fixed: overflow'` or native i64 message) |
| `recip`, division by zero | infinity | panic |
| `signum(0)` | `+1.0` | `+1` (kept: glam's `angle_to` and `any_orthonormal_*` rely on it) |
| epsilon thresholds | tuned for f32 | re-derived per call site, expressed in raw ULPs, listed in the item doc |
| `abs_diff_eq`, `Eq`, `Hash` | approximate only | `abs_diff_eq` kept; exact `PartialEq`/`Hash` also meaningful |
| `round`, `fract`, `%` on negatives | IEEE | `round` = half away from zero as in Rust; `fract = x - trunc(x)`, `fract_gl = x - floor(x)`; `rem` truncated, `rem_euclid` euclidean |
| `as_*` casts | saturating | `Fixed -> i32/u32` panics when out of range |
| algebraic reassociation | rounds after each operation | products are accumulated by `fixed::wide` and rescaled once per output: an equivalent formula may differ bitwise from a line-by-line float port |
| interpolation | `lerp` is `a*(1-t) + b*t` | `lerp` is `a + (b-a)*t` (exact at both ends, one rescale) |
| small-distance snap | `move_towards` snaps below `1e-4` | only a distance of exactly zero raw is snapped: every non-zero Q32.32 distance is resolved |
| alternative algorithms | platform libm | the deterministic transcendentals of `fixed` are public numeric choices; the measured error bounds live on the items |
| API surface | inherent methods, `Display` | extension traits to import (`FixedTrait`, `TrigTrait`, `ExpTrait`), pass by value, derived `Debug`; every omission or addition is listed on the item |

The `#### Deviations` section of an item is semantic only: gas notes, inlining choices and
"exact" parity statements do not belong there. `python3 scripts/deviations.py` prints the
inventory of every documented item.

## 4. Code conventions

Naming mirrors Rust's float API and glam's `FloatExt` exactly. `pub trait FixedTrait` +
`pub impl FixedImpl of FixedTrait`; operator impls `FixedAdd`, `FixedNeg`, ...; panic messages
`'Fixed: <reason>'` (<= 31 chars).

Hard rules (each one is backed by a measurement in report 05 section 6 / report 03 R1-R12):

1. Value types are `#[derive(Copy, Drop, Serde, PartialEq, Debug, Default, Hash)]` structs of
   named scalar fields with `pub` fields, passed **by value**. No `Array`, `Span`, `Felt252Dict`
   or loop in any fixed-size math (a `Span`+loop `Mat3*Mat3` is 9.2x the unrolled one).
2. Products go through the fused kernels of `fixed::wide`: one rescale per output scalar.
3. `#[inline(always)]` on every scalar operator, constructor, accessor and kernel helper. Public
   kernels are the only call boundaries. Large bodies (`powf`, `atan2`) are not inlined. Any
   inlining decision on a hot path is backed by a snapshot delta. Bytecode is the price
   (glam-cairo `docs/audits/R1-bytecode-size.md`, #31): an inlined item is paid at every call
   site (51 CASM felts for `Fixed * Fixed`), a non-inlined one once per class (`powf` 9.3k). The
   library does not ship non-inlined twins: a consumer short of bytecode wraps the call site in
   its own `#[inline(never)]` function, which is possible in that direction only; the compiler's
   `inlining-strategy` is left at its default. `gas/bytecode.size` tracks the fixture size in
   CI.
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
10. No stubbed success: an unimplemented function does not exist.

Gas accounting note (measured in glam-cairo, #34): inside a function Sierra gas is charged for
the most expensive branch whichever one runs, while steps count what ran; only the iterations of
a loop are metered as they execute. So a cheap early-out saves steps, not gas, and benches of
branching functions carry several inputs (`__small` / `__large` ...) mainly for the steps.

Doc template (every public item):

```cairo
/// Returns the square root of `self`, rounded toward zero.
///
/// Mirrors `f32::sqrt`.
/// #### Panics
/// * `'Fixed: sqrt negative'` if `self < 0`.
/// #### Deviations
/// * None.
```

## 5. Tests and gas tracking

- Correctness tests: `packages/fixed/tests/test_<module>.cairo`. Golden vectors come from the
  generator in `tools/refgen` (f64 oracles on inputs quantized to Q32.32 first, or exact integer
  oracles); tolerances are budgeted in raw ULPs and justified (0 for exact ops). Plus edge cases,
  seeded fuzz properties (`#[fuzzer(runs: 128, seed: ...)]`) and `#[should_panic(expected: ...)]`
  with the exact message for every panic path (`scripts/panic_coverage.py --check`).
- Benchmarks: `packages/benches/tests/bench_<module>.cairo`. A bench `X` is a pair of tests
  `X__base` / `X__op` with the same prelude; inputs go through `bb`, results through `sink`
  (`#[inline(never)]`), otherwise the compiler constant-folds the work down to the empty-test
  floor. **Every public function of `fixed` has a bench.**
- `scripts/bench.py snapshot` writes `gas/<module>.snap` (l2_gas = Sierra gas, the north star;
  steps, range checks and bitwise cells, the prover's cost). `scripts/bench.py check` fails on any
  difference; CI runs it, so every gas change is a reviewable diff in the pull request.
- `scripts/check.sh` = fmt + lint (`--deny-warnings`) + build + tests + snapshot check + bytecode
  size + panic coverage + README gas tables + golden vectors + docs.

## 6. Versioning

Pre-1.0. PATCH: fixes/perf with identical API **and identical numeric results**. MINOR: any API
change or any change of a numeric result (downstream determinism depends on bit-exact outputs).
Releases 0.1.0 to 0.3.0 were cut from `glam-cairo`; the next one is cut from this repository.
Consumers depend on the registry version (`fixed = "0.3.0"`). Compiler bumps are dedicated pull
requests that regenerate every snapshot.
