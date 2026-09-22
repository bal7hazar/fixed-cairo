//! Port of glam-rs `f32/affine3.rs` @ 0.33.8 on the Q32.32 scalar: a 3D affine transform
//! stored as a `Mat3` linear part and a `Vec3` translation. `Affine3A` collapses into it
//! (docs/DESIGN.md section 1).
//!
//! Products use the fused kernels of `fixed::wide`: point transforms and the translation of a
//! composition use `dot3_add`, so each output scalar is rescaled once. The inverse divides the
//! adjugate by ONE shared `Recip`.
//!
//! `Affine3RigidTrait` holds the physics-oriented additions of Dimforge's `glamx::Pose3`
//! (`inverse_rigid`, `inv_mul`), kept apart from the glam-rs parity surface.
//!
//! There is no NaN and no infinity: overflow and inversion of a singular transform panic
//! (docs/DESIGN.md section 3).

use core::ops::MulAssign;
use fixed::fixed::Fixed;
use fixed::wide::{
    RecipTrait, WideAdd, WideNarrow, WideNeg, WideSub, det3, dot3_add, dot4, mul_sub, wide_mul,
};
use crate::mat3::{Mat3, Mat3Trait};
use crate::mat4::{Mat4, Mat4Trait};
use crate::quat::{Quat, QuatTrait};
use crate::vec3::{Vec3, Vec3Trait};
use crate::vec4::Vec4;

/// A 3D affine transform, which can represent translation, rotation, scaling and shear.
///
/// Mirrors `glam::Affine3` (and `glam::Affine3A`, `glam::DAffine3`).
/// #### Deviations
/// * `Debug` is the derived Cairo formatting; `Display` and `Deref` are not implemented.
/// * No `NAN` const and no `is_nan` / `is_finite`: those values do not exist
///   (docs/DESIGN.md section 3).
/// * Not ported: `from_cols_slice` / `write_cols_to_slice` (no `Span` in fixed-size math),
///   `Product` (no iterator trait to implement), by-reference operator overloads, casts to the
///   collapsed f32/f64 variants and the `Affine3A` conversions (there is no distinct type).
/// * Heterogeneous `Mul` is not a core Cairo operator. `Affine3 * Mat4` is `mul_mat4` and
///   `Mat4 * Affine3` is `Mat4Trait::mul_affine3`.
#[derive(Copy, Drop, Serde, PartialEq, Debug, Hash)]
pub struct Affine3 {
    pub matrix3: Mat3,
    pub translation: Vec3,
}

