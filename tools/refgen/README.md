# refgen - golden vectors of `fixed`

`refgen` generates `packages/fixed/tests/golden_<module>.cairo`: for every tested function, a set
of inputs and the reference result (an `f64` computation, or an exact integer oracle that
computes the raw result), compared in Cairo within a tolerance budgeted in raw ULPs (`2^-32`).
It is the pruned copy of the generator of
[`glam-cairo`](https://github.com/bal7hazar/glam-cairo), where glam-rs is the oracle of the
vector and matrix types; this copy only knows the scalar types, and the two may diverge.

It is a standalone Cargo workspace (pinned `Cargo.lock`), not part of the scarb workspace.

```sh
cargo run --manifest-path tools/refgen/Cargo.toml -- gen [module...]    # write the golden files
cargo run --manifest-path tools/refgen/Cargo.toml -- check [module...]  # exit 1 if a file is stale
cargo run --manifest-path tools/refgen/Cargo.toml -- list               # specs, oracles, status
```

`check` runs in CI (job `golden`) and in `scripts/check.sh` when `cargo` is installed. Options
(before the command): `--all` previews with every `enabled = false` ignored, `--root <dir>` and
`--specs <dir>` point to another checkout / spec directory (used to test the generator itself).

## How it works

1. Inputs are drawn as **raw Q32.32 integers** from an integer-only PRNG (xoshiro256**) seeded by
   `"<module>::<function>"`: no float, no platform dependence. Hand-picked `edges` come first.
2. Each raw input converts to `f64` **exactly** (`|raw| <= 2^53`, enforced), the oracle closure
   runs on it, and the result is quantized to the nearest raw value.
3. A case is **skipped and redrawn** when the oracle result is not representable (overflow, NaN,
   infinity: a panic path on the Cairo side), when the oracle calls `skip(..)` / returns `None`
   (precondition), or when an f64 result is `>= max_abs` (default `2^20`: above it a double no
   longer resolves half a raw ULP). Panic paths are tested explicitly with `[[function.panics]]`.
4. The Cairo file is emitted already formatted (`scarb fmt --check` passes): one
   `#[cairofmt::skip]` `const [i64; N]` table and one `#[test]` looping over it per function,
   one `#[should_panic]` test per panic case, and the few `next_*` / `check_*` helpers the file
   needs (the golden files cannot share a module: `tests/lib.cairo` is not theirs to edit).
   A failure reads `wide::dot3 #7: got 123, expected 125 (tol 1)`.

Output is deterministic: same spec + same oracles = byte-identical file on every host.

## Adding the golden vectors of a module

A module has two files, both auto-discovered (`build.rs` scans `src/oracles/`, the CLI scans
`specs/`):

| file | content |
|---|---|
| `tools/refgen/specs/<module>.toml` | what to test: call expression, types, domains, tolerance |
| `tools/refgen/src/oracles/<module>.rs` | the reference: one closure per function |

The output `packages/fixed/tests/golden_<module>.cairo` must be declared in
`packages/fixed/tests/lib.cairo`. `specs/fixed.toml` and `specs/wide.toml` are the references to
copy from.

1. Oracle, `src/oracles/<module>.rs`:

   ```rust
   use crate::prelude::*;

   pub fn register(r: &mut Registry) {
       r.add("sqrt", |a| a[0].f().sqrt());                           // f64 -> Fixed
       r.add("lt", |a| a[0].raw() < a[1].raw());                     // -> bool
       // Exact integer oracle; `None` (overflow) skips the case.
       r.add("add", |a| Out::raw_checked(a[0].raw().checked_add(a[1].raw())));
   }
   ```

   Arguments: `a[i].f()` (`Fixed` as f64), `.raw()`, `.i32()`, `.u32()`, `.i64()`, `.bool()`,
   `.elems()` (tuple). Results: anything `Into<Out>`: `f64`, `bool`, `i32`, `u32`, `i64`,
   tuples up to 4, `Option<_>` (`None` skips), `skip("reason")`, and `Out::raw(i64)` /
   `Out::raw_checked(Option<i64>)` / `Out::raw_wide(i128)` for **integer oracles** that compute
   the exact raw result (no `max_abs` guard, usable on the full `i64` range: see
   `oracles/fixed.rs`).

2. Spec, `specs/<module>.toml`:

   ```toml
   module = "wide"                        # = file name, -> golden_wide.cairo
   package = "fixed"                      # the only package of this repository
   # enabled = false                      # master switch: emits the bare stub
   imports = ["fixed::wide"]              # traits / consts used by `call`; types are automatic

   [[function]]
   name = "dot3"                          # test golden_wide_dot3, oracle "dot3" (or `oracle = ".."`)
   # enabled = false                      # per-function switch
   call = "wide::dot3({0}, {1}, {2}, {3}, {4}, {5})"   # Cairo expression, {i} = i-th argument
   args = ["Fixed", "Fixed", "Fixed", "Fixed", "Fixed", "Fixed"]
   ret = "Fixed"
   cases = 32                             # random cases, on top of the edges
   tolerance = 0                          # |actual.raw - expected.raw| <= tolerance
   justification = "exact integer oracle."   # mandatory
   # max_abs = 1048576.0                  # f64 resolution guard (default 2^20)
   edges = [                              # hand-picked cases: one value per argument
       [1, 0, 0, 0, 1, 0],                # numbers are values (1 = 1.0) ...
       ["raw:1", "raw:-1", 0.5, 1, 2, 3], # ... "raw:<int|0xhex>" is a raw leaf
   ]

   [[function.panics]]                    # #[should_panic(expected: '...')] tests
   name = "overflow"
   args = [2000000, 2000000, 0, 0, 0, 0]
   expected = "Fixed: overflow"
   ```

   Types: `Fixed`, `i64`, `i32`, `u32`, `bool` and flat tuples `"(Fixed, bool)"` (flattened in
   order; nested arrays in `edges` are allowed).

   An argument is a type name (default domain) or a table:

   | key | meaning |
   |---|---|
   | `domain` | preset for the `Fixed` leaves: `position` (default, \|x\| <= 1000), `unit` [-1, 1], `t` [0, 1], `positive` (0, 1000], `small` \|x\| <= 8, `angle` \|x\| <= 2 pi, `scale` [0.01, 100], `wide` \|x\| <= 2^20, `full` (whole i64 range, **integer oracles only**) |
   | `min`, `max` | bounds (value units) overriding the preset; integer bounds for `i32` / `u32` / `i64` (defaults [-1000, 1000] / [0, 1000]) |
   | `nonzero`, `min_abs` | per-leaf exclusions (divisors) |
   | `custom` | name of a generator registered in the oracle file: `r.generator("name", \|rng\| value_of(...))` |
   | `elems` | per-element argument specs of a tuple argument |

   Half of the draws are uniform in the domain, the others are right-shifted (small magnitudes),
   integers and half-integers. Relations between arguments (`clamp`: `min <= max`) are handled by
   skipping in the oracle.

3. Generate, test, commit the spec, the oracle **and** the generated file:

   ```sh
   cargo run --manifest-path tools/refgen/Cargo.toml -- gen <module>
   snforge test -p fixed golden_<module>
   scripts/check.sh
   ```

## Tolerances

`tolerance` is in raw ULPs and `justification` is mandatory, including for 0. Never loosen a
tolerance to make a test pass: derive the bound (see `docs/DESIGN.md` section 5).

- exact operations (add, sub, neg, min, max, abs, floor, comparisons, constructors): **0**;
- one rescale or one division (`mul`, `div`, `sqrt`, a fused `dot3` / `mul_sub` / `norm3`): **1**.
  The Cairo side floors or truncates the real result, the oracle rounds it to nearest;
- chained operations: add the ULPs of every rescale, scaled by the magnitude of the factors that
  multiply them afterwards;
- transcendental functions: the documented max error of `fixed::trig` in ULPs, plus 1.

An f64 oracle is itself only accurate to `|result| * 2^-53`: below `2^20` that is under half a
raw ULP (already counted in the "1" above), beyond it the case is skipped by `max_abs`. Keep the
inputs of quadratic functions within `|x| <= 500`, or write an integer oracle.

## Layout

| path | role |
|---|---|
| `specs/<module>.toml` | per-module spec |
| `src/oracles/<module>.rs` | per-module oracles, listed by `build.rs` |
| `src/value.rs`, `src/types.rs` | values, conversions, quantization, Cairo types |
| `src/domain.rs`, `src/rng.rs` | input domains, PRNG |
| `src/cases.rs`, `src/emit.rs` | case generation and skipping, Cairo emission |

Changing anything outside `specs/` and `src/oracles/` (PRNG, sampling, emission) changes every
golden file: regenerate everything in the same pull request.
