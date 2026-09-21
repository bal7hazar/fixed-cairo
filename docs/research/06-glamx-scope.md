# 06 - Scope of the physics extensions: `glamx`, parry, rapier (task P1)

Date: 2026-09-21. Question: `docs/research/01-glam-rs-analysis.md` (item 7) and `00-synthesis.md`
(section 4) inferred, from crates.io metadata only, that rapier3d 0.35 and parry3d 0.31 build on
Dimforge's `glamx` instead of nalgebra, so that task P1 of `docs/PLAN.md` (port the `glamx`
extensions on top of `glam.cairo`) would replace most of the planned nalgebra port. This report
checks that against the actual sources and scopes the work.

Legend: **[V]** = verified in the cloned sources (file:line given), **[I]** = inferred (reasoning,
or arithmetic on the committed `gas/*.snap`), never measured on the new code.

## 0. Verdict

**Confirmed for parry, partially refuted for rapier, and the useful scope is smaller than the
research assumed.**

1. `glamx` exists (`github.com/dimforge/glamx`, v0.3.1) and contains exactly `Rot2`, `Rot3` (a
   type alias of `glam::Quat`), `Pose2`, `Pose3`, `MatExt`, `SymmetricEigen2/3`, `Svd2/3`
   (2 525 non-test lines, macro-generated for f32 / f64 / `A` variants). **[V]**
2. **parry 0.31.1 has no nalgebra dependency at all**: no manifest mentions it (the only hit is a
   commented-out `[patch]` line, `parry/Cargo.toml:86`), and `grep` finds no `na::` in
   `parry/src` outside comments and doc tests. Its whole public math is `glamx` re-exports
   (`parry/src/math/mod.rs:26-41`). **[V]**
3. **rapier 0.35.3 still depends on nalgebra, unconditionally** (`rapier/Cargo.toml:68`,
   `crates/rapier3d/Cargo.toml:125-126`, except on spirv). Its scalar geometry is `glamx`, but its
   SIMD (SoA, 4-lane) solver, the multibody joints and the contact/joint constraints that touch
   multibodies are written against nalgebra generics and dynamic matrices (section 4). **[V]**
4. Only a fraction of `glamx` matters for a rigid-body step. **Hot**: `Pose2/Pose3` (composition,
   `inv_mul`, `inverse_transform_point`, `transform_point`), `Rot2`, and `Rot3` = `Quat` (already
   ported). **Setup-time only**: `SymmetricEigen3` (collider / compound mass properties, OBB,
   convex-hull seeding, soft bodies). **Unused by parry and rapier**: `Svd2`, `Svd3`,
   `SymmetricEigen2` (aliased, never called), `Pose3::look_at_rh`, `face_towards`, `Rot2::powf`,
   `rotate_towards`. **[V]**
5. The physics-hot *matrix* code is **not in `glamx`**: it lives in parry/rapier
   (`SdpMatrix2/3`, world inverse inertia `R D R^T`, `gcross`, cross-product matrices,
   `kronecker`, `absolute_transform_vector`). A P1 that only mirrors `glamx` misses the most
   expensive per-step matrix operation (section 3.4, 6.1).
6. Recommendation: a new workspace package `glamx` (not `glam/src/ext`), five porter tasks for the
   rigid-body core plus one low-priority (`eigen3`), and **no** SVD (section 6).

## 1. Sources, versions

| repo | commit | version | how depends on glamx / nalgebra |
|---|---|---|---|
| `dimforge/glamx` | `f530eef` "Release v0.3.1 (#8)" | 0.3.1 | `glam ^0.33.7`, `simba 0.10`, `num-traits`; `nalgebra 0.35` optional (`Cargo.toml`) |
| `dimforge/parry` | `3383f51` "Release v0.31.1" | 0.31.1 | `glamx 0.3` (`parry/Cargo.toml:45`), `simba 0.10.1`; **no nalgebra** |
| `dimforge/rapier` | `28d0ba9` "feat: add support for soft-bodies (#1010)" | 0.35.3 (`Cargo.toml:48`) | `glamx 0.3.1` (`:69`) **and** `nalgebra 0.35` (`:68`), `simba`, `wide` |

Shallow clones in `/tmp/p1/{glamx,parry,rapier}`, default branches. rapier's HEAD is a few commits
past the 0.35.3 tag (soft bodies / FEM landed); the rigid-body code paths cited below are
unchanged by that. Sizes: parry `src` 79 506 lines / 344 files, rapier `src` 79 876 / 239.

## 2. What `glamx` contains (question 1) [V]

Everything is in `glamx/src/` (`lib.rs:63-125` lists the public surface). `pub use glam::*` is
re-exported, so users write `glamx::Vec3`. Numbers below are per scalar flavour (the Rust macros
stamp out f32, f64 `D*` and `A` copies; Cairo has one).

| module | public types | wraps (glam) | `pub fn` | operator / `From` impls | notes |
|---|---|---|---:|---:|---|
| `rot2.rs` (546 lines) | `Rot2`, `DRot2` | `Vec2`, `Mat2` | 29 | 11 | struct `{ re, im }` = unit complex (`rot2.rs:18`) |
| `rot3.rs` (15) | `Rot3`, `DRot3` | `Quat`, `DQuat` | 0 | - | `pub type Rot3 = glam::Quat` (`rot3.rs:6`) |
| `pose2.rs` (559) | `Pose2`, `DPose2` | `Rot2`, `Vec2`, `Vec3`, `Mat2`, `Mat3` | 20 | 21 | `{ rotation: Rot2, translation: Vec2 }` |
| `pose3.rs` (675) | `Pose3`, `Pose3A`, `DPose3` | `Quat`, `Vec3`/`Vec3A`, `Mat4`, `camera` | 22 | 25 | `{ rotation: Quat, translation: Vec3 }`; **`Pose3` (only) has a `padding: u32` field** for bytemuck/spirv (`pose3.rs:431-440`) |
| `matrix_ext.rs` (255) | trait `MatExt` | `Mat2`, `Mat3`, `Mat3A`, `DMat2`, `DMat3` | 7 (trait) | - | **not implemented for `Mat4`** |
| `eigen2.rs` (141) | `SymmetricEigen2` | `Mat2`, `Vec2` | 4 | 2 | closed form |
| `eigen3.rs` (409) | `SymmetricEigen3`, `SymmetricEigen3A`, `DSymmetricEigen3` | `Mat3`, `Vec3` | 6 (+1 private) | 6 | Eberly closed form (acos / cos) |
| `svd2.rs` (186) / `svd3.rs` (296) | `Svd2`, `Svd3` (+`A`, `D`) | `Mat2` / `Mat3` | 3 / 3 | 2 / 6 | 3x3 via `SymmetricEigen3(A^T A)` |