pub trait Affine3Trait {
    /// The degenerate zero transform. It transforms every vector and point to zero.
    ///
    /// Mirrors `glam::Affine3::ZERO`.
    const ZERO: Affine3;
    /// The identity transform.
    ///
    /// Mirrors `glam::Affine3::IDENTITY`.
    const IDENTITY: Affine3;
    /// Creates an affine transform from four column vectors.
    ///
    /// Mirrors `glam::Affine3::from_cols`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_cols(x_axis: Vec3, y_axis: Vec3, z_axis: Vec3, w_axis: Vec3) -> Affine3;
    /// Creates an affine transform from a `[Fixed; 12]` array in column-major order.
    ///
    /// Implementation notes:
    /// * The array is passed by value, as fixed-size Cairo values are.
    ///
    /// Mirrors `glam::Affine3::from_cols_array`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_cols_array(m: [Fixed; 12]) -> Affine3;
    /// Creates a `[Fixed; 12]` array storing the transform in column-major order.
    ///
    /// Implementation notes:
    /// * The transform is passed by value, as fixed-size Cairo values are.
    ///
    /// Mirrors `glam::Affine3::to_cols_array`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn to_cols_array(self: Affine3) -> [Fixed; 12];
    /// Creates an affine transform from a `[[Fixed; 3]; 4]` array in column-major order.
    ///
    /// Implementation notes:
    /// * The array is passed by value, as fixed-size Cairo values are.
    ///
    /// Mirrors `glam::Affine3::from_cols_array_2d`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_cols_array_2d(m: [[Fixed; 3]; 4]) -> Affine3;
    /// Creates a `[[Fixed; 3]; 4]` array storing the transform in column-major order.
    ///
    /// Implementation notes:
    /// * The transform is passed by value, as fixed-size Cairo values are.
    ///
    /// Mirrors `glam::Affine3::to_cols_array_2d`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn to_cols_array_2d(self: Affine3) -> [[Fixed; 3]; 4];
    /// Creates an affine transform that changes scale.
    ///
    /// Mirrors `glam::Affine3::from_scale`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * The `glam_assert!` precondition (`scale` not entirely zero) is not checked.
    fn from_scale(scale: Vec3) -> Affine3;
    /// Creates an affine transform from the given `rotation` quaternion.
    ///
    /// Implementation notes:
    /// * As `Mat3Trait::from_quat`: `rotation` must be normalized (not checked) and every
    ///   element is one fused two-term sum rescaled once.
    ///
    /// Mirrors `glam::Affine3::from_quat`.
    /// #### Panics
    /// * As `Mat3Trait::from_quat`.
    /// #### Deviations
    /// * None.
    fn from_quat(rotation: Quat) -> Affine3;
    /// Creates an affine transform containing a 3D rotation around a normalized rotation
    /// `axis` of `angle` (in radians).
    ///
    /// Implementation notes:
    /// * As `Mat3Trait::from_axis_angle`: `axis` must be normalized (not checked).
    ///
    /// Mirrors `glam::Affine3::from_axis_angle`.
    /// #### Panics
    /// * As `Mat3Trait::from_axis_angle`.
    /// #### Deviations
    /// * None.
    fn from_axis_angle(axis: Vec3, angle: Fixed) -> Affine3;
    /// Creates an affine transform containing a 3D rotation around the x axis of `angle`
    /// (in radians).
    ///
    /// Mirrors `glam::Affine3::from_rotation_x`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * `fixed::trig::sin_cos` is accurate to about 1 ULP over a turn.
    fn from_rotation_x(angle: Fixed) -> Affine3;
    /// Creates an affine transform containing a 3D rotation around the y axis of `angle`
    /// (in radians).
    ///
    /// Mirrors `glam::Affine3::from_rotation_y`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * `fixed::trig::sin_cos` is accurate to about 1 ULP over a turn.
    fn from_rotation_y(angle: Fixed) -> Affine3;
    /// Creates an affine transform containing a 3D rotation around the z axis of `angle`
    /// (in radians).
    ///
    /// Mirrors `glam::Affine3::from_rotation_z`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * `fixed::trig::sin_cos` is accurate to about 1 ULP over a turn.
    fn from_rotation_z(angle: Fixed) -> Affine3;
    /// Creates an affine transform from the given 3D `translation`.
    ///
    /// Implementation notes:
    /// * Exact.
    ///
    /// Mirrors `glam::Affine3::from_translation`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_translation(translation: Vec3) -> Affine3;
    /// Creates an affine transform from a 3x3 matrix (expressing scale, shear and rotation).
    ///
    /// Implementation notes:
    /// * Exact.
    ///
    /// Mirrors `glam::Affine3::from_mat3`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_mat3(mat3: Mat3) -> Affine3;
    /// Creates an affine transform from a 3x3 matrix (expressing scale, shear and rotation)
    /// and a translation vector.
    ///
    /// Implementation notes:
    /// * Exact.
    ///
    /// Mirrors `glam::Affine3::from_mat3_translation`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_mat3_translation(mat3: Mat3, translation: Vec3) -> Affine3;
    /// Creates an affine transform from the given 3D `scale`, `rotation` and `translation`.
    ///
    /// Equivalent to `from_translation(translation) * from_quat(rotation) * from_scale(scale)`.
    ///
    /// Mirrors `glam::Affine3::from_scale_rotation_translation`.
    /// #### Panics
    /// * As `Mat4Trait::from_scale_rotation_translation`.
    /// #### Deviations
    /// * `rotation` must be normalized (not checked).
    /// * The numerics of `Mat4Trait::from_scale_rotation_translation`: the scale of column
    ///   `i` is applied inside the single rescale of each element, where glam-rs rounds the
    ///   rotation matrix first and the scaled one second.
    fn from_scale_rotation_translation(scale: Vec3, rotation: Quat, translation: Vec3) -> Affine3;
    /// Creates an affine transform from the given 3D `rotation` and `translation`.
    ///
    /// Equivalent to `from_translation(translation) * from_quat(rotation)`.
    ///
    /// Implementation notes:
    /// * As `from_quat`; the translation is copied exactly.
    ///
    /// Mirrors `glam::Affine3::from_rotation_translation`.
    /// #### Panics
    /// * As `Mat3Trait::from_quat`.
    /// #### Deviations
    /// * None.
    fn from_rotation_translation(rotation: Quat, translation: Vec3) -> Affine3;
    /// The given `Mat4` must be an affine transform, i.e. contain no perspective transform.
    ///
    /// Mirrors `glam::Affine3::from_mat4`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * Exact; the 4th row is ignored, as in glam-rs.
    fn from_mat4(m: Mat4) -> Affine3;
    /// Extracts `scale`, `rotation` and `translation` from `self`.
    ///
    /// The transform is expected to be a non-degenerate affine transform. If it contains
    /// shear or other non-TRS transforms, the returned rotation is ill-defined.
    ///
    /// Mirrors `glam::Affine3::to_scale_rotation_translation`.
    /// #### Panics
    /// * As `Mat4Trait::to_scale_rotation_translation`: `'Fixed: division by zero'` if a
    ///   column of the linear part is zero, `'Fixed: overflow'` if a length or the
    ///   determinant does not fit the scalar range.
    /// #### Deviations
    /// * The numerics of `Mat4Trait::to_scale_rotation_translation` (the same code path on
    ///   the embedded matrix): the sign of the determinant negates `scale.x` exactly, each
    ///   column is divided by its own shared `Recip`, and the rotation is
    ///   `Quat::from_rotation_axes` of the normalized columns. The translation is exact.
    fn to_scale_rotation_translation(self: Affine3) -> (Vec3, Quat, Vec3);
    /// Creates a left-handed view transform using a camera position, a facing direction and
    /// an up direction.
    ///
    /// For a view coordinate system with `+X=right`, `+Y=up` and `+Z=forward`.
    ///
    /// Implementation notes:
    /// * As `look_to_rh`.
    ///
    /// Mirrors `glam::Affine3::look_to_lh`.
    /// #### Panics
    /// * As `look_to_rh`.
    /// #### Deviations
    /// * None.
    fn look_to_lh(eye: Vec3, dir: Vec3, up: Vec3) -> Affine3;
    /// Creates a right-handed view transform using a camera position, a facing direction
    /// and an up direction.
    ///
    /// For a view coordinate system with `+X=right`, `+Y=up` and `+Z=back`.
    ///
    /// Mirrors `glam::Affine3::look_to_rh`.
    /// #### Panics
    /// * `'Vec3: normalize zero'` if `dir` is zero or parallel to `up`.
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    /// #### Deviations
    /// * Deprecated in glam-rs 0.33.1 in favour of `glam::camera`; the name and layout are
    ///   the ones of `Affine3::look_to_rh`.
    /// * `dir` is normalized as in glam-rs (one square root, one shared division), then the
    ///   frame is `Mat4Trait::look_to_rh`: `s` is normalized the same way and every other
    ///   element is exact or one floored `dot3`.
    fn look_to_rh(eye: Vec3, dir: Vec3, up: Vec3) -> Affine3;
    /// Creates a left-handed view transform using a camera position, a focal point and an
    /// up direction.
    ///
    /// For a view coordinate system with `+X=right`, `+Y=up` and `+Z=forward`.
    ///
    /// Mirrors `glam::Affine3::look_at_lh`.
    /// #### Panics
    /// * `'Vec3: normalize zero'` if `center` is `eye`, or if the direction and `up` are
    ///   parallel.
    /// * `'i64_sub Overflow'` / `'i64_sub Underflow'` if `center - eye` leaves the scalar
    ///   range; as `look_to_rh` otherwise.
    /// #### Deviations
    /// * The `glam_assert!` precondition (`up` normalized) is not checked; as `look_to_rh`.
    fn look_at_lh(eye: Vec3, center: Vec3, up: Vec3) -> Affine3;
    /// Creates a right-handed view transform using a camera position, a focal point and an
    /// up direction.
    ///
    /// For a view coordinate system with `+X=right`, `+Y=up` and `+Z=back`.
    ///
    /// Implementation notes:
    /// * As `look_at_lh`.
    ///
    /// Mirrors `glam::Affine3::look_at_rh`.
    /// #### Panics
    /// * As `look_at_lh`.
    /// #### Deviations
    /// * None.
    fn look_at_rh(eye: Vec3, center: Vec3, up: Vec3) -> Affine3;
    /// Transforms the given 3D point, applying shear, scale, rotation and translation.
    ///
    /// Mirrors `glam::Affine3::transform_point3`.
    /// #### Panics
    /// * `'Fixed: overflow'` if an output component leaves the scalar range.
    /// #### Deviations
    /// * One `dot3_add` fused kernel per component: the three products and the translation
    ///   are rescaled once, so an output is at most 1 ULP below the exact value.
    fn transform_point3(self: Affine3, rhs: Vec3) -> Vec3;
    /// Transforms the given 3D vector, applying shear, scale and rotation (but NOT
    /// translation).
    ///
    /// Mirrors `glam::Affine3::transform_vector3`.
    /// #### Panics
    /// * `'Fixed: overflow'` if an output component leaves the scalar range.
    /// #### Deviations
    /// * One `dot3` fused kernel per component: the three products are rescaled once.
    fn transform_vector3(self: Affine3, rhs: Vec3) -> Vec3;
    /// Returns true if the absolute difference of all elements between `self` and `rhs` is
    /// less than or equal to `max_abs_diff`.
    ///
    /// Mirrors `glam::Affine3::abs_diff_eq`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * Differences are compared on 65 bits by the component methods and cannot overflow.
    fn abs_diff_eq(self: Affine3, rhs: Affine3, max_abs_diff: Fixed) -> bool;
    /// Returns the inverse of `self`.
    ///
    /// Implementation notes:
    /// * The linear part is `Mat3::inverse` inlined: fused adjugate, exact `det3`, one
    ///   division shared by the nine elements (`Recip`, rounded to nearest), so `inverse` is
    ///   singular exactly when `matrix3.determinant()` is zero.
    /// * The translation is `-(inverse * translation)` as in glam-rs, on the rounded inverse:
    ///   one `dot3` per component with the negation folded into its single rescale
    ///   (`floor(-x)`), so each component carries `|translation|_1 / 2` ULP from the rounded
    ///   inverse plus 1. The Cramer-rule translation (three more `det3` through the same
    ///   `Recip`, two roundings) is more accurate but costs 54 430 against 48 490 gas; it is
    ///   kept in `benches::alt::affine3` with the glam-rs two-stage formulation (54 470).
    ///
    /// Mirrors `glam::Affine3::inverse`.
    /// #### Panics
    /// * `'Affine3: singular'` if the determinant of `matrix3` is zero.
    /// * `'Fixed: overflow'` if an element of the adjugate or of the result leaves the scalar
    ///   range.
    /// #### Deviations
    /// * glam-rs returns an invalid transform when assertions are disabled; there is no NaN
    ///   here, so singular transforms panic.
    fn inverse(self: Affine3) -> Affine3;
    /// Multiplies this affine transform by a 4x4 matrix.
    ///
    /// Mirrors `impl Mul<Mat4> for glam::Affine3`.
    /// #### Panics
    /// * `'Fixed: overflow'` if a result element leaves the scalar range.
    /// #### Deviations
    /// * Cairo's core `Mul` is homogeneous, so the heterogeneous operator is named
    ///   `mul_mat4`.
    /// * The embedded 4th row `(0, 0, 0, 1)` is not multiplied: the 4th row of the result is
    ///   the 4th row of `rhs` (exact), the other twelve elements are one `dot4` each, bit
    ///   identical to `Mat4::from(self) * rhs`.
    fn mul_mat4(self: Affine3, rhs: Mat4) -> Mat4;
}

