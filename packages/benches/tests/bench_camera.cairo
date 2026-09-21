//! Gas benchmarks of `glam::camera` and of the alternatives kept in `benches::alt::camera`
//! (the `alt_*` benches).
//!
//! The constructors are branch free (the only branches are the sign split of the `Recip` and of
//! the divisions, which cost the same on both sides), so every function is measured on one
//! input: a 60 degree field of view, aspect 1.5, `near = 0.1`, `far = 100`, a 16 x 9 box.
//! Every input goes through `bb` (otherwise the computation is constant-folded away) and every
//! result through `sink`.

use benches::alt::camera as alt;
use benches::harness::{bb, sink};
use fixed::fixed::Fixed;
use glam::camera::lh::proj::{directx as lh_directx, opengl as lh_opengl, vulkan as lh_vulkan};
use glam::camera::lh::view as lh_view;
use glam::camera::rh::proj::{directx as rh_directx, opengl as rh_opengl, vulkan as rh_vulkan};
use glam::camera::rh::view as rh_view;
use glam::mat3::Mat3;
use glam::mat4::Mat4;
use glam::vec3::Vec3;
use glam::vec4::Vec4;

const FOV: Fixed = Fixed { raw: 4497679235 };
const ASPECT: Fixed = Fixed { raw: 0x180000000 };
const NEAR: Fixed = Fixed { raw: 429496730 };
const FAR: Fixed = Fixed { raw: 0x6400000000 };
const LEFT: Fixed = Fixed { raw: -0x800000000 };
const RIGHT: Fixed = Fixed { raw: 0x800000000 };
const BOTTOM: Fixed = Fixed { raw: -0x480000000 };
const TOP: Fixed = Fixed { raw: 0x480000000 };
const Z4: Vec4 = Vec4 {
    x: Fixed { raw: 0 }, y: Fixed { raw: 0 }, z: Fixed { raw: 0 }, w: Fixed { raw: 0 },
};
const Z3: Vec3 = Vec3 { x: Fixed { raw: 0 }, y: Fixed { raw: 0 }, z: Fixed { raw: 0 } };
const M4: Mat4 = Mat4 { x_axis: Z4, y_axis: Z4, z_axis: Z4, w_axis: Z4 };
const M3: Mat3 = Mat3 { x_axis: Z3, y_axis: Z3, z_axis: Z3 };
const AXIS: Vec3 = Vec3 {
    x: Fixed { raw: 0x6db6db6d }, y: Fixed { raw: 0xdb6db6db }, z: Fixed { raw: 0x49249249 },
};
const UP: Vec3 = Vec3 { x: Fixed { raw: 0 }, y: Fixed { raw: 0x100000000 }, z: Fixed { raw: 0 } };
const EYE: Vec3 = Vec3 {
    x: Fixed { raw: 0x100000000 }, y: Fixed { raw: 0x200000000 }, z: Fixed { raw: 0x300000000 },
};
const CENTER: Vec3 = Vec3 {
    x: Fixed { raw: 0x400000000 }, y: Fixed { raw: -0x100000000 }, z: Fixed { raw: 0x200000000 },
};

#[test]
fn lh_opengl_perspective__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_opengl_perspective__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(lh_opengl::perspective(f, a, n, z));
}

#[test]
fn lh_opengl_orthographic__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_opengl_orthographic__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(lh_opengl::orthographic(l, r, b, t, n, z));
}

#[test]
fn lh_opengl_frustum__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_opengl_frustum__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(lh_opengl::frustum(l, r, b, t, n, z));
}

#[test]
fn lh_vulkan_perspective__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_vulkan_perspective__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(lh_vulkan::perspective(f, a, n, z));
}

#[test]
fn lh_vulkan_perspective_infinite__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_vulkan_perspective_infinite__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let _r = bb(M4);
    sink(lh_vulkan::perspective_infinite(f, a, n));
}

#[test]
fn lh_vulkan_perspective_infinite_reverse__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_vulkan_perspective_infinite_reverse__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let _r = bb(M4);
    sink(lh_vulkan::perspective_infinite_reverse(f, a, n));
}

#[test]
fn lh_vulkan_orthographic__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_vulkan_orthographic__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(lh_vulkan::orthographic(l, r, b, t, n, z));
}

#[test]
fn lh_vulkan_frustum__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_vulkan_frustum__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(lh_vulkan::frustum(l, r, b, t, n, z));
}

#[test]
fn lh_directx_perspective__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_directx_perspective__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(lh_directx::perspective(f, a, n, z));
}

#[test]
fn lh_directx_perspective_infinite__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_directx_perspective_infinite__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let _r = bb(M4);
    sink(lh_directx::perspective_infinite(f, a, n));
}