Tests: 56 `#[test]` in total (`rot2` 13, `pose2` 10, `pose3` 9, ...), all with f32 / f64 tolerances
(`1e-3` .. `1e-10`, `assert_relative_eq!`): **glamx is a semantic oracle, not a bit-exact one**
(same status as glam-rs in DESIGN section 5). It can be linked into `tools/refgen` as an
f64 oracle (`DRot2`, `DPose2`, `DPose3`, `DSymmetricEigen3`): its `glam ^0.33.7` requirement is
compatible with the exact `=0.33.8` pin **[I]**.

### 2.1 Item list

* **`Rot2`** (`rot2.rs`): consts `IDENTITY`; ctors `from_cos_sin_unchecked` (`:33`),
  `from_matrix_unchecked`, `identity`, `new` / `from_angle` (`sin_cos`), `from_mat`,
  `from_mat_unchecked`, `from_rotation_arc`; accessors `angle` (`atan2`), `cos`, `sin`; algebra
  `inverse` (conjugate), `length`, `length_squared`, `length_recip`, `normalize` (identity when
  `len <= EPSILON`, `:121`), `normalize_mut`, `is_finite`, `is_nan`, `is_normalized`,
  `transform_vector`, `inverse_transform_vector`, `to_mat`; interpolation `slerp` (`self *
  new(angle_between * t)`, `:213`), `powf`, `rotate_towards`, `angle_between`, `dot`, `lerp`;
  operators `Rot2 * Rot2` (complex product), `Rot2 * Vec2`, `MulAssign`, `Default`.
* **`Pose2`** (`pose2.rs`): `IDENTITY`, `identity`, `from_translation`, `translation(x, y)`,
  `from_rotation`, `rotation(angle)`, `from_parts`, `new(translation, angle)`,
  `prepend_translation`, `append_translation`, `inverse`, `inv_mul` (**unfused**:
  `self.inverse() * rhs`, `:115`), `transform_point`, `transform_vector`,
  `inverse_transform_point`, `inverse_transform_vector`, `lerp`, `is_finite`, `is_nan`, `to_mat3`,
  `from_mat3`; operators `Pose2 * Pose2`, `Pose2 * Vec2` (point), `Rot2 * Pose2`, `Pose2 * Rot2`
  (+ `&` variants), `From<Rot2>`, `From<(Vec2, real)>` and back.
* **`Pose3`** (`pose3.rs`): same set with `Quat` (`new(translation, axisangle)` and
  `rotation(axisangle)` use `Quat::from_scaled_axis`), `inv_mul` **fused** (`:134`),
  `to_mat4`, `from_mat4` (via `Mat4::to_scale_rotation_translation`, heavy), plus `look_at_rh`
  (`:227`) and `face_towards` (`:249`), which call `glam::camera::{rh,lh}::view::look_at_quat`.
* **`MatExt`** (`matrix_ext.rs:24-59`): `abs`, `try_inverse` (returns `None` when
  `|det| < EPSILON`, `:76`), `swap_cols`, `swap_rows`, `symmetric_eigen`, `symmetric_eigenvalues`,
  `svd`.
* **`SymmetricEigen2`**: `new`, `reverse`, `eigenvalues`, `eigenvector`. **`SymmetricEigen3`**:
  `new`, `reverse`, `eigenvalues`, `eigenvector1/2/3`. **`Svd2/3`**: `new`, `from_matrix`,
  `recompose`.

### 2.2 Quirks that matter for a fixed-point port [V]

| where | quirk | consequence in Cairo |
|---|---|---|
| `eigen2.rs:71` | `eigenvector` divides by the **off-diagonal** `mat.y_axis.x`: a diagonal matrix gives NaN in f32 | Cairo would panic. Another reason not to port `SymmetricEigen2` without a consumer |
| `eigen3.rs:63-118` | closed form needs `acos`, 2x `cos`, `sqrt`, division by `p`; branch on `p1 == 0` (diagonal) | ~3 transcendentals, all Tier B (ported), but the thresholds need re-derivation |
| `eigen3.rs:144` | `d_max < 1e-20` (all eigenvalues equal) | `d_max` is a sum of squares and `1e-20` is below one squared Q32.32 ULP (`2^-64 = 5.4e-20`), so as written the test degenerates to `d_max == 0`: re-derive it in raw ULPs |
| `svd3.rs:67`, `svd2.rs:56` | `1e-10` thresholds | same, but unused: no consumer |
| `matrix_ext.rs:76,137` | `try_inverse` singular threshold `f32::EPSILON` | differs from the glam.cairo `try_inverse` (`det == 0` raw, DESIGN section 3): to be documented if ever ported |
| `pose3.rs:431-440` | `padding: u32` field on `Pose3` | drop (Deviation); no bytemuck / spirv |
| `pose2.rs:115`, `rot2.rs:213` | `Pose2::inv_mul` unfused; `Rot2::slerp` = `atan2` + `sin_cos` (~60 k gas [I]) | fuse `inv_mul`; keep `slerp` semantics but tier 2 |
| `pose3.rs:176` | `Pose3::lerp` uses `Quat::slerp` (122 180 gas in `gas/quat.snap`) | tier 2; an `nlerp` variant is what parry uses (`parry/src/query/sweep_toi/sweep.rs:34`) |
| whole crate | `is_finite` / `is_nan`, `approx`, serde / rkyv / bytemuck / nalgebra glue, `&T * &U` operator variants, f32 <-> f64 `From` | dropped (DESIGN section 1), reference-operator variants are meaningless for `Copy` structs passed by value |