/// Rigid-body helpers from Dimforge's `glamx::Pose3`, not part of glam-rs.
///
/// #### Preconditions
/// * `matrix3` must be a rotation (orthonormal, determinant `+1`); it is not checked. Then
///   its inverse is its transpose: no determinant and no division.
pub trait Affine3RigidTrait {
    /// Returns the inverse of a rigid transform: `R^T` and `-(R^T t)`.
    ///
    /// Mirrors `glamx::Pose3::inverse` (not in glam-rs).
    /// #### Panics
    /// * `'Fixed: overflow'` if a translation component leaves the scalar range.
    /// #### Deviations
    /// * The precondition is not checked: on a non-orthonormal `matrix3` the result is not
    ///   the inverse (use `Affine3Trait::inverse`).
    /// * The linear part is exact (a transpose); each translation component is one fused
    ///   `dot3` negated inside the rescale, i.e. the floor of the exact `-(R^T t)`.
    fn inverse_rigid(self: Affine3) -> Affine3;
    /// Returns `self.inverse_rigid() * rhs`, fused.
    ///
    /// Mirrors `glamx::Pose3::inv_mul` (not in glam-rs).
    /// #### Panics
    /// * `'Fixed: overflow'` if a result element leaves the scalar range.
    /// #### Deviations
    /// * The precondition is not checked.
    /// * The linear part is `R^T * rhs.matrix3` (one `dot3` per element) and the translation
    ///   `R^T (rhs.t - self.t)` as one exact six-product sum rescaled once: no intermediate
    ///   rounding and no intermediate overflow, unlike the composition of the two steps.
    fn inv_mul(self: Affine3, rhs: Affine3) -> Affine3;
}

