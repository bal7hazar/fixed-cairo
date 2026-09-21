# P1e - `glamx::eigen3`: symmetric 3x3 eigen-decomposition

Branch `feat/glamx-eigen3`. Read `docs/briefs/P1-glamx-common.md` and `docs/briefs/COMMON.md`.
Module `eigen3`. This is the numerically hardest item of the package: read report 06 sections 2.2,
3.3 and 6.5.7 first.

Consumers (setup time only, never in the simulation step): principal inertia and frame of compound
/ mesh mass properties, OBB fitting, convex-hull seeding in parry. So **correctness and
robustness come before gas**; still report gas and respect the hard Cairo rules where they apply.

API, mirroring glamx 0.3.1 `eigen3.rs` and the `Mat3` part of `matrix_ext.rs`:
`SymmetricEigen3 { eigenvalues: Vec3, eigenvectors: Mat3 }` (columns are the unit eigenvectors),
`SymmetricEigen3Trait::new(m: Mat3)` (the matrix is assumed symmetric: document which triangle is
read), `from_sdp(m: SdpMatrix3)` (natural input here, see `packages/glamx/src/sdp.cairo`),
`reverse`, `recompose` if upstream has it, and an extension trait on `Mat3` with
`symmetric_eigen()`, `symmetric_eigenvalues()`, `swap_cols`. Skip `SymmetricEigen2` and `Svd*`
(no consumer).

Algorithm, the core of the task. Upstream uses the closed form (trigonometric solution of the
characteristic cubic: `acos` + `cos`, then eigenvectors by cross products); rapier replaced it by a
Jacobi iteration for degenerate matrices (`soft_element_linalg.rs`), a warning sign for the closed
form. In Q32.32 the closed form loses accuracy when eigenvalues are close (the `acos` argument
saturates, cross products of nearly parallel rows vanish). Evaluate at least:
(a) the closed form with careful scaling (normalise the matrix by its largest entry / trace
    first, handle multiplicity 2 and 3 explicitly with thresholds derived in ULPs), and
(b) cyclic Jacobi rotations with a FIXED number of sweeps (a bounded loop with a compile-time
    count is acceptable here: this is iterative numerics at setup time, not fixed-size kernel
    math; alternatively unroll), each rotation computed without trigonometry
    (`t = sgn(tau) / (|tau| + sqrt(1 + tau^2))`, `c = 1 / sqrt(1 + t^2)`, `s = t c`).
Pick by measured accuracy on a Python mirror (bit-exact, committed as `scripts/gen_eigen3.py` or
inside the refgen oracle tests) over: random SPD matrices of condition number up to 1e6,
diagonal matrices, matrices with two equal eigenvalues, the identity scaled (three equal),
rank-deficient PSD matrices, inertia tensors of thin rods / flat plates. Ship the more robust one,
keep the other in `benches::alt::eigen3` with its bench, and document the accuracy of both:
`|A v - lambda v|` in ULPs relative to `|A|`, orthonormality `|V^T V - I|`, and
`|V diag(lambda) V^T - A|`. Eigenvalue ordering as upstream (document it); eigenvector sign is
arbitrary: tests and golden comparisons must be sign- and (for repeated eigenvalues)
subspace-invariant: compare `A v = lambda v` and the reconstruction, never raw components.

Golden vectors: the glamx f64 `DSymmetricEigen3` (or equivalent) is the oracle for eigenvalues
(tolerance derived from the measured accuracy); eigenvectors are checked through the residual
properties in `test_eigen3.cairo`, not component-wise. Overflow policy: inputs are scaled so that
the routine does not panic for any symmetric matrix whose entries fit comfortably in Q32.32
(document the supported range, e.g. |entries| < 2^20).