## 3. What parry and rapier actually use (question 2)

Method: `grep -Ew` over `parry/src` and `rapier/src` (excluding `crates/`, `examples`, `tests`,
benches). Counts include in-file `#[cfg(test)]` modules and skip `//` / `///` lines (so they are
lower than a raw `grep -c`, which is quoted where it differs). 2D / 3D split: a
small script attributes each line to `dim2` / `dim3` when it sits in a `#[cfg(feature =
"dimN")]` item or in a module declared under such a `cfg` in its parent `mod.rs`; "shared" =
compiled in both dimensions or ungated. **It is a rough split**: the same source tree builds
`parry2d` and `parry3d` / `rapier2d` and `rapier3d`, so "shared" code is 2D *and* 3D.
Numbers are `2D-only / 3D-only / shared`. [V]

### 3.1 Counts

| item | parry | rapier |
|---|---|---|
| `Pose` (type alias of `Pose2` / `Pose3`) | 50 / 109 / 440 (599 code hits, 940 with doc comments) | 6 / 23 / 215 |
| `Rotation` (alias of `Rot2` / `Rot3`) | 13 / 23 / 18 | 15 / 21 / 73 |
| `inv_mul` | 0 / 2 / 27 (34 with doc comments) | 0 / 0 / 10 |
| `inverse_transform_point` | 6 / 11 / 25 | 0 / 4 / 15 |
| `inverse_transform_vector` | 3 / 1 / 2 | 0 / 0 / 0 |
| `transform_point` | 20 / 14 / 18 | 0 / 8 / 8 |
| `transform_vector` | 1 / 0 / 0 | 0 / 16 / 32 |
| `from_parts` | 7 / 5 / 11 | 0 / 0 / 12 |
| `from_translation` | 0 / 1 / 19 | 0 / 2 / 21 |
| `prepend_translation` / `append_translation` | 0 / 0 / 4 / 0 / 0 / 1 | 1 / 1 / 8 / 1 / 1 / 7 |
| `.inverse()` (all types) | 4 / 16 / 86 | 2 / 5 / 34 |
| `from_angle` (2D rotation) | 3 / 0 / 0 | 5 / 0 / 0 (23 with doc comments) |
| `from_scaled_axis` / `to_scaled_axis` (3D) | 0 / 1 / 0 each | 0 / 4 / 0 each |
| `perp_dot` (`Vec2`) | 25 / 6 / 3 | 9 / 0 / 0 |
| `.cross(` (`Vec3`) | 0 / 64 / 1 | 0 / 58 / 1 |
| `gcross` (rapier's own trait) | 0 / 0 / 6 | 4 / 27 / 46 |
| `symmetric_eigen` / `symmetric_eigenvalues` (glamx) | 4 call sites, see 3.3 | 1 call site, see 3.3 |
| `MatExt` imports | 4 files | 1 file (`soft_element_linalg.rs:3`) |
| `Svd2`, `Svd3`, `.svd(` | **0** | **0** |
| `Pose3::look_at_rh`, `face_towards`, `slerp`, `rotate_towards` | **0** | **0** |
| `EulerRot` | 1 (a test, `aabb_triangle.rs:53`) | 0 |

`glamx` type names outside the aliases: 12 code lines in parry (`math/mod.rs` 6, `transformation/utils.rs`
6) and 4 in rapier (`rigid_body_components.rs` 2, `joint_constraint_helper.rs` 2). Everything else goes
through the dimension-agnostic aliases `Pose`, `Rotation`, `Vector`, `Matrix` (`Vector`: 4 298
parry + 1 760 rapier raw hits).

### 3.2 The hot subset of a rigid-body step (ranking) [V] for the call sites, [I] for the ranking

1. **`Pose` composition and relative pose**: `inv_mul` is the relative-pose primitive of collision
   detection, taken for every collider pair (44 raw hits in total; `transform_point` is the most
   frequent `Pose` method, 130 raw hits) (`rapier/src/geometry/narrow_phase/pair_update.rs:126,318`,
   `intersections.rs:128`, `pipeline/physics_world.rs:719`, `query_pipeline.rs:563`,
   `dynamics/ccd/ccd_solver.rs:297-298`, `control/character_controller.rs:266,520,935`;
   plus 29 parry code sites).
2. **`inverse_transform_point` / `transform_point`**: contact anchors into body frames
   (`solver/contact_constraint/contact_with_coulomb_friction.rs:306-307`,
   `contact_with_twist_friction.rs:295-314`, `generic_contact_constraint.rs:356`,
   `solver/solver_body.rs:280`), shape queries (parry, ~135 hits).
3. **`transform_vector`** (rotate a vector by a `Pose` / `Rotation`): 48 rapier hits.
4. **Angular velocity integration**: `RigidBodyVelocity::integrate`
   (`rapier/src/dynamics/rigid_body_components.rs:872-887`) = `append_translation(-com)`,
   `append_rotation(angvel * dt)`, `append_translation(com + linvel * dt)`. `append_rotation` is
   `Rotation::from_scaled_axis(w) * pose` in 3D and `Rotation::from_angle(w) * pose` in 2D
   (`rapier/src/utils/pos_ops.rs:125-137`). The solver substeps use the trig-free
   `integrate_linearized` (`rigid_body_components.rs:889-921`): 2D `(cos - w sin, sin + w cos)`
   then `Rot2::from_cos_sin_unchecked` + `normalize_mut` (`:896-900`); 3D `Quat::from_xyzw(hang, 1) * q` then
   `normalize`. That path needs exactly `Rot2 { re, im }` with public fields and
   `from_cos_sin_unchecked`.
5. **Rotation to matrix**: `Matrix::from_quat` (3D) / `Rot2::to_mat` (2D): joint bases
   (`joint_constraint_helper.rs:103,157`), `absolute_transform_vector`
   (`parry/src/utils/isometry_ops.rs:11-22`: `abs(R) * v`, the AABB-of-rotated-box kernel), and
   world inertia (3.4).
6. **Constructors**: `from_parts` (29 parry + 13 rapier hits), `from_translation` (20 + 23),
   `Pose::IDENTITY` / `identity()` (60 + 29), `Pose3::new` / `rotation` (axis-angle), `Pose2::new`.
7. Rare: `Pose::lerp` (1 rapier call, `soft_constraint_prepare.rs:72`), `to_mat3/4`, `from_mat*`
   (0 hits), tuple `From`s.

### 3.3 Where symmetric eigen-decomposition is used (setup, not the step) [V]

| site | what | when |
|---|---|---|
| `parry/src/mass_properties/mass_properties.rs:214-232` (`with_inertia_matrix`, 3D) | diagonalise a full inertia tensor into principal values + frame; fixes handedness with `swap_cols(1, 2)` | called from trimesh / voxel mass properties (`mass_properties_trimesh3d.rs:33`, `mass_properties_voxels.rs:204`) **and from `MassProperties::add`, `sub`, `sum`** (`mass_properties.rs:431,484,562`): i.e. every time a compound body's mass properties are (re)built |
| `parry/src/utils/obb.rs:10` | OBB of a point cloud (covariance eigenvectors) | shape construction |
| `parry/src/transformation/convex_hull3/initial_mesh.rs:50` | seed simplex of the 3D convex hull | shape construction |
| `parry/src/transformation/voxelization/voxel_set.rs:1086` | eigenvalues of a covariance matrix | voxelization |
| `rapier/.../soft_element_linalg.rs:69` | `symmetric_eigenvalues().max_element()` | soft bodies only |
| `rapier/.../soft_element_linalg.rs:11-66` | **rapier's own cyclic-Jacobi `symmetric_eigen`** (8 sweeps; a test named `symmetric_eigen_handles_degenerate_matrices`, `test.rs:354`, hints at why glamx's closed form is not used [I]); used by `soft_neo_hookean.rs:120,139`, `tearing_crack.rs:255` | soft bodies only |
| `rapier/.../soft_body_cluster.rs:782` | **nalgebra** `Matrix3::symmetric_eigen` | soft bodies only |

