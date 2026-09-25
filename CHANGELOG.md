# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning policy:
`docs/DESIGN.md` section 6 (any change of a numeric result is a MINOR bump).

Releases 0.1.0 to 0.3.0 of `fixed` were cut from
[`glam-cairo`](https://github.com/bal7hazar/glam-cairo) (tags `v0.1.0`..`v0.3.0` there, together
with `glam` and `glamx`); the entries below are the `fixed` part of its changelog, and the pull
request numbers refer to `glam-cairo`. The next release is cut from this repository.

## [Unreleased]

### Changed
- Repository split: `fixed` moves from `glam-cairo` to `fixed-cairo`, with its full history, its
  benches (`fixed`, `wide`, `trig`, `exp`), gas snapshots, golden-vector generator (pruned to the
  scalar types: no `glam` / `glamx` crate dependency any more), gate scripts and CI. The source
  and every numeric result are unchanged. `gas/bytecode.size` now tracks the `Scalar` contract
  fixture only (the `glam` / `glamx` fixtures stay in their repositories). The package name and
  the registry are unchanged; `repository` metadata will point here from the next release.

## [0.3.0] - 2026-09-23

Division follows the Rust reference (`f64 /`), requested by `nalgebra-cairo` (41 accuracy tests of
its LU / LDLT / Cholesky / QR / SVD regressed with the truncating division). **Numeric change**:
every result that goes through `/`, `recip` or `from_ratio` may move by 1 ULP.

### Added
- `FixedTrait::div_nearest`, `FixedTrait::recip_nearest`: the correctly rounded quotient (to
  nearest, ties to even), exact when representable (#42).
- `fixed::wide::RecipNearest` / `RecipNearestTrait::{new, div_nearest}`: a divisor prepared once,
  bit-identical to `x.div_nearest(d)`; cheaper from 3 quotients on (-12 % at 9) (#42).

### Changed
- `Fixed / Fixed`, `FixedTrait::recip` and `FixedTrait::from_ratio` round to nearest, ties to
  even, instead of truncating toward zero (`/` 3 740 -> 4 140 gas, `recip` 3 370 -> 3 670). `rem`,
  `div_euclid`, `rem_euclid` and `RecipTrait::mul` are unchanged. Measured accuracy: `tan` 2.22 ->
  1.73 ULP, `atan2` 3.22 -> 2.78, `log` 1.88 -> 1.35; `atan` 2.67 -> 2.75 (#42).

## [0.2.0] - 2026-09-23

API addition requested by `nalgebra-cairo` (generic code over one accumulator type); no numeric
result changes.

### Added
- `fixed::wide::Acc` (`AccTrait::{zero, add_prod, sub_prod, add, sub, narrow, sqrt, mul_narrow}`,
  `Add` / `Sub` / `Neg`, `Into<W1..W16, Acc>`): an exact Q64.64 accumulator whose type does not
  depend on the number of terms, bit-exact with the typed `W1..W16` chains (`add_prod` +200 gas
  per product as `Wn.add(wide_mul(..))`; `sqrt` 4 860 vs 1 920 for `W2.sqrt` to keep its two
  panic messages distinct). The absorbing-`W16` alternative (10x the cost) stays in
  `benches::alt::wide` (#40).
- `WideSqrt` for every `W1..W16` (was `W1..W3`) (#40).

## [0.1.0] - 2026-09-22

First release of `fixed` (Q32.32 scalar, fused kernels, transcendentals), after the R1 release
audit of `glam-cairo`.

### Added
- Workspace seed of the `Fixed` Q32.32 scalar; gas/step benchmark harness (`scripts/bench.py`,
  `gas/*.snap`) and CI.
- `tools/refgen`: golden-vector generator, CI `golden` job (#3).
- `fixed`: tier A scalar (`FixedTrait`, operators, rounding, `sqrt`, `FloatExt` helpers) and `wide` fused kernels with typed accumulators (#6).
- `fixed`: exact-integer golden vectors for tier A and `wide` (117 generated tests, tolerance 0) (#7).
- `fixed::trig`: loop-free `sin`, `cos`, `sin_cos`, `tan`, `asin`, `acos`, `atan`, `atan2` (about +-1 ULP, generator + bit-exact mirror in `scripts/gen_trig.py`) (#8).
- `fixed::exp`: loop-free `exp`, `exp2`, `exp_m1`, `ln`, `log2`, `log10`, `ln_1p`, `log`, `powf` (monotone, <= ~2 ULP, generator + mirror in `scripts/gen_exp.py`) (#18).
- Generated gas tables in the READMEs (`scripts/gas_tables.py`) (#28).
- Deviation inventory (`scripts/deviations.py`); overflow / division-by-zero deviations documented on `fixed` and the `wide` kernels (#30, #38).

### Changed
- `fixed::wide::is_unit2/3/4`: exact wide predicates (behind `glam`'s `is_normalized`, which becomes total and 50-56 % cheaper) (#32).
- Benchmarks: one snforge test crate per `tests/bench_<module>.cairo` (`[[test]]` targets checked by `scripts/bench.py`); `bench.py check <filter>` (#33).
- `packages/consumer` (unpublished Starknet contract fixtures) and `scripts/bytecode_size.py`: class sizes tracked in `gas/bytecode.size` and CI (#31).
- Panic coverage: `scripts/panic_coverage.py` maps every documented `(item, panic message)` pair to a `#[should_panic]` test and runs in CI (#37).
- `Fixed::move_towards`: unreachable documented panics removed and wrong native messages fixed (#39).
