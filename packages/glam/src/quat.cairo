//! Port of glam-rs `f32/scalar/quat.rs` @ 0.33.8 on the Q32.32 scalar: a quaternion representing
//! an orientation.
//!
//! Every product goes through a fused kernel of `fixed::wide` (one rescale per output scalar,
//! docs/DESIGN.md section 2.1): the Hamilton product of [`QuatTrait::mul_quat`] and the rotation
//! of [`QuatTrait::mul_vec3`] narrow once per component, never once per multiplication. The
//! losing candidates live in `benches::alt::quat` and the measurements in `gas/quat.snap`.
//!
//! The `f32` epsilons of glam-rs are meaningless at a resolution of `2^-32` and are re-derived
//! here (docs/DESIGN.md section 3): [`NEAR_ONE`] for the singular branches of
//! `from_rotation_arc*` and of `slerp`, and the thresholds documented on
//! [`QuatTrait::to_axis_angle`], [`QuatTrait::is_near_identity`] and
//! [`QuatTrait::rotate_towards`].
//!
//! There is no NaN and no infinity: overflow, division by zero and the normalization of the zero
//! quaternion panic.

use core::ops::{AddAssign, DivAssign, MulAssign, SubAssign};
use fixed::fixed::{Fixed, FixedTrait};
use fixed::trig::TrigTrait;
use fixed::wide::{
    NormTrait, Recip, RecipTrait, WideAdd, WideMul, WideNarrow, WideSub, dot4, is_unit4, mul_sub,
    norm2_wide, norm3_wide, norm4, norm4_squared, norm4_wide, wide_mul,
};
use crate::affine3::Affine3;
use crate::mat3::Mat3;
use crate::mat4::Mat4;
use crate::vec2::{Vec2, Vec2Trait};
use crate::vec3::{Vec3, Vec3Trait};
use crate::vec4::{Vec4, Vec4Trait};

/// A quaternion of Q32.32 fixed-point scalars representing an orientation.
///
/// It is intended to be of unit length but denormalizes as successive operations are applied:
/// the squared length of a product of two unit quaternions is within 9 ULP of one, and a chain
/// of successive products drifts by about 2.5 ULP per product (measured: at most 271 ULP after
/// 100 products, 2 400 after 1 000, over 200 random chains of the Python mirror and by
/// `fuzz_mul_quat_drift` in the tests). A unit quaternion therefore leaves the
/// [`QuatTrait::is_normalized`] band (1 024 ULP, `2.4e-7`) after about 400 successive products:
/// renormalizing every few hundred steps is enough.
///
/// Mirrors `glam::Quat`.
/// #### Deviations
/// * `Debug` is the derived Cairo formatting; `Display` is not implemented.
/// * No `NAN` const and no `is_nan` / `is_finite`: those values do not exist
///   (docs/DESIGN.md section 3).
/// * Not ported: `from_slice` / `write_to_slice` (no `Span` in fixed-size math), `Sum` /
///   `Product` (no iterator trait to implement), the by-reference operator overloads and
///   `as_dquat`. `from_euler` / `to_euler` are the extension trait
///   `glam::euler::QuatEulerTrait`.
#[derive(Copy, Drop, Serde, PartialEq, Debug, Hash)]
pub struct Quat {
    pub x: Fixed,
    pub y: Fixed,
    pub z: Fixed,
    pub w: Fixed,
}

/// Creates a quaternion from `x`, `y`, `z` and `w` values.
///
/// This should generally not be called manually unless you know what you are doing: use
/// [`QuatTrait::IDENTITY`] or [`QuatTrait::from_axis_angle`] instead.
///
/// Mirrors `glam::quat`.
/// #### Panics
/// * Never.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn quat(x: Fixed, y: Fixed, z: Fixed, w: Fixed) -> Quat {
    Quat { x, y, z, w }
}

