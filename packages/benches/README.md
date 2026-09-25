# benches

Unpublished. Gas and step benchmarks for `fixed` (`tests/bench_<module>.cairo`), the measurement
harness (`src/harness.cairo`) and the alternative implementations that lost a benchmark
(`src/alt/`). Run with `scripts/bench.py` from the repository root.

Each `tests/bench_<module>.cairo` is its own snforge test crate, declared as a `[[test]]` target
(`test-type = "integration"`) in `Scarb.toml`. snforge's cost per test grows with the size of the
compiled test program, so small crates run much faster than one large crate. A new bench file
needs its `[[test]]` entry (`scripts/bench.py` fails, and says so, when the two lists differ).
Bench names in `gas/*.snap` are `bench_<module>::<bench>`.
