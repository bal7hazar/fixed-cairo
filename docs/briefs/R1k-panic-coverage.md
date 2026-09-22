# R1k - panic coverage: item -> `should_panic` test manifest and checker

Branch `test/panic-coverage`. Read `docs/briefs/R1-common.md`, `docs/briefs/COMMON.md`, the
"Panic messages and tests" section of `docs/audits/R1-deviations.md`, and `scripts/deviations.py`
(the doc extractor you build on; reuse its parser, do not fork it).

Files you may create or edit: `scripts/panic_coverage.py`, `scripts/check.sh` (one added line),
`.github/workflows/ci.yml` (one added step in `fmt-lint`), `docs/audits/R1-panic-coverage.md`,
and **test files only** under `packages/{fixed,glam,glamx}/tests/test_*.cairo` plus the
generators of the generated test files (`tools/codegen/fvec_tests.py`, `fmat_tests.py`,
`intvec_tests.py`, then regenerate). No `src/` change except the doc template on the nine
`IndexView` impls of the vector modules (`packages/glam/src/{vec,ivec,uvec}{2,3,4}.cairo` through
their generators `tools/codegen/fvec.py` / `intvec.py`: add the `Mirrors` / `#### Panics` /
`#### Deviations` block, nothing else).

Problem (audit): 839 documented panic-message occurrences vs 634 `#[should_panic(expected: ...)]`
tests; every one of the 61 distinct messages has at least one test, but nothing says that every
**item** whose doc lists a panic has a test that exercises that panic on that item.

1. `scripts/panic_coverage.py` (dependency-free Python 3): for every public item with a
   non-`Never` `#### Panics` section, list the expected messages; for every
   `#[should_panic(expected: '<msg>')]` test, find which item it exercises. Attribution rule,
   in this order: (a) an explicit marker comment on the test, `// panics: <Type>::<item>`
   (add it where needed: that is most of the manual work); (b) the test name
   `test_<item>_panics*` / `test_<item>_<reason>` matching an item of the module under test;
   (c) otherwise "unattributed". Output: per package, a table item / message / test (or
   MISSING), a list of unattributed panic tests, and totals. `--check` exits 1 when a
   documented (item, message) pair has no test, or when a `should_panic` test is unattributed,
   except for pairs listed in an allowlist at the top of the script with a one-line reason each
   (inherited "As `X`" docs where the panic is exercised on `X`, helper self-tests such as the
   swizzle `'yx'` ones).
2. Fill the gaps: one test per missing (item, message) pair, table-driven where the module's
   tests are (compile budget of `COMMON.md`: no new test file, <= 1 200 lines per file, prefer
   extending an existing `should_panic` group over new functions when snforge's one-message-
   per-test rule allows). Do not weaken any assertion, do not change library behaviour; if a
   documented panic turns out to be unreachable or wrongly documented, do not touch `src/`: list
   it under Escalations with the evidence.
3. Wire `python3 scripts/panic_coverage.py --check` into `scripts/check.sh` and the CI
   `fmt-lint` job (it must run in < 5 s). Report `docs/audits/R1-panic-coverage.md`: before /
   after counts, the allowlist with reasons, the escalations.

Gate under `flock /tmp/glam-cairo-gate.lock`; one scarb / snforge command at a time. Commit
scopes `test(<pkg>)` / `chore(scripts)`. Pull request title
`test: panic coverage manifest and checker`. Model trailer: the model you are.
