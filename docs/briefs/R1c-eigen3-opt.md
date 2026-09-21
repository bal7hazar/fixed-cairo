# R1c - optimizer pass on `glamx::eigen3`

Branch `perf/eigen3`. Read `docs/briefs/R1-common.md`, `docs/briefs/COMMON.md`, then
`docs/briefs/P1e-eigen3.md` (the original brief), the module documentation of
`packages/glamx/src/eigen3.cairo`, `scripts/gen_eigen3.py` (bit-exact Python mirror and accuracy
study) and the body of pull request #29 (`gh pr view 29`).

Files you may edit: `packages/glamx/src/eigen3.cairo`, `packages/glamx/tests/test_eigen3.cairo`,
`packages/glamx/tests/golden_eigen3.cairo` (generated), `tools/refgen/specs/eigen3.toml`,
`tools/refgen/src/oracles/eigen3.rs`, `scripts/gen_eigen3.py`,
`packages/benches/tests/bench_eigen3.cairo`, `packages/benches/src/alt/eigen3.cairo`,
`gas/eigen3.snap`, `packages/glamx/README.md` (generated gas table only).

Baseline (`gas/eigen3.snap`): `new_generic` 586 320 gas / 4 629 steps, `eigenvalues_generic`
585 420 / 4 620, `new_two_equal` 227 740, `new_rod` 227 630, `new_diagonal` 106 420; the closed
form kept in `benches::alt` costs 262 780 (`new`) and 151 010 (`eigenvalues`) but lost on
robustness. `SymmetricEigen3` is setup-time code, so robustness and accuracy still come first:
the accuracy table of pull request #29 (eigenvalue error, `|A v - lambda v|`, `|V^T V - I|`,
`|V diag V^T - A|`, per corpus of `scripts/gen_eigen3.py`) is the contract. Re-run the study for
every candidate; a candidate that degrades any line of that table is rejected unless the
degradation is <= 1 ULP and the gas win is large (say so explicitly).

Candidates, to measure one by one (Python mirror first, then Cairo, then the bench):
1. **Values-only path** for `SymmetricEigen3Trait::eigenvalues` / `Mat3ExtTrait::
   symmetric_eigenvalues`: today they run the full decomposition and drop the vectors. Rotate the
   matrix only (no `v1/v2/v3` accumulation, no Gram-Schmidt, no Rayleigh refinement) and read the
   diagonal, or any cheaper scheme of equal accuracy (the closed form is known to fail on close
   eigenvalues; a hybrid that falls back is acceptable only if the switch threshold is derived and
   tested). The two entry points may then return eigenvalues that differ by a few ULP from
   `new(m).eigenvalues`: allowed, document it under `#### Deviations` with the measured bound.
2. **Polish of `v3`**: `v3 = v1.cross(v2).normalize()` with `v1`, `v2` already orthonormal to
   ~1 ULP: the final `normalize` (a square root and a shared division) may be redundant. Measure
   the orthonormality with and without.
3. **Cost of one rotation** (~40k gas each, up to 12): fewer divisions / square roots per
   rotation (`t`, `c`, `s` from one `Norm` / one `Recip`?), skip a rotation whose off-diagonal
   entry is already zero, update only the entries that change, early exit tested per rotation
   instead of per sweep.
4. **Diagonal / already-diagonal input** (`new_diagonal` 106k for what is a sort): find where the
   cost goes (scaling, polish, Rayleigh on exact axes) and short-circuit when it is bit-exact.
5. `SWEEPS = 6` with 4 measured as the maximum: keep the margin unless you can prove the bound.

Every shipped change keeps the Python mirror bit-exact with the Cairo code (`python3
scripts/gen_eigen3.py emit --check` is part of the gate) and keeps the tests sign- and
subspace-invariant. Commit scope `perf(eigen3)`. Pull request title
`perf(eigen3): <what won>`, body with the before/after gas table and the accuracy table
before/after. Model trailer: the model you are.