#[test]
fn lh_directx_perspective_infinite_reverse__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_directx_perspective_infinite_reverse__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let _r = bb(M4);
    sink(lh_directx::perspective_infinite_reverse(f, a, n));
}

#[test]
fn lh_directx_orthographic__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_directx_orthographic__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(lh_directx::orthographic(l, r, b, t, n, z));
}

#[test]
fn lh_directx_frustum__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_directx_frustum__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(lh_directx::frustum(l, r, b, t, n, z));
}

#[test]
fn lh_view_look_at_mat4__base() {
    let _e = bb(EYE);
    let _c = bb(CENTER);
    let _u = bb(UP);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_view_look_at_mat4__op() {
    let e = bb(EYE);
    let c = bb(CENTER);
    let u = bb(UP);
    let _r = bb(M4);
    sink(lh_view::look_at_mat4(e, c, u));
}

#[test]
fn lh_view_look_to_mat4__base() {
    let _e = bb(EYE);
    let _d = bb(AXIS);
    let _u = bb(UP);
    let r = bb(M4);
    sink(r);
}

#[test]
fn lh_view_look_to_mat4__op() {
    let e = bb(EYE);
    let d = bb(AXIS);
    let u = bb(UP);
    let _r = bb(M4);
    sink(lh_view::look_to_mat4(e, d, u));
}

#[test]
fn lh_view_look_at_mat3__base() {
    let _e = bb(EYE);
    let _c = bb(CENTER);
    let _u = bb(UP);
    let r = bb(M3);
    sink(r);
}

#[test]
fn lh_view_look_at_mat3__op() {
    let e = bb(EYE);
    let c = bb(CENTER);
    let u = bb(UP);
    let _r = bb(M3);
    sink(lh_view::look_at_mat3(e, c, u));
}

#[test]
fn lh_view_look_to_mat3__base() {
    let _d = bb(AXIS);
    let _u = bb(UP);
    let r = bb(M3);
    sink(r);
}

#[test]
fn lh_view_look_to_mat3__op() {
    let d = bb(AXIS);
    let u = bb(UP);
    let _r = bb(M3);
    sink(lh_view::look_to_mat3(d, u));
}

#[test]
fn rh_opengl_perspective__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_opengl_perspective__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(rh_opengl::perspective(f, a, n, z));
}

#[test]
fn rh_opengl_orthographic__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_opengl_orthographic__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(rh_opengl::orthographic(l, r, b, t, n, z));
}

#[test]
fn rh_opengl_frustum__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_opengl_frustum__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(rh_opengl::frustum(l, r, b, t, n, z));
}

#[test]
fn rh_vulkan_perspective__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_vulkan_perspective__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(rh_vulkan::perspective(f, a, n, z));
}

#[test]
fn rh_vulkan_perspective_infinite__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_vulkan_perspective_infinite__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let _r = bb(M4);
    sink(rh_vulkan::perspective_infinite(f, a, n));
}

#[test]
fn rh_vulkan_perspective_infinite_reverse__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_vulkan_perspective_infinite_reverse__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let _r = bb(M4);
    sink(rh_vulkan::perspective_infinite_reverse(f, a, n));
}

#[test]
fn rh_vulkan_orthographic__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_vulkan_orthographic__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(rh_vulkan::orthographic(l, r, b, t, n, z));
}

#[test]
fn rh_vulkan_frustum__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_vulkan_frustum__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(rh_vulkan::frustum(l, r, b, t, n, z));
}

#[test]
fn rh_directx_perspective__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_directx_perspective__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(rh_directx::perspective(f, a, n, z));
}

#[test]
fn rh_directx_perspective_infinite__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_directx_perspective_infinite__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let _r = bb(M4);
    sink(rh_directx::perspective_infinite(f, a, n));
}

#[test]
fn rh_directx_perspective_infinite_reverse__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_directx_perspective_infinite_reverse__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let _r = bb(M4);
    sink(rh_directx::perspective_infinite_reverse(f, a, n));
}

#[test]
fn rh_directx_orthographic__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_directx_orthographic__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(rh_directx::orthographic(l, r, b, t, n, z));
}

#[test]
fn rh_directx_frustum__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_directx_frustum__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(rh_directx::frustum(l, r, b, t, n, z));
}

