# R1l - doc-only deviation fixes from the audit

Branch `docs/deviations-fixes`. Doc comments only: no code, no test, no snapshot may change
(`scripts/bench.py check` and every test must be byte-for-byte unaffected; the gate proves it).
Read `docs/briefs/R1-common.md`, `docs/briefs/COMMON.md`, `docs/audits/R1-deviations.md`
(sections "Deviations not covered by DESIGN", "Suspected undocumented deviations", "Prioritized
follow-ups" P1 / P2) and `docs/DESIGN.md` section 3 (the 8 rows added after the audit are the
wording to point to).

Files you may edit: doc comments (`///`, `//!`) in `packages/{fixed,glam,glamx}/src/**/*.cairo`;
for the generated modules through their generators (`tools/codegen/fvec.py`, `fmat.py`,
`intvec.py`, `swizzles.py`, then regenerate; `--check` clean). `docs/API_PARITY.md` if the
parity script reads docs (run `python3 scripts/api_parity.py --check`). Nothing else.

1. **Stale camera module doc** (`packages/glam/src/camera.cairo` lines ~40-42): the
   `look_*_affine3` / `look_*_quat` constructors exist since #26; fix the list of omissions.
2. **`Deviations: None.` on items that panic where float upstream continues** (audit table
   "Suspected undocumented deviations" and the P1 rows): `Fixed::{from_ratio, abs, copysign,
   ceil, round, mul_add, remap, move_towards}`, the `Mat*::abs` family, the `fixed::wide` public
   kernels, `glamx::{pose2, pose3, rot2, sdp}` items at representable extremes, and the vector
   `round` / `ceil` wording through the generator. Wording: one bullet, `* Overflow panics
   (`'Fixed: overflow'` / the native message) where f32 returns +-inf or a larger finite value:
   DESIGN section 3, "overflow".` (adapt: division by zero -> "division by zero" row).
3. **Non-semantic bullets out of `#### Deviations`** (P2): gas / inlining notes, "exact",
   "as X", pass-by-value remarks, alternative-bench references move to the item's main text
   (before `Mirrors`) or to the module doc; `#### Deviations` keeps semantic differences only.
   Keep the text, move it: no information is lost.
4. **Reversed `clamp` range** (`Fixed::clamp`, vector `clamp`): document the out-of-contract
   result exactly as the code computes it (audit: the branch order can select `min`); do not
   change the code.
5. Re-run `python3 scripts/deviations.py --format markdown > /dev/null` to make sure the
   extractor still parses every item (its `--check` compares against the audit appendix of
   2026-09-21 and is expected to differ now: do not update the audit).

Gate under `flock /tmp/glam-cairo-gate.lock`; one scarb / snforge command at a time. One commit
per package (`docs(fixed): ...`, `docs(glam): ...`, `docs(glamx): ...`), one pull request
`docs: deviation wording fixes from the R1 audit`. Model trailer: the model you are.
