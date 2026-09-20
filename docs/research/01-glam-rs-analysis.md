# glam-rs analysis for the Cairo port

> Research note 01 — source-level analysis of `glam-rs`, to drive the plan of a
> fixed-point Cairo port (`glam.cairo`) used as the foundation of a provable
> physics engine.

- **Analyzed version:** `glam` **0.33.8**
- **Commit:** `465b60040b40c0b06ae983d1655de67721710841` ("Prepare 0.33.8 release (#839)", 2026-09-20)
- **Upstream:** <https://github.com/bitshifter/glam-rs> (MIT OR Apache-2.0, MSRV 1.68.2)
- **Method:** everything below was read from the actual source tree (shallow
  clone), not from memory. Method counts come from `grep` on `pub fn` /
  `impl` lines of the generated scalar files. Section 6 (usage by physics
  engines) is partially based on crates.io metadata and prior knowledge and is
  flagged as such.

---

## 0. Executive summary

1. glam is **not generic**: every concrete type (`Vec3`, `DVec3`, `IVec3`, ...)
   is a separate, **generated** Rust file. 148 of the 203 files in `src/`
   (~225k lines) are produced from 18 Tera templates (~13k lines) driven by
   `codegen.json` (160 outputs). The real "source of truth" is therefore small:
   `vec.rs.tera`, `mat.rs.tera`, `quat.rs.tera`, `affine.rs.tera`,
   `vec_mask.rs.tera`, `swizzle_*.tera`, `camera_*.tera`, `float.rs.tera`,
   plus hand-written `euler.rs`, `float.rs`, `f32/math.rs`.
2. For Cairo only the **scalar** (`is_scalar = true`) code path is relevant.
   It is plain struct-of-fields arithmetic and ports almost line by line.
3. The **scalar math layer** glam needs is exactly 22 functions
   (`src/f32/math.rs`): `abs, acos_approx, atan2, cos, sin, sin_cos, tan, sqrt,
   copysign, signum, round, trunc, ceil, floor, exp, exp2, ln, log2, powf,
   mul_add, div_euclid, rem_euclid` — plus native `+ - * / %`, comparisons,
   `min/max/clamp`, `recip` (`1.0 / x`), and the `FloatExt` helpers (`lerp,
   inverse_lerp, smoothstep, remap, fract_gl, step, saturate, move_towards`).
   **No `asin`, no exact `acos`, no `atan`, no `sinh/cosh`.** `exp/ln/pow/log2/
   exp2` are only used by element-wise vector wrappers and never by any
   geometric algorithm, so they can be deferred.
4. Geometric core really only needs: **`sqrt`, `sin_cos`, `atan2`,
   `acos_approx` (a degree-7 polynomial × sqrt — trivially portable), `abs`,
   `signum`** (+ `tan` for 3 deprecated projection functions).
5. Proposed Cairo type set (one fixed-point scalar `Fixed`): `Vec2, Vec3, Vec4,
   Mat2, Mat3, Mat4, Quat, Affine2, Affine3, BVec2/3/4, EulerRot`, plus
   `IVec2/3/4` and `UVec2/3/4` (one signed and one unsigned width to start
   with), swizzles as a trait, camera as a late optional module. Drop `Vec3A`,
   `Mat3A`, `Affine3A`, `BVec3A`, `BVec4A`, all `D*` types, all SIMD backends,
   all serialization/interop features, NaN/Infinity constants and semantics.
6. There is a **dependency cycle** in glam (`Vec3 -> Quat -> Vec3/Vec4/Mat3`,
   `Mat3 -> Quat`, `Quat -> Mat3/Mat4/Affine3`, `Mat2 <-> Mat3`, ...). In Cairo
   (one crate, modules can reference each other freely) this is not a
   compile-time problem, but it matters for **parallel work planning**: see
   the layered plan in section 4, which cuts the cycle by moving a handful of
   "cross-type" methods into a late integration step.
7. **Important ecosystem finding:** current `rapier3d` (0.35.3) and `parry3d`
   (0.31.1) depend on **`glamx ^0.3`** (Dimforge's "glam extensions": `Rot2`,
   `Pose2`, `Pose3`, `MatExt`, symmetric eigen-decomposition, SVD 2x2/3x3),
   which wraps `glam ^0.33`. rapier/parry have migrated their public math from
   nalgebra to glam. The planned "nalgebra port" can likely be reduced to a
   port of **glamx** plus the few dynamically-sized pieces rapier still takes
   from nalgebra (multibody joints / `DMatrix`, `DVector`). This raises the
   priority and the payoff of the glam port.

---

## 1. Repository layout and architecture

### 1.1 Top level

| Path | Role |
|---|---|
| `Cargo.toml` | single crate `glam` 0.33.8; workspace members `tools/ci`, `tools/codegen` (git submodule -> `bitshifter/glam-codegen`, empty in a shallow clone), `tools/test_no_std` |
| `codegen.json` | declares, per template, the default properties and every output file with its property overrides (160 outputs) |
| `templates/*.tera` | 18 Tera templates, 13,264 lines — the real source of most of the library |
| `src/` | 203 `.rs` files, ~225k lines, 148 of them carry the header `// Generated from <x>.tera template. Edit the template, not the generated file.` |
| `tests/` | 25 integration test files (~23.8k lines) + `tests/support` macros |
| `benches/` | criterion + gungraun (iai-like) benches per type |
| `ARCHITECTURE.md` | design goals: SIMD by default, **no generics**, **no traits** (except swizzles), fast compile, std-like API |

### 1.2 `src/` module map

```
src/lib.rs            crate docs, feature gating, module wiring, re-exports
src/macros.rs         glam_assert!, const_assert!, const_assert_eq!
src/float.rs          trait FloatExt (hand-written)            -> impl in f32/float.rs, f64/float.rs
src/euler.rs          EulerRot enum + FromEuler/ToEuler (hand-written, macro-instantiated for f32/f64)
src/deref.rs          Vec3<T>/Vec4<T>/Cols2/3/4 structs used as Deref targets by SIMD-backed types
src/align16.rs        Align16 wrapper (SSE2 const construction)
src/sse2.rs neon.rs wasm.rs coresimd.rs spirv.rs   SIMD helper intrinsics (shared m128 helpers)
src/features.rs + features/impl_*.rs   optional integrations (approx, arbitrary, bytemuck, encase,
                                        float_eq, mint, rand, rkyv, serde, speedy, zerocopy)
src/bool.rs  + bool/   BVec2, BVec3, BVec4 (always scalar) ; BVec3A, BVec4A per backend
                       (bool/{scalar,sse2,neon,wasm,coresimd}/bvec{3,4}a.rs)
src/f32.rs   + f32/    Vec2, Vec3, Mat3, Affine2, Affine3, Affine3A, float.rs, math.rs  (scalar only, shared)
                       f32/{scalar,sse2,neon,wasm,coresimd}/{vec3a,vec4,quat,mat2,mat3a,mat4}.rs
src/f64.rs   + f64/    DVec2/3/4, DMat2/3/4, DQuat, DAffine2, DAffine3, float.rs, math.rs (always scalar)
src/{i8,u8,i16,u16,i32,u32,i64,u64,isize,usize}.rs + dirs    {I8,U8,I16,U16,I,U,I64,U64,ISize,USize}Vec{2,3,4}
src/swizzles.rs + swizzles/   vec_traits.rs (Vec2Swizzles/Vec3Swizzles/Vec4Swizzles) + 45 *_impl.rs
src/camera.rs + camera/       camera::{rh,lh}::{view,proj::{opengl,vulkan,directx}} free functions (f32)
src/dcamera.rs + dcamera/     same for f64
src/prelude.rs
```

Backend selection for the 6 SIMD-capable f32 types (`Vec3A, Vec4, Quat, Mat2,
Mat3A, Mat4`) is done in `src/f32.rs` with `cfg`:

- `scalar` — when no SIMD target feature is available **or** feature `scalar-math` is set;
- `sse2` (x86/x86_64), `neon` (aarch64), `wasm` (simd128), `coresimd` (nightly portable SIMD).

`Vec2`, `Vec3`, `Mat3`, `Affine2`, `Affine3` and every `f64`/integer type are
**always scalar**. So the Cairo port must track: `src/f32/{vec2,vec3,mat3,
affine2,affine3,float,math}.rs` + `src/f32/scalar/{vec4,quat,mat2,mat4}.rs` +
`src/bool/bvec{2,3,4}.rs` + `src/euler.rs` + `src/float.rs` +
`src/i32/*`, `src/u32/*` + `src/swizzles/*` + `src/camera/*`.

### 1.3 Codegen / template system

`codegen.json` structure: `templates.<name>.properties` gives defaults,
`templates.<name>.outputs.<path>.properties` overrides per generated file.

| Template | Outputs | Properties |
|---|---:|---|
| `vec.rs.tera` (4,742 lines) | 45 | `scalar_t`, `dim`, `is_align`, `is_scalar`, `is_sse2`, `is_neon`, `is_wasm`, `is_coresimd` |
| `mat.rs.tera` (3,183) | 19 | same |
| `quat.rs.tera` (1,570) | 6 | `scalar_t` + backend flags |
| `affine.rs.tera` (1,029) | 5 | `scalar_t`, `dim`, `is_align` + backend flags |
| `vec_mask.rs.tera` (591) | 13 | `scalar_t` (`bool`/`u32`), `dim` + backend flags |
| `swizzle_traits.rs.tera` | 1 | — |
| `swizzle_impl.rs.tera` | 45 | `dim`, `self_t`, `vec2_t`, `vec3_t`, `vec4_t` + backend flags |
| `swizzle_test.rs.tera` | 12 | `scalar_t` |
| `float.rs.tera` | 2 | `scalar_t` |
| `camera_mod/impl/view/proj.rs.tera` | 2+2+4+4 | `scalar_t`, `is_rh` |
| `sse2/neon/wasm/coresimd/macros.rs.tera` | helpers | — |

