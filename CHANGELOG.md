# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning policy:
`docs/DESIGN.md` section 6 (any change of a numeric result is a MINOR bump).

## [Unreleased]

### Added
- Research reports and benchmark prototype (`docs/research/`), design (`docs/DESIGN.md`) and
  execution plan (`docs/PLAN.md`).
- Workspace with the `fixed`, `glam` and `benches` packages; seed of the `Fixed` Q32.32 scalar.
- Gas/step benchmark harness (`scripts/bench.py`, `gas/*.snap`) and CI.
- `glam`: `BVec2`, `BVec3`, `BVec4` (#2).
- `tools/refgen`: golden-vector generator using glam-rs 0.33.8 (f64) as the oracle, CI `golden` job (#3).
- `fixed`: tier A scalar (`FixedTrait`, operators, rounding, `sqrt`, `FloatExt` helpers) and `wide` fused kernels with typed accumulators (#6).
- `fixed`: exact-integer golden vectors for tier A and `wide` (117 generated tests, tolerance 0) (#7).
- `glam`: `IVec2/3/4`, `UVec2/3/4` generated from one template (`tools/codegen/intvec.py`) (#5).