pub trait QuatTrait {
    /// All zeros.
    ///
    /// Mirrors `glam::Quat::ZERO` (private there, public here: there is no `Default` derive to
    /// reach it with).
    const ZERO: Quat;
    /// The identity quaternion: no rotation.
    ///
    /// Mirrors `glam::Quat::IDENTITY`.
    const IDENTITY: Quat;
    /// Creates a new rotation quaternion.
    ///
    /// This should generally not be called manually unless you know what you are doing.
    ///
    /// #### Preconditions
    /// * The input is not checked to be normalized.
    ///
    /// Mirrors `glam::Quat::from_xyzw`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_xyzw(x: Fixed, y: Fixed, z: Fixed, w: Fixed) -> Quat;
    /// Creates a rotation quaternion from an array.
    ///
    /// #### Preconditions
    /// * The input is not checked to be normalized.
    ///
    /// Mirrors `glam::Quat::from_array`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_array(a: [Fixed; 4]) -> Quat;
    /// Creates a new rotation quaternion from a 4D vector.
    ///
    /// #### Preconditions
    /// * The input is not checked to be normalized.
    ///
    /// Mirrors `glam::Quat::from_vec4`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_vec4(v: Vec4) -> Quat;
    /// Converts `self` to `[x, y, z, w]`.
    ///
    /// Mirrors `glam::Quat::to_array`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn to_array(self: Quat) -> [Fixed; 4];
    /// Returns the vector part of the quaternion.
    ///
    /// Mirrors `glam::Quat::xyz`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn xyz(self: Quat) -> Vec3;
    /// Creates a quaternion for a normalized rotation `axis` and `angle` (in radians).
    ///
    /// #### Preconditions
    /// * `axis` must be a unit vector; it is not checked (glam-rs checks it under the
    ///   `glam_assert` feature, docs/DESIGN.md section 3).
    ///
    /// Implementation notes:
    /// * `angle * 0.5` is floored before the reduction, and `sin_cos` is accurate to 1.02 ULP:
    ///   each component is within 3 ULP of the exact result. `sin_cos` shares the range
    ///   reduction: 11 950 gas cheaper than the `sin` plus `cos` of `benches::alt::quat`
    ///   (40 350 vs 52 300).
    ///
    /// Mirrors `glam::Quat::from_axis_angle`.
    /// #### Panics
    /// * `'Fixed: overflow'` if a component of the result does not fit the scalar range (only
    ///   reachable with an axis far longer than one).
    /// #### Deviations
    /// * Overflow panics where f32 returns infinity or a larger finite value: docs/DESIGN.md
    ///   section 3, "overflow".
    fn from_axis_angle(axis: Vec3, angle: Fixed) -> Quat;
    /// Creates a quaternion that rotates `v.length()` radians around `v.normalize()`.
    ///
    /// `from_scaled_axis(Vec3::ZERO)` is the identity quaternion.
    ///
    /// Implementation notes:
    /// * The `from_axis_angle(v / length, length)` of glam-rs, with the three divisions sharing
    ///   one `Recip`: an axis-aligned input stays exactly axis-aligned, so that
    ///   `from_scaled_axis(Vec3::Z.mul_scalar(a))` is exactly `from_rotation_z(a)`. Folding the
    ///   sine into that division (`v * (sin(angle / 2) / length)`) is 4 470 gas cheaper
    ///   (44 350 vs 48 820) but loses that exactness; it is kept in `benches::alt::quat`.
    ///
    /// Mirrors `glam::Quat::from_scaled_axis`.
    /// #### Panics
    /// * `'Fixed: overflow'` if `v.length()` does not fit the scalar range (`|v| >= 2^31`).
    /// #### Deviations
    /// * The length is the floor of the exact one, so the angle is at most 1 ULP short.
    fn from_scaled_axis(v: Vec3) -> Quat;
    /// Creates a quaternion from the `angle` (in radians) around the x axis.
    ///
    /// Implementation notes:
    /// * As [`QuatTrait::from_axis_angle`]: within 2 ULP of the exact result.
    ///
    /// Mirrors `glam::Quat::from_rotation_x`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_rotation_x(angle: Fixed) -> Quat;
    /// Creates a quaternion from the `angle` (in radians) around the y axis.
    ///
    /// Implementation notes:
    /// * As [`QuatTrait::from_rotation_x`].
    ///
    /// Mirrors `glam::Quat::from_rotation_y`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_rotation_y(angle: Fixed) -> Quat;
    /// Creates a quaternion from the `angle` (in radians) around the z axis.
    ///
    /// Implementation notes:
    /// * As [`QuatTrait::from_rotation_x`].
    ///
    /// Mirrors `glam::Quat::from_rotation_z`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_rotation_z(angle: Fixed) -> Quat;
    /// Creates a quaternion from the columns of a 3x3 rotation matrix.
    ///
    /// #### Preconditions
    /// * Each axis must be a unit vector and the three must be orthogonal; it is not checked.
    ///   A matrix that contains scales, shears or other non-rotation transformations gives an
    ///   ill-defined quaternion, as in glam-rs.
    ///
    /// Implementation notes:
    /// * `0.5 / sqrt(4 c^2)` is one `fixed::wide::Recip` of `2 sqrt(4 c^2)`, shared by the four
    ///   components and rounded to nearest, instead of a truncated `Fixed` reciprocal
    ///   multiplied four times: one rounding instead of two, and 130 gas cheaper as well
    ///   (19 770 against 19 900, `alt_from_rotation_axes_fixed_recip`). The square root is the
    ///   floor of the exact one, so each component is within `1 + |component| / |c|` ULP of the
    ///   exact value, i.e. at most 3 ULP. Measured over 50 000 random unit quaternions of the
    ///   Python mirror: at most 4 raw ULP per component over the `Quat -> Mat3 -> Quat` round
    ///   trip and 16 over `Mat3 -> Quat -> Mat3`, where the matrix itself is already 1 ULP off
    ///   per element.
    ///
    /// Mirrors `glam::Quat::from_rotation_axes`.
    /// #### Panics
    /// * `'i64_add Overflow'` / `'i64_sub Overflow'` (and their `Underflow` forms) if an element
    ///   is far outside `[-1, 1]`. The division and the square root cannot fail, and the result
    ///   cannot overflow either: whichever branch is taken, the value under the root is
    ///   `1 - m22 -+ (m11 -+ m00) >= 1` by the very tests that select it, so the shared
    ///   reciprocal is at most `1/2` and each output component -- at most half of an already
    ///   valid scalar -- stays in range.
    /// #### Deviations
    /// * The four-branch algorithm of glam-rs (`XMQuaternionRotationMatrix`), branching on
    ///   `m22 <= 0` then on `m11 -+ m00 <= 0`, so that the component the division is carried by
    ///   is the largest of the four (at least `1 / 2` in absolute value).
    fn from_rotation_axes(x_axis: Vec3, y_axis: Vec3, z_axis: Vec3) -> Quat;
    /// Creates a quaternion from a 3x3 rotation matrix.
    ///
    /// #### Preconditions
    /// * As [`QuatTrait::from_rotation_axes`].
    ///
    /// Mirrors `glam::Quat::from_mat3`.
    /// #### Panics
    /// * As [`QuatTrait::from_rotation_axes`].
    /// #### Deviations
    /// * Takes the matrix by value; glam-rs takes `&Mat3`.
    fn from_mat3(mat: Mat3) -> Quat;
    /// Creates a quaternion from the upper 3x3 rotation matrix inside a homogeneous 4x4 matrix.
    ///
    /// #### Preconditions
    /// * As [`QuatTrait::from_rotation_axes`], on the upper 3x3 part.
    ///
    /// Mirrors `glam::Quat::from_mat4`.
    /// #### Panics
    /// * As [`QuatTrait::from_rotation_axes`].
    /// #### Deviations
    /// * Takes the matrix by value; glam-rs takes `&Mat4`.
    fn from_mat4(mat: Mat4) -> Quat;
    /// Creates a quaternion from the 3x3 rotation matrix inside a 3D affine transform.
    ///
    /// #### Preconditions
    /// * Each column of `a.matrix3` must be normalized and the columns must be orthogonal; it
    ///   is not checked. Scales, shears and other non-rotation transforms give an ill-defined
    ///   quaternion, as in glam-rs.
    ///
    /// Mirrors `glam::Quat::from_affine3`.
    /// #### Panics
    /// * As [`QuatTrait::from_rotation_axes`].
    /// #### Deviations
    /// * Takes the affine transform by value; glam-rs takes `&Affine3`.
    fn from_affine3(a: Affine3) -> Quat;
    /// Creates a quaternion rotation from a facing direction and an up direction, for a
    /// left-handed view coordinate system with `+X=right`, `+Y=up` and `+Z=forward`.
    ///
    /// #### Preconditions
    /// * `dir` and `up` must be unit vectors; it is not checked.
    ///
    /// Implementation notes:
    /// * As [`QuatTrait::look_to_rh`].
    ///
    /// Mirrors `glam::Quat::look_to_lh`.
    /// #### Panics
    /// * As [`QuatTrait::look_to_rh`].
    /// #### Deviations
    /// * None.
    fn look_to_lh(dir: Vec3, up: Vec3) -> Quat;
    /// Creates a quaternion rotation from a facing direction and an up direction, for a
    /// right-handed view coordinate system with `+X=right`, `+Y=up` and `+Z=back`.
    ///
    /// #### Preconditions
    /// * `dir` and `up` must be unit vectors; it is not checked.
    ///
    /// Mirrors `glam::Quat::look_to_rh`.
    /// #### Panics
    /// * `'Vec3: normalize zero'` if `dir` and `up` are parallel.
    /// * As [`QuatTrait::from_rotation_axes`] otherwise.
    /// #### Deviations
    /// * Deprecated in glam-rs 0.33.1 in favour of `glam::camera::rh::view::look_to_quat`,
    ///   which is not ported yet (task C1 of `docs/PLAN.md`); the name and the layout are the
    ///   ones of `Quat::look_to_rh`, as for `Mat4::look_to_rh`.
    /// * The side axis is normalized (one square root, one shared division) and the up axis is
    ///   one `mul_sub` per component: the three axes are within 2 ULP per component of the
    ///   exact frame before `from_rotation_axes` runs.
    fn look_to_rh(dir: Vec3, up: Vec3) -> Quat;
    /// Creates a quaternion rotation from a camera position, a focal point and an up direction,
    /// for a left-handed view coordinate system with `+X=right`, `+Y=up` and `+Z=forward`.
    ///
    /// #### Preconditions
    /// * `up` must be a unit vector; it is not checked.
    ///
    /// Implementation notes:
    /// * As [`QuatTrait::look_to_rh`].
    ///
    /// Mirrors `glam::Quat::look_at_lh`.
    /// #### Panics
    /// * `'Vec3: normalize zero'` if `center` is `eye`, or if the direction and `up` are
    ///   parallel.
    /// * As [`QuatTrait::look_to_rh`] otherwise.
    /// #### Deviations
    /// * None.
    fn look_at_lh(eye: Vec3, center: Vec3, up: Vec3) -> Quat;
    /// Creates a quaternion rotation from a camera position, a focal point and an up direction,
    /// for a right-handed view coordinate system with `+X=right`, `+Y=up` and `+Z=back`.
    ///
    /// #### Preconditions
    /// * `up` must be a unit vector; it is not checked.
    ///
    /// Implementation notes:
    /// * As [`QuatTrait::look_to_rh`].
    ///
    /// Mirrors `glam::Quat::look_at_rh`.
    /// #### Panics
    /// * `'Vec3: normalize zero'` if `center` is `eye`, or if the direction and `up` are
    ///   parallel.
    /// * As [`QuatTrait::look_to_rh`] otherwise.
    /// #### Deviations
    /// * None.
    fn look_at_rh(eye: Vec3, center: Vec3, up: Vec3) -> Quat;
    /// Returns the minimal rotation transforming `from` into `to`, in the plane spanned by the
    /// two vectors. Rotates at most 180 degrees.
    ///
    /// `from_rotation_arc(from, to) * from ~= to`.
    ///
    /// #### Preconditions
    /// * `from` and `to` must be unit vectors; it is not checked.
    ///
    /// Mirrors `glam::Quat::from_rotation_arc`.
    /// #### Panics
    /// * `'Fixed: overflow'` if an input is far longer than one.
    /// #### Deviations
    /// * The singular bands use [`NEAR_ONE`] (`1 - 2^-20`) where glam-rs uses
    ///   `1 - 2 f32::EPSILON`: see the const. In the 0 degree band the identity is returned
    ///   instead of a rotation of at most `1.4e-3` rad, and in the 180 degree band the axis is
    ///   an arbitrary orthonormal vector of `from`, i.e. the rotation is off by at most
    ///   `1.4e-3` rad (glam-rs documents `1e-3` for `f32`). Outside the bands the result is
    ///   within 2 ULP per component.
    fn from_rotation_arc(from: Vec3, to: Vec3) -> Quat;
    /// Returns the minimal rotation transforming `from` into `to` **or** `-to`, i.e. making
    /// `from` colinear with `to`. Rotates at most 90 degrees.
    ///
    /// #### Preconditions
    /// * `from` and `to` must be unit vectors; it is not checked.
    ///
    /// Implementation notes:
    /// * As [`QuatTrait::from_rotation_arc`].
    ///
    /// Mirrors `glam::Quat::from_rotation_arc_colinear`.
    /// #### Panics
    /// * As [`QuatTrait::from_rotation_arc`], plus `'i64_neg Underflow'` if a component of `to`
    ///   is `Fixed::MIN`.
    /// #### Deviations
    /// * None.
    fn from_rotation_arc_colinear(from: Vec3, to: Vec3) -> Quat;
    /// Returns the minimal rotation transforming `from` into `to`, around the z axis. Rotates
    /// at most 180 degrees.
    ///
    /// #### Preconditions
    /// * `from` and `to` must be unit vectors; it is not checked.
    ///
    /// Mirrors `glam::Quat::from_rotation_arc_2d`.
    /// #### Panics
    /// * `'Fixed: overflow'` if an input is far longer than one.
    /// #### Deviations
    /// * The singular bands use [`NEAR_ONE`], as [`QuatTrait::from_rotation_arc`].
    /// * The normalization divides once (`Recip`, rounded to nearest) instead of multiplying by
    ///   a reciprocal square root: within 1 ULP per component.
    fn from_rotation_arc_2d(from: Vec2, to: Vec2) -> Quat;
    /// Returns the rotation axis (normalized) and angle (in radians) of `self`.
    ///
    /// Mirrors `glam::Quat::to_axis_angle`.
    /// #### Panics
    /// * `'Fixed: overflow'` if `self.xyz().length()` does not fit the scalar range.
    /// #### Deviations
    /// * `(Vec3::X, 0)` is returned when the vector part is shorter than [`AXIS_EPS`]
    ///   (`2^-16`), where glam-rs uses `1e-8`: the axis is `xyz / length` with a floored
    ///   length, so its own length is off by up to `1 ULP / length` and a shorter vector part
    ///   cannot produce a unit axis (`1.5e-5` at the threshold). The rotation dropped that way
    ///   is at most `2 * 2^-16 = 3.1e-5` rad.
    /// * `atan2` is accurate to 3.22 ULP and the doubling is exact: the angle is within 7 ULP.
    fn to_axis_angle(self: Quat) -> (Vec3, Fixed);
    /// Returns the rotation axis scaled by the rotation angle in radians.
    ///
    /// Implementation notes:
    /// * The `to_axis_angle().0 * angle` of glam-rs: the axis is normalized first, so an
    ///   axis-aligned quaternion gives back exactly `axis * angle`. Sharing the division
    ///   (`xyz * (angle / length)`) is 6 670 gas cheaper (40 500 vs 47 170) but loses that
    ///   exactness; it is kept in `benches::alt::quat`.
    ///
    /// Mirrors `glam::Quat::to_scaled_axis`.
    /// #### Panics
    /// * As [`QuatTrait::to_axis_angle`].
    /// #### Deviations
    /// * `Vec3::ZERO` below the [`AXIS_EPS`] threshold of [`QuatTrait::to_axis_angle`].
    fn to_scaled_axis(self: Quat) -> Vec3;
    /// Returns the quaternion conjugate of `self`. For a unit quaternion it is also the
    /// inverse.
    ///
    /// Implementation notes:
    /// * Exact.
    ///
    /// Mirrors `glam::Quat::conjugate`.
    /// #### Panics
    /// * `'i64_neg Underflow'` if `x`, `y` or `z` is `Fixed::MIN`.
    /// #### Deviations
    /// * None.
    fn conjugate(self: Quat) -> Quat;
    /// Returns the inverse of a normalized quaternion, i.e. its conjugate.
    ///
    /// #### Preconditions
    /// * `self` must be normalized: it is **not** normalized before conjugating, exactly as in
    ///   glam-rs (which checks the precondition under the `glam_assert` feature only). Use
    ///   `q.normalize().inverse()` for a quaternion that may have drifted, and
    ///   `q.conjugate().div_scalar(q.length_squared())` for a general one.
    ///
    /// Implementation notes:
    /// * Exact.
    ///
    /// Mirrors `glam::Quat::inverse`.
    /// #### Panics
    /// * As [`QuatTrait::conjugate`].
    /// #### Deviations
    /// * None.
    fn inverse(self: Quat) -> Quat;
    /// Computes the dot product of `self` and `rhs`: the cosine of the angle between the two
    /// rotations for unit quaternions.
    ///
    /// Mirrors `glam::Quat::dot`.
    /// #### Panics
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    /// #### Deviations
    /// * The `dot4` fused kernel: the exact sum of the 4 products is rescaled once (floored),
    ///   so the result is at most 1 ULP below the exact dot product.
    fn dot(self: Quat, rhs: Quat) -> Fixed;
    /// Computes the length of `self`.
    ///
    /// Mirrors `glam::Quat::length`.
    /// #### Panics
    /// * `'Fixed: overflow'` if the length does not fit the scalar range.
    /// #### Deviations
    /// * The integer square root of the raw sum of squares: the floor of the exact length, at
    ///   most 1 ULP below it, with no intermediate rescale.
    fn length(self: Quat) -> Fixed;
    /// Computes the squared length of `self`.
    ///
    /// Mirrors `glam::Quat::length_squared`.
    /// #### Panics
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    /// #### Deviations
    /// * One fused rescale (floored): at most 1 ULP below the exact value.
    fn length_squared(self: Quat) -> Fixed;
    /// Computes `1 / length()`.
    ///
    /// Mirrors `glam::Quat::length_recip`.
    /// #### Panics
    /// * `'Fixed: division by zero'` if the length is zero.
    /// * `'Fixed: overflow'` if the length or the result does not fit the scalar range.
    /// #### Deviations
    /// * The reciprocal of the floored length, truncated: at most 2 ULP from the exact value
    ///   for a length of at least one.
    fn length_recip(self: Quat) -> Fixed;
    /// Returns `self` normalized to length one.
    ///
    /// Mirrors `glam::Quat::normalize`.
    /// #### Panics
    /// * `'Quat: normalize zero'` if the length is zero (raw sum of squares below 1), where
    ///   glam-rs returns NaN.
    /// #### Deviations
    /// * One integer square root, one division and one fused multiplication per component
    ///   (rounded to nearest): each component is within `1 ULP / length + 1/2 ULP` of the exact
    ///   value.
    fn normalize(self: Quat) -> Quat;
    /// Returns `true` if the length of `self` is one.
    ///
    /// Mirrors `glam::Quat::is_normalized`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * The threshold is 1024 raw ULP (`2^-22`) on the squared length, as for `Vec4`, where
    ///   glam-rs uses `2e-4`: a quaternion normalized by this module is within a few ULP of
    ///   one, and a chain of about 400 successive products stays inside the band (see [`Quat`]).
    ///   The exact Q64.64 sum is compared without narrowing, so long inputs return `false`
    ///   instead of overflowing.
    fn is_normalized(self: Quat) -> bool;
    /// Returns `true` if `self` is a rotation near the identity.
    ///
    /// Implementation notes:
    /// * The threshold `1 - 1e-6` of glam-rs, quantized to `1 - 4295 ULP`: the shortest
    ///   rotation angle is `2 acos(|w|)`, i.e. `2.83e-3` rad at the threshold. Comparing `|w|`
    ///   instead of computing that angle costs at most 1 340 gas instead of 32 070
    ///   (`benches::alt::quat`).
    ///
    /// Mirrors `glam::Quat::is_near_identity`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn is_near_identity(self: Quat) -> bool;
    /// Returns the angle (in radians) of the minimal rotation between `self` and `rhs`, in
    /// `[0, pi]`.
    ///
    /// #### Preconditions
    /// * Both quaternions must be normalized; it is not checked.
    ///
    /// Mirrors `glam::Quat::angle_between`.
    /// #### Panics
    /// * `'Fixed: overflow'` if the dot product does not fit the scalar range.
    /// #### Deviations
    /// * `acos` is the precise `fixed::trig::acos` (2.96 ULP) and not the degree-7
    ///   `acos_approx` of glam-rs; it is clamped to `[-1, 1]` first, as `acos_approx` is. The
    ///   doubling is exact.
    /// * `acos` is ill-conditioned near a dot product of one: the 1 ULP of `dot` becomes up to
    ///   `sqrt(2 * 2^-32) = 2.1e-5` rad on the angle of two nearly equal rotations.
    fn angle_between(self: Quat, rhs: Quat) -> Fixed;
    /// Rotates towards `rhs` up to `max_angle` (in radians), without going past it.
    ///
    /// When `max_angle` is zero the result is `self`, and when it is
    /// `self.angle_between(rhs)` the result is `rhs`. A negative `max_angle` rotates towards
    /// the opposite of `rhs`.
    ///
    /// #### Preconditions
    /// * Both quaternions must be normalized; it is not checked.
    ///
    /// Mirrors `glam::Quat::rotate_towards`.
    /// #### Panics
    /// * As [`QuatTrait::slerp`].
    /// #### Deviations
    /// * The `1e-4` rad shortcut of glam-rs, quantized to 429 497 ULP. It stays above the
    ///   `2.1e-5` rad noise of [`QuatTrait::angle_between`] near zero, so the branch is taken
    ///   on the same side as the exact computation whenever the angle is outside
    ///   `1e-4 +- 2.1e-5`.
    /// * `max_angle / angle` truncates toward zero (1 ULP).
    fn rotate_towards(self: Quat, rhs: Quat, max_angle: Fixed) -> Quat;
    /// Returns `true` if the absolute difference of all elements between `self` and `rhs` is
    /// less than or equal to `max_abs_diff`.
    ///
    /// Mirrors `glam::Quat::abs_diff_eq`.
    /// #### Panics
    /// * Never (the differences are computed on 65-bit values).
    /// #### Deviations
    /// * None.
    fn abs_diff_eq(self: Quat, rhs: Quat, max_abs_diff: Fixed) -> bool;
    /// Performs a linear interpolation between `self` and `end` based on `s`, and normalizes
    /// the result.
    ///
    /// When `s` is zero the result is `self` and when `s` is one the result is `end`. The
    /// shortest path is taken: `end` is negated when the dot product is negative.
    ///
    /// #### Preconditions
    /// * Both quaternions must be normalized; it is not checked.
    ///
    /// Implementation notes:
    /// * Each component is one fused `a (1 - s) + b s` (a single floor rescale) instead of the
    ///   two rounded products of glam-rs, then the shared normalization: within 2 ULP and
    ///   7 020 gas cheaper (24 120 vs 31 140).
    ///
    /// Mirrors `glam::Quat::lerp`.
    /// #### Panics
    /// * `'Quat: normalize zero'` if the interpolant is zero, which unit inputs cannot produce
    ///   (the sign flip aligns `end` with `self`): only a zero input reaches it.
    /// * `'Fixed: overflow'` / `'i64_sub Underflow'` if `s` is far outside `[0, 1]`.
    /// #### Deviations
    /// * Overflow panics where f32 returns infinity or a larger finite value: docs/DESIGN.md
    ///   section 3, "overflow".
    fn lerp(self: Quat, end: Quat, s: Fixed) -> Quat;
    /// Performs a spherical linear interpolation between `self` and `end` based on `s`.
    ///
    /// When `s` is zero the result is `self` and when `s` is one the result is `end`. The
    /// shortest path is taken.
    ///
    /// #### Preconditions
    /// * Both quaternions must be normalized; it is not checked.
    ///
    /// Implementation notes:
    /// * The division by `sin(theta)` is a single shared `Recip` rounded to nearest instead of
    ///   the reciprocal-then-multiply of glam-rs: 8 570 gas cheaper (122 180 vs 130 750).
    ///
    /// Mirrors `glam::Quat::slerp`.
    /// #### Panics
    /// * As [`QuatTrait::lerp`] on the near-identity branch.
    /// * `'Fixed: overflow'` if a component of the result does not fit the scalar range.
    /// #### Deviations
    /// * The nlerp fallback of glam-rs is taken below [`NEAR_ONE`] (`1 - 2^-20`) instead of
    ///   `1 - f32::EPSILON`: see the const. Both branches are then accurate to about
    ///   `4e-7` (~1 600 ULP) in the worst case, at the threshold itself.
    /// * `end` is not negated on the long path: the sign is folded into the interpolation
    ///   weight, which is exact and cannot overflow.
    fn slerp(self: Quat, end: Quat, s: Fixed) -> Quat;
    /// Performs a spherical linear interpolation between `self` and `end`, preserving the
    /// rotation direction even when that selects the longer arc.
    ///
    /// When `s` is zero the result is `self` and when `s` is one the result is `end`.
    ///
    /// #### Preconditions
    /// * Both quaternions must be normalized; it is not checked.
    ///
    /// Mirrors `glam::Quat::slerp_long`.
    /// #### Panics
    /// * As [`QuatTrait::slerp`]. Antipodal inputs at `s = 0.5` reach a zero linear
    ///   interpolant and panic with `'Quat: normalize zero'`, where glam-rs produces NaNs when
    ///   assertions are disabled.
    /// #### Deviations
    /// * Shares the implementation and Q32.32 threshold of [`QuatTrait::slerp`], but does not
    ///   flip `end` when the dot product is negative. The linear fallback tests `abs(dot)` as
    ///   in glam-rs.
    fn slerp_long(self: Quat, end: Quat, s: Fixed) -> Quat;
    /// Multiplies two quaternions: the combined rotation, `self` applied after `rhs`.
    ///
    /// #### Preconditions
    /// * Both quaternions must be normalized for the result to be a rotation; it is not
    ///   checked. The result is not perfectly normalized (see [`Quat`]).
    ///
    /// Implementation notes:
    /// * Each component is one exact 4-term Q64.64 sum rescaled once (floored) instead of four
    ///   rounded products: at most 1 ULP below the exact component, 3.7x cheaper (10 040 vs
    ///   37 080 gas), and an intermediate term outside the scalar range does not panic.
    ///
    /// Mirrors `glam::Quat::mul_quat` and `impl Mul for glam::Quat`.
    /// #### Panics
    /// * `'Fixed: overflow'` if a component of the result does not fit the scalar range.
    /// #### Deviations
    /// * Overflow panics where f32 returns infinity or a larger finite value: docs/DESIGN.md
    ///   section 3, "overflow".
    fn mul_quat(self: Quat, rhs: Quat) -> Quat;
    /// Multiplies a quaternion and a 3D vector, returning the rotated vector.
    ///
    /// #### Preconditions
    /// * `self` must be normalized; it is not checked.
    ///
    /// Implementation notes:
    /// * The glam-rs formulation `v (w^2 - b.b) + b (2 v.b) + (b x v) 2w` with `b = self.xyz()`,
    ///   with every term kept as an exact Q96.96 triple product and one rescale per output
    ///   component: at most 1 ULP below the exact result. The `t = 2 b x v; v + w t + b x t`
    ///   formulation saves three multiplications but rounds three times and costs 2.4x as much
    ///   (22 580 vs 9 360, `benches::alt::quat`).
    ///
    /// Mirrors `glam::Quat::mul_vec3`.
    /// #### Panics
    /// * `'Fixed: overflow'` if a component of the result does not fit the scalar range.
    /// #### Deviations
    /// * Overflow panics where f32 returns infinity or a larger finite value: docs/DESIGN.md
    ///   section 3, "overflow".
    fn mul_vec3(self: Quat, rhs: Vec3) -> Vec3;
    /// Returns `[self.x * rhs, self.y * rhs, ..]`.
    ///
    /// Mirrors `impl Mul<f32> for glam::Quat`.
    /// #### Panics
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    /// #### Deviations
    /// * glam-rs spells this with an operator; the core operator traits of Cairo are
    ///   homogeneous (docs/DESIGN.md section 3).
    /// * The product is floored (one rescale per component), not rounded to nearest.
    fn mul_scalar(self: Quat, rhs: Fixed) -> Quat;
    /// Returns `[self.x / rhs, self.y / rhs, ..]`.
    ///
    /// Mirrors `impl Div<f32> for glam::Quat`.
    /// #### Panics
    /// * `'Fixed: division by zero'` if `rhs` is zero.
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    /// #### Deviations
    /// * glam-rs spells this with an operator (docs/DESIGN.md section 3).
    /// * One division shared by the components (`Recip`) and one fused multiplication each,
    ///   rounded to nearest.
    fn div_scalar(self: Quat, rhs: Fixed) -> Quat;
}

