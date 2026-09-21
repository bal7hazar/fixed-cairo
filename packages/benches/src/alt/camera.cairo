//! Alternative implementations benchmarked against `camera`. The winner of each comparison is in
//! `glam::camera`; the losers stay here with their benches (`bench_camera.cairo`, `alt_*`).
//!
//! Every variant is `#[inline(always)]` like the shipped constructors, so the benches compare
//! formulations, not call boundaries; the `*_call` and `*_delegate` variants are the ones that
//! measure a call boundary. The perspective variants are the left-handed `[0, 1]` (DirectX)
//! matrix (`perspective_gl_two_div`: the `[-1, 1]` one), written against the public API of
//! `fixed` only.

use fixed::fixed::{Fixed, ONE, ZERO};
use fixed::trig::TrigTrait;
use fixed::wide::{RecipTrait, WideAdd, WideNarrow, WideNeg, wide_mul};
use glam::camera::lh::proj::directx as lh_directx;
use glam::camera::rh::view as rh_view;
use glam::mat3::Mat3;
use glam::mat4::{Mat4, Mat4Trait};
use glam::vec3::Vec3;
use glam::vec4::Vec4;

const HALF: Fixed = Fixed { raw: 0x80000000 };

#[inline(always)]
fn persp(xx: Fixed, yy: Fixed, zz: Fixed, zw: Fixed, tz: Fixed) -> Mat4 {
    Mat4 {
        x_axis: Vec4 { x: xx, y: ZERO, z: ZERO, w: ZERO },
        y_axis: Vec4 { x: ZERO, y: yy, z: ZERO, w: ZERO },
        z_axis: Vec4 { x: ZERO, y: ZERO, z: zz, w: zw },
        w_axis: Vec4 { x: ZERO, y: ZERO, z: tz, w: ZERO },
    }
}

/// The shipped formulation of `lh::proj::directx::perspective` without any precondition check:
/// what the five `assert`s cost.
#[inline(always)]
pub fn perspective_unchecked(
    vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed, far: Fixed,
) -> Mat4 {
    let (s, c) = (vertical_fov * HALF).sin_cos();
    let h = c / s;
    let q = far / (far - near);
    persp(h / aspect_ratio, h, q, ONE, wide_mul(near, q).neg().narrow())
}

/// The half angle as `fov.raw / 2` instead of `fov * 0.5` (one floor rescale): same value for a
/// positive angle, slightly more expensive.
#[inline(always)]
pub fn perspective_raw_div2(
    vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed, far: Fixed,
) -> Mat4 {
    let (s, c) = Fixed { raw: vertical_fov.raw / 2 }.sin_cos();
    let h = c / s;
    let q = far / (far - near);
    persp(h / aspect_ratio, h, q, ONE, wide_mul(near, q).neg().narrow())
}

/// `cot` as `1 / tan(fov / 2)`: `tan` is itself `sin / cos`, so this is a second division.
#[inline(always)]
pub fn perspective_tan(vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed, far: Fixed) -> Mat4 {
    let h = ONE / (vertical_fov * HALF).tan();
    let q = far / (far - near);
    persp(h / aspect_ratio, h, q, ONE, wide_mul(near, q).neg().narrow())
}

/// The formulation of glam-rs: `1 / (far - near)` first (one shared `Recip`), then one fused
/// quotient per depth term. `near * far` is formed as a wide product of `near` and the quotient
/// `far / (far - near)`, so it does not overflow either.
#[inline(always)]
pub fn perspective_recip(
    vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed, far: Fixed,
) -> Mat4 {
    let (s, c) = (vertical_fov * HALF).sin_cos();
    let h = c / s;
    let r = RecipTrait::new(far - near);
    let q = r.mul(far);
    persp(h / aspect_ratio, h, q, ONE, wide_mul(near, q).neg().narrow())
}

/// `[-1, 1]` depth with two divisions (`(far + near) / d` and `far / d`) instead of `2 q - 1`.
#[inline(always)]
pub fn perspective_gl_two_div(
    vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed, far: Fixed,
) -> Mat4 {
    let (s, c) = (vertical_fov * HALF).sin_cos();
    let h = c / s;
    let d = far - near;
    let q = far / d;
    let zz = (far + near) / d;
    let p = wide_mul(near, q);
    persp(h / aspect_ratio, h, zz, ONE, p.add(p).neg().narrow())
}

/// `tz = -(near * far) / d` with the plain operators of `Fixed` (`near * far` is a rescaled
/// `Fixed`: it overflows for `near * far >= 2^31`).
#[inline(always)]
pub fn perspective_plain_ops(
    vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed, far: Fixed,
) -> Mat4 {
    let (s, c) = (vertical_fov * HALF).sin_cos();
    let h = c / s;
    let d = far - near;
    persp(h / aspect_ratio, h, far / d, ONE, -(near * far) / d)
}

/// The left-handed OpenGL orthographic with plain divisions (six) instead of one `Recip` per axis.
#[inline(always)]
pub fn orthographic_div(
    left: Fixed, right: Fixed, bottom: Fixed, top: Fixed, near: Fixed, far: Fixed,
) -> Mat4 {
    let two = ONE + ONE;
    let w = right - left;
    let h = top - bottom;
    let d = far - near;
    Mat4 {
        x_axis: Vec4 { x: two / w, y: ZERO, z: ZERO, w: ZERO },
        y_axis: Vec4 { x: ZERO, y: two / h, z: ZERO, w: ZERO },
        z_axis: Vec4 { x: ZERO, y: ZERO, z: two / d, w: ZERO },
        w_axis: Vec4 {
            x: -(left + right) / w, y: -(top + bottom) / h, z: -(far + near) / d, w: ONE,
        },
    }
}

/// `lh::proj::directx::perspective` behind a call boundary: what `#[inline(always)]` saves.
#[inline(never)]
pub fn perspective_call(vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed, far: Fixed) -> Mat4 {
    lh_directx::perspective(vertical_fov, aspect_ratio, near, far)
}

/// `lh::proj::directx::orthographic` behind a call boundary.
#[inline(never)]
pub fn orthographic_call(
    left: Fixed, right: Fixed, bottom: Fixed, top: Fixed, near: Fixed, far: Fixed,
) -> Mat4 {
    lh_directx::orthographic(left, right, bottom, top, near, far)
}

/// `rh::view::look_to_mat3` behind a call boundary.
#[inline(never)]
pub fn look_to_mat3_call(dir: Vec3, up: Vec3) -> Mat3 {
    rh_view::look_to_mat3(dir, up)
}

/// `rh::view::look_to_mat4` as a call of the non-inlined `Mat4::look_to_rh` (the first version
/// of the module, before the body was inlined into `camera_impl`).
pub fn look_to_mat4_delegate(eye: Vec3, dir: Vec3, up: Vec3) -> Mat4 {
    Mat4Trait::look_to_rh(eye, dir, up)
}

/// `rh::view::look_at_mat4` as a call of the non-inlined `Mat4::look_at_rh`.
pub fn look_at_mat4_delegate(eye: Vec3, center: Vec3, up: Vec3) -> Mat4 {
    Mat4Trait::look_at_rh(eye, center, up)
}
