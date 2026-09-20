# refgen - golden vectors, glam-rs as the oracle

`refgen` generates `packages/<pkg>/tests/golden_<module>.cairo`: for every ported function, a set
of inputs and the result glam-rs **0.33.8** (f64 `D*` types, `scalar-math`, `libm`) gives for
them, compared in Cairo within a tolerance budgeted in raw ULPs (`2^-32`).

It is a standalone Cargo workspace (pinned `Cargo.lock`), not part of the scarb workspace.

```sh
cargo run --manifest-path tools/refgen/Cargo.toml -- gen [module...]    # write the golden files
cargo run --manifest-path tools/refgen/Cargo.toml -- check [module...]  # exit 1 if a file is stale
cargo run --manifest-path tools/refgen/Cargo.toml -- list               # specs, oracles, status
```

`check` runs in CI (job `golden`) and in `scripts/check.sh` when `cargo` is installed. Options
(before the command): `--all` previews with every `enabled = false` ignored, `--root <dir>` and
`--specs <dir>` point to another checkout / spec directory (used to test the generator itself).

## How it works

1. Inputs are drawn as **raw Q32.32 integers** from an integer-only PRNG (xoshiro256**) seeded by
   `"<module>::<function>"`: no float, no platform dependence. Hand-picked `edges` come first.
2. Each raw input converts to `f64` **exactly** (`|raw| <= 2^53`, enforced), the oracle closure
   runs glam-rs on it, and the result is quantized to the nearest raw value.
3. A case is **skipped and redrawn** when the oracle result is not representable (overflow, NaN,
   infinity: a panic path on the Cairo side), when the oracle calls `skip(..)` / returns `None`
   (precondition), or when an f64 result is `>= max_abs` (default `2^20`: above it a double no
   longer resolves half a raw ULP). Panic paths are tested explicitly with `[[function.panics]]`.
4. The Cairo file is emitted already formatted (`scarb fmt --check` passes): one
   `#[cairofmt::skip]` `const [i64; N]` table and one `#[test]` looping over it per function,
   one `#[should_panic]` test per panic case, and the few `next_*` / `check_*` helpers the file
   needs (the golden files cannot share a module: `tests/lib.cairo` is not theirs to edit).
   A failure reads `vec3::dot #7: got 123, expected 125 (tol 1)`.

Output is deterministic: same spec + same oracles = byte-identical file on every host.

## Adding the golden vectors of a module (porter workflow)

You only ever touch two files of your own, never a shared one:

| file | content |
|---|---|
| `tools/refgen/specs/<module>.toml` | what to test: call expression, types, domains, tolerance |
| `tools/refgen/src/oracles/<module>.rs` | how glam-rs computes it: one closure per function |

Both are auto-discovered (`build.rs` scans `src/oracles/`, the CLI scans `specs/`). The output
file `packages/<package>/tests/golden_<module>.cairo` already exists as a stub and is already
declared in `tests/lib.cairo`. `specs/vec2.toml`, `specs/vec3.toml` (disabled worked examples)
and `specs/fixed.toml` are the references to copy from.

1. Oracle, `src/oracles/<module>.rs`:

   ```rust
   use crate::prelude::*;

   pub fn register(r: &mut Registry) {
       r.add("dot", |a| a[0].dvec3().dot(a[1].dvec3()));          // -> Fixed
       r.add("cross", |a| a[0].dvec3().cross(a[1].dvec3()));      // -> Vec3
       r.add("cmplt", |a| a[0].dvec3().cmplt(a[1].dvec3()));      // -> BVec3
       r.add("to_axis_angle", |a| a[0].dquat().to_axis_angle());  // -> (Vec3, Fixed)
       // Option: `None` skips the case; spec: call = "{0}.try_normalize().unwrap()", ret = "Vec3".
       r.add("try_normalize", |a| a[0].dvec3().try_normalize());
   }
   ```

   Arguments: `a[i].f()` (`Fixed` as f64), `.raw()`, `.i32()`, `.u32()`, `.i64()`, `.bool()`,
   `.dvec2/3/4()`, `.dquat()`, `.dmat2/3/4()`, `.daffine2/3()`, `.bvec2/3/4()`, `.ivec2/3/4()`,
   `.uvec2/3/4()`, `.elems()` (tuple). Results: anything `Into<Out>`: `f64`, the glam `D*` / `BVec*`
   / `IVec*` / `UVec*` types, `bool`, `i32`, `u32`, `i64`, tuples up to 4, `Option<_>`
   (`None` skips), `skip("reason")`, and `Out::raw(i64)` / `Out::raw_checked(Option<i64>)` /
   `Out::raw_wide(i128)` for **integer oracles** that compute the exact raw result (no `max_abs`
   guard, usable on the full `i64` range: see `oracles/fixed.rs`).

