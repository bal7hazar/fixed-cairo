# F6 - correctly rounded division: `div_nearest`, `recip_nearest` (nalgebra-cairo escalation)

Branch `feat/div-nearest`. Read `docs/briefs/R1-common.md` (foreground only, gate under `flock`,
one scarb / snforge command at a time), `docs/briefs/COMMON.md`, `docs/DESIGN.md` section 2
("Rounding": `div`, `rem`, `recip`, `from_ratio` truncate; `RecipTrait::mul` rounds to nearest,
ties toward +infinity), `packages/fixed/src/fixed.cairo` (`FixedDiv`, `recip`, `from_ratio`),
`packages/fixed/src/wide.cairo` (`Recip`), `scripts/gen_bounded.py` (`recip_wide`, `recip_mul`),
`tools/refgen/specs/fixed.toml` + `tools/refgen/src/oracles/fixed.rs` (exact integer oracles).

Files you may edit: `packages/fixed/src/{fixed,wide}.cairo`, `scripts/gen_bounded.py` and its
outputs `packages/fixed/src/internal/{bounded,acc}.cairo`, `packages/fixed/tests/test_{fixed,
wide}.cairo`, the fixed golden files through `tools/refgen/specs/{fixed,wide}.toml` +
`tools/refgen/src/oracles/{fixed,wide}.rs`, `packages/benches/tests/bench_{fixed,wide}.cairo`,
`packages/benches/src/alt/{fixed,wide}.cairo`, `gas/{fixed,wide}.snap` (no other snapshot may
change), `docs/API_PARITY.md` and the READMEs' generated gas tables when stale. Not the versions,
not `CHANGELOG.md`, not `docs/DESIGN.md` (the orchestrator's).

## Why

nalgebra-cairo routes every division through `Real::div` / `Real::recip`. The owner ruled that
division must behave like the Rust reference: `f64 /` is correctly rounded, to nearest, ties to
even. With the truncating `Fixed / Fixed`, 41 accuracy tests of its LU / LDLT / Cholesky / QR /
SVD regress (LU6 determinant 93 -> 1 112 ULP). `RecipTrait::mul` fixes them but is only within
`1/2 + |x| / 2^64` ULP with ties toward +infinity: not a correctly rounded quotient.

## API (pure addition; existing results and gas unchanged)

- `FixedTrait::div_nearest(self: Fixed, rhs: Fixed) -> Fixed`:
  `round_half_even(self.raw * 2^32 / rhs.raw)` on the exact rational. Exact whenever the quotient
  is representable. Panics `'Fixed: division by zero'`, `'Fixed: overflow'` (the same messages as
  `/`: check which one `/` raises today and use the same).
- `FixedTrait::recip_nearest(self: Fixed) -> Fixed` == `ONE.div_nearest(self)`.
- `RecipTrait::div_nearest(self: Recip, x: Fixed) -> Fixed`: **bit-identical** to
  `x.div_nearest(d)` for every `x`, `d`, computed from the shared reciprocal plus an exact
  correction (the `Recip` quotient is within 1 ULP of the true one, so one remainder check
  `x * 2^32 - q * d` on wide operands, one comparison with `|d| / 2` and a tie-to-even step should
  suffice: prove it in the doc, with the error bound of `recip_mul`). It needs `d`: if storing
  `d` in `Recip` changes any existing snapshot (the `normalize*` / `inverse` family), use a
  separate type instead (e.g. `RecipNearest`, `RecipNearestTrait::{new, div_nearest}`), and
  measure both. The point for nalgebra: a shared divisor gives the same bits as per-element
  division, as in Rust.
- Full doc template; `#### Deviations`: none on semantics (this IS the Rust semantics); mention
  that `/` still truncates in 0.2 (see below).

## Tests

Exact integer oracle (Rust `i128` in refgen, or Python integers in the tests): golden vectors on
the extremes (`MIN`, `MAX`, `+-1` raw, `+-ONE`, quotients at the overflow boundary) and
**exhaustive tie cases** `2 |r| == |b|` for both signs of each operand (odd and even truncated
quotient, so both tie directions are exercised), plus exactness (`q * b == a` cases return `q`).
`RecipTrait::div_nearest == div_nearest`: a seeded fuzz property (`runs: 128`, <= 2 new fuzz
tests in total) plus the boundary table. One `should_panic` per documented panic with the
`// panics: <Owner>::<item>` marker.

## Gas (measure; winner in the library, losers in `alt`)

Benches for `div_nearest`, `recip_nearest`, `RecipTrait::div_nearest` (one division), and the
shared case `Recip::new(d)` + 2 / 3 / 4 / 9 `div_nearest` vs as many per-element `div_nearest`.
Candidates for the rounding step: comparison of `2|r|` with `|b|` then parity; the bias trick
(`(2 * a * 2^32 + b) div (2 * b)` with a tie fix-up); any other you find. Report against the
truncating `div` (3 740 gas) and `recip` (3 370).

## Measurement for the owner's decision (report only, do NOT commit)

Whether `Fixed / Fixed`, `FixedTrait::recip` and `from_ratio` themselves should switch to
round-half-even (the whole stack would mirror `f64 /`) is the owner's call. To inform it, on a
scratch branch (never pushed): switch `FixedDiv::div`, `recip` and `from_ratio` to the nearest
kernel and report (a) the gas delta of `div` / `recip`, (b) which snapshots of `gas/*.snap`
change and by how much at most, (c) how many golden / unit tests of `fixed`, `glam`, `glamx`
fail and whether each failure is only an expected-value change (regenerable) or a tolerance
problem. Then discard the scratch branch.

## Done

Gate green in the foreground; commits `feat(fixed): ...` / `feat(wide): ...` with your model's
trailer; pull request `feat(fixed): correctly rounded div_nearest / recip_nearest` with the gas
table and the measurement section; CI green; `REPORT.md` with the exact public symbols. Do not
merge.

## Part 2 (decided by the orchestrator on 2026-09-23, after the owner deferred to the Rust reference)

Given after part 1 is done, in the same pull request, as separate commits
(`feat(fixed)!: ...`). Rust's `f64 /` and `1.0 / x` round to nearest, ties to even; this port
follows the reference:
- `Fixed / Fixed` (`FixedDiv`, `FixedDivAssign`), `FixedTrait::recip` and `from_ratio` become the
  nearest kernel (`div_nearest` / `recip_nearest` stay as named aliases, documented as such).
- `rem` is unchanged: Rust's float `%` is the exact truncated remainder, which it already is.
  `div_euclid` / `rem_euclid` are unchanged (integer-valued quotient, as in Rust).
- `RecipTrait::mul` is unchanged (fused single rounding of `x / d`, DESIGN section 3
  "reassociation").
- Every golden file, unit test and snapshot that changes is regenerated or updated, across
  `fixed`, `glam`, `glamx` (the allowlist extends to their tests, goldens, refgen specs /
  oracles, `gas/*.snap`, `gas/bytecode.size`, the generated READMEs and `docs/API_PARITY.md`).
  An expected value changes: regenerate from the oracle. A tolerance no longer holds: stop and
  escalate with the case, never loosen it.
- The `#### Deviations` of `div`, `recip`, `from_ratio` and every item that documented
  "truncates" are updated (`python3 scripts/deviations.py` still parses; `panic_coverage.py
  --check` green).