pub impl QuatImpl of QuatTrait {
    const ZERO: Quat = Quat {
        x: Fixed { raw: 0 }, y: Fixed { raw: 0 }, z: Fixed { raw: 0 }, w: Fixed { raw: 0 },
    };
    const IDENTITY: Quat = Quat {
        x: Fixed { raw: 0 },
        y: Fixed { raw: 0 },
        z: Fixed { raw: 0 },
        w: Fixed { raw: 0x100000000 },
    };

    #[inline(always)]
    fn from_xyzw(x: Fixed, y: Fixed, z: Fixed, w: Fixed) -> Quat {
        Quat { x, y, z, w }
    }

    #[inline(always)]
    fn from_array(a: [Fixed; 4]) -> Quat {
        let [x, y, z, w] = a;
        Quat { x, y, z, w }
    }

    #[inline(always)]
    fn from_vec4(v: Vec4) -> Quat {
        Quat { x: v.x, y: v.y, z: v.z, w: v.w }
    }

    #[inline(always)]
    fn to_array(self: Quat) -> [Fixed; 4] {
        [self.x, self.y, self.z, self.w]
    }

    #[inline(always)]
    fn xyz(self: Quat) -> Vec3 {
        Vec3 { x: self.x, y: self.y, z: self.z }
    }

