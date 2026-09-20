## Summary

<!-- What does this PR port / change? Reference the glam-rs source file(s). -->

## Type

- [ ] feat (new port) - [ ] perf - [ ] fix - [ ] test - [ ] docs - [ ] chore

## Gas delta

<!-- Paste the relevant `gas_snapshot.json` diff as a table. Justify any increase. -->

| bench | before | after | delta |
|---|---|---|---|

## Checklist

- [ ] `scripts/check.sh` is green locally
- [ ] Tests: golden vectors, edge cases, properties, `should_panic` with exact messages
- [ ] A bench with non-constant inputs exists for each hot operation
- [ ] Deviations from glam-rs documented (`#### Deviations` + `docs/DESIGN.md`)
- [ ] `docs/PORTING_STATUS.md` and `CHANGELOG.md` updated
- [ ] Breaking change (API or numeric results): yes / no
