# R1j - `glamx::rot2`: `lerp` as upstream, `is_normalized`

Branch `fix/rot2-lerp`. Read `docs/briefs/R1-common.md`, `docs/briefs/COMMON.md`,
`docs/briefs/P1b-rot2.md`, the "Mandatory deep check: `Rot2::lerp`" section of
`docs/audits/R1-deviations.md`, `packages/glamx/src/rot2.cairo`, and glamx 0.3.1 `src/rot2.rs`
(`git clone --depth 1 --branch v0.3.1 https://github.com/dimforge/glamx /tmp/glamx`; check the
tag name).

Files you may edit: `packages/glamx/src/rot2.cairo`, `packages/glamx/tests/test_rot2.cairo`,
`packages/glamx/tests/golden_rot2.cairo` (generated), `tools/refgen/specs/rot2.toml`,
`tools/refgen/src/oracles/rot2.rs`, `packages/benches/tests/bench_rot2.cairo`,
`packages/benches/src/alt/rot2.cairo`, `gas/rot2.snap` and any caller snapshot that changes
(`pose2`), `docs/API_PARITY.md` and the READMEs' generated gas tables when stale,
`gas/bytecode.size` if `scripts/bytecode_size.py check` reports a change.

This is a **numeric and API change**, decided by the orchestrator and recorded in
`docs/DESIGN.md` section 3 ("interpolation" row): a same-name rotation `lerp` keeps the upstream
semantics.

1. `Rot2::lerp(self, rhs, s)`: the component-wise linear blend of upstream (`rot2.rs`, `lerp`),
   **not normalised**, with the same `a + (b - a) * s` fused form as `Fixed::lerp` (exact at both
   ends, one rescale per component; document that upstream computes `a*(1-s) + b*s`). The
   midpoint of antipodes is the zero rotation `(0, 0)` as upstream: no panic, no identity
   fallback. Golden vectors from the glamx f64 oracle (exact where representable, otherwise 1 ULP
   with the derivation), including `s = 0`, `s = 1`, the midpoint of `(1,0)` / `(0,1)`, and
   antipodes. Doc: `#### Deviations` now `None.` for the semantics (rounding rule only); the
   module-level docs and `Pose2` docs no longer describe `lerp` as normalised.
2. `Rot2::nlerp` is **not** added (glamx 0.3.1 has none; "an unported function does not exist").
   If a normalised blend is wanted, callers spell `lerp(..).normalize()`; say so in the `lerp` doc.
3. `Rot2::is_normalized(self) -> bool`: upstream `(re^2 + im^2 - 1).abs() < 2e-4`; here through
   `fixed::wide::is_unit2(re, im, 1024)` (the same 1 024 raw ULP band as `Vec2` / `Quat`, i.e.
   `2^-22`, inclusive; document the difference from upstream's strict `2e-4` under `#### Deviations`
   exactly as `Vec2::is_normalized` does). Total: no panic on long inputs. Tests at the
   boundaries `1 +- 1024` / `1 +- 1025` raw ULP and at `Fixed::MAX` / `MIN` components. Check the
   type-level list of omitted APIs in `rot2.cairo` and remove `is_normalized` from it if it is
   listed; make sure every remaining omission there is real.
4. Benches: `lerp` (mid-range `s`, plus `s = 0` and `s = 1` if the code branches),
   `is_normalized` true / false; snapshot regenerated; `pose2` snapshot regenerated if it changed.
5. `REPORT.md`: list under "Numeric changes" the old and new results of `lerp` on the golden
   inputs, for the changelog.

Commit scope `fix(rot2)`. Pull request title `fix(rot2): lerp as upstream (not normalised),
is_normalized`. Model trailer: the model you are.