    fn from_axis_angle(axis: Vec3, angle: Fixed) -> Quat {
        let (s, c) = (angle * F_HALF).sin_cos();
        Quat { x: axis.x * s, y: axis.y * s, z: axis.z * s, w: c }
    }

    fn from_scaled_axis(v: Vec3) -> Quat {
        let n = norm3_wide(v.x, v.y, v.z);
        match n.try_recip() {
            Some(r) => {
                // `from_axis_angle(v / length, length)`: the axis is normalized first, so that an
                // axis-aligned input stays exactly axis-aligned.
                let axis = Vec3 { x: r.mul(v.x), y: r.mul(v.y), z: r.mul(v.z) };
                Self::from_axis_angle(axis, n.to_fixed())
            },
            None => Self::IDENTITY,
        }
    }

    fn from_rotation_x(angle: Fixed) -> Quat {
        let (s, c) = (angle * F_HALF).sin_cos();
        Quat { x: s, y: F_ZERO, z: F_ZERO, w: c }
    }

    fn from_rotation_y(angle: Fixed) -> Quat {
        let (s, c) = (angle * F_HALF).sin_cos();
        Quat { x: F_ZERO, y: s, z: F_ZERO, w: c }
    }

    fn from_rotation_z(angle: Fixed) -> Quat {
        let (s, c) = (angle * F_HALF).sin_cos();
        Quat { x: F_ZERO, y: F_ZERO, z: s, w: c }
    }