Inside a template, the head block derives names from `scalar_t` / `dim`:
`self_t`, `vec2_t/vec3_t/vec4_t`, `quat_t`, `mask_t` (`BVecN` for scalar,
`BVecNA` for aligned/SIMD), `is_float`, `is_signed`, `unsigned_scalar_t`,
`opposite_signedness_t`, `from_types` (lossless `From`), `try_from_types`
(`TryFrom`). The body is then a long sequence of `{% if is_float %}`,
`{% if is_signed %}`, `{% if dim == 3 %}`, `{% if is_sse2 %}` ... blocks.

**Takeaway for Cairo.** Cairo *does* have generics and traits, so the no-generics
constraint that forced codegen in Rust does not apply. Two viable designs:

- (A) generic `Vec3<T>` with trait bounds (`Add, Sub, Mul, Div, Neg, PartialOrd,
  Zero, One, + a `Real`-like trait for sqrt/sin_cos/atan2`), instantiated for the
  fixed-point scalar and for `i32`/`u32`-like integers;
- (B) concrete types per scalar family (mirrors glam, best for gas/step cost
  control and simpler error messages), optionally with a small script-based
  generator.

The template conditionals are a precise spec of what differs between float /
signed-int / unsigned-int vectors (see 2.4), whichever design is chosen.

### 1.4 Feature flags

| Feature | Meaning | Relevance to Cairo |
|---|---|---|
| `std` (default), `libm`, `nostd-libm` | math backend selection for `math.rs` (one of them is mandatory) | replaced by our fixed-point scalar layer |
| `f64`, `i8..u64`, `isize`, `usize`, `float-types`, `integer-types`, `size-types`, `all-types` (default) | compile each scalar family | pick a subset |
| `scalar-math` | disable SIMD, native alignment | this *is* our target semantics |
| `glam-assert`, `debug-glam-assert` | enable `glam_assert!` argument validation (normalized inputs, non-zero det, `min <= max`...) | map to Cairo `assert!` — decide on/off policy (see 3.3) |
| `cuda` | alignment for CUDA | drop |
| `core-simd` | nightly portable SIMD | drop |
| `fast-math` | deprecated no-op | drop |
| `approx`, `arbitrary`, `bytemuck`, `bytecheck`, `encase`, `float_eq`, `mint`, `rand`, `rkyv`, `serde`, `speedy`, `zerocopy` | optional trait impls | drop all; Cairo equivalents are `Serde`, `starknet::Store`, `Drop/Copy/PartialEq/Debug/Default/Hash` derives |

### 1.5 The scalar math layer (`src/f32/math.rs`, `src/f64/math.rs`)

Three interchangeable modules (`std_math`, `libm_math`, `no_backend_math`)
export the same 22 `pub(crate)` functions. This is **the exact scalar
primitive set glam needs from its number type**:

| Primitive | Signature | Who uses it (scalar f32 code path; occurrence counts from `grep math::`) |
|---|---|---|
| `abs` | `f -> f` | vec `abs`, `is_normalized`, `any_orthogonal_vector`, slerp guards; Quat `is_near_identity`, `angle_between` |
| `signum` | `f -> f` | vec `signum`; `Vec2::angle_to/rotate_towards`; `Vec3::any_orthonormal_*`; `Mat4/Affine2/Affine3::to_scale_*` (sign of determinant) |
| `copysign` | `(f, f) -> f` | vec `copysign` only |
| `sqrt` | `f -> f` | `length`, `clamp_length*`, `refract`, `angle_between`, vec `sqrt`; Quat `from_rotation_axes`, `from_rotation_arc_2d`; euler `to_euler` |
| `sin`, `cos` | `f -> f` | vec element-wise `sin/cos`; `Vec3::slerp`, `Quat::slerp_impl` (3 × `sin`) |
| `sin_cos` | `f -> (f, f)` | `Vec2::from_angle`, `Vec3::rotate_x/y/z`; Quat `from_axis_angle`, `from_rotation_x/y/z`; `Mat2::from_angle/from_scale_angle`; Mat3 (6), Mat4 (8) rotation builders and perspective; euler `from_euler` (6); camera proj (3) |
| `tan` | `f -> f` | only 3 deprecated `Mat4` projections: `perspective_rh_gl`, `perspective_infinite_rh`, `perspective_infinite_reverse_rh` (the others use `sin_cos` and `cos/sin`); the new `camera` module uses `sin_cos` only |
| `acos_approx` | `f -> f` | `Vec2::angle_to`, `Vec3::angle_between`, `Vec3::slerp`, `Quat::angle_between`, `Quat::slerp_impl` |
| `atan2` | `(y, x) -> f` | `Vec2::to_angle`, `Vec3::angle_to`, `Quat::to_axis_angle`, `Affine2::to_scale_angle_translation`, euler `to_euler` (10) |
| `floor`, `ceil`, `round`, `trunc` | `f -> f` | vec element-wise; `fract` (`x - trunc`), `fract_gl` (`x - floor`); `FloatExt::fract_gl`. `round` = half away from zero |
| `div_euclid`, `rem_euclid` | `(f, f) -> f` | vec element-wise only |
| `mul_add` | `(a, b, c) -> a*b+c` | vec element-wise only |
| `exp`, `exp2`, `ln`, `log2`, `powf` | | vec element-wise only — **no internal consumer** |

For **f32**, `acos_approx` is glam's own implementation (from DirectXMath
`XMScalarAcos`; the f64 module instead defines `acos_approx` as the exact
`f64::acos(x.clamp(-1, 1))`):
clamp to [-1, 1], 7th-degree minimax polynomial in `|x|` multiplied by
`sqrt(1 - |x|)`, mirrored with `PI - result` for negative input. It ports
directly to fixed-point (8 coefficients, 7 multiplications, 1 sqrt):

```
coeffs as written in src/f32/math.rs (highest degree first):
 -0.0012624911, 0.00667009, -0.017088126, 0.03089188,
 -0.050174303, 0.08897899, -0.2145988, 1.5707963
result = poly(|x|) * sqrt(1 - |x|);  if x < 0 { PI - result }
```

Used *outside* `math.rs` directly on the primitive type:

- operators `+ - * / %` (`%` = truncated remainder, used by `Rem` impls), unary `-`;
- comparisons `< <= > >= == !=` (min/max are written as `if a < b { a } else { b }`);
- `f32::clamp`, `f32::is_finite`, `f32::is_nan`, `f32::is_sign_negative`;
- reciprocal written as `1.0 / x`; halving/doubling as `* 0.5`, `* 2.0`, `x + x`;
- constants: `0, 1, -1, 0.5, 2, 3`, `PI`, `f32::EPSILON` (1.19e-7), `MIN`, `MAX`, `NAN`, `INFINITY`, `NEG_INFINITY`;
- casts `as f64 / as i32 / as u32 ...` for the `as_*` conversions;
- `FloatExt` (`src/float.rs`, implemented in `src/f32/float.rs`):
  `lerp(a, b, t) = a + (b - a) * t`, `inverse_lerp`, `smoothstep`, `remap`,
  `fract_gl`, `step`, `saturate`, `move_towards`.

Hard-coded tolerances found in the f32 scalar sources (all must be re-derived
for the chosen fixed-point format, see 3.3):

| Constant | Where | Purpose |
|---|---|---|
| `2e-4` | `VecN::is_normalized` (same value for f64!) | `|len² - 1| <= 2e-4` |
| `1e-4` | `VecN::move_towards`, `Quat::rotate_towards` | snap to target |
| `1 - 3e-7` | `Vec3::slerp` | parallel-vector guard |
| `1 - 2·EPSILON` | `Quat::from_rotation_arc{,_2d}` | parallel / anti-parallel guard |
| `1 - EPSILON` | `Quat::slerp`, `slerp_long` | fallback to nlerp |
| `1 - 1e-6` | `Quat::is_near_identity` | |
| `1e-8` | `Quat::to_axis_angle` | zero-rotation guard |
| `16·EPSILON` | euler `to_euler` | gimbal-lock guard |
| `1e-6` | `Mat3::transform_point2`, `Mat4::transform_point3` asserts | last row must be `(0,0,1)` / `(0,0,0,1)` |

---

## 2. Type inventory

### 2.1 All public types (0.33.8, `all-types`)

| Family | Types | Count |
|---|---|---:|
| f32 vectors | `Vec2`, `Vec3`, `Vec3A` (16-byte aligned / SIMD), `Vec4` | 4 |
| f32 matrices | `Mat2`, `Mat3`, `Mat3A`, `Mat4` | 4 |
| f32 rotation / transform | `Quat`, `Affine2`, `Affine3` (new, unaligned), `Affine3A` | 4 |
| f64 | `DVec2/3/4`, `DMat2/3/4`, `DQuat`, `DAffine2`, `DAffine3` | 9 |
| integer vectors | `{I8,U8,I16,U16,I,U,I64,U64,ISize,USize}Vec{2,3,4}` | 30 |
| masks | `BVec2`, `BVec3`, `BVec4`, `BVec3A`, `BVec4A` | 5 |
| misc | `EulerRot` (24 orders), `FloatExt`, `Vec2Swizzles`, `Vec3Swizzles`, `Vec4Swizzles`, modules `camera`, `dcamera`, free ctor fns `vec3(..)`, `mat4(..)`, `quat(..)` ... | |

