# 00 - Synthesis: benchmark of the Cairo ecosystem for a glam-rs port

Date: 2026-09-20. Toolchain used for every measurement: scarb / cairo 2.19.4, snforge 0.61.0.
This file summarizes five reports; read them for the evidence.

| report | subject |
|---|---|
| [01](01-glam-rs-analysis.md) | glam-rs 0.33.8: architecture, full API inventory, scalar primitives, dependency graph, tests |
| [02](02-architecture-best-practices.md) | alexandria + starknet-agentic: workspace, CI, conventions, agent-driven workflow |
| [03](03-origami-analysis.md) | origami: `algebra` crate review, step-saving idioms of the `map` crate |
| [04](04-fixed-point-and-linalg-analysis.md) | cubit + orion: fixed-point and linear algebra code review, scalar design space |
| [05](05-gas-benchmarks.md) | 496 empirical micro-benchmarks (`bench/`): primitives, scalar shoot-out, composites, trig |

## 1. Library scorecard

| library | analysed version | what it is a reference for | reuse | verdict |
|---|---|---|---|---|
| **alexandria** | Cairo 2.16.0, snforge 0.56 | workspace layout, per-package manifests, operator traits, doc template, `WideMul` + single division, `NonZero` const divisors, `const [T; N]` tables | conventions only | Best architecture reference. Weak spots to avoid: no lint in CI, gas script that never fails, invalid committed gas JSON, sign-magnitude `i257`, a `fast_cos` that is wrong for negative inputs. |
| **origami** | scarb 2.12.2 | step-saving idioms (`map` crate): bit-packing in a felt, `/ 2^i % 2` instead of bitwise, const power tables, `match` tables, hand-unrolled loops | idioms only | `algebra` is a sketch: private modules (cannot be consumed), `Span`-backed matrices that allocate per op, Laplace-expansion inverse (3x3 on i128 = 1.23M gas), depends on a cubit fork. No gas tracking at all. |
| **starknet-agentic** | 2026-09-14 | agent-driven repo hygiene: single canonical `AGENTS.md`, roles with owns / does-not-own, definition of done, escalation format, "rationalizations to reject", SHA-pinned actions, `all-checks` job, optimization rules (`DivRem`, `while i != n`, bounded ints) | process | Adopted almost entirely (see `AGENTS.md`). |
| **cubit** | 1.4.0, Cairo >= 2.7 | fixed-point algorithms: `u128_sqrt(mag * ONE)`, `exp2`/`log2` decomposition, atan range reduction, test helpers | ideas + test vectors (MIT) | Representation is the problem: `{mag, sign}` = 2 felts, negative zero, sign decision trees on every add/compare; `f128` mul/div go through `u256`; Taylor-recursion `sin` = 128 670 gas; LUTs written as if-trees; no `atan2`; gas never measured. |
| **orion** | Cairo 2.5.3, unmaintained | - | nothing | Wrappers/copies of cubit plus `Span`-based tensors with per-element index arrays; `linalg` has no determinant / inverse / cross / quaternion. A `Span`+loop `Mat3*Mat3` proxy measured 9.2x our unrolled struct version. NaN encoded as negative zero. |

## 2. Measured facts that drive the design (report 05)

| class | l2_gas |
|---|---:|
| felt252 add / mul | 100 |
| u8..u64 add / mul (`WideMul` 64x64->128 = 100) | 570 |
| i64 add / lt | 840 / 770 |
| div, rem, shift by constant | 1 010 - 1 210 |
| and / or / xor (+1 bitwise builtin cell) | 1 083 |
| const-array lookup / `match` table / 8-entry if-chain | 1 270 / 2 370 / 3 200 |
| loop iteration overhead | 1 200 - 1 400 |
| non-inlined call to a panicking function | ~2 000 |
| u128 mul / i128 mul / u256 mul | 3 230 / 7 550 / 14 180 |
| variable shift through `pow` | 14 940 |

**The owner's heuristic (math < bitwise < loops) is confirmed** and refined: div/mod costs the
same gas as a bitwise op but no builtin cell, so masks and shifts are always `DivRem` by a constant;
the real hidden costs are range checks, panicking call boundaries and crossing 64-bit operands.

Scalar shoot-out (Q32.32):

| op | cubit-style `{mag, sign}` | `Fixed { raw: i64 }` + bounded ints + fused kernels |
|---|---:|---:|
| add / lt | 4 050 / 3 110 | 840 / 770 |
| mul / div | 2 970 / 2 970 | 2 050 / 4 850 |
| Vec3 dot / length | 15 750 / 20 280 | 4 680 / 4 520 |
| Mat3 x Mat3 | 134 250 | 25 480 |
| Mat4 x Mat4 | 335 800 | 47 230 |
| Quat x Quat / rotate Vec3 | 87 780 / 115 910 | 15 230 / 23 710 |
| sin / sin_cos | 128 670 / 263 610 | 18 420 (4.7e-10) / 28 060 |
| atan2 / acos | 83 740 (atan) / 113 810 | 22 420 / 25 740 |

The win comes from **fusing** (sum raw Q64.64 products, rescale once per output), not from the
integer type alone: a plain i64 with one rescale per product is on par with inlined cubit.

## 3. Decisions

1. Scalar = `Fixed { raw: i64 }`, Q32.32, floor rounding, panics on overflow, own package
   `fixed` (shared with `nalgebra.cairo` / `rapier.cairo`). Details: `docs/DESIGN.md`.
2. All kernels written against the fused `fixed::wide` API; flat, unrolled, `Copy` structs.
3. Loop-free transcendentals: constant-divisor range reduction + Horner minimax polynomials,
   generated coefficients with a bit-exact Python mirror.
4. Concrete types, no generic scalar (E2143: `inline(always)` is rejected on impl-generic
   functions; glam-rs itself is monomorphic).
5. No dependency on cubit, orion, origami or alexandria. Ideas and test vectors only (all MIT).
6. Gas tracking: `X__base` / `X__op` bench pairs with black-boxed inputs, committed
   `gas/<module>.snap` (l2_gas + steps + builtins), exact-equality check in CI.
7. Virtual workspace (`fixed`, `glam`, unpublished `benches`), SHA-pinned CI with a single
   `all-checks` status, agent workflow of `AGENTS.md`.

## 4. Notable finding for the sibling projects

rapier3d 0.35 / parry3d 0.31 now depend on Dimforge's `glamx` (glam + `Rot2`, `Pose2`, `Pose3`,
symmetric eigen, SVD); parry has no direct nalgebra dependency any more. To be confirmed against
their sources, but the `nalgebra.cairo` effort can probably shrink to a `glamx`-like extension on
top of this repository plus dynamic-size matrices for multibody dynamics.