    fn from_rotation_axes(x_axis: Vec3, y_axis: Vec3, z_axis: Vec3) -> Quat {
        // Based on the `XMQuaternionRotationMatrix` of DirectXMath, as glam-rs is: the branch
        // taken is the one of the largest of the four components, so that `4 c^2 >= 1` and the
        // shared division is always well conditioned. `r` is `1 / (4 |c|)`, i.e. the
        // `0.5 / sqrt(4 c^2)` of glam-rs, kept wide.
        if !z_axis.z.is_positive() {
            // x^2 + y^2 >= z^2 + w^2
            let dif10 = y_axis.y - x_axis.x;
            let omm22 = F_ONE - z_axis.z;
            if !dif10.is_positive() {
                // x^2 >= y^2
                let four_xsq = omm22 - dif10;
                let r = recip_of_twice_sqrt(four_xsq);
                Quat {
                    x: r.mul(four_xsq),
                    y: r.mul(x_axis.y + y_axis.x),
                    z: r.mul(x_axis.z + z_axis.x),
                    w: r.mul(y_axis.z - z_axis.y),
                }
            } else {
                // y^2 >= x^2
                let four_ysq = omm22 + dif10;
                let r = recip_of_twice_sqrt(four_ysq);
                Quat {
                    x: r.mul(x_axis.y + y_axis.x),
                    y: r.mul(four_ysq),
                    z: r.mul(y_axis.z + z_axis.y),
                    w: r.mul(z_axis.x - x_axis.z),
                }
            }
        } else {
            // z^2 + w^2 >= x^2 + y^2
            let sum10 = y_axis.y + x_axis.x;
            let opm22 = F_ONE + z_axis.z;
            if !sum10.is_positive() {
                // z^2 >= w^2
                let four_zsq = opm22 - sum10;
                let r = recip_of_twice_sqrt(four_zsq);
                Quat {
                    x: r.mul(x_axis.z + z_axis.x),
                    y: r.mul(y_axis.z + z_axis.y),
                    z: r.mul(four_zsq),
                    w: r.mul(x_axis.y - y_axis.x),
                }
            } else {
                // w^2 >= z^2
                let four_wsq = opm22 + sum10;
                let r = recip_of_twice_sqrt(four_wsq);
                Quat {
                    x: r.mul(y_axis.z - z_axis.y),
                    y: r.mul(z_axis.x - x_axis.z),
                    z: r.mul(x_axis.y - y_axis.x),
                    w: r.mul(four_wsq),
                }
            }
        }
    }