Total: **56 concrete math types**. Size of the scalar generated files
(lines / `pub fn` / top-level `impl` blocks):

| File | Lines | pub fns | impl blocks |
|---|---:|---:|---:|
| `f32/vec2.rs` | 1,978 | 102 | 99 |
| `f32/vec3.rs` | 2,241 | 111 | 99 |
| `f32/scalar/vec3a.rs` | 2,273 | 112 | 104 |
| `f32/scalar/vec4.rs` | 2,266 | 97 | 106 |
| `f32/scalar/mat2.rs` | 963 | 42 | 55 |
| `f32/mat3.rs` | 1,410 | 57 | 60 |
| `f32/scalar/mat4.rs` | 2,071 | 74 | 55 |
| `f32/scalar/quat.rs` | 1,334 | 50 | 53 |
| `f32/affine2.rs` | 636 | 24 | 36 |
| `f32/affine3.rs` | 700 | 31 | 26 |
| `f32/affine3a.rs` | 721 | 33 | 26 |
| `i32/ivec2.rs` / `ivec3.rs` / `ivec4.rs` | 2,889 / 3,038 / 3,383 | 71 / 72 / 70 | 258 / 260 / 263 |
| `u32/uvec3.rs` | 2,887 | 62 | 258 |
| `bool/bvec3.rs` | 338 | 8 | 27 |

The `impl` count is inflated by Rust's by-ref operator permutations
(`T op T`, `T op &T`, `&T op T`, `&T op &T`, plus `OpAssign<T>`, `OpAssign<&T>`)
— e.g. each of `Add/Sub/Mul/Div/Rem` yields 16 impls on a float vector
(vec∘vec ×4, vec∘scalar ×4, scalar∘vec ×4, assign ×4). In Cairo this collapses
to ~3 impls per operator (`Vec∘Vec`, `Vec∘Scalar`, `Scalar∘Vec`) + the
`*Assign` traits.

### 2.2 Float vectors (`Vec2`, `Vec3`, `Vec4`; `Vec3A` = `Vec3` API)

Struct: `#[derive(Clone, Copy, PartialEq)] #[repr(C)] pub struct Vec3 { pub x, pub y, pub z }` (no `Eq`/`Hash` for floats).

**Constants** — `ZERO, ONE, NEG_ONE, MIN, MAX, NAN, INFINITY, NEG_INFINITY,
X, Y, (Z, W), NEG_X, NEG_Y, (NEG_Z, NEG_W), AXES: [Self; N]`, and the backend
flags `USES_CORE_SIMD, USES_NEON, USES_SCALAR_MATH, USES_SSE2, USES_WASM_SIMD,
USES_WASM32_SIMD`.

**Methods common to the three dims** (grouped; ~85 shared):

| Group | Methods |
|---|---|
| Construction | `new`, `splat`, `from_array`, `to_array`, `from_slice`, `write_to_slice`, `map(f)`, `select(mask, a, b)`, free fn `vecN(..)`; `From` for arrays, tuples, `(Vec2, f32)`, `(Vec3, f32)`, `BVecN` (bool -> 0/1) |
| Component access | public fields, `with_x/y/z/w`, `Index/IndexMut<usize>`, `AsRef/AsMut<[T; N]>`, `extend` (Vec2->Vec3, Vec3->Vec4), `truncate` (Vec3->Vec2, Vec4->Vec3) |
| Arithmetic ops | `Add, Sub, Mul, Div, Rem` (vec∘vec, vec∘scalar, scalar∘vec) + `*Assign`, `Neg`, `Sum`, `Product`, `mul_add(a, b)`, `recip`, `div_euclid`, `rem_euclid` |
| Dot / length / normalize | `dot`, `dot_into_vec`, `length`, `length_squared`, `length_recip`, `distance`, `distance_squared`, `normalize`, `try_normalize -> Option`, `normalize_or(fallback)`, `normalize_or_zero`, `normalize_and_length -> (Self, f32)`, `is_normalized`, `clamp_length`, `clamp_length_max`, `clamp_length_min` |
| Reductions | `min_element`, `max_element`, `min_position`, `max_position`, `element_sum`, `element_product` |
| Comparison / masks | `cmpeq, cmpne, cmpge, cmpgt, cmple, cmplt -> BVecN`, `is_negative_bitmask -> u32`, `is_negative_mask`, `is_finite`, `is_finite_mask`, `is_nan`, `is_nan_mask`, `abs_diff_eq(rhs, eps)`, `PartialEq` |
| Min / max / clamp / sign | `min`, `max`, `clamp`, `abs`, `signum`, `copysign`, `saturate`, `step`, `smoothstep` |
| Rounding | `round`, `floor`, `ceil`, `trunc`, `fract` (`x - trunc x`), `fract_gl` (`x - floor x`) |
| Transcendental, element-wise | `exp, exp2, ln, log2, powf, sqrt, sin, cos, sin_cos` |
| Interpolation | `lerp(rhs, s)`, `move_towards(rhs, d)`, `midpoint(rhs)` |
| Projection family | `project_onto`, `reject_from`, `project_onto_normalized`, `reject_from_normalized`, `reflect(normal)`, `refract(normal, eta)` |
| Casts | `as_dvecN`, `as_{i8,u8,i16,u16,i,u,i64,u64,isize,usize}vecN` (11) |
| Formatting | `Display` (`[x, y, z]`, honours precision), `Debug` |

**Dim-specific:**

| Type | Extra methods |
|---|---|
| `Vec2` (102 fns) | `from_angle`, `to_angle` (atan2), `angle_to` (signed, acos + sign of perp_dot), `perp`, `perp_dot` (2D cross), `rotate(rhs)` (complex multiply), `rotate_angle`, `rotate_towards(rhs, max_angle)` |
| `Vec3` (111 fns) | `cross`, `from_homogeneous(Vec4)`, `to_homogeneous`, `to_vec3a`, `angle_between` (acos), `angle_to(rhs, axis)` (atan2, signed), `rotate_x/y/z(angle)`, `rotate_axis(axis, angle)` (*uses Quat*), `rotate_towards` (*uses Quat*), `any_orthogonal_vector`, `any_orthonormal_vector`, `any_orthonormal_pair` (Pixar branchless ONB), `slerp` (*uses Quat in the anti-parallel branch*) |
| `Vec4` (97 fns) | `truncate`, `project() -> Vec3` (perspective divide); constants `W`, `NEG_W`; `From<(Vec3, f32)>`, `From<(f32, Vec3)>`, `From<(Vec2, Vec2)>`, `From<(Vec2, f32, f32)>` |
| `Vec3A` (112 fns) | same as `Vec3` + `from_vec4`, `to_vec3` |

### 2.3 Masks: `BVec2`, `BVec3`, `BVec4` (+ `BVec3A`, `BVec4A`)

`#[derive(Clone, Copy, PartialEq, Eq, Hash)] struct BVec3 { x: bool, y: bool, z: bool }`.
8 methods: `new, splat, from_array, bitmask -> u32, any, all, test(index),
set(index, value)`; constants `FALSE`, `TRUE`; ops `BitAnd, BitOr, BitXor`
(+Assign), `Not`; `From<[bool; N]>`, `Into<[bool; N]>`, `Into<[u32; N]>`,
`Debug/Display`, `Default`. The `A` variants store `u32`/SIMD masks and have the
identical API. No dependency on any other type.

### 2.4 Integer vectors (30 types, identical API per signedness)

Struct derives additionally `Eq, Hash`. Signed: 70–72 fns; unsigned: 62 fns.
Compared with float vectors:

- **Kept:** construction, access, `dot`, `dot_into_vec`, `cross` (dim 3),
  `min/max/clamp`, reductions, `cmp*`, `select`, `length_squared`,
  `distance_squared` (signed only), `div_euclid/rem_euclid` (signed), `abs`,
  `signum`, `is_negative_bitmask/mask` (signed), `perp/perp_dot/rotate`
  (IVec2), `extend/truncate`, arithmetic ops, `Sum/Product`, `as_*` casts.
- **Removed:** everything requiring reals — `length`, `normalize*`, `lerp`,
  rounding, transcendental, `project/reject/reflect/refract`, angles,
  `is_finite/is_nan`, `abs_diff_eq`, `NAN/INFINITY` constants.
- **Added:** `manhattan_distance`, `checked_manhattan_distance`,
  `chebyshev_distance`; `checked_{add,sub,mul,div} -> Option`,
  `wrapping_{add,sub,mul,div}`, `saturating_{add,sub,mul,div}`; mixed-sign
  helpers `checked/wrapping/saturating_{add,sub}_unsigned` (signed) and
  `checked/wrapping/saturating_add_signed` (unsigned); bitwise ops `BitAnd,
  BitOr, BitXor, Not`, shifts `Shl/Shr` by every integer scalar type and by
  integer vectors (this is where the ~258 impl blocks come from: 40 `Shl` + 40
  `Shr` + 32 assign variants); `From` (lossless widening) and `TryFrom`
  (narrowing / sign change) between all integer vector types.
- Unsigned has no `NEG_*` constants, no `Neg`, no `abs/signum`.

### 2.5 Matrices

Column-major, fields `x_axis, y_axis, (z_axis, w_axis)` of the matching vector
type; `#[derive(Clone, Copy)]` + manual `PartialEq`. Constants: `ZERO`,
`IDENTITY`, `NAN`.

