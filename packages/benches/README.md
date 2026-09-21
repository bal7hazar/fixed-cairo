# benches

Unpublished. Gas and step benchmarks for `fixed` and `glam` (`tests/bench_<module>.cairo`), the
measurement harness (`src/harness.cairo`) and the alternative implementations that lost a
benchmark (`src/alt/`). Run with `scripts/bench.py` from the repository root.

Each `tests/bench_<module>.cairo` is its own snforge test crate, declared as a `[[test]]` target
(`test-type = "integration"`) in `Scarb.toml`; `tests/lib.cairo` is no longer used. snforge's cost
per test grows with the size of the compiled test program, so 31 small crates run all 4 700 benches
in ~80 s where one crate took ~990 s. A new bench file needs its `[[test]]` entry (`scripts/bench.py`
fails, and says so, when the two lists differ). Bench names in `gas/*.snap` are unchanged
(`bench_<module>::<bench>`).