No rigid-body step, no contact solve, no joint solve, no CCD sweep calls an eigen-decomposition.
2D never calls one (`SymmetricEigen2` is only aliased at `parry/src/math/mod.rs:210-213`).

### 3.4 Cross-product matrices, inertia transforms, angular integration: where they really are

| need | where it is implemented | in `glamx`? |
|---|---|---|
| world inverse inertia `R D R^T` (3D) | `MassProperties::world_inv_inertia`, `parry/src/mass_properties/mass_properties.rs:259-271`: `Matrix::from_quat(rot * frame)`, transpose, scale the 3 columns by `inv_principal_inertia`, `lhs * rhs`, then `SdpMatrix3::from_sdp_matrix` (recomputed at every position sync, `rapier/src/dynamics/rigid_body_components.rs:555`) | no |
| symmetric 3x3 storage + ops | `parry::utils::SdpMatrix2/3` (`parry/src/utils/sdp_matrix.rs`, 385 lines): `new`, `zero`, `diagonal`, `add_diagonal`, `inverse_unchecked`, `from_sdp_matrix`, `mul_vec`, `mul_mat`, `quadform` (`M^T S M`), `quadform3x2`, `Add`, `Mul<real>`, `Mul<Vec3>`. `AngularInertiaOps` (`rapier/src/utils/angular_inertia_ops.rs`) adds `inverse` (adjugate, `det == 0` -> zero), `transform_vector`, `into_matrix`. 2D angular inertia is a plain scalar. 37 hits in parry + rapier (`SdpMatrix3`) | **no** |
| angular acceleration `I^-1 * torque` | `RigidBodyForces::integrate`, `rigid_body_components.rs:1037-1051` | no (uses `SdpMatrix3 * Vec3`) |
| cross-product matrix, `gcross`, `kronecker`, orthonormal basis | `rapier/src/utils/{cross_product,cross_product_matrix,orthonormal_basis}.rs`, `parry/src/math/vector_ext.rs` (`kronecker`, `angle`, `ith`, `vget`), `parry/src/math/mod.rs:226` (`orthonormal_subspace_basis`) | no |
| quaternion differentials `diff_conj1_2` (joint Jacobians) | `rapier/src/utils/rotation_ops.rs:17-33` (`RotationOps`) | no |
| angular velocity integration | `RigidBodyVelocity::integrate` (`rigid_body_components.rs:872`) / `integrate_linearized` (`:889`, `:908`) | uses `glamx` `Pose::append_*`, `Rot2::from_cos_sin_unchecked`, `Quat::from_scaled_axis` |

Consequence: `SdpMatrix3` and its `R D R^T` kernel are, by volume of use, **more important for a
rigid-body step than every `glamx` matrix item combined**, and they are absent from `glamx`.

## 4. What parry / rapier still take from nalgebra (question 3) [V]

**parry: nothing** (section 0, point 2). It does keep `simba` (`ComplexField` / `RealField` for
scalar `sqrt`, `sin_cos`, ...) and `wide` (via simba) for its SIMD BVH; neither has a Cairo
counterpart to port (`fixed` covers the scalar functions).

**rapier**: `nalgebra` is a hard dependency (`Cargo.toml:68`, macros feature; on spirv it is
dropped and only "the subset of its API that doesn't require nalgebra" remains,
`crates/rapier3d/Cargo.toml:122-126`). Used for:

| feature / module | nalgebra items | volume |
|---|---|---|
| SIMD SoA solver: `SimdVector<N>`, `SimdAngVector<N>`, `SimdPoint<N>`, `SimdPose<N> = Isometry{2,3}<N>`, `SimdRotation<N> = UnitComplex / UnitQuaternion<N>`, `SimdMatrix<N>`, `SimdRealField` (`rapier/src/lib.rs:186-228`) | `Vector2/3`, `Point2/3`, `Isometry`, `UnitComplex`, `UnitQuaternion`, `Matrix2/3` over the lane type `SimdReal = simba::simd::WideF32x4` (`parry/src/lib.rs:92`) | 34 rapier files mention `SimdReal` / `SIMD_WIDTH` (288 `SimdReal` hits), `Isometry2/3`, `UnitComplex`, `UnitQuaternion` (16 code lines: `lib.rs` 4, `utils/pos_ops.rs` 8, `utils/rotation_ops.rs` 4, `utils/scalar_type.rs` 4). **Meaningless without SIMD: in Cairo the lane type is `Fixed`, `SimdVector<Fixed>` = `Vec3`** [I] |
| multibody joints (`dynamics/joint/multibody_joint/`, 4 329 lines) | `DVector`, `DMatrix`, `DVectorView(Mut)`, `OMatrix`, `SMatrix`, `SVector`, `Dyn`, **`LU<Real, Dyn, Dyn>`** (`multibody.rs:113,119,160,1045-1050`), `StorageMut` | `multibody.rs` alone: 85 hits; `DVector` family 118 hits in 15 files |
| generic (multibody-aware) constraints (`solver/contact_constraint/generic_contact_constraint*.rs`, `solver/joint_constraint/generic_joint_constraint*.rs`, `velocity_solver.rs`, `solver_body.rs`) | `Jacobian = Matrix{3,6}xX`, `JacobianView(Mut)`, `DVector` (`rapier/src/lib.rs:262-303`) | 27 `Jacobian` hits |
| `alloc` feature | `DVector`, `DMatrix` aliases (`lib.rs:246-249`) | gate of all the above |
| soft bodies (new in HEAD, `dynamics/soft_body/`, `solver/soft_constraint/`, `solver/soft_fem/`: 2 506 lines in `soft_fem` alone) | `Matrix3::symmetric_eigen` (`soft_body_cluster.rs:782`); the FEM solver has **its own skyline Cholesky** (`soft_fem_skyline.rs`), it does not use `nalgebra::Cholesky` | small |
| misc | `na::Vector1` (2D tangent impulse), `Translation2/3`, `Point2/3`, `nalgebra::Matrix3xX`, `SVector<Real, 6>` | a handful |

There is **no** use of nalgebra `SVD`, `QR`, sparse matrices or `Cholesky` (only the word in
comments) in `rapier/src`.

What this means for `nalgebra.cairo`: a rigid-body-only world (contacts, impulse joints, CCD,
no multibody, no soft bodies) needs **none** of it beyond `Vec2/3`, `Mat2/3`, `Quat`, `Pose*`. What
remains is (a) fixed-capacity `Vec6` / `Mat6` / 6xN Jacobians and a dynamic-size LU solve for
multibody dynamics, (b) nothing for SIMD. DESIGN rule 1 (no `Array` / `Span` / loop in fixed-size
math) already prescribes fixed-size monomorphic types, so a `DMatrix` / `DVector` port is a design
question of its own (fixed maximum DoF? generated `MatNxN`?), **not** part of P1 (section 6.5).

## 5. glam types used by parry / rapier that glam.cairo does not port (question 4) [V]

| glam-rs type | used how | covered by DESIGN section 1 collapse? |
|---|---|---|
| `Vec3A` | `math/mod.rs:37,40` alias; BVH ray / AABB fields (`partitioning/bvh/bvh_queries.rs:14-30`, `bvh_tree.rs:402-403`), 8 hits | **yes** (`Vec3A` -> `Vec3`); parry itself aliases `Vec3A = DVec3` in the f64 build |
| `Mat3A`, `Affine3A`, `Affine2`, `Affine3`, `Mat4`, `Quat` (by name) | 0 hits by name (rotations are `Rotation` / `Rot3`, `glamx::Pose3A` exists but is unused) | yes / n/a |
| `Vec4` | `math/mod.rs:37,40` re-export only, 0 uses | yes |
| `DVec2/3`, `DMat2/3`, `DQuat`, `DPose*` | f64 crates (`parry3d-f64`, `rapier3d-f64`): the same source with `Real = f64` | **yes**: one scalar, f64 variants collapse |
| `IVec2`, `IVec3` (f32 builds), `I64Vec2`, `I64Vec3` (f64 builds) | `IVector` for voxel grids: 238 hits in parry, `ivect_to_vect` / `vect_to_ivect` (`math/mod.rs:276-312`) | `IVec2/3` ported (VI); `I64Vec*` are "other integer widths": not needed, use `IVec*` (i32) like the f32 build. **Gap**: `IVec2/3::as_vec2/3` (and `UVec*`) do not exist yet (`packages/glam/src/ivec3.cairo:34` "will land with the `Vec3` port"; `Vec3::as_ivec3` exists), needed by `ivect_to_vect` (voxels, not P1) |
| `EulerRot` | 1 test (`aabb_triangle.rs:53`) | ported (E1) |
| `UVec*`, `BVec*` | 0 hits | ported anyway |
| `spirv`, `bytemuck`, `encase`, `rkyv`, `serde`, `approx`, `libm` features | glue | dropped (DESIGN section 1) |

Beyond glam types, parry/rapier depend on `simba` scalar traits (`ComplexField`, `RealField`,
`SimdRealField`) and `wide`, which vanish with the monomorphic `Fixed` scalar.

## 6. Recommendation (question 5)

### 6.1 Items worth porting first (priority order)