    #[inline(always)]
    fn from_mat3(mat: Mat3) -> Quat {
        Self::from_rotation_axes(mat.x_axis, mat.y_axis, mat.z_axis)
    }

    #[inline(always)]
    fn from_mat4(mat: Mat4) -> Quat {
        Self::from_rotation_axes(
            mat.x_axis.truncate(), mat.y_axis.truncate(), mat.z_axis.truncate(),
        )
    }

    #[inline(always)]
    fn from_affine3(a: Affine3) -> Quat {
        Self::from_mat3(a.matrix3)
    }

    #[inline(always)]
    fn look_to_lh(dir: Vec3, up: Vec3) -> Quat {
        Self::look_to_rh(-dir, up)
    }

    fn look_to_rh(dir: Vec3, up: Vec3) -> Quat {
        let s = dir.cross(up).normalize();
        let u = s.cross(dir);
        Self::from_rotation_axes(
            Vec3 { x: s.x, y: u.x, z: -dir.x },
            Vec3 { x: s.y, y: u.y, z: -dir.y },
            Vec3 { x: s.z, y: u.z, z: -dir.z },
        )
    }

    #[inline(always)]
    fn look_at_lh(eye: Vec3, center: Vec3, up: Vec3) -> Quat {
        Self::look_to_lh((center - eye).normalize(), up)
    }

    #[inline(always)]
    fn look_at_rh(eye: Vec3, center: Vec3, up: Vec3) -> Quat {
        Self::look_to_rh((center - eye).normalize(), up)
    }

    fn from_rotation_arc(from: Vec3, to: Vec3) -> Quat {
        let d = from.dot(to);
        if d > NEAR_ONE {
            // 0 degree singularity: from ~= to.
            Self::IDENTITY
        } else if d < NEG_NEAR_ONE {
            // 180 degree singularity: from ~= -to.
            Self::from_axis_angle(from.any_orthonormal_vector(), F_PI)
        } else {
            let c = from.cross(to);
            Self::normalize(Quat { x: c.x, y: c.y, z: c.z, w: F_ONE + d })
        }
    }

    fn from_rotation_arc_colinear(from: Vec3, to: Vec3) -> Quat {
        if from.dot(to).is_negative() {
            Self::from_rotation_arc(from, -to)
        } else {
            Self::from_rotation_arc(from, to)
        }
    }

    fn from_rotation_arc_2d(from: Vec2, to: Vec2) -> Quat {
        let d = from.dot(to);
        if d > NEAR_ONE {
            Self::IDENTITY
        } else if d < NEG_NEAR_ONE {
            // Rotation around z by pi radians.
            Quat { x: F_ZERO, y: F_ZERO, z: F_ONE, w: F_ZERO }
        } else {
            // The z component of a 3D cross product with x = y = 0.
            let z = mul_sub(from.x, to.y, to.x, from.y);
            let w = F_ONE + d;
            let r = norm2_wide(z, w).recip();
            Quat { x: F_ZERO, y: F_ZERO, z: r.mul(z), w: r.mul(w) }
        }
    }

    fn to_axis_angle(self: Quat) -> (Vec3, Fixed) {
        let n = norm3_wide(self.x, self.y, self.z);
        if n.to_fixed() >= AXIS_EPS {
            let a = n.to_fixed().atan2(self.w);
            let r = n.recip();
            (Vec3 { x: r.mul(self.x), y: r.mul(self.y), z: r.mul(self.z) }, a + a)
        } else {
            (Vec3Trait::X, F_ZERO)
        }
    }

    fn to_scaled_axis(self: Quat) -> Vec3 {
        let (axis, angle) = Self::to_axis_angle(self);
        Vec3 { x: axis.x * angle, y: axis.y * angle, z: axis.z * angle }
    }

    #[inline(always)]
    fn conjugate(self: Quat) -> Quat {
        Quat { x: -self.x, y: -self.y, z: -self.z, w: self.w }
    }

    #[inline(always)]
    fn inverse(self: Quat) -> Quat {
        Self::conjugate(self)
    }

    #[inline(always)]
    fn dot(self: Quat, rhs: Quat) -> Fixed {
        dot4(self.x, rhs.x, self.y, rhs.y, self.z, rhs.z, self.w, rhs.w)
    }

    #[inline(always)]
    fn length(self: Quat) -> Fixed {
        norm4(self.x, self.y, self.z, self.w)
    }

    #[inline(always)]
    fn length_squared(self: Quat) -> Fixed {
        norm4_squared(self.x, self.y, self.z, self.w)
    }

    #[inline(always)]
    fn length_recip(self: Quat) -> Fixed {
        Self::length(self).recip()
    }

    #[inline(always)]
    fn normalize(self: Quat) -> Quat {
        let n = norm4_wide(self.x, self.y, self.z, self.w);
        match n.try_recip() {
            Some(r) => Quat {
                x: r.mul(self.x), y: r.mul(self.y), z: r.mul(self.z), w: r.mul(self.w),
            },
            None => core::panic_with_felt252('Quat: normalize zero'),
        }
    }

    #[inline(always)]
    fn is_normalized(self: Quat) -> bool {
        is_unit4(self.x, self.y, self.z, self.w, NORMALIZED_EPS_RAW)
    }

    #[inline(always)]
    fn is_near_identity(self: Quat) -> bool {
        // The shortest rotation angle is `2 acos(|w|)`; `acos` decreases, so comparing `|w|` to
        // the cosine threshold avoids computing the angle.
        self.w > NEAR_IDENTITY_W || self.w < NEG_NEAR_IDENTITY_W
    }

    #[inline(always)]
    fn angle_between(self: Quat, rhs: Quat) -> Fixed {
        let a = Self::dot(self, rhs).abs().acos_clamped();
        a + a
    }

    fn rotate_towards(self: Quat, rhs: Quat, max_angle: Fixed) -> Quat {
        // Keep the dot and half-angle for the interpolation: calling `slerp` here would compute
        // both a second time.
        let d0 = Self::dot(self, rhs);
        let flip = d0.is_negative();
        let d = if flip {
            -d0
        } else {
            d0
        };
        let theta = d.acos_clamped();
        let angle = theta + theta;
        if angle <= ROTATE_TOWARDS_EPS {
            rhs
        } else {
            let s = (max_angle / angle).clamp(F_NEG_ONE, F_ONE);
            if d > NEAR_ONE {
                lerp_impl(self, rhs, s, if flip {
                    -s
                } else {
                    s
                })
            } else {
                slerp_weights(self, rhs, s, theta, flip)
            }
        }
    }

    #[inline(always)]
    fn abs_diff_eq(self: Quat, rhs: Quat, max_abs_diff: Fixed) -> bool {
        self.x.abs_diff_eq(rhs.x, max_abs_diff)
            && self.y.abs_diff_eq(rhs.y, max_abs_diff)
            && self.z.abs_diff_eq(rhs.z, max_abs_diff)
            && self.w.abs_diff_eq(rhs.w, max_abs_diff)
    }

    fn lerp(self: Quat, end: Quat, s: Fixed) -> Quat {
        let t = if Self::dot(self, end).is_negative() {
            -s
        } else {
            s
        };
        lerp_impl(self, end, s, t)
    }

    fn slerp(self: Quat, end: Quat, s: Fixed) -> Quat {
        slerp_impl(self, end, s, true)
    }

    fn slerp_long(self: Quat, end: Quat, s: Fixed) -> Quat {
        slerp_impl(self, end, s, false)
    }

