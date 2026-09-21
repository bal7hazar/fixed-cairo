//! View (camera) constructors for right-handed world coordinate systems.
//!
//! Every function transforms world space points into a right-handed Y-up
//! view space with X-right and -Z-forward.
//!
//! * `look_at_*` targets a focal point (`center`)
//! * `look_to_*` targets a forward direction (`dir`)
//!
//! Functions returning `Mat4` return a full view transform (rotation and translation).
//! Functions returning `Mat3` return only the view rotation.

use crate::affine3::{Affine3, Affine3Trait};
use crate::camera::camera_impl;
use crate::mat3::Mat3;
use crate::mat4::Mat4;
use crate::quat::{Quat, QuatTrait};
use crate::vec3::{Vec3, Vec3Trait};

/// Returns a `Mat4` view matrix from eye, focal point, and up.
///
/// Transforms right-handed world space points into right-handed Y-up view space.
///
/// Mirrors `glam::camera::rh::view::look_at_mat4`.
/// #### Panics
/// * `'Vec3: normalize zero'` if `center == eye`, or if the direction and `up` are parallel.
/// * `'Fixed: overflow'` if an element does not fit the scalar range.
/// * `'i64_neg Underflow'` if an element is `MIN`.
/// * `'i64_sub Overflow'` / `'i64_sub Underflow'` if an element difference leaves the scalar range.
/// #### Deviations
/// * The `glam_assert!` preconditions are not checked (docs/DESIGN.md section 3): `up` must be
///   normalized.
/// * Bit-identical to `Mat4::look_at_rh` (`glam::mat4`), inlined: measured 4.2k (`look_to`) to 5.1k
///   (`look_at`) gas cheaper than calling it (`alt_look_*_mat4_delegate` in `gas/camera.snap`). `s`
///   is normalized (one square root, one shared division), every other element is exact or one
///   floored `dot3`.
#[inline(always)]
pub fn look_at_mat4(eye: Vec3, center: Vec3, up: Vec3) -> Mat4 {
    camera_impl::look_to_mat4_rh(eye, Vec3Trait::normalize(center - eye), up)
}

/// Returns a `Mat4` view matrix from eye, forward direction, and up.
///
/// Transforms right-handed world space points into right-handed Y-up view space.
///
/// Mirrors `glam::camera::rh::view::look_to_mat4`.
/// #### Panics
/// * `'Vec3: normalize zero'` if `dir` and `up` are parallel.
/// * `'Fixed: overflow'` if an element does not fit the scalar range.
/// * `'i64_neg Underflow'` if an element is `MIN`.
/// #### Deviations
/// * The `glam_assert!` preconditions are not checked (docs/DESIGN.md section 3): `dir` and `up`
///   must be normalized.
/// * Bit-identical to `Mat4::look_to_rh` (`glam::mat4`), inlined: measured 4.2k (`look_to`) to 5.1k
///   (`look_at`) gas cheaper than calling it (`alt_look_*_mat4_delegate` in `gas/camera.snap`). `s`
///   is normalized (one square root, one shared division), every other element is exact or one
///   floored `dot3`.
#[inline(always)]
pub fn look_to_mat4(eye: Vec3, dir: Vec3, up: Vec3) -> Mat4 {
    camera_impl::look_to_mat4_rh(eye, dir, up)
}

/// Returns an `Affine3` view transform from eye, focal point, and up.
///
/// Mirrors `glam::camera::rh::view::look_at_affine3`.
/// #### Panics
/// * As [`look_at_mat4`].
/// #### Deviations
/// * The `glam_assert!` preconditions are not checked. The shared Mat4 look-to kernel is used,
///   then its exact affine columns are extracted.
#[inline(always)]
pub fn look_at_affine3(eye: Vec3, center: Vec3, up: Vec3) -> Affine3 {
    Affine3Trait::from_mat4(
        camera_impl::look_to_mat4_rh(eye, Vec3Trait::normalize(center - eye), up),
    )
}