pub impl Affine3Impl of Affine3Trait {
    const ZERO: Affine3 = Affine3 {
        matrix3: Mat3 {
            x_axis: Vec3 { x: F_ZERO, y: F_ZERO, z: F_ZERO },
            y_axis: Vec3 { x: F_ZERO, y: F_ZERO, z: F_ZERO },
            z_axis: Vec3 { x: F_ZERO, y: F_ZERO, z: F_ZERO },
        },
        translation: Vec3 { x: F_ZERO, y: F_ZERO, z: F_ZERO },
    };
    const IDENTITY: Affine3 = Affine3 {
        matrix3: Mat3 {
            x_axis: Vec3 { x: F_ONE, y: F_ZERO, z: F_ZERO },
            y_axis: Vec3 { x: F_ZERO, y: F_ONE, z: F_ZERO },
            z_axis: Vec3 { x: F_ZERO, y: F_ZERO, z: F_ONE },
        },
        translation: Vec3 { x: F_ZERO, y: F_ZERO, z: F_ZERO },
    };

    #[inline(always)]
    fn from_cols(x_axis: Vec3, y_axis: Vec3, z_axis: Vec3, w_axis: Vec3) -> Affine3 {
        Affine3 { matrix3: Mat3 { x_axis, y_axis, z_axis }, translation: w_axis }
    }