**Shared matrix API (all dims, ~38 fns):** `from_cols`, `from_rows`,
`from_cols_array`, `to_cols_array`, `from_cols_array_2d`, `to_cols_array_2d`,
`from_rows_array`, `to_rows_array`, `from_cols_slice`, `write_cols_to_slice`,
`from_rows_slice`, `from_diagonal`, `col`, `col_mut`, `row`, `set_row`,
`diagonal`, `transpose`, `determinant`, `inverse`, `try_inverse -> Option`,
`inverse_or_zero`, `mul_vecN`, `mul_transpose_vecN`, `mul_matN`, `add_matN`,
`sub_matN`, `mul_scalar`, `div_scalar`, `mul_diagonal_scale`, `recip`, `abs`,
`abs_diff_eq`, `is_finite`, `is_nan`, `as_dmatN`.
Operators: `Add, Sub, Neg, Mul<Self>, Mul<VecN>, Mul<f32>, f32 * Mat, Div<f32>`
(+Assign), `Sum`, `Product`, `AsRef/AsMut<[f32; N*N]>`, `Default` (= IDENTITY),
`Debug/Display`.

| Type | pub fns | Specific |
|---|---:|---|
| `Mat2` | 42 | `from_scale_angle`, `from_angle`, `from_mat3`, `from_mat3_minor(m, i, j)`, `from_mat3a`, `from_mat3a_minor` |
| `Mat3` | 57 | 3D rotation: `from_quat`, `from_axis_angle`, `from_euler`, `to_euler`, `from_rotation_x/y/z`; 2D homogeneous: `from_translation(Vec2)`, `from_angle`, `from_scale_angle_translation`, `from_scale(Vec2)`, `from_mat2`, `transform_point2`, `transform_vector2`; `from_mat4`, `from_mat4_minor`; `mul_vec3a`; deprecated `look_to_lh/rh`, `look_at_lh/rh` (moved to `camera::*::view`) |
| `Mat4` | 74 | TRS: `from_scale_rotation_translation`, `from_rotation_translation`, `to_scale_rotation_translation`, `from_quat`, `from_mat3`, `from_mat3_translation`, `from_mat3a`, `from_translation`, `from_axis_angle`, `from_euler`, `to_euler`, `from_rotation_x/y/z`, `from_scale`; view (deprecated aliases): `look_to_lh/rh`, `look_at_lh/rh`; projection (deprecated aliases of `camera::*::proj`): `frustum_rh_gl`, `frustum_lh`, `frustum_rh`, `perspective_rh_gl`, `perspective_lh`, `perspective_rh`, `perspective_infinite_lh`, `perspective_infinite_reverse_lh`, `perspective_infinite_rh`, `perspective_infinite_reverse_rh`, `orthographic_rh_gl`, `orthographic_lh`, `orthographic_rh`; point ops: `project_point3` (with perspective divide), `transform_point3`, `transform_vector3` (+ `*3a` variants); `Mul<Affine3>` both ways |

Algorithms (scalar): Mat2 inverse = adjugate / det; Mat3 determinant =
`x·(y×z)`, inverse = transposed cross products / det; Mat4 inverse = cofactor
expansion with 18 2×2 sub-determinants then `1/det`; `inverse` asserts `det != 0`
only under `glam_assert`, `try_inverse` returns `None` iff `det == 0.0` exactly.

### 2.6 `Quat` (50 pub fns, 53 impls)

Fields `x, y, z, w`; constants `IDENTITY`, `NAN` (+ private `ZERO`).

| Group | Methods |
|---|---|
| Construction | `from_xyzw`, `from_array`, `from_vec4`, `from_slice`, `write_to_slice`, `to_array`, `xyz`, free fn `quat(..)` |
| From rotations | `from_axis_angle`, `from_scaled_axis`, `from_rotation_x/y/z`, `from_euler(EulerRot, a, b, c)`, `from_rotation_axes(x, y, z)`, `from_mat3`, `from_mat3a`, `from_mat4`, `from_affine3`, `from_affine3a`, `from_rotation_arc(from, to)`, `from_rotation_arc_colinear`, `from_rotation_arc_2d(Vec2, Vec2)`, deprecated `look_to_lh/rh`, `look_at_lh/rh` |
| To rotations | `to_axis_angle -> (Vec3, f32)`, `to_scaled_axis`, `to_euler(EulerRot)` |
| Algebra | `conjugate`, `inverse` (= conjugate, asserts normalized), `dot`, `length`, `length_squared`, `length_recip`, `normalize`, `mul_quat`, `mul_vec3`, `mul_vec3a` |
| Predicates | `is_finite`, `is_nan`, `is_normalized`, `is_near_identity`, `abs_diff_eq` |
| Interpolation / angles | `angle_between`, `rotate_towards(rhs, max_angle)`, `lerp` (nlerp with shortest-path sign flip), `slerp`, `slerp_long` |
| Casts | `as_dquat` |
| Operators | `Add`, `Sub`, `Mul<f32>`, `Div<f32>`, `Neg`, `Mul<Quat>`, `Mul<Vec3>`, `Mul<Vec3A>` (+Assign), `Sum`, `Product`, `Default` (IDENTITY), `PartialEq`, `AsRef<[f32;4]>`, `From/Into Vec4`, tuples, arrays |

In the scalar backend `dot/length/normalize/is_normalized/abs_diff_eq` delegate
to `Vec4`. `mul_vec3` uses the expanded form
`v·(w² − b·b) + b·(2·(v·b)) + (b × v)·(2w)` (no matrix built).
`from_rotation_axes` is the branchy numerically-robust matrix→quat (4 cases on
`m22`, `m11 ± m00`), one `sqrt` + one division.

### 2.7 Affine transforms

| Type | Fields | pub fns | API |
|---|---|---:|---|
| `Affine2` | `matrix2: Mat2`, `translation: Vec2` | 24 | `ZERO/IDENTITY/NAN`, `from_cols`, `from_cols_array(_2d)`, `to_cols_array(_2d)`, `from_cols_slice`, `write_cols_to_slice`, `from_scale`, `from_angle`, `from_translation`, `from_mat2`, `from_mat2_translation`, `from_scale_angle_translation`, `from_angle_translation`, `from_mat3`, `from_mat3a`, `to_scale_angle_translation`, `transform_point2`, `transform_vector2`, `inverse`, `is_finite`, `is_nan`, `abs_diff_eq`, `as_daffine2`; ops: `Mul<Self>`, `Mul<Mat3>` both ways, `From<Affine2> for Mat3`, `Product`, `Deref` to columns |
| `Affine3` / `Affine3A` | `matrix3: Mat3(A)`, `translation: Vec3(A)` | 31 / 33 | same pattern + `from_quat`, `from_axis_angle`, `from_rotation_x/y/z`, `from_mat3`, `from_mat3_translation`, `from_scale_rotation_translation`, `from_rotation_translation`, `from_mat4`, `to_scale_rotation_translation`, deprecated `look_to/at_lh/rh`, `transform_point3`, `transform_vector3` (+ `*3a`), `inverse`; ops: `Mul<Self>`, `Mul<Mat4>` both ways, `From<Affine3> for Mat4` |

`inverse()` is the *general* affine inverse (`M⁻¹`, `-(M⁻¹ t)`) — it does not
assume orthonormality. Composition: `(A·B).matrix = A.m · B.m`,
`(A·B).translation = A.m · B.t + A.t`.

### 2.8 Euler (`src/euler.rs`, hand-written, 452 lines)

`EulerRot` has 24 variants: 6 Tait-Bryan intrinsic (`ZYX, ZXY, YXZ` (default),
`YZX, XYZ, XZY`), 6 proper Euler intrinsic (`ZYZ, ZXZ, YXY, YZY, XYX, XZX`), and
the 12 extrinsic counterparts (`*Ex`). Implementation follows Ken Shoemake
(Graphics Gems IV): an `Order { initial_axis, parity_even, initial_repeated,
frame_static }` descriptor drives a single generic algorithm:

- `from_euler` for `Mat3` (3 × `sin_cos`, 9 products) and for `Quat`
  (3 × `sin_cos` of half angles); `Mat4` wraps `Mat3`.
- `to_euler` for `Mat3` (1 `sqrt` + 3 `atan2`, gimbal-lock guard
  `16·EPSILON`); `Quat::to_euler` converts to `Mat3` first; `Mat4` via `Mat3`.

Primitives needed: `sin_cos`, `sqrt`, `atan2` only.

### 2.9 Camera (`src/camera/`, new in 0.33.x)

Free functions namespaced by handedness and graphics API:
`camera::{rh,lh}::view::{look_at,look_to}_{mat4,affine3,affine3a,mat3,mat3a,quat}`
(12 per handedness) and
`camera::{rh,lh}::proj::{opengl,vulkan,directx}::{perspective,
perspective_infinite, perspective_infinite_reverse, orthographic, frustum}`
(opengl has no infinite variants). Depth range: OpenGL `[-1, 1]`, Vulkan/DirectX
`[0, 1]`. Implementation in `camera_impl.rs` uses only `sin_cos` + division.
The old `Mat4::perspective_*`/`look_at_*` methods are deprecated aliases (since 0.33.1).

### 2.10 Swizzles

Three traits with associated types: `Vec2Swizzles` (28 methods), `Vec3Swizzles`
(123), `Vec4Swizzles` (372) — every permutation-with-repetition of components
producing a Vec2/Vec3/Vec4 (`xy`, `zyx`, `xxyy`, ...) plus `with_xy(rhs)`-style
setters for non-repeating selections. One generated impl per vector type (45
files). Pure data shuffling, no arithmetic. **Internally glam only uses a
handful** (`xy()`, `xyz()` in Mat2/Mat3/Mat4/euler).

---

## 3. What makes sense in Cairo

### 3.1 Drop / keep decisions