| # | item | source | why / consumer | glam.cairo prerequisites (all on `main` unless noted) |
|---|---|---|---|---|
| 1 | **`Pose3`** `{ rotation: Quat, translation: Vec3 }`: ctors, `from_parts`, `new` / `rotation` (axis-angle), `prepend_` / `append_translation`, `inverse` (conjugate, no division), **fused** `inv_mul`, `transform_point` / `_vector`, `inverse_transform_point` / `_vector`, `Pose3 * Pose3`, `Rot3 * Pose3`, `Pose3 * Rot3`, `From<Rot3>`, `From<(Vec3, Rot3)>` | glamx `pose3.rs` | rapier / parry hot set 3.2 items 1-3, 6 | `Quat` (`mul_quat`, `mul_vec3`, `conjugate`), `Vec3` |
| 2 | **`Rot2`** `{ re, im }`: `IDENTITY`, `from_cos_sin_unchecked`, `new` / `from_angle`, `angle`, `cos`, `sin`, `inverse`, `Rot2 * Rot2`, `transform_vector` / `inverse_transform_vector` (+ `Rot2 * Vec2` as a named method), `to_mat`, `from_mat(_unchecked)`, `normalize`, `normalize_mut`, `length`, `length_squared`, `dot`, `lerp`, `angle_between`, `from_rotation_arc` | glamx `rot2.rs` | 2D everything; `integrate_linearized` needs public `re` / `im` | `Vec2`, `Mat2`, `fixed::trig` (`sin_cos`, `atan2`) |
| 3 | **`Pose2`** `{ rotation: Rot2, translation: Vec2 }`: same list as `Pose3` | glamx `pose2.rs` | 2D | `Rot2` |
| 4 | **`SdpMatrix3`** (+ `SdpMatrix2`) and the world-inertia kernel `R D R^T` -> `SdpMatrix3`, `quadform`, `mul_vec`, `inverse` | **parry** `utils/sdp_matrix.rs`, `rapier` `angular_inertia_ops.rs`, `parry` `mass_properties.rs:259-271` | per-body-per-step matrix work, absent from glamx | `Mat3`, `Quat`, `fixed::wide` typed accumulators |
| 5 | `Rot3 = Quat` alias (`pub type Rot3 = Quat;`) | glamx `rot3.rs` | name parity | type aliases are ordinary Cairo [I]; the port must confirm impls resolve through the alias |
| 6 | tier 2: `Pose*::lerp` (prefer an `nlerp` variant, `Quat::slerp` costs 122 k), `to_mat3/4`, `from_mat3/4` (use `Quat::from_mat3` of the linear part instead of `to_scale_rotation_translation`), `Rot2::slerp`, `rotate_towards`, tuple `From`s | glamx | 0-1 consumer each | - |
| 7 | **`SymmetricEigen3`** (+ `reverse`), `Mat3::symmetric_eigen`, `symmetric_eigenvalues`, `swap_cols` | glamx `eigen3.rs`, `matrix_ext.rs` | setup-time only (3.3): compound / mesh mass properties, OBB, hull seeding | `Mat3`, `Vec3` (`cross`, `any_orthonormal_pair`), `trig::acos` / `cos` |
| - | **Do not port**: `Svd2`, `Svd3`, `SymmetricEigen2`, `Pose3::look_at_rh`, `face_towards`, `Rot2::powf`, `is_finite` / `is_nan`, `Pose3A`, all f32 <-> f64 / nalgebra / approx glue, `MatExt::abs` (`Mat2/3::abs` exist), `MatExt::try_inverse` (`Mat*::try_inverse` exist, semantics differ, see 2.2), `swap_rows` | - | 0 consumers ("an unported function does not exist", AGENTS principle 6) | - |

Small helpers that parry / rapier define and that a `Fixed` physics engine needs but that are
**not** glamx: `Vec3::kronecker`, cross-product matrix / `gcross`, `orthonormal_subspace_basis`,
`absolute_transform_vector` (`abs(R) * v`), `quat diff_conj1_2`. They belong to the layer that
mirrors parry / rapier (`rapier.cairo`, or a `parry.cairo` if the collision code is ported: the
stated sibling repos are only `nalgebra.cairo` and `rapier.cairo`, so this is an open question,
6.5.1), except where they are one-liners on `Vec3` / `Mat3`, which a `glamx` extension trait can
carry cheaply.

### 6.2 Gas estimates on the existing snapshots [I]

Additive sums of `gas/*.snap` entries (`bench_<type>::<fn>`), **not measured on new code**; fused
implementations should come out lower.

| operation | built from | est. l2_gas |
|---|---|---:|
| `Rot2 * Rot2`, `Rot2 * Vec2` | same formula as `Vec2::rotate` | ~4 700 |
| `Rot2::new` / `angle` | `sin_cos` 31 300 / `atan2` 28 120 | ~31 300 / ~28 100 |
| `Pose2 * Pose2`, `inv_mul` | rot 4 700 + rot-vec 4 700 + `Vec2` add 2 600 | ~12 000 |
| `Pose3 * Pose3` | `mul_quat` 10 040 + `mul_vec3` 9 360 + `Vec3` add 3 440 | ~22 800 |
| `Pose3::inv_mul` | `conjugate` 1 000 + sub 3 440 + `mul_vec3` 9 360 + `mul_quat` 10 040 | ~23 800 |
| `Pose3::transform_point` | `mul_vec3` 9 360 + add 3 440 | ~12 800 |
| `Pose3::inverse_transform_point` | sub 3 440 + `conjugate` 1 000 + `mul_vec3` 9 360 | ~13 800 |
| angular integration, exact (`from_scaled_axis`) | 48 820 + `mul_quat` 10 040 (+ `normalize` 10 500) | ~58 900 (~69 400) |
| angular integration, linearized (rapier `integrate_linearized`) | `mul_quat` 10 040 + `normalize` 10 500 | ~20 500 |
| world inverse inertia, rapier's formula | `from_quat` 20 660 + `transpose` 900 + 3x `mul_scalar` 5 960 + `mul_mat3` 19 640 | ~59 000 |