    #[inline(always)]
    fn from_cols_array(m: [Fixed; 12]) -> Affine3 {
        let [m00, m01, m02, m10, m11, m12, m20, m21, m22, tx, ty, tz] = m;
        Affine3 {
            matrix3: Mat3 {
                x_axis: Vec3 { x: m00, y: m01, z: m02 },
                y_axis: Vec3 { x: m10, y: m11, z: m12 },
                z_axis: Vec3 { x: m20, y: m21, z: m22 },
            },
            translation: Vec3 { x: tx, y: ty, z: tz },
        }
    }

    #[inline(always)]
    fn to_cols_array(self: Affine3) -> [Fixed; 12] {
        let Affine3 { matrix3: Mat3 { x_axis: x, y_axis: y, z_axis: z }, translation: w } = self;
        [x.x, x.y, x.z, y.x, y.y, y.z, z.x, z.y, z.z, w.x, w.y, w.z]
    }

    #[inline(always)]
    fn from_cols_array_2d(m: [[Fixed; 3]; 4]) -> Affine3 {
        let [x, y, z, w] = m;
        let [m00, m01, m02] = x;
        let [m10, m11, m12] = y;
        let [m20, m21, m22] = z;
        let [tx, ty, tz] = w;
        Affine3 {
            matrix3: Mat3 {
                x_axis: Vec3 { x: m00, y: m01, z: m02 },
                y_axis: Vec3 { x: m10, y: m11, z: m12 },
                z_axis: Vec3 { x: m20, y: m21, z: m22 },
            },
            translation: Vec3 { x: tx, y: ty, z: tz },
        }
    }

    #[inline(always)]
    fn to_cols_array_2d(self: Affine3) -> [[Fixed; 3]; 4] {
        let Affine3 { matrix3: Mat3 { x_axis: x, y_axis: y, z_axis: z }, translation: w } = self;
        [[x.x, x.y, x.z], [y.x, y.y, y.z], [z.x, z.y, z.z], [w.x, w.y, w.z]]
    }

    #[inline(always)]
    fn from_scale(scale: Vec3) -> Affine3 {
        Affine3 { matrix3: Mat3Trait::from_diagonal(scale), translation: Vec3Trait::ZERO }
    }