#[test]
fn rh_view_look_at_mat4__base() {
    let _e = bb(EYE);
    let _c = bb(CENTER);
    let _u = bb(UP);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_view_look_at_mat4__op() {
    let e = bb(EYE);
    let c = bb(CENTER);
    let u = bb(UP);
    let _r = bb(M4);
    sink(rh_view::look_at_mat4(e, c, u));
}

#[test]
fn rh_view_look_to_mat4__base() {
    let _e = bb(EYE);
    let _d = bb(AXIS);
    let _u = bb(UP);
    let r = bb(M4);
    sink(r);
}

#[test]
fn rh_view_look_to_mat4__op() {
    let e = bb(EYE);
    let d = bb(AXIS);
    let u = bb(UP);
    let _r = bb(M4);
    sink(rh_view::look_to_mat4(e, d, u));
}

#[test]
fn rh_view_look_at_mat3__base() {
    let _e = bb(EYE);
    let _c = bb(CENTER);
    let _u = bb(UP);
    let r = bb(M3);
    sink(r);
}

#[test]
fn rh_view_look_at_mat3__op() {
    let e = bb(EYE);
    let c = bb(CENTER);
    let u = bb(UP);
    let _r = bb(M3);
    sink(rh_view::look_at_mat3(e, c, u));
}

#[test]
fn rh_view_look_to_mat3__base() {
    let _d = bb(AXIS);
    let _u = bb(UP);
    let r = bb(M3);
    sink(r);
}

#[test]
fn rh_view_look_to_mat3__op() {
    let d = bb(AXIS);
    let u = bb(UP);
    let _r = bb(M3);
    sink(rh_view::look_to_mat3(d, u));
}

#[test]
fn alt_perspective_unchecked__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn alt_perspective_unchecked__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(alt::perspective_unchecked(f, a, n, z));
}

#[test]
fn alt_perspective_raw_div2__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn alt_perspective_raw_div2__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(alt::perspective_raw_div2(f, a, n, z));
}

#[test]
fn alt_perspective_tan__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn alt_perspective_tan__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(alt::perspective_tan(f, a, n, z));
}

#[test]
fn alt_perspective_recip__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn alt_perspective_recip__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(alt::perspective_recip(f, a, n, z));
}

#[test]
fn alt_perspective_gl_two_div__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn alt_perspective_gl_two_div__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(alt::perspective_gl_two_div(f, a, n, z));
}

#[test]
fn alt_perspective_plain_ops__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn alt_perspective_plain_ops__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(alt::perspective_plain_ops(f, a, n, z));
}

#[test]
fn alt_orthographic_div__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn alt_orthographic_div__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(alt::orthographic_div(l, r, b, t, n, z));
}

#[test]
fn alt_perspective_call__base() {
    let _f = bb(FOV);
    let _a = bb(ASPECT);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn alt_perspective_call__op() {
    let f = bb(FOV);
    let a = bb(ASPECT);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(alt::perspective_call(f, a, n, z));
}

#[test]
fn alt_orthographic_call__base() {
    let _l = bb(LEFT);
    let _r = bb(RIGHT);
    let _b = bb(BOTTOM);
    let _t = bb(TOP);
    let _n = bb(NEAR);
    let _z = bb(FAR);
    let r = bb(M4);
    sink(r);
}

#[test]
fn alt_orthographic_call__op() {
    let l = bb(LEFT);
    let r = bb(RIGHT);
    let b = bb(BOTTOM);
    let t = bb(TOP);
    let n = bb(NEAR);
    let z = bb(FAR);
    let _r = bb(M4);
    sink(alt::orthographic_call(l, r, b, t, n, z));
}

#[test]
fn alt_look_to_mat3_call__base() {
    let _d = bb(AXIS);
    let _u = bb(UP);
    let r = bb(M3);
    sink(r);
}

#[test]
fn alt_look_to_mat3_call__op() {
    let d = bb(AXIS);
    let u = bb(UP);
    let _r = bb(M3);
    sink(alt::look_to_mat3_call(d, u));
}

#[test]
fn alt_look_to_mat4_delegate__base() {
    let _e = bb(EYE);
    let _d = bb(AXIS);
    let _u = bb(UP);
    let r = bb(M4);
    sink(r);
}

#[test]
fn alt_look_to_mat4_delegate__op() {
    let e = bb(EYE);
    let d = bb(AXIS);
    let u = bb(UP);
    let _r = bb(M4);
    sink(alt::look_to_mat4_delegate(e, d, u));
}

#[test]
fn alt_look_at_mat4_delegate__base() {
    let _e = bb(EYE);
    let _c = bb(CENTER);
    let _u = bb(UP);
    let r = bb(M4);
    sink(r);
}

#[test]
fn alt_look_at_mat4_delegate__op() {
    let e = bb(EYE);
    let c = bb(CENTER);
    let u = bb(UP);
    let _r = bb(M4);
    sink(alt::look_at_mat4_delegate(e, c, u));
}
