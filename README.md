# glam.cairo

A port of [glam-rs](https://github.com/bitshifter/glam-rs) to [Cairo](https://www.cairo-lang.org):
deterministic, gas-efficient vector, matrix and quaternion math on a signed Q32.32 fixed-point
scalar. It is the base layer of a provable game physics stack, together with the Cairo ports of
nalgebra and rapier.

| package | content |
|---|---|
| [`fixed`](packages/fixed) | `Fixed { raw: i64 }` Q32.32 scalar, fused kernels, loop-free trigonometry |
| [`glam`](packages/glam) | `Vec2/3/4`, `Mat2/3/4`, `Quat`, `Affine2/3`, `BVec*`, `IVec*`, `UVec*` |

Status: work in progress, see [`docs/PORTING_STATUS.md`](docs/PORTING_STATUS.md).

## Why another math library

Every design choice is measured in Cairo steps and Sierra gas
([research synthesis](docs/research/00-synthesis.md)). Compared with a cubit-style sign-magnitude
scalar, the prototype of this design (`docs/research/bench`) measures 7.1x cheaper on `Mat4 * Mat4`, 5.8x on
`Quat * Quat` and 7x on `sin`, at 4.7e-10 precision.

## Development

```bash
asdf install          # scarb + starknet-foundry from .tool-versions
scripts/check.sh      # fmt, lint, build, tests, gas snapshot check, docs
scripts/bench.py run  # net gas / steps / builtins per benchmark
```

Every function ships with a benchmark; `gas/*.snap` is committed and CI fails on any unreviewed
gas change. Contributor and agent rules: [`AGENTS.md`](AGENTS.md). Design:
[`docs/DESIGN.md`](docs/DESIGN.md). Plan: [`docs/PLAN.md`](docs/PLAN.md).

## License

MIT