    #[inline(always)]
    fn from_quat(rotation: Quat) -> Affine3 {
        Affine3 { matrix3: Mat3Trait::from_quat(rotation), translation: Vec3Trait::ZERO }
    }

    #[inline(always)]
    fn from_axis_angle(axis: Vec3, angle: Fixed) -> Affine3 {
        Affine3 { matrix3: Mat3Trait::from_axis_angle(axis, angle), translation: Vec3Trait::ZERO }
    }

    #[inline(always)]
    fn from_rotation_x(angle: Fixed) -> Affine3 {
        Affine3 { matrix3: Mat3Trait::from_rotation_x(angle), translation: Vec3Trait::ZERO }
    }

    #[inline(always)]
    fn from_rotation_y(angle: Fixed) -> Affine3 {
        Affine3 { matrix3: Mat3Trait::from_rotation_y(angle), translation: Vec3Trait::ZERO }
    }

    #[inline(always)]
    fn from_rotation_z(angle: Fixed) -> Affine3 {
        Affine3 { matrix3: Mat3Trait::from_rotation_z(angle), translation: Vec3Trait::ZERO }
    }

    #[inline(always)]
    fn from_translation(translation: Vec3) -> Affine3 {
        Affine3 { matrix3: Mat3Trait::IDENTITY, translation }
    }

    #[inline(always)]
    fn from_mat3(mat3: Mat3) -> Affine3 {
        Affine3 { matrix3: mat3, translation: Vec3Trait::ZERO }
    }

    #[inline(always)]
    fn from_mat3_translation(mat3: Mat3, translation: Vec3) -> Affine3 {
        Affine3 { matrix3: mat3, translation }
    }

    #[inline(always)]
    fn from_scale_rotation_translation(scale: Vec3, rotation: Quat, translation: Vec3) -> Affine3 {
        Self::from_mat4(Mat4Trait::from_scale_rotation_translation(scale, rotation, translation))
    }

    #[inline(always)]
    fn from_rotation_translation(rotation: Quat, translation: Vec3) -> Affine3 {
        Affine3 { matrix3: Mat3Trait::from_quat(rotation), translation }
    }

    #[inline(always)]
    fn from_mat4(m: Mat4) -> Affine3 {
        Affine3 {
            matrix3: Mat3 {
                x_axis: Vec3 { x: m.x_axis.x, y: m.x_axis.y, z: m.x_axis.z },
                y_axis: Vec3 { x: m.y_axis.x, y: m.y_axis.y, z: m.y_axis.z },
                z_axis: Vec3 { x: m.z_axis.x, y: m.z_axis.y, z: m.z_axis.z },
            },
            translation: Vec3 { x: m.w_axis.x, y: m.w_axis.y, z: m.w_axis.z },
        }
    }

    #[inline(always)]
    fn to_scale_rotation_translation(self: Affine3) -> (Vec3, Quat, Vec3) {
        Mat4Trait::to_scale_rotation_translation(self.into())
    }

    #[inline(always)]
    fn look_to_lh(eye: Vec3, dir: Vec3, up: Vec3) -> Affine3 {
        Self::look_to_rh(eye, -dir, up)
    }

    fn look_to_rh(eye: Vec3, dir: Vec3, up: Vec3) -> Affine3 {
        Self::from_mat4(Mat4Trait::look_to_rh(eye, dir.normalize(), up))
    }

    #[inline(always)]
    fn look_at_lh(eye: Vec3, center: Vec3, up: Vec3) -> Affine3 {
        Self::look_to_lh(eye, center - eye, up)
    }

    #[inline(always)]
    fn look_at_rh(eye: Vec3, center: Vec3, up: Vec3) -> Affine3 {
        Self::look_to_rh(eye, center - eye, up)
    }

    #[inline(always)]
    fn transform_point3(self: Affine3, rhs: Vec3) -> Vec3 {
        let m = self.matrix3;
        let t = self.translation;
        Vec3 {
            x: dot3_add(m.x_axis.x, rhs.x, m.y_axis.x, rhs.y, m.z_axis.x, rhs.z, t.x),
            y: dot3_add(m.x_axis.y, rhs.x, m.y_axis.y, rhs.y, m.z_axis.y, rhs.z, t.y),
            z: dot3_add(m.x_axis.z, rhs.x, m.y_axis.z, rhs.y, m.z_axis.z, rhs.z, t.z),
        }
    }