| glam item | Decision | Rationale |
|---|---|---|
| SIMD backends (`sse2`, `neon`, `wasm`, `coresimd`), `deref.rs`, `align16.rs`, `spirv.rs` | **Drop** | Cairo VM has no SIMD; the cost model is steps/builtins, not cache lines |
| `Vec3A`, `Mat3A`, `Affine3A`, `BVec3A`, `BVec4A` | **Drop** | exist only for 16-byte alignment/SIMD. Name the Cairo 3D affine `Affine3` (matches glam ≥ 0.33's unaligned `Affine3`) |
| `D*` (f64) family | **Drop as separate types** | one fixed-point scalar. If two precisions are ever wanted, use a generic scalar parameter rather than type duplication |
| `USES_*` constants, `cuda`, `fast-math` | Drop | |
| bytemuck / zerocopy / rkyv / speedy / encase / mint / serde / rand / arbitrary / approx / float_eq | **Drop**; replace with Cairo derives `Copy, Drop, Serde, PartialEq, Debug, Default` and optionally `starknet::Store` / `Hash` | Note: fixed-point vectors *can* be `Eq`/`Hash` (unlike f32), which is valuable for storage keys and deterministic state commitment |
| `NAN`, `INFINITY`, `NEG_INFINITY` constants; `is_nan`, `is_nan_mask`, `is_finite`, `is_finite_mask`; `Mat*/Quat/Affine::NAN` | **Drop** (or keep `is_finite` as `true` stub for API parity — not recommended) | fixed-point has no NaN/Inf. Operations that would produce them must **panic** (division by zero, sqrt of negative, overflow) or return `Option` |
| `MIN`, `MAX` | Keep | map to scalar min/max representable |
| `from_slice`, `write_to_slice`, `AsRef/AsMut`, `col_mut`, `IndexMut` | Adapt | use `Span<T>` / `Array<T>` constructors, `to_array` -> fixed-size array or tuple; no interior mutable references in Cairo: replace `col_mut`/`IndexMut` by `with_col`/`set_col`/`with_x` style |
| `map(f)` | Optional | closures exist in recent Cairo but are costly; low priority |
| `Sum`/`Product` iterators | Optional | provide `sum(Span<Vec3>)` helpers |
| `Display`/`Debug` | `Debug` derive only, `Display` optional | |
| Integer vectors, 10 widths × 3 dims | **Keep 2 families first**: `IVecN` (i32) and `UVecN` (u32); consider `I64VecN`/`U64VecN` later | Useful for grids, voxel/cell coordinates, spatial hashing in broad-phase. Cairo integer ops **panic on overflow by default**, so plain ops ≙ Rust debug; `checked_*`/`wrapping_*`/`saturating_*` map to `core::num::traits::{CheckedAdd, WrappingAdd, SaturatingAdd, ...}`. Shifts are not native operators in Cairo (emulate with mul/div by powers of two) — low priority. `isize/usize` -> skip |
| `BVec2/3/4` | **Keep** | trivial, needed by `cmp*` and `select` |
| Swizzles | Keep as traits, low priority; implement Vec2/Vec3 fully (28 + 123) and Vec4 lazily (372 methods is code-size heavy: generate by script, consider feature-gating) | |
| `euler` | Keep (needs only sin_cos/sqrt/atan2) | medium priority; for physics it is an I/O convenience |
| `camera` / projection matrices | Keep as late optional module | rendering concern, not physics; cheap to port (sin_cos + division) |
| `exp, exp2, ln, log2, powf` element-wise | Defer | no internal consumer; only port if the scalar lib provides them cheaply |
| `glam_assert!` | Keep as a deliberate policy | see 3.3 |

### 3.2 Proposed mapping

One scalar type `Fixed` (signed fixed-point; format decided in the scalar-layer
research note — the glam layer should be written against a small trait surface
so the format can change):

```
scalar layer   Fixed  (+ FixedTrait: ZERO, ONE, HALF, TWO, PI, EPSILON-like tolerances,
                        abs, signum, copysign, sqrt, sin, cos, sin_cos, tan, acos_approx, atan2,
                        floor, ceil, round, trunc, div_euclid, rem_euclid, mul_add, recip,
                        min, max, clamp, lerp & FloatExt helpers; later exp/exp2/ln/log2/powf)

glam (Rust)                         glam.cairo
---------------------------------   ------------------------------
Vec2 / DVec2                     -> Vec2
Vec3 / Vec3A / DVec3             -> Vec3
Vec4 / DVec4                     -> Vec4
Mat2 / DMat2                     -> Mat2
Mat3 / Mat3A / DMat3             -> Mat3
Mat4 / DMat4                     -> Mat4
Quat / DQuat                     -> Quat
Affine2 / DAffine2               -> Affine2
Affine3 / Affine3A / DAffine3    -> Affine3
BVec2, BVec3, BVec4 (BVec3A/4A)  -> BVec2, BVec3, BVec4
IVec2/3/4, UVec2/3/4             -> IVec2/3/4 (i32), UVec2/3/4 (u32)
I8/U8/I16/U16/I64/U64/ISize/USize vectors -> not ported initially (I64/U64 on demand)
EulerRot                         -> EulerRot (enum, 24 variants)
FloatExt                         -> methods on Fixed (lerp, inverse_lerp, smoothstep, remap, fract_gl, step, saturate, move_towards)
Vec{2,3,4}Swizzles               -> same traits
camera::{rh,lh}::{view,proj}     -> same module tree (optional, late)
as_* casts                       -> Vec3 <-> IVec3 / UVec3 (`as_ivec3` = trunc toward zero, saturating in Rust!)
```

Note on `as_*` casts: Rust `f32 as i32` **saturates** and maps NaN to 0. A
fixed-point → integer cast should define: truncation toward zero, and either
panic or saturate on out-of-range (choose and document; saturation matches Rust).

### 3.3 Semantics that change under fixed-point

1. **No NaN / Inf propagation.** glam relies on IEEE behaviour as an *error
   channel*: `try_normalize`/`normalize_or`/`normalize_and_length` compute
   `rcp = 1.0 / length` and test `rcp.is_finite() && rcp > 0.0`; `Vec3::slerp`
   comments "or NaN if either vector has a zero length" and lets the NaN fall
   through a comparison. In Cairo these must be rewritten as explicit
   pre-checks: `if length_squared == 0 (or < tiny) { fallback }`. `normalize()`
   of the zero vector must **panic** (glam returns NaN/asserts).
2. **`normalize` of tiny or huge vectors.** `length_squared = x²+y²+z²`
   underflows to 0 for components below `sqrt(resolution)` (e.g. with 32
   fractional bits, anything below ~1.5e-5 squares to zero; with 16 fractional
   bits, below ~4e-3!) and overflows for large components. glam's own test
   vectors include `(1, 1e-7, 0)` … `(1, 1e-16, 0)`, which are below the
   resolution of most practical fixed-point formats. Mitigations to decide in
   the scalar note: widen the intermediate (compute the sum of squares in a
   double-width integer and take an integer sqrt — natural in Cairo with
   `u128`/`u256`), or pre-scale by `max_element(abs(v))`. **Recommendation:**
   implement `dot`/`length_squared`/`length` with a wide accumulator and a
   single final rescale — it is both more precise and cheaper (one rescale
   instead of N).
3. **Overflow.** Rust floats never trap; Cairo integer arithmetic panics. Hot
   spots: `length_squared`, `dot`, `cross` (products of two coordinates),
   `determinant` (triple products: magnitude ~ s³), `Mat4::inverse` (products
   of 2×2 sub-determinants: s⁴), projection matrices with large `far/near`.
   A proof that fails on overflow is a liveness concern for a game — define
   a documented safe input range (world bounds) per operation.
4. **`inverse` / `determinant` precision.** `1/det` with a small det loses
   almost all significant bits in fixed-point. `try_inverse` tests `det == 0.0`
   exactly; in fixed-point prefer `|det| <= threshold -> None`. For rigid
   transforms prefer structure-aware inverses (rotation: transpose / conjugate;
   `Affine3` with orthonormal `matrix3`: `Rᵀ, -Rᵀt`) — glam's `Affine3::inverse`
   is the general one; an extra `inverse_rigid()` (like nalgebra `Isometry`
   / glamx `Pose3`) is worth adding. Divide once: compute the adjugate in wide
   precision, then divide each entry by det (rather than multiplying by a
   truncated `1/det`).
5. **Epsilon constants** (table in 1.5) are tuned to f32. `f32::EPSILON`
   (1.19e-7) may be *below the resolution* of the fixed-point format, turning
   guards like `dot > 1 - EPSILON` into `dot > 1` (never true) or `dot >= 1`.
   Every threshold needs to be re-expressed as "k ULPs of `Fixed`" or a
   format-specific constant; `is_normalized`'s `2e-4` should be checked against
   the actual error of fixed-point `normalize` (error ≈ a few ULPs × dim).
6. **`slerp`**: needs `acos_approx` + 3 × `sin` + a division by `sin(theta)`;
   near-parallel falls back to nlerp at `dot > 1 - EPSILON`. In fixed-point
   use a much wider fallback band (e.g. `dot > 0.9995`) because
   `1/sin(theta)` amplifies quantization noise for small theta. For physics,
   nlerp (`Quat::lerp`) is usually sufficient — slerp is an animation feature.
7. **Quaternion drift.** Repeated `mul_quat` in fixed-point denormalizes faster
   than in f32; integrators must renormalize every step. `Quat::inverse`
   asserts normalization; `mul_vec3` assumes it (the formula does not divide by
   `|q|²`), so an un-normalized quat scales vectors.
8. **`signum` at zero.** Float `signum(+0.0) = 1.0`, `signum(-0.0) = -1.0`;
   there is no `-0` in fixed-point and the natural integer convention is
   `signum(0) = 0`. glam uses `signum` semantically in: `Vec2::angle_to`
   (returns `angle * signum(perp_dot)` — with `signum(0)=0` the angle between
   anti-parallel vectors becomes 0 instead of π!), `Vec3::any_orthonormal_*`
   (`sign + z` in a denominator — `signum(0) = 0` gives a division by zero for
   `z = 0`), `to_scale_rotation_translation` (sign of det). **Decision needed:**
   provide both `signum` (0 → +1, float-compatible, used internally) and
   possibly `sign` (0 → 0) on the scalar. Likewise `is_negative_bitmask` tests
   the sign bit (true for `-0.0`); in fixed-point it is simply `x < 0`.
9. **`abs_diff_eq`, `PartialEq`.** Exact `==` becomes meaningful and
   deterministic (major advantage: cross-client determinism is free, which is
   the hard problem for float physics engines). `abs_diff_eq(rhs, eps)` ports
   as is.
10. **`min/max/clamp` NaN caveats** in the docs disappear; `clamp` asserts
    `min <= max`.
11. **Rounding of mul/div.** Fixed-point multiplication truncates (toward zero
    or −∞ depending on the implementation). Choose one rounding mode, document
    it, and make the Rust reference generator emulate it if bit-exact vectors
    are wanted (see 5.3). Truncation toward −∞ (floor) introduces a systematic
    negative bias in long simulations; round-to-nearest costs a bit more.
12. **`rem`/`%`, `div_euclid`, `rem_euclid`, `fract`, `round`**: define
    explicitly for negatives: glam `Rem` = truncated remainder (sign of
    dividend); `round` = half away from zero; `fract` = `x - trunc(x)`
    (negative for negative x); `fract_gl` = `x - floor(x)`.
13. **`glam_assert!`**: in Rust it is off by default (UB-free garbage results
    instead). In a provable setting a silent garbage result is a soundness
    hazard for game logic; an assert costs steps. Recommendation: keep cheap
    asserts always on (division by zero / zero determinant — they panic anyway),
    and put the expensive ones (`is_normalized` = a dot product per call)
    behind a Scarb feature mirroring `glam-assert`.
14. **Angles.** `sin_cos` is called with arbitrary angles (no range reduction
    by the caller), including `angle * 0.5` and `PI * s`; the scalar layer must
    handle full-range reduction modulo 2π with a precise `PI` constant.
    `max_angle.clamp(a - PI, a)` in `rotate_towards` relies on a `PI` constant.

---

## 4. Dependency graph and implementation order

### 4.1 Actual `use` dependencies in glam (scalar f32 path)

Read from the `use crate::{...}` lines and method bodies; `Vec3A/Mat3A/Affine3A/D*`
references are omitted since they are dropped.

| Type | Depends on | Through |
|---|---|---|
| `math` / `FloatExt` | — | |
| `BVec2/3/4` | — | |
| `Vec2` | math, `BVec2`, `Vec3` | `extend`, `From<(Vec2, f32)>` |
| `Vec3` | math, `FloatExt`, `BVec3`, `Vec2`, `Vec4`, **`Quat`** | `truncate`/`extend`/`from_homogeneous`; **`rotate_axis`, `rotate_towards`, `slerp` call `Quat::from_axis_angle(..) * self`** |
| `Vec4` | math, `BVec4`, `Vec2`, `Vec3` | `truncate`, `project`, `From` tuples |
| `IVecN` / `UVecN` | `BVecN`, sibling dims, other integer widths (`From/TryFrom/as_*`), float vecs (`as_vecN`) | |
| `Mat2` | math, swizzles, `Vec2`, **`Mat3`** | `from_mat3`, `from_mat3_minor` |
| `Mat3` | math, swizzles, euler, `Vec2`, `Vec3`, **`Mat2`, `Mat4`, `Quat`** | `from_mat2`, `transform_point2` (builds a `Mat2`), `from_mat4(_minor)`, `from_quat`, `from_euler/to_euler` |
| `Mat4` | math, swizzles, euler, `Vec3`, `Vec4`, **`Mat3`, `Quat`** | `from_mat3`, `from_quat`, `from/to_scale_rotation_translation`, euler; `Mul<Affine3>` impls live in `affine3.rs` |
| `Quat` | math, euler, `Vec2`, `Vec3`, `Vec4`, **`Mat3`, `Mat4`, `Affine3`** | delegates `dot/length/normalize` to `Vec4`; `from_mat3/from_mat4/from_affine3` (all reduce to `from_rotation_axes(Vec3, Vec3, Vec3)`); `from_rotation_arc_2d(Vec2)` |
| `Affine2` | `Mat2`, `Mat3`, `Vec2`, math (`atan2`, `signum`) | `from_mat3`, `From<Affine2> for Mat3`, `Mul<Mat3>` |
| `Affine3` | `Mat3`, `Mat4`, `Quat`, `Vec3`, math (`signum`) | `from_quat`, `from_mat4`, `to_scale_rotation_translation`, `Mul<Mat4>` |
| `euler` | `Mat3`, `Mat4`, `Quat`, `Vec3`, `Vec3Swizzles`, math | trait impls *for* those types |
| `swizzles` | `Vec2`, `Vec3`, `Vec4` (each impl references all three) | |
| `camera` | math, `Vec3`, `Vec4`, `Mat3`, `Mat4`, `Quat`, `Affine3` | |

Cycles: `Vec2 ↔ Vec3 ↔ Vec4` (trivial conversions), `Vec3 ↔ Quat`,
`Mat2 ↔ Mat3 ↔ Mat4`, `Mat3/Mat4 ↔ Quat`, `Quat ↔ Affine3`. In Cairo, modules
of one package may be mutually recursive, so this compiles fine; the cycle only
matters for *splitting the work*.

### 4.2 Cutting the cycles: "core" vs "cross" methods

Split each type into a **core** part (depends only on lower layers) and a
**cross-type** part (conversions/rotations involving higher layers), the latter
implemented in a late integration pass or in the file of the higher-level type:

- `Vec3` core = everything except `rotate_axis`, `rotate_towards`, `slerp`
  (3 methods, need `Quat`). Alternative: implement those 3 with Rodrigues'
  formula directly (no `Quat`), which is also cheaper in fixed-point.
- `VecN` dim conversions (`extend`, `truncate`, `from_homogeneous`,
  `to_homogeneous`, `project`, tuple `From`s): tiny; do in the VecN layer once
  all three structs exist (define the three structs first, in one commit).
- `Mat2::from_mat3(_minor)`, `Mat3::from_mat4(_minor)`, `Mat3::from_mat2`,
  `Mat4::from_mat3(_translation)`: tiny; integration pass.
- `Mat3::from_quat`, `Mat4::from_quat`, `Mat4::{from,to}_scale_rotation_translation`,
  `Quat::from_mat3/from_mat4/from_affine3`: integration pass; note
  `Quat::from_rotation_axes(Vec3, Vec3, Vec3)` is core-Quat and carries the real
  algorithm.

### 4.3 Layered implementation order (maximizing parallelism)

```
L0  Fixed scalar + math primitives           [blocking; own research note]
    ├─ tier A (needed by everything geometric): add/sub/mul/div/rem, neg, cmp, abs, signum, min/max/clamp,
    │          recip, sqrt, floor/ceil/round/trunc, mul_add, lerp & FloatExt, constants (PI, HALF, ...)
    ├─ tier B (rotations): sin, cos, sin_cos, atan2, acos_approx, tan
    └─ tier C (deferred): exp, exp2, ln, log2, powf, div_euclid, rem_euclid, copysign

L1  (parallel, no inter-dependencies once the 3+3 struct definitions are committed)
    ├─ BVec2, BVec3, BVec4                         (needs nothing)
    ├─ Vec2 core   (needs L0-A; angle methods need L0-B)
    ├─ Vec3 core   (same)
    ├─ Vec4 core   (same)
    ├─ IVec2/3/4, UVec2/3/4                        (needs only BVec + core integers; fully independent of L0)
    └─ test-vector generator (Rust side, see section 5)  (independent)

L2  (parallel; each needs only its VecN)
    ├─ Mat2 core   (Vec2)
    ├─ Mat3 core   (Vec3, + Vec2 for the 2D-homogeneous helpers)
    ├─ Mat4 core   (Vec4, Vec3)            — excluding projections/look_at (-> camera)
    ├─ Quat core   (Vec3, Vec4; L0-B)      — from_axis_angle, from_rotation_axes, from_rotation_arc,
    │                                        mul_quat, mul_vec3, conjugate, normalize, lerp, slerp, to_axis_angle
    └─ Swizzles for Vec2/Vec3/Vec4 (script-generated)

L3  (parallel)
    ├─ Cross-type integration: Vec3::{rotate_axis, rotate_towards, slerp}; MatN<->MatM conversions;
    │   Mat3/Mat4::from_quat; Quat::from_mat3/from_mat4; Mat4 TRS compose/decompose
    ├─ Affine2   (Mat2, Vec2, Mat3 conversions)
    ├─ Affine3   (Mat3, Vec3, Quat, Mat4 conversions)  + Quat::from_affine3
    └─ Euler     (EulerRot + from/to for Mat3, Quat, Mat4)

L4  (optional / late, parallel)
    ├─ camera::{rh,lh}::{view,proj}   (+ deprecated Mat4::perspective_* aliases if API parity is desired)
    ├─ Vec4 swizzles (372 methods), integer-vector swizzles
    ├─ tier-C element-wise functions (exp/ln/powf...)
    └─ glamx-like extensions for the physics engine: Rot2, Pose2, Pose3 (isometries),
        symmetric eigen-decomposition 2x2/3x3, SVD (needed by rapier/parry — see section 6)
```

Critical path: `L0-A -> Vec3 -> Mat3 + Quat -> Affine3 (-> Pose3)`. Everything
2D (`Vec2 -> Mat2 -> Affine2`) is an independent track and the cheapest
vertical slice to validate the approach end-to-end (scalar → vector → matrix →
transform → tests against reference vectors), as only `sin_cos`/`atan2` are
needed on top of tier A.

---

## 5. Test strategy

### 5.1 How glam tests are organized

- `tests/*.rs` — one integration-test file per concept: `vec2.rs` (2,551
  lines, 138 `glam_test!` blocks), `vec3.rs` (2,934 / 148), `vec4.rs`
  (2,981 / 134), `mat2.rs` (32), `mat3.rs` (38), `mat4.rs` (38), `quat.rs`
  (46), `affine2.rs` (24), `affine3.rs` (25), `camera.rs` (56), `float.rs` (6),
  `euler.rs` (exhaustive loops), 12 generated `swizzles_*.rs`.
- **Macro-parameterized**: tests are written once as `macro_rules!`
  (`impl_vec3_tests!`, `impl_vec3_signed_tests!`, `impl_vec3_float_tests!`,
  `impl_vec3_signed_integer_tests!`, `impl_vec3_unsigned_integer_tests!`,
  `impl_vec3_eq_hash_tests!`, `impl_vec3_{scalar_,}shift_op_tests!`,
  `impl_vec3_{scalar_,}bit_op_tests!`, `impl_vec3_*_try_from_tests!`,
  `impl_bvec3_tests!`, `impl_mat3_tests!`, `impl_quat_tests!`,
  `impl_affine3_tests!`, `impl_camera_tests!` ...) and instantiated in one
  `mod` per concrete type (`mod vec3 {..}`, `mod vec3a {..}`, `mod dvec3 {..}`,
  `mod ivec3 {..}` ...). This mirrors the template structure exactly: the
  macro layering (`base` → `signed` → `float` / `integer`) tells which test
  applies to which scalar family.
- `tests/support/macros.rs`: `glam_test!` (native + wasm-bindgen), `should_panic!`,
  `should_glam_assert!` (only active with the assert features),
  `assert_approx_eq!(a, b[, eps[, ctx]])` (default eps = `f32::EPSILON`),
  shared edge-case inputs `vec2_float_test_vectors!` / `vec3_float_test_vectors!`
  (axes, `(1, 1e-3 … 1e-16, 0)`, Pixar ONB pathological cases), the normalize
  test suite, wrapping/saturating/try_from helper macros.
- `tests/support.rs`: `FloatCompare` trait (`approx_eq`, `abs_diff`) implemented
  for every float type, `deg()` / `rad()` helpers.
- `tests/euler.rs`: for all 24 orders, iterates angles in [-180°, 180°] by 15°
  steps on three axes (25³ = 15,625 combos per order) and checks
  quat → euler → quat round-trips (`E_EPS = 2e-6` f32, `1e-8` f64) and
  Mat3/Mat4/Quat agreement, using a canonical-sign quaternion.
- Typical tolerances in the f32 tests: `1e-6` (most common), `1e-5`, `1e-3`
  (decompose, some slerp), `2e-7`/`5e-7`, exact equality for construction /
  ops on small integers-as-floats.
- Test names worth mirroring (quat): `test_rotation, test_from_scaled_axis,
  test_mul_vec3, test_angle_between, test_lerp, test_slerp,
  test_slerp_constant_speed, test_slerp_tau, test_slerp_negative_tau,
  test_slerp_pi, test_slerp_long, test_slerp_extrapolate,
  test_slerp_near_parallel, test_slerp_long_near_antipodal,
  test_rotate_towards, test_rotation_arc, test_to_axis_angle,
  test_is_near_identity_threshold`; (mat3): `test_mat3_det, test_mat3_inverse,
  test_mat3_transform2d, test_from_ypr, test_from_mat4_minor ...`.
- Benches (`benches/*.rs`, criterion + gungraun instruction counts) list the
  operations upstream considers performance-critical — a good seed list for
  Cairo step/gas benchmarks: mat mul, mat inverse, mat transform
  point/vector, quat mul quat, quat mul vec3, vec normalize/length/dot/cross,
  affine mul/inverse/transform.

### 5.2 What to port as-is

1. **Algebraic / exact tests** (construction, accessors, ops on small
   integers, min/max/clamp, cmp/masks/select, extend/truncate, swizzles,
   transpose, identity, mat/affine mul on integer-valued data,
   BVec tests, the entire integer-vector suites incl. checked/wrapping/
   saturating, manhattan/chebyshev). These are exactly representable in
   fixed-point → port with exact `==`.
2. **Property tests** with tolerance: `M * M⁻¹ ≈ I`, `q * q⁻¹ ≈ identity`,
   `normalize().length() ≈ 1`, `from_axis_angle` vs `Mat3::from_axis_angle`
   agreement, TRS compose→decompose round-trip, euler round-trips (on a
   coarser grid: 24 orders × 25³ is far too many steps for `snforge`; sample
   e.g. 45° steps or a fixed pseudo-random subset), slerp constant speed.
3. **Drop**: NaN/Inf tests (`test_nan`, `test_min_max_nan`, `test_clamp_nan`,
   `test_is_finite`), alignment/size tests (`test_align`, `test_mask_align16`),
   `test_fmt*` (unless `Display` is implemented), serde/bytemuck/rand tests,
   `Vec3A`/`D*` instantiations, sub-resolution normalize vectors (`1e-14`…),
   adapted rather than deleted where they encode real edge cases (tiny-vector
   normalization policy must get its *own* fixed-point tests).

### 5.3 Generating reference vectors from Rust

Build a small Rust crate `tools/refgen` (in the Cairo repo) depending on
`glam = "=0.33.8"` with `default-features = false, features = ["std", "f64",
"scalar-math"]`:

- **Use the `D*` (f64) types as the oracle.** 53-bit mantissa is far more
  precise than any practical fixed-point format (e.g. Q64.64 has 64 fractional
  bits but inputs/outputs within game ranges are still well resolved by f64 to
  ~1e-15 relative), so f64 results can be treated as "exact" and the *entire*
  measured discrepancy attributed to the fixed-point implementation. Note: in
  the f64 module `acos_approx` is the exact clamped `f64::acos`, so the oracle
  is exact for `angle_between`/`slerp` too; if the Cairo scalar layer ports the
  f32 degree-7 polynomial, budget its intrinsic approximation error (order
  1e-7…1e-6 rad) in the tolerance of those functions.
- `scalar-math` guarantees the scalar code path (the same one being ported),
  so operation order — and hence rounding behaviour — matches the port.
- Input generation: deterministic PRNG (fixed seed; `rand_xoshiro` is already
  glam's dev-dependency) over **ranges representative of the engine**
  (positions in ±1e3…1e4, unit vectors, unit quaternions, angles in ±2π,
  scales in [0.01, 100]) + the hand-picked edge cases from
  `vec{2,3}_float_test_vectors!` that are representable + axis-aligned /
  degenerate cases (parallel & anti-parallel vectors, 180° rotations,
  gimbal lock ±90°, singular matrices).
- **Quantize inputs first**: convert each f64 input to the fixed-point raw
  integer (round-to-nearest), convert back to f64, and feed *that* to glam.
  This removes input-quantization error from the comparison; the emitted
  vector stores raw integers for inputs and expected outputs.
- Output format: one Cairo test module per type/function family, generated
  (`#[test] fn test_vec3_cross_ref() { let cases: Span<(…)> = array![…].span(); … }`),
  or a JSON/CSV consumed by a generator script. Keep ~16–64 cases per function
  to bound `snforge` step counts; keep a larger corpus for an off-chain
  differential fuzzer (Rust harness running the Cairo code through
  `cairo-run`/`scarb execute`, or a bit-exact Rust model of `Fixed`).
- **Tolerances** (expressed in ULPs of `Fixed`, `u = 2^-frac_bits`):
  - exact (0 ULP): add/sub/neg/min/max/clamp/cmp/abs/floor/ceil/trunc/round, swizzles, integer vectors;
  - ≤ 1–2 ULP per multiplication: `dot`, `cross`, `mul_vecN` → budget `dim` … `2·dim` ULP; matrix product `2·dim` ULP per entry;
  - `sqrt`, `length`: 1–2 ULP (if computed from a wide accumulator);
  - `normalize`: a few ULP absolute per component;
  - `sin/cos/atan2/acos_approx`: set by the scalar implementation (target ≤ 1e-6…1e-7 absolute, to be at least as good as glam-f32, whose own tests use 1e-6);
  - `inverse`, `determinant`, `to_scale_rotation_translation`, `slerp`: **relative / conditioned** tolerance — scale by `1/|det|` or use `1e-4`…`1e-5` absolute on well-conditioned inputs (glam itself uses `1e-3`…`1e-5` here);
  - rule of thumb for acceptance vs f32-glam parity: the fixed-point port should meet glam's own f32 test tolerances (mostly `1e-6`) on the representable input ranges, which requires ≥ ~24–32 fractional bits.
- Bit-exact mode (optional, stronger): implement the `Fixed` arithmetic model
  in Rust (same rounding), re-implement nothing else — instantiate the ported
  algorithms through a thin generic shim — and require **exact equality** with
  Cairo. This catches transcription bugs that tolerance-based tests miss and
  doubles as the off-chain simulator the game client will need anyway for
  client-side prediction.

---

## 6. The "hot" subset for game physics

> Evidence level: crates.io dependency metadata was checked on 2026-09-20
> (`rapier3d 0.35.3`: `glamx ^0.3`, `nalgebra ^0.35`, `simba`, `wide`,
> `parry3d ^0.30.2`; `parry3d 0.31.1`: `glamx ^0.3`, `simba`, no direct
> nalgebra). glamx 0.3.1 (<https://github.com/dimforge/glamx>) describes itself
> as "Extensions for glam: Pose2, Pose3, Rot2, and matrix utilities" and lists
> `Rot2/DRot2`, `Rot3` (= glam quaternions), `Pose2`, `Pose3`, `MatExt`,
> `SymmetricEigen2/3`, `Svd2/3`. The rapier/parry/bevy *source* was not
> inspected in this task; the usage ranking below is from prior knowledge of
> those code bases and should be validated in the rapier/parry research notes.

### 6.1 Priority tiers

**Tier 1 — used in every narrow-phase / solver / integrator inner loop**

| Type | Operations |
|---|---|
| `Vec3` (3D) / `Vec2` (2D) | `+ - * /` (vec and scalar), `neg`, `dot`, `cross` (`perp_dot`, `perp` in 2D), `length`, `length_squared`, `normalize`, `try_normalize`/`normalize_or_zero`, `normalize_and_length`, `distance(_squared)`, `min`, `max`, `abs`, `clamp`, `min/max_element`, `min/max_position` (SAT / support-axis selection), `lerp`, `any_orthonormal_pair` (contact tangent basis), `project_onto(_normalized)`, `reject_from`, `clamp_length_max` (velocity limits), indexing, `ZERO/X/Y/Z`, `cmp*` + `select` (AABB tests) |
| `Quat` (3D) / `Rot2`-like unit complex or `Vec2::rotate`, `Mat2::from_angle` (2D) | `mul_quat`, `mul_vec3`, `conjugate/inverse`, `normalize` (every integration step), `from_axis_angle`, `from_scaled_axis` (angular-velocity integration: `q' = from_scaled_axis(ω·dt) * q`), `to_scaled_axis`/`to_axis_angle` (joint errors), `dot`, `IDENTITY`, `lerp` (nlerp), `from_rotation_arc` |
| `Mat3` (3D) / `Mat2` (2D) | `mul_vec3`, `mul_mat3`, `transpose`, `from_quat` (world-space inertia `R·I⁻¹·Rᵀ`), `from_diagonal`, `inverse`/`try_inverse` (inertia tensor, constraint effective mass), `determinant`, `add/sub`, `mul_scalar`, `from_cols`, `col/row`, `mul_transpose_vec3`, `abs` (OBB→AABB extents: `abs(R) · half_extents`), skew-symmetric/cross-matrix (not in glam — extension) |
| Isometry (`Pose3` = `Quat` + `Vec3`, `Pose2` = rot + `Vec2`) — **not in glam**; nearest glam type is `Affine3`/`Affine2` | compose (`*`), `inverse` (rigid), `inv_mul` (`a⁻¹·b`, relative pose — the single most used op in collision detection), `transform_point`, `transform_vector`, `inverse_transform_point/vector`, `lerp_slerp` (CCD / interpolation) |

**Tier 2 — broad-phase, shapes, queries, utilities**

- AABB math: component-wise `min/max`, `cmple/cmpge().all()`, `midpoint`, `abs`, half-extents; `UVec/IVec` for grid / spatial-hash cells (`floor` → `as_ivec3`).
- `Affine3`/`Affine2` (`from_scale_rotation_translation`, `transform_point3`, `transform_vector3`, `inverse`, `mul`) — bevy `GlobalTransform` is an `Affine3A`; bevy `Transform` is `{translation: Vec3, rotation: Quat, scale: Vec3}` and leans on `Quat * Vec3`, `Mat4/Affine3A::from_scale_rotation_translation`, `to_scale_rotation_translation`, `Quat::from_rotation_arc`, `look_to/look_at`, `Quat::from_euler/to_euler`, `slerp`.
- `Vec3::angle_between`, `Vec2::angle_to`/`to_angle`/`from_angle`/`rotate`, `reflect` (kinematic bounce), `move_towards`, `rotate_towards`.
- `Vec4`, `Mat4`: mostly rendering (projection, view); physics needs them only for `Quat`'s internals (scalar backend delegates to `Vec4`) and TRS conversions.
- `EulerRot`: authoring / debugging convenience.

**Tier 3 — rendering / shading / rarely used in physics**

`camera` projections, `refract`, `smoothstep`, `step`, `fract*`, element-wise
`exp/ln/powf/sin/cos`, `Vec4` swizzles, shift/bit ops on integer vectors,
narrow integer widths (i8/u8/i16/u16), `slerp_long`, `is_near_identity`.

### 6.2 Consequences for the plan

1. The physics-critical vertical slice is **`Fixed` → `Vec3` → `Quat` + `Mat3`
   → `Pose3`/`Affine3`** (and `Vec2` → `Mat2`/`Rot2` → `Pose2` for a 2D
   engine, which is substantially cheaper to prove and a good first
   milestone). This is exactly the critical path of section 4.3.
2. glam has **no isometry type**; rapier/parry get it from `glamx`
   (`Pose2/Pose3`, `Rot2`). Plan a `glamx.cairo`-style extension module early
   (L4 above, but schedule it right after L3 for the physics track): `Rot2`
   (unit complex: `cos`, `sin`), `Pose2`, `Pose3` with `inv_mul`, rigid
   `inverse`, plus `Mat3` helpers used by rigid-body dynamics (cross-product
   matrix, symmetric 3×3 "sdp" matrices for inertia, symmetric
   eigen-decomposition for principal inertia axes; SVD only if a consumer
   appears).
3. Since rapier ≥ 0.3x/parry ≥ 0.3x sit on glam+glamx, the separate
   **nalgebra port can be scoped down** to what rapier still pulls from
   nalgebra (dynamic-size `DMatrix/DVector` and LU/Cholesky for multibody
   joints), which a first provable engine can skip entirely (no multibodies).
4. For gas/step budgeting, the ops to benchmark first (they dominate a
   simulation step): `Vec3` dot/cross/normalize, `Quat::mul_quat`,
   `Quat::mul_vec3`, `Quat::normalize`, `Mat3::mul_vec3`, `Mat3::mul_mat3`,
   `Mat3::inverse`, `Pose3` compose / `inv_mul` / transform_point. The
   dominant scalar costs are fixed-point `mul` (one wide multiply + rescale),
   `div`, and `sqrt` — design `dot`, `cross`, `mul_mat3`, `mul_quat` around
   **wide accumulation with a single rescale per output component** instead of
   composing scalar `mul`s (cf. 3.3 item 2), which is the main structural
   optimization available to a fixed-point glam that the float original does
   not need.

---

## Appendix A — files to keep open while porting

| Cairo module | Reference file(s) in glam-rs 0.33.8 |
|---|---|
| scalar math | `src/f32/math.rs`, `src/float.rs`, `src/f32/float.rs` |
| `Vec2` | `src/f32/vec2.rs` |
| `Vec3` | `src/f32/vec3.rs` |
| `Vec4` | `src/f32/scalar/vec4.rs` |
| `BVec*` | `src/bool/bvec2.rs`, `bvec3.rs`, `bvec4.rs` |
| `IVec*`, `UVec*` | `src/i32/ivec{2,3,4}.rs`, `src/u32/uvec{2,3,4}.rs` |
| `Mat2` | `src/f32/scalar/mat2.rs` |
| `Mat3` | `src/f32/mat3.rs` |
| `Mat4` | `src/f32/scalar/mat4.rs` |
| `Quat` | `src/f32/scalar/quat.rs` |
| `Affine2`, `Affine3` | `src/f32/affine2.rs`, `src/f32/affine3.rs` |
| euler | `src/euler.rs` |
| swizzles | `src/swizzles/vec_traits.rs`, `vec2_impl.rs`, `vec3_impl.rs`, `scalar/vec4_impl.rs`; generator logic in `templates/swizzle_*.tera` |
| camera | `src/camera/camera_impl.rs`, `src/camera/{rh,lh}/{view,proj}.rs` |
| differences between scalar families | `templates/vec.rs.tera` (`is_float`, `is_signed` conditionals) |
| tests | `tests/{vec2,vec3,vec4,mat2,mat3,mat4,quat,affine2,affine3,euler,float,camera}.rs`, `tests/support/macros.rs`, `tests/support.rs` |

## Appendix B — approximate porting volume

Counting scalar-path public methods only, after the drops of section 3.1
(no NaN/finite, no `as_*` to dropped types, no `*3a`, no slices-by-reference):

| Module | Methods (approx.) | Operator impls (Cairo, approx.) |
|---|---:|---:|
| `Vec2` | ~85 | ~25 |
| `Vec3` | ~95 | ~25 |
| `Vec4` | ~80 | ~25 |
| `BVec2/3/4` | 8 × 3 | 4 × 3 |
| `IVec2/3/4` + `UVec2/3/4` | ~55 × 3 + ~48 × 3 | ~20 × 6 (without shifts) |
| `Mat2` | ~32 | ~10 |
| `Mat3` | ~45 | ~10 |
| `Mat4` | ~45 (+17 deprecated view/proj aliases → camera) | ~10 |
| `Quat` | ~40 | ~10 |
| `Affine2` | ~20 | ~4 |
| `Affine3` | ~25 | ~4 |
| euler | 24-variant enum + 2 × 3 conversions | — |
| swizzles | 28 + 123 + 372 (generated) | — |
| camera | 24 view + 26 proj (generated-style) | — |
| **Total (excl. swizzles/camera)** | **~750 methods** | **~250 impls** |
