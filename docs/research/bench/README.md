# glam.cairo gas/step micro-benchmarks

Empirical cost measurements used to choose the scalar representation and the coding rules of the
Cairo port of `glam-rs`. Toolchain is pinned in `.tool-versions` (scarb 2.19.4, snforge 0.61.0).

## Run

```bash
./scripts/run_all.sh            # regenerate sources, run correctness tests, run all benchmarks
./scripts/run_all.sh snapshot   # ... and rewrite ./gas-snapshot
./scripts/run_all.sh check      # ... and fail (exit 1) if anything differs from ./gas-snapshot  (CI)

python3 scripts/bench.py run composite           # only benchmarks whose name contains "composite"
python3 scripts/bench.py check --tolerance 0.5   # allow +-0.5 % drift
python3 scripts/bench.py run composite --tag foo # side experiment -> results/results.foo.{md,csv}
```

Outputs: `results/results.md` / `results/results.csv` (one row per benchmark: l2_gas, steps,
range_check, bitwise, other builtins, memory holes), `results/raw/*.txt` (verbatim snforge output),
`results/trig_errors.md` (accuracy of the transcendental variants), `gas-snapshot`.

## How a cost is measured

`bench.py` runs the whole suite twice:

```bash
snforge test --detailed-resources --tracked-resource sierra-gas    # -> l2_gas (= sierra gas)
snforge test --detailed-resources --tracked-resource cairo-steps   # -> steps, builtins, memory holes
```

Every benchmark `X` is a pair of tests, `X__base` and `X__op`, with the *same* prelude:

```cairo
#[test] fn X__base() { let a = bb(..); let b = bb(..); let r = bb(..); sink(r); }
#[test] fn X__op()   { let a = bb(..); let b = bb(..); let r = bb(..); sink(a * b); }
```

and `cost(X) = X__op - X__base` for each metric. `bb` and `sink` (`src/harness.cairo`) are
`#[inline(never)]`: without them the compiler constant-folds the operation away (a test doing
`1 + 2` costs exactly as much as an empty test). Results are deterministic (bit-identical between
runs); the residual noise of the subtraction is about +-1 step (see `tests/validation.cairo`, which
re-measures a few operations amortised over a 100-iteration loop).

## Layout

| path | content |
|---|---|
| `src/harness.cairo` | `bb`, `sink` |
| `src/prims_support.cairo`, `src/prims_tables.cairo`* | helpers and lookup tables for the primitive benchmarks |
| `src/fixed/mag.cairo` | A: cubit-style `{ mag: u64, sign: bool }` Q32.32 (algorithms copied from cubit) |
| `src/fixed/magi.cairo`* | A': A with `#[inline(always)]` |
| `src/fixed/i64n.cairo` | B: `i64` Q32.32, stable corelib operators only |
| `src/fixed/i64b.cairo`, `i64b_types.cairo`* | C/E: `i64` Q32.32, bounded-int arithmetic + fused (single rescale) kernels |
| `src/fixed/felt.cairo` | D: `felt252`-backed Q32.32, unchecked add/sub, lazy reduction |
| `src/fixed/q64.cairo` | F: Q64.64 `{ mag: u128, sign }`, add/mul/div only |
| `src/glam.cairo` | generic Vec3/Mat3/Mat4/Quat workloads written against the `Fused` kernels |
| `src/trig.cairo`, `src/trig_gen.cairo`* | our loop-free sin/cos/sin_cos/atan2/atan/acos/asin |
| `src/cubit_trig.cairo`, `src/cubit_lut.cairo` | vendored cubit trig (Taylor recursion, if-tree LUTs) on `FMag` |
| `tests/prims.cairo`*, `scalar.cairo`*, `composite.cairo`*, `trig.cairo`* | the benchmarks |
| `tests/correctness*.cairo`* | every representation against exact expected values; Cairo trig against the bit-exact Python mirrors |
| `tests/validation.cairo` | methodology cross-check (loop-amortised measurements) |
| `alt/` | tiny package comparing `scarb cairo-test` and `scarb execute --print-resource-usage` with snforge |
| `scripts/gen_*.py` | generators for the files marked * (`gen_trig.py` needs numpy) |
| `scripts/bench.py` | runner, parser, `gas-snapshot` writer/checker |

## CI sketch

```yaml
- uses: software-mansion/setup-scarb@v1          # reads .tool-versions
- uses: foundry-rs/setup-snfoundry@v4            # reads .tool-versions (check the current major)
- run: ./scripts/run_all.sh check                # fails on any unreviewed gas change
```

To accept a change: `./scripts/run_all.sh snapshot` and commit `gas-snapshot`; the diff of that file
is the gas review.