    #[inline(always)]
    fn mul_quat(self: Quat, rhs: Quat) -> Quat {
        // The Hamilton product: four exact 4-term sums, the signs carried by `sub` (free) rather
        // than by negating the operands.
        Quat {
            x: wide_mul(self.w, rhs.x)
                .add(wide_mul(self.x, rhs.w))
                .add(wide_mul(self.y, rhs.z))
                .sub(wide_mul(self.z, rhs.y))
                .narrow(),
            y: wide_mul(self.w, rhs.y)
                .sub(wide_mul(self.x, rhs.z))
                .add(wide_mul(self.y, rhs.w))
                .add(wide_mul(self.z, rhs.x))
                .narrow(),
            z: wide_mul(self.w, rhs.z)
                .add(wide_mul(self.x, rhs.y))
                .sub(wide_mul(self.y, rhs.x))
                .add(wide_mul(self.z, rhs.w))
                .narrow(),
            w: wide_mul(self.w, rhs.w)
                .sub(wide_mul(self.x, rhs.x))
                .sub(wide_mul(self.y, rhs.y))
                .sub(wide_mul(self.z, rhs.z))
                .narrow(),
        }
    }

    #[inline(always)]
    fn mul_vec3(self: Quat, rhs: Vec3) -> Vec3 {
        // `v (w^2 - b.b) + b (2 v.b) + (b x v) 2w` with `b = self.xyz()`: every term is a triple
        // product, the sums stay exact at the Q96.96 scale and each component is rescaled once.
        let s1 = wide_mul(self.w, self.w)
            .sub(wide_mul(self.x, self.x))
            .sub(wide_mul(self.y, self.y))
            .sub(wide_mul(self.z, self.z));
        let d = wide_mul(rhs.x, self.x).add(wide_mul(rhs.y, self.y)).add(wide_mul(rhs.z, self.z));
        let s2 = d.add(d);
        let cx = wide_mul(self.y, rhs.z).sub(wide_mul(rhs.y, self.z));
        let cy = wide_mul(self.z, rhs.x).sub(wide_mul(rhs.z, self.x));
        let cz = wide_mul(self.x, rhs.y).sub(wide_mul(rhs.x, self.y));
        Vec3 {
            x: s1.mul(rhs.x).add(s2.mul(self.x)).add(cx.add(cx).mul(self.w)).narrow(),
            y: s1.mul(rhs.y).add(s2.mul(self.y)).add(cy.add(cy).mul(self.w)).narrow(),
            z: s1.mul(rhs.z).add(s2.mul(self.z)).add(cz.add(cz).mul(self.w)).narrow(),
        }
    }

    #[inline(always)]
    fn mul_scalar(self: Quat, rhs: Fixed) -> Quat {
        Quat { x: self.x * rhs, y: self.y * rhs, z: self.z * rhs, w: self.w * rhs }
    }

    #[inline(always)]
    fn div_scalar(self: Quat, rhs: Fixed) -> Quat {
        let r = RecipTrait::new(rhs);
        Quat { x: r.mul(self.x), y: r.mul(self.y), z: r.mul(self.z), w: r.mul(self.w) }
    }
}

/// Component-wise `+`. The sum is not normalized, and adding two rotations is **not** combining
/// them (that is [`QuatTrait::mul_quat`]). Exact.
///
/// Mirrors `impl Add for glam::Quat`.
/// #### Panics
/// * `'i64_add Overflow'` / `'i64_add Underflow'` if a component leaves the scalar range.
pub impl QuatAdd of Add<Quat> {
    #[inline(always)]
    fn add(lhs: Quat, rhs: Quat) -> Quat {
        Quat { x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z, w: lhs.w + rhs.w }
    }
}

/// Component-wise `+=`, delegating to [`QuatAdd`].
///
/// Mirrors `impl AddAssign for glam::Quat`.
pub impl QuatAddAssign of AddAssign<Quat, Quat> {
    #[inline(always)]
    fn add_assign(ref self: Quat, rhs: Quat) {
        self = self + rhs;
    }
}

/// Component-wise `-`. The difference is not normalized. Exact.
///
/// Mirrors `impl Sub for glam::Quat`.
/// #### Panics
/// * `'i64_sub Overflow'` / `'i64_sub Underflow'` if a component leaves the scalar range.
pub impl QuatSub of Sub<Quat> {
    #[inline(always)]
    fn sub(lhs: Quat, rhs: Quat) -> Quat {
        Quat { x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z, w: lhs.w - rhs.w }
    }
}

/// Component-wise `-=`, delegating to [`QuatSub`].
///
/// Mirrors `impl SubAssign for glam::Quat`.
pub impl QuatSubAssign of SubAssign<Quat, Quat> {
    #[inline(always)]
    fn sub_assign(ref self: Quat, rhs: Quat) {
        self = self - rhs;
    }
}

/// The Hamilton product, i.e. [`QuatTrait::mul_quat`].
///
/// Mirrors `impl Mul for glam::Quat`.
/// #### Panics
/// * `'Fixed: overflow'` if a component of the result does not fit the scalar range.
/// #### Deviations
/// * `Quat * Vec3` is not an operator: the core `Mul<T>` of Cairo is homogeneous
///   (docs/DESIGN.md section 3). Use [`QuatTrait::mul_vec3`].
pub impl QuatMul of Mul<Quat> {
    #[inline(always)]
    fn mul(lhs: Quat, rhs: Quat) -> Quat {
        QuatImpl::mul_quat(lhs, rhs)
    }
}

/// Hamilton-product `*=`, delegating to [`QuatTrait::mul_quat`].
///
/// Mirrors `impl MulAssign for glam::Quat`.
pub impl QuatMulAssign of MulAssign<Quat, Quat> {
    #[inline(always)]
    fn mul_assign(ref self: Quat, rhs: Quat) {
        self = QuatTrait::mul_quat(self, rhs);
    }
}

/// Scalar `*=`, delegating to [`QuatTrait::mul_scalar`].
///
/// Mirrors `impl MulAssign<f32> for glam::Quat`.
pub impl QuatMulAssignScalar of MulAssign<Quat, Fixed> {
    #[inline(always)]
    fn mul_assign(ref self: Quat, rhs: Fixed) {
        self = QuatTrait::mul_scalar(self, rhs);
    }
}

/// Scalar `/=`, delegating to [`QuatTrait::div_scalar`].
///
/// Mirrors `impl DivAssign<f32> for glam::Quat`.
pub impl QuatDivAssignScalar of DivAssign<Quat, Fixed> {
    #[inline(always)]
    fn div_assign(ref self: Quat, rhs: Fixed) {
        self = QuatTrait::div_scalar(self, rhs);
    }
}

/// Component-wise negation: the same rotation, with the opposite interpolation path.
///
/// Mirrors `impl Neg for glam::Quat`.
/// #### Panics
/// * `'i64_neg Underflow'` if a component is `Fixed::MIN`.
/// #### Deviations
/// * glam-rs spells it `self * -1.0`, which panics with `'Fixed: overflow'` in the same case.
pub impl QuatNeg of Neg<Quat> {
    #[inline(always)]
    fn neg(a: Quat) -> Quat {
        Quat { x: -a.x, y: -a.y, z: -a.z, w: -a.w }
    }
}

/// The identity quaternion.
///
/// Mirrors `impl Default for glam::Quat`.
/// #### Panics
/// * Never.
/// #### Deviations
/// * Not derived: the derive would produce the zero quaternion.
pub impl QuatDefault of Default<Quat> {
    #[inline(always)]
    fn default() -> Quat {
        QuatImpl::IDENTITY
    }
}

/// Mirrors `impl From<Quat> for glam::Vec4`.
pub impl QuatIntoVec4 of Into<Quat, Vec4> {
    #[inline(always)]
    fn into(self: Quat) -> Vec4 {
        Vec4 { x: self.x, y: self.y, z: self.z, w: self.w }
    }
}

