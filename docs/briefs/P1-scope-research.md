# P1 (research) - scope of the physics extensions

Branch `docs/p1-scope`. Read-only research task; the only deliverable is one markdown report,
`docs/research/06-glamx-scope.md`, delivered as a pull request (this brief explicitly allows that
one file under `docs/`; nothing else may change). Do not write Cairo code.

## Question

`docs/research/01-glam-rs-analysis.md` found, from crates.io metadata only, that rapier3d 0.35 and
parry3d 0.31 depend on Dimforge's `glamx` (glam 0.33 + `Rot2`, `Pose2`, `Pose3`, symmetric eigen
decomposition, SVD...) instead of using nalgebra directly. Task P1 of `docs/PLAN.md` would port
those extensions on top of `glam.cairo`. Confirm or refute this from the actual sources, and scope
the work.

## Method

Clone (shallow) into `/tmp`: `https://github.com/dimforge/glamx` (if it exists under that name;
otherwise find the crate's repository from `https://crates.io/crates/glamx`), `dimforge/parry`,
`dimforge/rapier`. Check the versions actually depending on `glamx`. Then answer, with file paths
and line references:

1. What does `glamx` contain exactly? Full inventory of types, traits and functions (`Rot2`,
   `Rot3`?, `Pose2`, `Pose3`, `MatExt`, eigen/SVD, `Vec*Ext`...), with method counts, and which
   glam types they wrap.
2. Which of those items do parry and rapier actually use, and how often (rough `grep` counts per
   item, split 2D / 3D)? Identify the hot subset for a rigid-body step: pose composition,
   `inv_mul`, rotating vectors, inertia tensor transforms (`R * I * R^T`), symmetric 3x3
   eigen-decomposition (where is it used?), cross-product matrices, angular velocity integration.
3. What do parry/rapier still take from nalgebra directly (dynamic matrices for multibody,
   `DVector`, sparse solvers...)? List the features/modules concerned.
4. Which glam-rs types do they use that glam.cairo does not port (`Vec3A`, `Mat3A`, `Affine3A`,
   `DVec*` under an f64 feature...), and are they covered by our type collapse (DESIGN section 1)?
5. Recommendation: the list of extension items worth porting first for a provable 2D and 3D rigid
   body step, a proposed module layout (`packages/glam/src/ext/*` or a new `glamx` package in this
   workspace), what belongs to `nalgebra.cairo` instead, open design questions (e.g. `Rot2` as
   `(cos, sin)` pair, `Pose3` = `Quat` + `Vec3` vs the `Affine3RigidTrait` of task A3), and an
   effort estimate in porter tasks.

## Done

One commit `docs(research): scope of the glamx physics extensions (P1)` ending with the line
`Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`, `git push -u origin docs/p1-scope`,
`gh pr create --base main` (body ending with
`🤖 Generated with [Claude Code](https://claude.com/claude-code)`), wait for CI green in the
foreground (`gh pr checks <n> --watch --interval 20`). Do not merge. State clearly in the report
what was verified in source versus inferred. Work autonomously; do not ask questions.
