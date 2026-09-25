# S1 - extract `fixed-cairo`

Read `docs/SPLIT.md` first (the decisions), then `docs/briefs/R1-common.md` (foreground only, gate
under `flock`, one scarb / snforge command at a time) and `docs/briefs/COMMON.md`.

You are in a worktree of `glam-cairo` on branch `split/fixed`, cut from `origin/main`: it carries
the full history. Turn this branch into the first state of the new repository
`git@github.com:bal7hazar/fixed-cairo.git` (already created, empty), **in one commit on top of the
history** (`chore: split fixed-cairo out of glam-cairo`), then push it there as `main`:
`git remote add fixed git@github.com:bal7hazar/fixed-cairo.git && git push fixed split/fixed:main`.
**Never push this branch to `origin` (glam-cairo).** This bootstrap push to the new repository's
`main` is the one exception to "open a pull request": the repository is empty.

Keep, pruned to `fixed` (delete everything else):
- `packages/fixed` (unchanged source: the split must not change a single result);
- `packages/benches`: `harness`, `alt/{fixed,wide,trig,exp}`, `tests/bench_{fixed,wide,trig,exp}`
  and their `[[test]]` targets; `gas/{fixed,wide,trig,exp}.snap` byte-for-byte unchanged;
- `scripts/`: `bench.py`, `check.sh`, `gen_bounded.py`, `gen_trig.py`, `gen_exp.py`,
  `panic_coverage.py`, `deviations.py`, `gas_tables.py` (fixed README table only),
  `bytecode_size.py` + `packages/consumer` with the `Scalar` fixture only (`gas/bytecode.size`
  regenerated: the fixtures change, say so), `agent.sh`; pruned of every glam / glamx reference;
- `tools/refgen`: the `fixed` / `wide` specs and oracles only; drop the `glam` / `glamx` crate
  dependencies if nothing uses them any more (`Cargo.lock` regenerated), goldens byte-identical;
- `.github/` (workflow: jobs for the `fixed` package only; `all-checks` kept as the single
  required status), `.tool-versions`, `LICENSE`, `.gitignore`, `Scarb.toml` (workspace members
  `packages/*`, `repository = "https://github.com/bal7hazar/fixed-cairo"`, version stays `0.3.0`,
  no `glam` / `glamx` in `[workspace.dependencies]`), `Scarb.lock`.
- Documents, adapted to a scalar-only repository: `README.md` (what `fixed` is, install
  `fixed = "0.3.0"`, the generated gas table), `AGENTS.md` and `CLAUDE.md` (same rules, map and
  commands of this repository; the orchestrator lives in `glam-cairo`, see its
  `docs/ORCHESTRATOR.md`), `docs/DESIGN.md` = section 2 "The scalar" of glam-cairo's DESIGN
  (with 2.1 and 2.2), the relevant rows of section 3 and sections 4-6 as they apply to `fixed`,
  `CHANGELOG.md` = the `fixed` entries of glam-cairo's changelog grouped under 0.1.0 / 0.2.0 /
  0.3.0 with a line saying these were released from `glam-cairo`, plus an `[Unreleased]` entry
  "repository split". No `docs/research`, `docs/audits`, `docs/briefs`, orchestration docs.

Done: the full gate of the new layout green in the foreground (`flock /tmp/glam-cairo-gate.lock
scripts/check.sh`), then push to `fixed-cairo` `main`, then wait for its CI in the foreground
(`gh run watch` / `gh run list -R bal7hazar/fixed-cairo`) until green, fixing forward with more
commits pushed to `fixed-cairo` `main` if needed. `REPORT.md` (uncommitted, in this worktree):
what was kept / removed, which checks run where, the CI result, anything that could not be made
standalone. Commit trailer with your model.