Two engine-level consequences: (a) the trig-free linearized integration is ~3x cheaper than the
exact one, and rapier already ships it (first-order, different numerics: a semantic choice for
`rapier.cairo`, not a drop-in swap; suggest it as the default for solver substeps); (b) a fused
`R D R^T` kernel (6 output scalars of a symmetric result, one rescale each) is the single
largest optimisation target of the matrix side, hence item 4.

### 6.3 Module layout: a new `glamx` package, not `glam/src/ext`

```
packages/glamx/
  Scarb.toml              # deps: fixed, glam; dev: snforge_std, assert_macros
  src/lib.cairo           # re-exports types and traits only (DESIGN section 4)
  src/rot2.cairo  src/rot3.cairo  src/pose2.cairo  src/pose3.cairo
  src/sdp.cairo           # SdpMatrix2 / SdpMatrix3 (+ world-inertia kernel)   [parry-derived]
  src/eigen3.cairo        # SymmetricEigen3 + Mat3 ext trait                   [tier 3]
  tests/test_<m>.cairo  tests/golden_<m>.cairo
```
Benches and snapshots follow the existing convention (`packages/benches/tests/bench_pose3.cairo`,
`gas/pose3.snap`, ...).

Why a package:
1. It mirrors upstream (glam and glamx are separate crates, siblings depend on packages of this
   repository, `AGENTS.md` repository map). The `glam` package stays a **clean glam-rs 0.33.8
   parity surface** for the R1a / R1 audit: the A3 brief already had to isolate its `glamx`-derived
   `Affine3RigidTrait` for that reason.
2. **Compile budget**: `glam_tests` is the largest compile of the workspace (~10 GB,
   `docs/briefs/COMMON.md`); new types in that crate make every existing module pay for them; a
   separate `glamx_tests` crate isolates the cost.
3. Independent tag / publish (`scarbs.xyz`): `nalgebra.cairo` / `rapier.cairo` can pin `glamx`
   without re-pinning glam for physics-only changes.
Cost: one orchestrator PR before the porters (Scarb workspace dependency, package manifest, stubs
declared in `lib.cairo`, `scripts/check.sh` / CI `-p glamx`, `benches` dependency, DESIGN section 1
table, refgen dependency on `glamx =0.3.1` as f64 oracle). `glam/src/ext/*` would avoid that PR but
mixes non-glam types into the parity surface and the 10 GB compile.

### 6.4 What belongs to `nalgebra.cairo` instead

* fixed-capacity `Vec6` / `Mat6` / `6xN` Jacobian types and a small-`n` LU solve for multibody
  (rapier `multibody.rs`), if multibody dynamics is wanted at all (feature `alloc`);
* the generic `Jacobian` / constraint types of `generic_*_constraint*.rs`;
* nothing else: no SIMD types, no `Isometry` / `UnitQuaternion` (superseded by `Pose*` / `Quat`), no
  Cholesky / SVD / QR / sparse (rapier does its own FEM factorisation).
This is a scope *reduction* of `nalgebra.cairo` relative to the synthesis, but it is smaller than
"glamx + DMatrix": the `glamx` part is what section 6.1 lists, the dynamic-matrix part is optional
and deferred.

### 6.5 Open design questions (to be decided by the orchestrator)

1. **Where does parry's math go?** `SdpMatrix*`, `absolute_transform_vector`, `kronecker`,
   `orthonormal_subspace_basis` are parry code, but no `parry.cairo` is planned. Proposal: `glamx`
   carries `SdpMatrix*` (used by both parry and rapier) and rapier.cairo carries the rest.
2. **`Rot2` representation.** Recommended: struct `{ re, im }` with public fields, exactly like
   glamx (rapier reads `rotation.re` / `.im`, `rigid_body_components.rs:896-898`). Alternative: a
   newtype over `Vec2` (reuses `Vec2::rotate` / `from_angle`); rejected because the field names are
   API and a `Vec2` newtype does not enforce the unit invariant either. `Rot2 * Rot2` is not
   renormalised (as in glamx): with floor rounding the error of each fused output is one-sided
   (`[-1, 0]` ULP), so the norm shrinks by up to ~2^-32 per composition, i.e. ~2e-4 after 10^6
   compositions [I, order of magnitude]. The documented policy must be "renormalise every step or
   every N steps", which is what rapier does (`normalize_mut`, `normalize`).
3. **`Pose3` = `Quat + Vec3` vs `Affine3` + `Affine3RigidTrait` (task A3).** Recommended:
   `Pose3` as in glamx. `rotation` / `translation` are public fields used verbatim by rapier and
   parry (`solver_body.rs:263`, `mass_properties.rs:320-331`), so an `Affine3` backing would break
   API parity and need a matrix -> quaternion extraction at every `pose.rotation` read. Storage:
   7 scalars vs 12. Costs [I, from the snapshots]: composition ~22 800 (quat) vs ~27 000+ (`Mat3 *
   Mat3` 19 640 + `Mat3 * Vec3` 7 160 + adds); `transform_point` ~12 800 (quat) vs ~7 800
   (`Affine3`, A3 brief target); a cached rotation matrix pays off after ~9-10 points per pose
   (`from_quat` 20 660 / (9 360 - 7 160)), which is a caching decision for the engine, not a
   representation decision for `Pose3`. Keep `Affine3RigidTrait` (A3) as is: it serves scaled /
   generic transforms and `Pose3::to_affine3`-style conversions, not the rigid pose.
4. **Trait naming and operators.** Follow the glam.cairo convention (`Pose3Trait` / `Pose3Impl`,
   `Pose3Mul`, named heterogeneous methods `mul_vec3`, `mul_rot3`, ...). `Pose3::translation(x,y,z)`
   and `Pose3::rotation(axisangle)` are associated functions that share a name with a struct
   field: legal in Rust, to be checked against the Cairo compiler (a `self`-less trait function
   should not clash with field access) [I].
