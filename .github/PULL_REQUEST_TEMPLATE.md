## Summary

<!-- What does this PR change? Reference the Rust reference (`f32` / `f64` / glam `FloatExt`) where relevant. -->

## Type

- [ ] feat - [ ] perf - [ ] fix - [ ] test - [ ] docs - [ ] chore

## Gas delta

<!-- Paste the relevant `gas/*.snap` diff as a table. Justify any increase. -->

| bench | before | after | delta |
|---|---|---|---|

## Checklist

- [ ] `scripts/check.sh` is green locally
- [ ] Tests: golden vectors, edge cases, properties, `should_panic` with exact messages
- [ ] A bench with non-constant inputs exists for each hot operation
- [ ] Deviations documented (`#### Deviations` + `docs/DESIGN.md`)
- [ ] `CHANGELOG.md` updated
- [ ] Breaking change (API or numeric results, affects every consuming repository): yes / no