2. Spec, `specs/<module>.toml`:

   ```toml
   module = "vec3"                        # = file name, -> golden_vec3.cairo
   package = "glam"                       # "fixed" | "glam"
   # enabled = false                      # master switch: emits the bare stub
   imports = ["glam::vec3::Vec3Trait"]    # traits / consts used by `call`; types are automatic

   [[function]]
   name = "dot"                           # test golden_vec3_dot, oracle "dot" (or `oracle = ".."`)
   # enabled = false                      # per-function switch
   call = "{0}.dot({1})"                  # Cairo expression, {i} = i-th argument
   args = [{ type = "Vec3", min = -500.0, max = 500.0 }, "Vec3"]
   ret = "Fixed"
   cases = 32                             # random cases, on top of the edges
   tolerance = 1                          # |actual.raw - expected.raw| <= tolerance
   justification = "fused kernel: one floor rescale vs round to nearest."   # mandatory
   # max_abs = 1048576.0                  # f64 resolution guard (default 2^20)
   edges = [                              # hand-picked cases: one value per argument
       [[1, 0, 0], [0, 1, 0]],            # numbers are values (1 = 1.0) ...
       [["raw:1", "raw:-1", 0.5], [1, 2, 3]],   # ... "raw:<int|0xhex>" is a raw leaf
   ]

   [[function.panics]]                    # #[should_panic(expected: '...')] tests
   name = "overflow"
   args = [[2000000, 0, 0], [2000000, 0, 0]]
   expected = "Fixed: overflow"
   ```

   Types: `Fixed`, `i64`, `i32`, `u32`, `bool`, `Vec2/3/4`, `Quat`, `Mat2/3/4`, `Affine2/3`,
   `BVec2/3/4`, `IVec2/3/4`, `UVec2/3/4` and flat tuples `"(Vec3, Fixed)"`. Composite values are
   flattened in glam's column-major order (`to_cols_array`); nested arrays in `edges` are allowed.

   An argument is a type name (default domain) or a table:

   | key | meaning |
   |---|---|
   | `domain` | preset for the `Fixed` leaves: `position` (default, \|x\| <= 1000), `unit` [-1, 1], `t` [0, 1], `positive` (0, 1000], `small` \|x\| <= 8, `angle` \|x\| <= 2 pi, `scale` [0.01, 100], `wide` \|x\| <= 2^20, `full` (whole i64 range, **integer oracles only**) |
   | `min`, `max` | bounds (value units) overriding the preset; integer bounds for `i32` / `u32` / `i64` / `IVec*` / `UVec*` (defaults [-1000, 1000] / [0, 1000]) |
   | `nonzero`, `min_abs` | per-leaf exclusions (divisors) |
   | `constraint` | whole value: `normalized` (vectors, quaternions), `nonzero` + `min_len`, `invertible` + `min_det`, `rotation` (matrices / affines, translation from the leaf domain), `trs` + `scale_min` / `scale_max` |
   | `custom` | name of a generator registered in the oracle file: `r.generator("name", \|rng\| value_of(...))` |
   | `elems` | per-element argument specs of a tuple argument |

   Half of the draws are uniform in the domain, the others are right-shifted (small magnitudes),
   integers and half-integers. Relations between arguments (`clamp`: `min <= max`) are handled by
   skipping in the oracle.

   The default Cairo layouts are the glam-rs ones (`Vec3 { x, y, z }` at `glam::vec3::Vec3`,
   `Mat3 { x_axis, y_axis, z_axis }`, `Affine3 { matrix3, translation }`, ...). A module that
   departs from them overrides the path and/or the field names (same order):

   ```toml
   [types.Mat3]
   path = "glam::mat3::Mat3"
   fields = ["c0", "c1", "c2"]
   ```

3. Generate, test, commit the spec, the oracle **and** the generated file:

   ```sh
   cargo run --manifest-path tools/refgen/Cargo.toml -- gen <module>
   snforge test -p <package> golden_<module>
   scripts/check.sh
   ```

Enabling a pre-written entry (`fixed` tier A, `vec2`, `vec3`) = deleting its `enabled = false`
line (or the module-level one), aligning `call` with the final Cairo API, and step 3.

## Tolerances

`tolerance` is in raw ULPs and `justification` is mandatory, including for 0. Never loosen a
tolerance to make a test pass: derive the bound (see `docs/DESIGN.md` section 5).

- exact operations (add, sub, neg, min, max, abs, floor, comparisons, constructors): **0**;
- one rescale or one division (`mul`, `div`, `sqrt`, a fused `dot` / `cross` / `length`): **1**.
  The Cairo side floors or truncates the real result, the oracle rounds it to nearest;
- chained operations: add the ULPs of every rescale, scaled by the magnitude of the factors that
  multiply them afterwards (`normalize`: 2 for `len >= 1`; shorter vectors amplify by `1 / len`
  and deserve their own entry with their own domain);
- transcendental functions: the documented max error of `fixed::trig` in ULPs, plus 1;
- conditioned results (`inverse`, `slerp` near antipodal, ...): restrict the domain
  (`invertible` + `min_det`, `trs`) until the bound is provable, and state it.

An f64 oracle is itself only accurate to `|result| * 2^-53`: below `2^20` that is under half a
raw ULP (already counted in the "1" above), beyond it the case is skipped by `max_abs`. Keep the
inputs of quadratic functions within `|x| <= 500`, or write an integer oracle.

## Layout

| path | role |
|---|---|
| `specs/<module>.toml` | per-module spec (porter-owned) |
| `src/oracles/<module>.rs` | per-module oracles (porter-owned), listed by `build.rs` |
| `src/value.rs`, `src/types.rs` | values, glam conversions, quantization, Cairo layouts |
| `src/domain.rs`, `src/rng.rs` | input domains, constraints, PRNG |
| `src/cases.rs`, `src/emit.rs` | case generation and skipping, Cairo emission |

Changing anything outside `specs/` and `src/oracles/` (PRNG, sampling, emission) changes every
golden file: it is an orchestrator-level change, regenerate everything in the same pull request.