    #[inline(always)]
    fn transform_vector3(self: Affine3, rhs: Vec3) -> Vec3 {
        self.matrix3.mul_vec3(rhs)
    }

    #[inline(always)]
    fn abs_diff_eq(self: Affine3, rhs: Affine3, max_abs_diff: Fixed) -> bool {
        self.matrix3.abs_diff_eq(rhs.matrix3, max_abs_diff)
            && self.translation.abs_diff_eq(rhs.translation, max_abs_diff)
    }

    fn inverse(self: Affine3) -> Affine3 {
        inverse_shared_recip(self)
    }

    #[inline(always)]
    fn mul_mat4(self: Affine3, rhs: Mat4) -> Mat4 {
        Mat4 {
            x_axis: mul_col4(self, rhs.x_axis),
            y_axis: mul_col4(self, rhs.y_axis),
            z_axis: mul_col4(self, rhs.z_axis),
            w_axis: mul_col4(self, rhs.w_axis),
        }
    }
}

pub impl Affine3RigidImpl of Affine3RigidTrait {
    #[inline(always)]
    fn inverse_rigid(self: Affine3) -> Affine3 {
        let x = self.matrix3.x_axis;
        let y = self.matrix3.y_axis;
        let z = self.matrix3.z_axis;
        let t = self.translation;
        Affine3 {
            matrix3: Mat3 {
                x_axis: Vec3 { x: x.x, y: y.x, z: z.x },
                y_axis: Vec3 { x: x.y, y: y.y, z: z.y },
                z_axis: Vec3 { x: x.z, y: y.z, z: z.z },
            },
            translation: Vec3 { x: neg_dot3(x, t), y: neg_dot3(y, t), z: neg_dot3(z, t) },
        }
    }

    #[inline(always)]
    fn inv_mul(self: Affine3, rhs: Affine3) -> Affine3 {
        let r = self.matrix3;
        let a = self.translation;
        let b = rhs.translation;
        Affine3 {
            matrix3: Mat3 {
                x_axis: r.mul_transpose_vec3(rhs.matrix3.x_axis),
                y_axis: r.mul_transpose_vec3(rhs.matrix3.y_axis),
                z_axis: r.mul_transpose_vec3(rhs.matrix3.z_axis),
            },
            translation: Vec3 {
                x: rigid_row(r.x_axis, a, b),
                y: rigid_row(r.y_axis, a, b),
                z: rigid_row(r.z_axis, a, b),
            },
        }
    }
}

/// `Default` is `Affine3::IDENTITY`, as in glam-rs.
///
/// Mirrors `impl Default for glam::Affine3`.
pub impl Affine3Default of Default<Affine3> {
    #[inline(always)]
    fn default() -> Affine3 {
        Affine3Trait::IDENTITY
    }
}

/// Affine composition: `matrix3 * rhs.matrix3` (nine `dot3`) and
/// `matrix3 * rhs.translation + translation` (three `dot3_add`, one rescale per component).
///
/// Mirrors `impl Mul for glam::Affine3`.
pub impl Affine3Mul of Mul<Affine3> {
    #[inline(always)]
    fn mul(lhs: Affine3, rhs: Affine3) -> Affine3 {
        Affine3 {
            matrix3: lhs.matrix3 * rhs.matrix3, translation: lhs.transform_point3(rhs.translation),
        }
    }
}

/// Mirrors `impl MulAssign for glam::Affine3`.
pub impl Affine3MulAssign of MulAssign<Affine3, Affine3> {
    #[inline(always)]
    fn mul_assign(ref self: Affine3, rhs: Affine3) {
        self = self * rhs;
    }
}

/// Embeds an affine transform in a homogeneous 4x4 matrix (4th row `(0, 0, 0, 1)`).
///
/// Mirrors `impl From<glam::Affine3> for glam::Mat4`.
pub impl Affine3IntoMat4 of Into<Affine3, Mat4> {
    #[inline(always)]
    fn into(self: Affine3) -> Mat4 {
        Mat4Trait::from_mat3_translation(self.matrix3, self.translation)
    }
}