5. **Thresholds** (`Rot2::normalize` `len <= EPSILON`, `is_normalized` `2e-4`, eigen `1e-20`) are
   f32-tuned: re-derive in raw ULPs per DESIGN section 3, per item, listed under `#### Deviations`.
6. **`Pose3::from_mat4`** upstream goes through `to_scale_rotation_translation` (scale extraction,
   square roots, several divisions): use the `Quat::from_mat3` of the linear part (19 770 gas)
   and document the rigid-only precondition.
7. **`SymmetricEigen3` algorithm.** Closed form (`acos` 27 390 + 2x `cos` 22 130 + sqrt, cross
   products, `any_orthonormal_pair` divisions: ~150-250 k gas [I]) vs a loop-free Jacobi / Newton
   variant vs computing mass properties off-chain and feeding principal inertia + frame directly
   (`MassProperties::with_principal_inertia_frame`, `mass_properties.rs:193`). Since it is
   setup-time, prefer correctness (property tests `A v = lambda v`, orthonormality, the
   multiplicity-2 and multiplicity-3 cases) over gas; rapier itself replaced glamx's version by a
   Jacobi loop for degenerate soft-body matrices (`soft_element_linalg.rs:11`), which is a warning
   sign for the closed form.
8. **2D angular inertia is a scalar** (`SimdAngularInertia<N> = N` in 2D, `lib.rs:219`): `sdp`
   is 3D-only in practice; `SdpMatrix2` (15 parry hits) is used for 2D constraint blocks
   (`quadform3x2`), keep it but after `SdpMatrix3`.

### 6.6 Effort estimate (porter tasks; one module = one task = one PR, AGENTS.md)

| id | task | size | depends on | parallel with |
|---|---|---|---|---|
| P0 | orchestrator: bootstrap the `glamx` package (manifest, stubs, `lib.cairo`, CI / `check.sh`, benches dep, refgen `glamx` oracle, DESIGN / PLAN / PORTING_STATUS) | S | - | - |
| P1a | `pose3` (+ `rot3` alias) | M | P0, `Quat` (merged) | P1b, P1d |
| P1b | `rot2` (29 fns, trig, ULP thresholds) | M | P0, F3 (merged) | P1a, P1d |
| P1c | `pose2` | S | P1b | P1a |
| P1d | `sdp` (`SdpMatrix3`, `SdpMatrix2`, world-inertia `R D R^T` fused kernel, `quadform`, `inverse`; may request `fixed::wide` accumulators) | M | P0 | P1a, P1b |
| P1e | `eigen3` (+ Mat3 ext) | L | P0, `trig::acos` / `cos` (merged) | after the others; low priority |
| R1' | reviewer / optimizer pass over `glamx` (gas: fused `inv_mul`, `R D R^T`) | S | P1a-d | - |

Total: **5 porter tasks + 1 orchestrator bootstrap + 1 optimizer pass** (`eigen3` deferrable).
Sizes: S = a few hundred lines, M = one glam-sized module with golden vectors, L = M plus
numerical analysis. Deliberately excluded: `Svd*`, `SymmetricEigen2`, look-at (0 consumers).

### 6.7 Follow-ups for the orchestrator (not done here: this task may only add this file)

1. `docs/PLAN.md` P1: replace by P0, P1a-e above; `docs/DESIGN.md` section 1: add the `glamx`
   package row once P0 lands; `docs/PORTING_STATUS.md`: split P1.
2. `docs/research/00-synthesis.md` section 4 and `01-glam-rs-analysis.md` item 7 should read:
   "parry has no nalgebra dependency; rapier still needs nalgebra for its SIMD solver and
   multibody; the glamx surface used by both is `Pose*`, `Rot2`, `SymmetricEigen3`".
3. `docs/briefs/A3-affine3.md`: no change required; note that `Affine3RigidTrait` is unrelated to
   `Pose3` (6.5.3).
4. glam.cairo gap found on the way: `IVec2/3/4::as_vec*` and `UVec*::as_vec*` are missing
   (`ivec3.cairo:34`); a small cross-type task like X1, needed for `ivect_to_vect` (voxels).

## 7. Verified vs inferred

**Verified in source (file:line cited above):** glamx contents, method and test counts, the
struct layouts and every quirk of section 2.2; parry / rapier dependency declarations; the
absence of nalgebra in parry; the nalgebra items rapier uses and where; every call site listed in
3.2 / 3.3 / 3.4; the zero-use claims (`Svd*`, `look_at_rh`, `face_towards`, `slerp`,
`rotate_towards`); rapier's own Jacobi eigen solver; the glam.cairo gas figures quoted from
`gas/*.snap` and the `IVec3::as_vec3` gap.

**Inferred (not verified):** the hot-subset *ranking* (call-site counts, not profiling: no
rapier benchmark was run); all gas estimates of 6.2 and 6.5.3 (sums of existing snapshot entries);
that glamx `glam ^0.33.7` resolves against the refgen `=0.33.8` pin; the Cairo type alias and
field / function name clash behaviour; the 2^-32-per-composition drift order of magnitude; the
`eigen3` gas range; that the 2D / 3D split is only approximate (attribution by `cfg` heuristics,
"shared" code is compiled twice).

## 8. Reproduction

```
git clone --depth 1 https://github.com/dimforge/{glamx,parry,rapier} /tmp/p1/...
grep -rEow '<item>' parry/src rapier/src --include='*.rs' | wc -l      # counts of 3.1
grep -rn 'symmetric_eigen\|SymmetricEigen' parry/src rapier/src --include='*.rs'   # 3.3
grep -rEc '\bna::|DVector|DMatrix|Jacobian|SimdReal|LU\b' rapier/src --include='*.rs'  # section 4
```
The 2D / 3D attribution script (about 60 lines of Python: `cfg`-gated modules in the parent
`mod.rs` plus `#[cfg(feature = "dimN")]` item extents) is not committed: this task's allowlist is
this single file.
