# R1i - bytecode size of a consumer contract

Branch `chore/bytecode-size`. Measurement and tooling task. Read `docs/briefs/R1-common.md`,
`docs/briefs/COMMON.md`, `docs/DESIGN.md` (rule 4.3 on `#[inline(always)]`, section 2.2 on the
polynomial segments of the transcendentals) and the "bytecode growth" risk of `docs/PLAN.md`.

Files you may create or edit: a new unpublished package `packages/consumer/**` (`publish =
false` like `packages/benches`; the workspace globs `packages/*`, so the root `Scarb.toml` needs
no change: if you believe it does, escalate), `scripts/bytecode_size.py`,
`docs/audits/R1-bytecode-size.md`, `gas/bytecode.snap` (or another name that `scripts/bench.py`
does not pick up), `scripts/check.sh` and `.github/workflows/ci.yml` (one added check each, only
if it costs < 1 minute; otherwise document the manual command). No library code changes.

Question to answer: the library trades bytecode for gas (`#[inline(always)]` on every scalar
operator and kernel helper, unrolled matrices, loop-free transcendental polynomials with constant
tables). It has never been linked into a Starknet contract. How large is the compiled class of a
realistic consumer, how far is it from the network limits, and which library items are the
heaviest per call site?

1. `packages/consumer`: a Starknet contract package (`starknet` dependency pinned to the
   toolchain of `.tool-versions`, `[[target.starknet-contract]]` with `sierra = true`,
   `casm = true`), with several contracts of increasing weight, inputs coming from calldata or
   storage so that nothing is constant-folded:
   - `scalar`: one entry point per `fixed` family (`mul`, `div`, `sqrt`, `sin_cos`, `atan2`,
     `exp`, `ln`, `powf`);
   - `particles2d`: a 2D integrator step on `Vec2` / `Rot2` / `Pose2` (semi-implicit Euler, a
     circle-circle contact, storage of `Fixed` fields);
   - `rigid3d`: what one rapier-style 3D step touches: `Vec3` dot / cross / normalize, `Quat`
     mul / normalize / `mul_vec3` / integration from an angular velocity, `Mat3` mul / transpose /
     inverse, `Pose3` mul / `inv_mul` / `transform_point`, `SdpMatrix3` world inertia;
   - `kitchen_sink`: everything above plus `Mat4` inverse, `slerp`, Euler conversions, a camera
     projection and `SymmetricEigen3`.
   Keep the contracts small and readable: they are measurement fixtures, not a product.
2. `scripts/bytecode_size.py` (dependency-free Python 3): builds the package in the release
   profile, reads `target/release/*.contract_class.json` and `*.compiled_contract_class.json` and
   reports per contract: Sierra program length (felts), CASM bytecode length (felts), JSON file
   sizes in bytes, and the ratio to the current Starknet limits. Find the authoritative current
   limits (maximum contract bytecode size in felts, maximum contract class size in bytes; Starknet
   documentation "chain info / limits", version notes) with the WebSearch/WebFetch tools if you
   have them, cite the URL and the Starknet version; if you cannot verify them, say so, report
   absolute numbers, and leave the limits as clearly marked parameters of the script. Modes:
   default prints the table, `snapshot` writes the snapshot file, `check` fails on a difference.
3. Attribution: marginal cost per call site. For the ~25 heaviest-looking items (`Fixed` `mul`,
   `div`, `sqrt`, `sin_cos`, `atan2`, `exp`, `powf`, `dot3`, `normalize3`, `Vec3::cross`,
   `Mat3::mul_mat3`, `Mat3::inverse`, `Mat4::mul_mat4`, `Mat4::inverse`, `Quat::mul_quat`,
   `Quat::mul_vec3`, `Quat::slerp`, `Pose3::mul`, `Pose3::inv_mul`, `SdpMatrix3` world inertia,
   `SymmetricEigen3::new`...), measure the CASM felts added by the first call site and by a
   second call site in another entry point (inlined bodies are paid per call site, non-inlined
   ones once): a generated probe contract per item, or entry points toggled by the script, is
   fine. Table: item / felts for the 1st use / felts for each further use / `inline(always)` today
   (yes/no).
4. Report `docs/audits/R1-bytecode-size.md`: the numbers, the distance to the limits, how many
   call sites of the heaviest inlined items fit in one class, and concrete recommendations
   (which items should lose `#[inline(always)]` or gain a non-inlined twin, with the gas cost of
   that choice taken from `gas/*.snap` or measured; whether the compiler's
   `inlining-strategy` setting in the consumer's `Scarb.toml` changes the picture: measure
   `default` vs `avoid` vs a numeric threshold if supported by scarb 2.19.4). Recommendations
   only: do not change the library.

Gate: `flock /tmp/glam-cairo-gate.lock scripts/check.sh` green (the new package must pass fmt,
lint and build with the workspace; it needs no tests beyond what makes the gate pass). Commit
`chore(consumer): bytecode size fixtures and report`, pull request with the headline table in the
body, wait for CI, do not merge. Model trailer: the model you are.
