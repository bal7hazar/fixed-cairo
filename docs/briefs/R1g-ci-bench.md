# R1g - faster bench job (CI and local gate)

Branch `chore/ci-bench`. Tooling task, no library code. Read `docs/briefs/R1-common.md`,
`docs/briefs/COMMON.md`, `scripts/bench.py`, `scripts/check.sh`, `.github/workflows/ci.yml` and
`docs/DESIGN.md` section 5.

Files you may edit: `scripts/bench.py`, `scripts/check.sh`, `.github/workflows/ci.yml`,
`packages/benches/Scarb.toml` and `packages/benches/README.md` if needed. No `gas/*.snap` may
change: the snapshot content is the invariant of this task (`scripts/bench.py check` green with the
committed files, byte for byte).

Problem: the CI job `bench` takes ~15 minutes and is the long pole of `all-checks` (~26 minutes
on `main`). `scripts/bench.py` runs snforge twice over the `benches` package
(`--tracked-resource sierra-gas` for l2_gas, then `--tracked-resource cairo-steps` for steps and
builtins), after a separate `scarb build --workspace`, and each invocation appears to recompile
the test crate. Locally the same cost is paid by `scripts/check.sh`.

Do, measuring every step (`/usr/bin/time -v`, wall clock and peak RSS, before / after, cold and
warm `target/`):
1. Find where the time goes: compile vs run, per snforge invocation; whether the second run
   reuses the artifacts of the first (same profile / same `target` directory / flags that
   invalidate the cache); whether `scarb build --workspace` in that job is useful at all (the
   `test` jobs already build each package).
2. Get both metrics from **one compile**: e.g. a single snforge run if 0.61.0 can report
   sierra gas and steps together (read `snforge test --help` and the detailed-resources output),
   or two runs sharing one compiled artifact. No metric may be dropped and the numbers must be
   identical to the committed snapshots.
3. If still slow, split the CI job with a matrix over groups of bench modules (the filter
   argument of `bench.py` already exists) so that the groups run in parallel; `bench.py check
   <filter>` must then check only the matching snapshots and the union must cover every
   `gas/*.snap` (add a guard that fails if a bench module belongs to no group). Keep `all-checks`
   as the single required status and keep the gas report in the step summary.
4. Cache what is safe to cache in CI (scarb registry / `target`), keyed on `.tool-versions` and
   `Scarb.lock`; the pinned action SHAs stay pinned.
5. Same speed-up for `scripts/check.sh` when it applies (no loss of coverage).

Done: the usual gate (`flock /tmp/glam-cairo-gate.lock scripts/check.sh`), a pull request
`chore(ci): <what won>` whose own CI run shows the new timings; report the before / after
timings per job and locally. Model trailer: the model you are. Do not merge.