/// Creates a quaternion from the 3x3 rotation matrix inside a 3D affine transform.
///
/// If the linear part contains scales, shears or other non-rotation transformations, the
/// resulting quaternion is ill-defined.
///
/// Mirrors `glam::Quat::from_affine3`.
/// #### Panics
/// * As `QuatTrait::from_rotation_axes`.
/// #### Deviations
/// * Kept as a compatibility alias; new code should call `QuatTrait::from_affine3`.
/// * The `glam_assert!` precondition (normalized columns) is not checked.
#[inline(always)]
pub fn quat_from_affine3(a: Affine3) -> Quat {
    QuatTrait::from_affine3(a)
}

/// One column of `Mat4::from(a) * c`: three `dot4` (the translation times `c.w` is the fourth
/// product) and `c.w` itself, since the embedded 4th row is `(0, 0, 0, 1)`.
#[inline(always)]
fn mul_col4(a: Affine3, c: Vec4) -> Vec4 {
    let m = a.matrix3;
    let t = a.translation;
    Vec4 {
        x: dot4(m.x_axis.x, c.x, m.y_axis.x, c.y, m.z_axis.x, c.z, t.x, c.w),
        y: dot4(m.x_axis.y, c.x, m.y_axis.y, c.y, m.z_axis.y, c.z, t.y, c.w),
        z: dot4(m.x_axis.z, c.x, m.y_axis.z, c.y, m.z_axis.z, c.z, t.z, c.w),
        w: c.w,
    }
}

/// `r . (b - a)` as one exact sum of six products, rescaled once.
#[inline(always)]
fn rigid_row(r: Vec3, a: Vec3, b: Vec3) -> Fixed {
    wide_mul(r.x, b.x)
        .add(wide_mul(r.y, b.y))
        .add(wide_mul(r.z, b.z))
        .sub(wide_mul(r.x, a.x).add(wide_mul(r.y, a.y)).add(wide_mul(r.z, a.z)))
        .narrow()
}

/// `Mat3::inverse` inlined (fused adjugate, exact `det3`, ONE shared `Recip` for the nine
/// elements), then `-(inverse * translation)`: one `dot3` per component, the negation folded
/// into the wide sum before its single rescale.
fn inverse_shared_recip(a: Affine3) -> Affine3 {
    let x = a.matrix3.x_axis;
    let y = a.matrix3.y_axis;
    let z = a.matrix3.z_axis;
    let det = det3(x.x, x.y, x.z, y.x, y.y, y.z, z.x, z.y, z.z);
    if det == F_ZERO {
        core::panic_with_felt252('Affine3: singular');
    }
    let r = RecipTrait::new(det);
    // The rows of the inverse: the cross products of the columns, divided by the determinant.
    let r0 = Vec3 {
        x: r.mul(mul_sub(y.y, z.z, y.z, z.y)),
        y: r.mul(mul_sub(y.z, z.x, y.x, z.z)),
        z: r.mul(mul_sub(y.x, z.y, y.y, z.x)),
    };
    let r1 = Vec3 {
        x: r.mul(mul_sub(z.y, x.z, z.z, x.y)),
        y: r.mul(mul_sub(z.z, x.x, z.x, x.z)),
        z: r.mul(mul_sub(z.x, x.y, z.y, x.x)),
    };
    let r2 = Vec3 {
        x: r.mul(mul_sub(x.y, y.z, x.z, y.y)),
        y: r.mul(mul_sub(x.z, y.x, x.x, y.z)),
        z: r.mul(mul_sub(x.x, y.y, x.y, y.x)),
    };
    let t = a.translation;
    Affine3 {
        matrix3: Mat3 {
            x_axis: Vec3 { x: r0.x, y: r1.x, z: r2.x },
            y_axis: Vec3 { x: r0.y, y: r1.y, z: r2.y },
            z_axis: Vec3 { x: r0.z, y: r1.z, z: r2.z },
        },
        translation: Vec3 { x: neg_dot3(r0, t), y: neg_dot3(r1, t), z: neg_dot3(r2, t) },
    }
}

/// `-(a . b)` as one exact sum of three products, negated, rescaled once: `floor(-(a . b))`.
#[inline(always)]
fn neg_dot3(a: Vec3, b: Vec3) -> Fixed {
    wide_mul(a.x, b.x).add(wide_mul(a.y, b.y)).add(wide_mul(a.z, b.z)).neg().narrow()
}

/// `0`.
const F_ZERO: Fixed = Fixed { raw: 0 };

/// `1`.
const F_ONE: Fixed = Fixed { raw: 0x100000000 };
