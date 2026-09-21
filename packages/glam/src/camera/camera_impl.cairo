//! Internal primitives shared by the view and projection constructors of `camera::{lh, rh}`.
//!
//! glam-rs parameterizes one kernel over `RH`, `ZO` and `YFLIP` const generics. Cairo has none
//! (and `#[inline(always)]` is rejected on generic functions, E2143), so the scalars every
//! variant needs are computed by the small helpers below and each public function picks the
//! signs itself. Every helper is `#[inline(always)]`.

use fixed::fixed::{Fixed, HALF, ONE, PI, ZERO};
use fixed::trig::TrigTrait;
use fixed::wide::{RecipTrait, WideAdd, WideNarrow, WideNeg, wide_mul};
use crate::mat3::Mat3;
use crate::mat4::Mat4;
use crate::vec3::{Vec3, Vec3Trait};
use crate::vec4::Vec4;

pub(crate) const NEG_TWO: Fixed = Fixed { raw: -0x200000000 };

/// The perspective layout: `x_axis = (xx, 0, 0, 0)`, `y_axis = (0, yy, 0, 0)`,
/// `z_axis = (0, 0, zz, zw)`, `w_axis = (0, 0, tz, 0)`.
#[inline(always)]
pub(crate) fn persp(xx: Fixed, yy: Fixed, zz: Fixed, zw: Fixed, tz: Fixed) -> Mat4 {
    Mat4 {
        x_axis: Vec4 { x: xx, y: ZERO, z: ZERO, w: ZERO },
        y_axis: Vec4 { x: ZERO, y: yy, z: ZERO, w: ZERO },
        z_axis: Vec4 { x: ZERO, y: ZERO, z: zz, w: zw },
        w_axis: Vec4 { x: ZERO, y: ZERO, z: tz, w: ZERO },
    }
}

/// The frustum layout: as `persp` with the off-axis terms `zx`, `zy` in `z_axis`.
#[inline(always)]
pub(crate) fn frust(
    xx: Fixed, yy: Fixed, zx: Fixed, zy: Fixed, zz: Fixed, zw: Fixed, tz: Fixed,
) -> Mat4 {
    Mat4 {
        x_axis: Vec4 { x: xx, y: ZERO, z: ZERO, w: ZERO },
        y_axis: Vec4 { x: ZERO, y: yy, z: ZERO, w: ZERO },
        z_axis: Vec4 { x: zx, y: zy, z: zz, w: zw },
        w_axis: Vec4 { x: ZERO, y: ZERO, z: tz, w: ZERO },
    }
}

/// The orthographic layout: a diagonal, the translation in `w_axis`.
#[inline(always)]
pub(crate) fn ortho(xx: Fixed, yy: Fixed, zz: Fixed, tx: Fixed, ty: Fixed, tz: Fixed) -> Mat4 {
    Mat4 {
        x_axis: Vec4 { x: xx, y: ZERO, z: ZERO, w: ZERO },
        y_axis: Vec4 { x: ZERO, y: yy, z: ZERO, w: ZERO },
        z_axis: Vec4 { x: ZERO, y: ZERO, z: zz, w: ZERO },
        w_axis: Vec4 { x: tx, y: ty, z: tz, w: ONE },
    }
}

/// `near > 0`, the `glam_assert!` of glam-rs.
#[inline(always)]
pub(crate) fn check_near(near: Fixed) {
    assert(near > ZERO, 'camera: near not positive');
}

/// `(cot(fov / 2) / aspect, cot(fov / 2))`: `xx` and the unflipped `yy` of a perspective.
///
/// `fov * 0.5` floors (measured 220 gas cheaper than `fov.raw / 2`, same value for a positive
/// angle), `sin_cos` shares the range reduction, one truncated division gives the cotangent.
#[inline(always)]
pub(crate) fn fov_scales(fov: Fixed, aspect: Fixed) -> (Fixed, Fixed) {
    assert(fov > ZERO && fov < PI, 'camera: fov out of range');
    assert(aspect != ZERO, 'camera: aspect zero');
    let (s, c) = (fov * HALF).sin_cos();
    let h = c / s;
    (h / aspect, h)
}

/// `far / (far - near)`, truncated: the only division of the depth terms of a perspective and
/// of a frustum.
#[inline(always)]
pub(crate) fn depth_q(near: Fixed, far: Fixed) -> Fixed {
    check_near(near);
    assert(far > ZERO, 'camera: far not positive');
    far / (far - near)
}