/// Mirrors `glam::Quat::from_vec4`.
pub impl Vec4IntoQuat of Into<Vec4, Quat> {
    #[inline(always)]
    fn into(self: Vec4) -> Quat {
        Quat { x: self.x, y: self.y, z: self.z, w: self.w }
    }
}

/// Mirrors `glam::Quat::from_array`.
pub impl FixedArrayIntoQuat of Into<[Fixed; 4], Quat> {
    #[inline(always)]
    fn into(self: [Fixed; 4]) -> Quat {
        let [x, y, z, w] = self;
        Quat { x, y, z, w }
    }
}

/// Mirrors `impl From<Quat> for [f32; 4]`.
pub impl QuatIntoFixedArray of Into<Quat, [Fixed; 4]> {
    #[inline(always)]
    fn into(self: Quat) -> [Fixed; 4] {
        [self.x, self.y, self.z, self.w]
    }
}

/// Mirrors `glam::Quat::from_xyzw`.
pub impl FixedTupleIntoQuat of Into<(Fixed, Fixed, Fixed, Fixed), Quat> {
    #[inline(always)]
    fn into(self: (Fixed, Fixed, Fixed, Fixed)) -> Quat {
        let (x, y, z, w) = self;
        Quat { x, y, z, w }
    }
}

/// Mirrors `impl From<Quat> for (f32, f32, f32, f32)`.
pub impl QuatIntoFixedTuple of Into<Quat, (Fixed, Fixed, Fixed, Fixed)> {
    #[inline(always)]
    fn into(self: Quat) -> (Fixed, Fixed, Fixed, Fixed) {
        (self.x, self.y, self.z, self.w)
    }
}

/// `0`.
const F_ZERO: Fixed = Fixed { raw: 0 };

/// `1`.
const F_ONE: Fixed = Fixed { raw: 0x100000000 };

/// `-1`.
const F_NEG_ONE: Fixed = Fixed { raw: -0x100000000 };

/// `1 / 2`.
const F_HALF: Fixed = Fixed { raw: 0x80000000 };

/// `pi`.
const F_PI: Fixed = Fixed { raw: 13493037705 };

/// The `is_normalized` threshold: 1024 raw ULP (`2^-22`) on the squared length, as for `Vec4`.
const NORMALIZED_EPS_RAW: u16 = 1024;

/// `1 - 2^-20`, the cosine threshold of the singular branches of `from_rotation_arc`,
/// `from_rotation_arc_2d` and `slerp`, where glam-rs uses `1 - f32::EPSILON` (`slerp`) and
/// `1 - 2 f32::EPSILON` (the arcs).
///
/// Below a half-angle of `theta = acos(NEAR_ONE) = 1.95e-3` rad the `slerp` branch divides by
/// `sin(theta)`, which costs `3 ULP / sin(theta) = 3.5e-7` on each component, while the nlerp
/// fallback differs from the exact slerp by `theta^2 / 8 = 4.8e-7`: the two branches meet with
/// the same accuracy, which is what fixes the threshold. The same band makes the 180 degree
/// branch of `from_rotation_arc` accurate to `sqrt(2 * 2^-20) = 1.4e-3` rad (glam-rs documents
/// `1e-3` for `f32`) and keeps the normalization of the general branch, whose length is
/// `sqrt(2 (1 + dot))`, within `2^-32 / 1.4e-3 = 1.7e-7` per component.
pub const NEAR_ONE: Fixed = Fixed { raw: 0xfffff000 };

/// `-(1 - 2^-20)`: see [`NEAR_ONE`].
pub const NEG_NEAR_ONE: Fixed = Fixed { raw: -0xfffff000 };

/// `2^-16`, the shortest vector part `to_axis_angle` and `to_scaled_axis` accept before
/// returning the identity axis, where glam-rs uses `1e-8`: the axis is `xyz / length` with a
/// floored length, so `|axis|` is off by up to `1 ULP / length`, i.e. `1.5e-5` at the threshold.
pub const AXIS_EPS: Fixed = Fixed { raw: 0x10000 };

/// `1 - 1e-6` quantized (`1 - 4295 ULP`), the `is_near_identity` threshold of glam-rs: an angle
/// of `2 acos(1 - 1e-6) = 2.83e-3` rad.
pub const NEAR_IDENTITY_W: Fixed = Fixed { raw: 4294963001 };

/// `-(1 - 1e-6)`: see [`NEAR_IDENTITY_W`].
const NEG_NEAR_IDENTITY_W: Fixed = Fixed { raw: -4294963001 };

/// `1e-4` rad quantized (429 497 ULP), the angle below which `rotate_towards` returns the target
/// directly, as in glam-rs.
pub const ROTATE_TOWARDS_EPS: Fixed = Fixed { raw: 429497 };

/// `1 / (2 sqrt(v))`, the shared division of the four branches of
/// [`QuatTrait::from_rotation_axes`]: the `0.5 / sqrt(v)` of glam-rs, kept wide so that the four
/// components it scales are rounded once instead of twice.
///
/// `v` is `4 c^2` for the largest component `c` of the quaternion, so `v >= 1` for a rotation
/// matrix and the square root loses at most 1 ULP relative to `2 |c| >= 1`.
#[inline(always)]
fn recip_of_twice_sqrt(v: Fixed) -> Recip {
    let s = v.sqrt();
    RecipTrait::new(s + s)
}

/// Shared body of `slerp` and `slerp_long`. A rotation is represented by both `q` and `-q`:
/// the short path folds a negative dot into the second weight, while the long path preserves it.
#[inline(always)]
fn slerp_impl(a: Quat, b: Quat, s: Fixed, shortest: bool) -> Quat {
    let d0 = QuatImpl::dot(a, b);
    let flip = shortest && d0.is_negative();
    let d = if flip {
        -d0
    } else {
        d0
    };
    let near = if shortest {
        d > NEAR_ONE
    } else {
        d.abs() > NEAR_ONE
    };
    if near {
        // `sin(theta)` is too small to divide by: interpolate linearly as glam-rs does.
        lerp_impl(a, b, s, if flip {
            -s
        } else {
            s
        })
    } else {
        let theta = d.acos();
        slerp_weights(a, b, s, theta, flip)
    }
}

/// The trigonometric interpolation after the caller has selected the path and computed `theta`.
#[inline(always)]
fn slerp_weights(a: Quat, b: Quat, s: Fixed, theta: Fixed, flip: bool) -> Quat {
    let scale1 = (theta * (F_ONE - s)).sin();
    let sin2 = (theta * s).sin();
    let scale2 = if flip {
        -sin2
    } else {
        sin2
    };
    let r = RecipTrait::new(theta.sin());
    Quat {
        x: r.mul(wide_mul(a.x, scale1).add(wide_mul(b.x, scale2)).narrow()),
        y: r.mul(wide_mul(a.y, scale1).add(wide_mul(b.y, scale2)).narrow()),
        z: r.mul(wide_mul(a.z, scale1).add(wide_mul(b.z, scale2)).narrow()),
        w: r.mul(wide_mul(a.w, scale1).add(wide_mul(b.w, scale2)).narrow()),
    }
}

/// `(a (1 - s) + b t).normalize()`: the `lerp_impl` of glam-rs with the sign of the shortest
/// path folded into the weight `t = +-s`, one fused rescale per component.
#[inline(always)]
fn lerp_impl(a: Quat, b: Quat, s: Fixed, t: Fixed) -> Quat {
    let u = F_ONE - s;
    QuatImpl::normalize(
        Quat {
            x: wide_mul(a.x, u).add(wide_mul(b.x, t)).narrow(),
            y: wide_mul(a.y, u).add(wide_mul(b.y, t)).narrow(),
            z: wide_mul(a.z, u).add(wide_mul(b.z, t)).narrow(),
            w: wide_mul(a.w, u).add(wide_mul(b.w, t)).narrow(),
        },
    )
}
