# R1b - gas tables in the READMEs

Branch `chore/gas-tables`. Tooling task, no Cairo code. Files you may create or edit:
`scripts/gas_tables.py`, `scripts/check.sh` (one added line), `README.md`,
`packages/fixed/README.md`, `packages/glam/README.md`, `packages/glamx/README.md`,
`.github/workflows/ci.yml` (one added step next to the `api_parity.py --check` step). Read
`AGENTS.md`, `docs/DESIGN.md` section 5 and `scripts/api_parity.py` (precedent for a generated,
checked document).

Write a dependency-free Python 3 script that reads `gas/*.snap` (format: header line
`# bench: l2_gas steps range_check bitwise other_builtins`, then `bench_<module>::<name>: <5
ints>`) and rewrites, between the markers `<!-- gas:begin -->` and `<!-- gas:end -->` of each
README, a curated table of headline operations (l2_gas, steps, range checks):
- `packages/fixed/README.md`: scalar ops (`add`, `mul`, `div`, `sqrt`, `floor`...), fused kernels
  (`dot3`, `mul_sub`, `det3`, `norm3`, `normalize3`, `recip_*`), trig (`sin`, `cos`, `sin_cos`,
  `atan2`, `acos`...), exp (`exp`, `exp2`, `ln`, `log2`, `powf`).
- `packages/glam/README.md`: per type (`Vec2/3/4`, `Mat2/3/4`, `Quat`, `Affine2/3`, Euler,
  camera) the 5-10 operations a game or physics engine calls most (`dot`, `cross`, `length`,
  `normalize`, `mul_vec3`, `mul_mat3`, `inverse`, `determinant`, `mul_quat`, `slerp`,
  `from_axis_angle`, `transform_point3`, `from_euler`, `perspective`...).
- `packages/glamx/README.md`: `Pose3`, `Pose2`, `Rot2`, `SdpMatrix3` headline ops (a module
  without a snapshot yet is skipped without error).
- root `README.md`: a short "at a glance" table of about 15 operations across the packages,
  replacing the prototype numbers currently quoted in the "Why another math library" section
  with the measured ones (keep the comparison with the cubit-style prototype, citing
  `docs/research/00-synthesis.md` for those figures).
The curated lists are data at the top of the script (bench names as they appear in the
snapshots: check they exist; a listed bench that is missing from an existing snapshot is an
error so the lists cannot rot silently). Exclude `alt_*` and `composite_*` benches. Modes:
default rewrites the READMEs; `--check` exits 1 if any README is stale. Wire `--check` into
`scripts/check.sh` and the CI `fmt-lint` job. Output deterministic, tables sorted as listed,
numbers with thin grouping (`12 345`), a caption naming the toolchain from `.tool-versions` and
stating that numbers are net of the test overhead (`X__op - X__base`).

Done: `scripts/check.sh` green in the foreground; conventional commit
`chore(readme): generated gas tables` with a `Co-Authored-By:` trailer naming your model; push;
`gh pr create --base main` (body ending with
`🤖 Generated with [Claude Code](https://claude.com/claude-code)`); wait for CI green in the
foreground. Do not merge. Write `REPORT.md` (not committed). Work autonomously; do not ask
questions.