/// Returns an `Affine3` view transform from eye, forward direction, and up.
///
/// Mirrors `glam::camera::rh::view::look_to_affine3`.
/// #### Panics
/// * As [`look_to_mat4`].
/// #### Deviations
/// * The `glam_assert!` preconditions are not checked. The shared Mat4 look-to kernel is used,
///   then its exact affine columns are extracted.
#[inline(always)]
pub fn look_to_affine3(eye: Vec3, dir: Vec3, up: Vec3) -> Affine3 {
    Affine3Trait::from_mat4(camera_impl::look_to_mat4_rh(eye, dir, up))
}

/// Returns a `Mat3` view rotation (no translation) from eye, focal point, and up.
///
/// Transforms right-handed world space points into right-handed Y-up view space.
///
/// Mirrors `glam::camera::rh::view::look_at_mat3`.
/// #### Panics
/// * `'Vec3: normalize zero'` if `center == eye`, or if the direction and `up` are parallel.
/// * `'Fixed: overflow'` if an element does not fit the scalar range.
/// * `'i64_neg Underflow'` if an element is `MIN`.
/// * `'i64_sub Overflow'` / `'i64_sub Underflow'` if an element difference leaves the scalar range.
/// #### Deviations
/// * The `glam_assert!` preconditions are not checked (docs/DESIGN.md section 3): `up` must be
///   normalized.
/// * `Mat3A` collapses into `Mat3`: there is no `look_at_mat3a`.
/// * `s` is normalized (one square root, one shared division), every other element is exact.
#[inline(always)]
pub fn look_at_mat3(eye: Vec3, center: Vec3, up: Vec3) -> Mat3 {
    camera_impl::look_to_mat3_rh(Vec3Trait::normalize(center - eye), up)
}

/// Returns a `Mat3` view rotation (no translation) from direction and up.
///
/// Transforms right-handed world space points into right-handed Y-up view space.
///
/// Mirrors `glam::camera::rh::view::look_to_mat3`.
/// #### Panics
/// * `'Vec3: normalize zero'` if `dir` and `up` are parallel.
/// * `'Fixed: overflow'` if an element does not fit the scalar range.
/// * `'i64_neg Underflow'` if an element is `MIN`.
/// #### Deviations
/// * The `glam_assert!` preconditions are not checked (docs/DESIGN.md section 3): `dir` and `up`
///   must be normalized.
/// * `Mat3A` collapses into `Mat3`: there is no `look_to_mat3a`.
/// * `s` is normalized (one square root, one shared division), every other element is exact.
#[inline(always)]
pub fn look_to_mat3(dir: Vec3, up: Vec3) -> Mat3 {
    camera_impl::look_to_mat3_rh(dir, up)
}

/// Returns a quaternion view rotation from eye, focal point, and up.
///
/// Mirrors `glam::camera::rh::view::look_at_quat`.
/// #### Panics
/// * As [`look_at_mat3`], then as [`QuatTrait::from_mat3`].
/// #### Deviations
/// * The `glam_assert!` preconditions are not checked. The shared Mat3 look-to kernel is
///   converted with `Quat::from_mat3`.
#[inline(always)]
pub fn look_at_quat(eye: Vec3, center: Vec3, up: Vec3) -> Quat {
    QuatTrait::from_mat3(camera_impl::look_to_mat3_rh(Vec3Trait::normalize(center - eye), up))
}

/// Returns a quaternion view rotation from forward direction and up.
///
/// Mirrors `glam::camera::rh::view::look_to_quat`.
/// #### Panics
/// * As [`look_to_mat3`], then as [`QuatTrait::from_mat3`].
/// #### Deviations
/// * The `glam_assert!` preconditions are not checked. The shared Mat3 look-to kernel is
///   converted with `Quat::from_mat3`.
#[inline(always)]
pub fn look_to_quat(dir: Vec3, up: Vec3) -> Quat {
    QuatTrait::from_mat3(camera_impl::look_to_mat3_rh(dir, up))
}
