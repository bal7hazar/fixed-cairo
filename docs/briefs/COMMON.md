# Common rules of every porter brief

Appended to every task brief of `docs/briefs/`. The orchestrator launches a porter with
`claude -p "Read docs/briefs/<TASK>.md and docs/briefs/COMMON.md, then execute the task."` (or the
`codex exec` equivalent) from the task's own worktree; see `docs/ORCHESTRATOR.md`.

- Read `AGENTS.md` and `docs/DESIGN.md` first; they define the hard Cairo rules (no bitwise ops,
  no loops/arrays in fixed-size math, `#[inline(always)]` on small helpers only, every product
  through the fused kernels of `fixed::wide`, one rescale per output component, plain panicking
  operators), the doc template (`Mirrors`, `#### Panics`, `#### Deviations`), the naming
  (`XTrait`/`XImpl`, operator impls `XAdd`...), and the definition of done.
- House style precedents on `main`: `packages/glam/src/vec3.cairo` (+ its tests, golden, benches,
  `tools/codegen/fvec.py`, `fvec_tests.py`, `tools/codegen/README.md`), `packages/glam/src/quat.cairo`
  (hand-written module), `packages/fixed/src/wide.cairo`, `packages/fixed/src/trig.cairo` +
  `scripts/gen_trig.py` (generated coefficients + bit-exact Python mirror), `tools/refgen/README.md`
  and `tools/refgen/specs/vec3.toml` + `tools/refgen/src/oracles/vec3.rs` (golden vectors: exact
  integer oracles where the Cairo result is exactly defined, justified ULP tolerances otherwise;
  never loosen a tolerance to make a mismatch pass: investigate).
- Gas: per DESIGN rule 9, when a formulation is not obvious implement the candidates, bench them
  with `X__base`/`X__op` pairs and `bb`-wrapped inputs (`benches::harness`), several inputs for
  branching code, ship the winner, keep the losers in `benches::alt::<module>` with their benches.
  Measured facts so far: a shared `Recip` only pays off from two divisions on; fused `a - k*b`
  forms beat `self - project_onto`; one `sin_cos` (~31 300 gas) beats `sin` + `cos` (~44 900).
- Compile budget: the `glam_tests` crate is the largest compile of the workspace (~10 GB locally)
  and CI runs it on a 4-core runner. Tests are table-driven (one `#[test]` per function group
  looping over a `const` table), <= 1 200 lines per test file, generated golden files <= 1 500
  lines, at most 6 seeded fuzz properties per module with `runs: 128` (CI overrides with
  `--fuzzer-runs 32`). Measure with `/usr/bin/time -l snforge test -p <pkg> <filter>`.
- Golden vectors: add `tools/refgen/specs/<module>.toml` + `tools/refgen/src/oracles/<module>.rs`,
  regenerate with `cargo run --manifest-path tools/refgen/Cargo.toml -- gen <module>`; never
  hand-edit `golden_*.cairo`. Minimal `tools/refgen/src/**` fixes are allowed when a type is
  missing (say so in the report).
- Never edit `packages/glam/src/lib.cairo`, `docs/**`, `CHANGELOG.md`, `Scarb.toml`,
  `.github/**`, `scripts/**` (unless the brief lists a script) or another task's module: list
  needed re-exports / missing kernels / design questions under "Escalations" in your report.
  The glam-rs constructor functions (`mat3(..)`, `quat(..)`) are module-level `pub fn`, never
  re-exported at the crate root.
- glam-rs 0.33.8 sources: clone with
  `git clone --depth 1 --branch 0.33.8 https://github.com/bitshifter/glam-rs /tmp/glam-rs` if the
  brief's path is missing. Mirror the scalar (non-SIMD) code paths.
- DONE = `scarb fmt --workspace`; `scripts/check.sh` green in the FOREGROUND (never leave a
  command running in the background and end your turn: in headless mode that ends the session);
  `scripts/bench.py snapshot bench_<module>` for each of your bench modules; generator `--check`
  clean; conventional commits (`feat(<module>): ...`) each ending with a `Co-Authored-By:` trailer
  naming the model that actually did the work (e.g. `Co-Authored-By: Claude Opus 5
  <noreply@anthropic.com>`); `git push -u origin <branch>`;
  `gh pr create --base main` following `.github/PULL_REQUEST_TEMPLATE.md` (gas table of headline
  ops), body ending with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`;
  `gh pr checks <n> --watch --interval 20` in the foreground until all green (fix failures). Do
  NOT merge. Finally write `REPORT.md` at the worktree root (do not `git add` it): summary,
  public API signatures, gas table (headline ops + winners/losers), thresholds/numeric choices,
  deviations, deferred items, requested `lib.cairo` re-exports, escalations, PR URL.
- `docs/API_PARITY.md` is generated: when your task changes the public API of `glam` or `fixed`,
  run `python3 scripts/api_parity.py` and commit the regenerated file (the only file under `docs/`
  you may touch); `scripts/check.sh` and CI fail when it is stale. If an item you ported still
  shows as `missing` because of a naming rule, add the rule at the top of the script and say so.
- Work autonomously; do not ask questions; do not widen the scope.
