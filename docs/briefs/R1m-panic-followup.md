# R1m - follow-up of the panic coverage: quat tests and the escalated doc gaps

Branch `test/panic-followup`. Read `docs/briefs/R1-common.md`, `docs/briefs/COMMON.md`,
`scripts/panic_coverage.py` (its allowlist at the top is your worklist) and the "Escalations"
section of `docs/audits/R1-panic-coverage.md`.

Files you may edit: `packages/glam/tests/test_quat.cairo`; the doc comments (only) of the items
listed below in `packages/{fixed,glam,glamx}/src/**` (generated modules through
`tools/codegen/fvec.py` / `fmat.py`, then regenerate, `--check` clean); the allowlist of
`scripts/panic_coverage.py`; `docs/audits/R1-panic-coverage.md` (append a "Follow-up (#R1m)"
section). No other file; no behaviour change; every `gas/*.snap` and `gas/bytecode.size`
byte-for-byte unchanged (the gate proves it).

1. **The 21 `deferred: quat PR in flight` allowlist entries**: write the missing
   `#[should_panic(expected: ...)]` tests in `test_quat.cairo` with the `// panics: Quat::<item>`
   marker (the quat pull request #36 is merged: `is_normalized` / `is_near_identity` are total
   now, so if a documented panic on them no longer exists, fix the doc instead and say so),
   remove the entries. `python3 scripts/panic_coverage.py --check` must be green with no
   `deferred` entry left.
2. **Unreachable documented panics** (escalation 1): for each item, verify by reading the code
   (and a scratch test if cheap) that the panic really cannot happen; then remove that bullet
   from `#### Panics` (or set `* Never.`), and remove the allowlist entry. If one of them IS
   reachable, keep the doc, add the test, and say so.
3. **Wrong message in the doc** (escalation 2): `Fixed::move_towards`, `SdpMatrix{2,3}::
   add_diagonal`, `SdpMatrix{2,3}Add` / `Sub`, camera `orthographic` / `frustum`: put the
   message the code actually raises (`'i64_add Underflow'`, `'i64_sub Overflow'`, ...) and
   make sure the test expects it; remove the allowlist entries.
4. Line budget: do not add a test file (the `tests/lib.cairo` files are orchestrator-owned).
   `test_quat.cairo` may cross 1 200 lines by the 21 tests only: say by how much.

Gate under `flock /tmp/glam-cairo-gate.lock`; one scarb / snforge command at a time. Commit
scopes `test(quat)`, `docs(<pkg>)`, `chore(scripts)`. Pull request title
`test: quat panic tests and the escalated doc gaps (R1k follow-up)`. Model trailer: the model
you are.