/// `-near * q`: `tz` of the `[0, 1]` depth range (`-near * far / (far - near)`), one floor
/// rescale of the exact product.
#[inline(always)]
pub(crate) fn depth_tz(near: Fixed, q: Fixed) -> Fixed {
    wide_mul(near, q).neg().narrow()
}

/// `-2 * near * q`: `tz` of the `[-1, 1]` depth range, the doubling is exact in the wide sum.
#[inline(always)]
pub(crate) fn depth_tz2(near: Fixed, q: Fixed) -> Fixed {
    let p = wide_mul(near, q);
    p.add(p).neg().narrow()
}

/// `(num / (hi - lo), -(lo + hi) / (hi - lo))`: the scale and the translation of one
/// orthographic axis, `num = 2`; `num = -2` flips the scale only (Vulkan Y: glam-rs does not flip
/// the translation). One shared reciprocal, both quotients rounded to nearest.
#[inline(always)]
pub(crate) fn ortho_axis(lo: Fixed, hi: Fixed, num: Fixed) -> (Fixed, Fixed) {
    let r = RecipTrait::new(hi - lo);
    let mid = lo + hi;
    (r.mul(num), r.mul(-mid))
}

/// `(num / (far - near), -near / (far - near))`: `zz` and `tz` of the `[0, 1]` orthographic
/// depth range, `num = +-1`.
#[inline(always)]
pub(crate) fn ortho_depth_zo(near: Fixed, far: Fixed, num: Fixed) -> (Fixed, Fixed) {
    let r = RecipTrait::new(far - near);
    (r.mul(num), r.mul(-near))
}

/// `(num / (far - near), -(far + near) / (far - near))`: `zz` and `tz` of the `[-1, 1]`
/// orthographic depth range, `num = +-2`.
#[inline(always)]
pub(crate) fn ortho_depth_gl(near: Fixed, far: Fixed, num: Fixed) -> (Fixed, Fixed) {
    let r = RecipTrait::new(far - near);
    let sum = far + near;
    (r.mul(num), r.mul(-sum))
}

/// `(2 near / (hi - lo), (hi + lo) / (hi - lo))`: the scale and the off-axis term of one frustum
/// axis (`two_near = 2 * near`).
#[inline(always)]
pub(crate) fn frustum_axis(lo: Fixed, hi: Fixed, two_near: Fixed) -> (Fixed, Fixed) {
    let r = RecipTrait::new(hi - lo);
    (r.mul(two_near), r.mul(hi + lo))
}

/// As `frustum_axis` with both terms negated (Vulkan Y).
#[inline(always)]
pub(crate) fn frustum_axis_flip(lo: Fixed, hi: Fixed, two_near: Fixed) -> (Fixed, Fixed) {
    let r = RecipTrait::new(hi - lo);
    let mid = hi + lo;
    (r.mul(-two_near), r.mul(-mid))
}

/// The right-handed view rotation `(s, u, -dir)` as rows: `s = normalize(dir x up)`,
/// `u = s x dir`.
#[inline(always)]
pub(crate) fn look_to_mat3_rh(dir: Vec3, up: Vec3) -> Mat3 {
    let s = Vec3Trait::normalize(Vec3Trait::cross(dir, up));
    let u = Vec3Trait::cross(s, dir);
    Mat3 {
        x_axis: Vec3 { x: s.x, y: u.x, z: -dir.x },
        y_axis: Vec3 { x: s.y, y: u.y, z: -dir.y },
        z_axis: Vec3 { x: s.z, y: u.z, z: -dir.z },
    }
}

/// The right-handed view matrix: `look_to_mat3_rh` plus the translation `(-eye . s, -eye . u,
/// eye . dir)`.
#[inline(always)]
pub(crate) fn look_to_mat4_rh(eye: Vec3, dir: Vec3, up: Vec3) -> Mat4 {
    let s = Vec3Trait::normalize(Vec3Trait::cross(dir, up));
    let u = Vec3Trait::cross(s, dir);
    Mat4 {
        x_axis: Vec4 { x: s.x, y: u.x, z: -dir.x, w: ZERO },
        y_axis: Vec4 { x: s.y, y: u.y, z: -dir.y, w: ZERO },
        z_axis: Vec4 { x: s.z, y: u.z, z: -dir.z, w: ZERO },
        w_axis: Vec4 {
            x: -Vec3Trait::dot(eye, s),
            y: -Vec3Trait::dot(eye, u),
            z: Vec3Trait::dot(eye, dir),
            w: ONE,
        },
    }
}
