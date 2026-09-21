# R1h - audit of every documented deviation

Branch `docs/deviations-audit`. Reviewer task: you write one report, you change no library code.
Read `docs/briefs/R1-common.md`, `docs/briefs/COMMON.md`, `AGENTS.md`, `docs/DESIGN.md` (section 3
is the reference: "Semantics that differ from glam-rs"; section 2 for the rounding rules).

Files you may create or edit: `docs/audits/R1-deviations.md` and `scripts/deviations.py` (the
extractor below). Nothing else: no `.cairo` file, no other document. The gate for this task is
`scarb fmt --check --workspace` + `python3 scripts/deviations.py --check` (not the full
`scripts/check.sh`: you change no code).

Reference sources, cloned on demand: `git clone --depth 1 --branch 0.33.8
https://github.com/bitshifter/glam-rs /tmp/glam-rs`, `git clone --depth 1 --branch v0.3.1
https://github.com/dimforge/glamx /tmp/glamx` (check the tag name; scalar, non-SIMD code paths).

Context: the public items of `packages/{fixed,glam,glamx}/src/*.cairo` carry ~1 130
`#### Deviations` sections, ~630 of which are not `None.`. They were written by a dozen different
porter agents over 29 pull requests. Before `v0.1.0` freezes the numeric results (DESIGN
section 6), the owner needs to know that every deviation is deliberate, consistent across
modules, and covered by DESIGN section 3.

1. `scripts/deviations.py` (dependency-free Python 3): extracts every item's `Mirrors`,
   `#### Panics` and `#### Deviations` text with file, line, type and function name; default
   mode prints a TSV / Markdown inventory, `--check` verifies that the inventory embedded in the
   report's appendix is up to date. Generated modules are read as committed.
2. Classify each non-`None` deviation into the rows of DESIGN section 3 (NaN/infinity, overflow,
   normalize of zero, division by zero, `signum(0)`, epsilon thresholds in ULPs, `abs_diff_eq`,
   inverse, scalar operators, rounding of `round`/`fract`/`rem`, casts, `glam_assert`,
   `acos_approx`) or into **"not covered by DESIGN"**. The last class is the main deliverable:
   one line per distinct deviation with the items that carry it, what upstream does (quote the
   upstream file and function), what this port does, and a verdict: `keep + add to DESIGN`,
   `align with upstream`, `document better`, `bug`.
3. Mandatory deep checks, reading both the Cairo code and the upstream code:
   - `Rot2::lerp` normalises here and not upstream (glamx `rot2.rs`): consequences for a caller
     that ports rapier code line by line, and for `Pose2::lerp`; compare with `Rot2::nlerp` /
     `slerp` upstream; recommend keep or align.
   - Every threshold re-derived in ULPs (`is_normalized`, `slerp` / `from_rotation_arc` near-one
     thresholds, `to_axis_angle`, `any_orthonormal_*`, `Mat*::inverse` singularity, eigen3, the
     camera preconditions, `Affine*::decompose`...): table of item / upstream value / value here in
     raw ULPs and as a real number / derivation present in the doc (yes/no) / same value used by
     the sibling types (`Vec2` vs `Vec3` vs `Vec4` vs `Quat` vs `Rot2`). Flag inconsistencies.
   - Items whose doc says `Deviations: None.` but whose behaviour differs from upstream: sample
     at least the panicking paths (`#### Panics` non-empty with `Deviations: None.` is suspect:
     upstream returns NaN/inf), the rounding-sensitive functions (`round`, `fract`, `rem_euclid`,
     `div_euclid`, `powf` of negatives, `atan2(0, 0)`, `signum(0)`, `clamp` with `min > max`,
     `clamp_length`), and the `glam_assert!` preconditions that are silently unchecked here.
   - Panic messages: exact string, `'<Type>: <reason>'` convention, <= 31 characters, the same
     reason spelled the same way across types; every documented panic has a
     `#[should_panic(expected: ...)]` test (grep the test files) and vice versa.
4. Report `docs/audits/R1-deviations.md`: summary with counts per class; the "not covered" table;
   the threshold table; the list of suspected undocumented deviations with evidence (input,
   upstream result, result here); proposed wording for the rows to add to DESIGN section 3; a
   prioritised list of follow-up fixes, each sized (doc-only / numeric change / API change) and
   attributed to its module so that they can be delegated one pull request per module; appendix:
   the generated inventory.

Evidence over opinion: when you claim a behaviour, cite file and line, and when cheap run it
(`snforge test -p glam <filter>` with a scratch test that you do not commit, under
`flock /tmp/glam-cairo-gate.lock`). Commit `docs(audit): deviation audit for v0.1.0`, pull request
with the summary in the body, wait for CI, do not merge. Model trailer: the model you are.
