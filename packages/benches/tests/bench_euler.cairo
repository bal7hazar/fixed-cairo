//! Gas benchmarks of `glam::euler` and of the alternatives kept in `benches::alt::euler`
//! (the `alt_*` benches).
//!
//! Three things move the cost: the number of `sin_cos` / `atan2` calls (which dominate
//! everything else by an order of magnitude, see `gas/trig.snap`), the branch taken inside
//! `to_euler` (the gimbal-lock branch calls `atan2` twice instead of three times), and whether
//! the `EulerRot` is a literal at the call site. The `__const` pairs measure the last one: the
//! 24-arm `decode` and the six-arm permutation `match` fold away when the order is known, which
//! is the normal case in user code (`Quat::from_euler(EulerRot::YXZ, ..)`). Everywhere else the
//! order goes through `bb` and the dispatch is paid in full.
//!
//! Every input goes through `bb` (otherwise the computation is constant-folded away) and every
//! result through `sink`.

use benches::alt::euler as alt;
use benches::harness::{bb, sink};
use fixed::fixed::Fixed;
use glam::euler::{EulerRot, Mat3EulerTrait, Mat4EulerTrait, QuatEulerTrait};
use glam::mat3::Mat3;
use glam::mat4::Mat4Trait;
use glam::quat::Quat;
use glam::vec3::Vec3;

/// 30, 18 and 12.9 degrees.
const A: Fixed = Fixed { raw: 2248839617 };
const B: Fixed = Fixed { raw: 1349303770 };
const C: Fixed = Fixed { raw: 963788407 };
/// `pi / 2`: the gimbal-lock middle angle of a Tait-Bryan order.
const HALF_PI: Fixed = Fixed { raw: 6746518852 };
const ZERO: Fixed = Fixed { raw: 0 };
/// A Tait-Bryan order and a proper Euler one (the repeated branch).
const TAIT: EulerRot = EulerRot::YXZ;
const PROPER: EulerRot = EulerRot::ZXZ;

/// `Mat3EulerTrait::from_euler(YXZ, A, B, C)`: the general branch of `to_euler`.
const M: Mat3 = Mat3 {
    x_axis: Vec3 {
        x: Fixed { raw: 3773960764 }, y: Fixed { raw: 908943861 }, z: Fixed { raw: -1837875209 },
    },
    y_axis: Vec3 {
        x: Fixed { raw: -180707035 }, y: Fixed { raw: 3982343257 }, z: Fixed { raw: 1598446502 },
    },
    z_axis: Vec3 {
        x: Fixed { raw: 2042378317 }, y: Fixed { raw: -1327217884 }, z: Fixed { raw: 3537503013 },
    },
};
/// A rotation whose middle angle is `pi / 2` for `YXZ`: the gimbal-lock branch.
const G: Mat3 = Mat3 {
    x_axis: Vec3 {
        x: Fixed { raw: 3720254131 }, y: Fixed { raw: 0 }, z: Fixed { raw: -2146266669 },
    },
    y_axis: Vec3 {
        x: Fixed { raw: 2146266669 }, y: Fixed { raw: 0 }, z: Fixed { raw: 3720254131 },
    },
    z_axis: Vec3 { x: Fixed { raw: 0 }, y: Fixed { raw: -4294967296 }, z: Fixed { raw: 0 } },
};
/// `QuatEulerTrait::from_euler(YXZ, A, B, C)`.
const Q: Quat = Quat {
    x: Fixed { raw: 767835973 },
    y: Fixed { raw: 1018366377 },
    z: Fixed { raw: 285977146 },
    w: Fixed { raw: 4091249073 },
};

#[test]
fn mat3_from_euler__base() {
    let _o = bb(TAIT);
    let _a = bb(A);
    let _b = bb(B);
    let _c = bb(C);
    let r = bb(M);
    sink(r);
}

#[test]
fn mat3_from_euler__op() {
    let o = bb(TAIT);
    let a = bb(A);
    let b = bb(B);
    let c = bb(C);
    let _r = bb(M);
    sink(Mat3EulerTrait::from_euler(o, a, b, c));
}

#[test]
fn mat3_from_euler__repeated__base() {
    let _o = bb(PROPER);
    let _a = bb(A);
    let _b = bb(B);
    let _c = bb(C);
    let r = bb(M);
    sink(r);
}

#[test]
fn mat3_from_euler__repeated__op() {
    let o = bb(PROPER);
    let a = bb(A);
    let b = bb(B);
    let c = bb(C);
    let _r = bb(M);
    sink(Mat3EulerTrait::from_euler(o, a, b, c));
}

#[test]
fn mat3_from_euler__const__base() {
    let _a = bb(A);
    let _b = bb(B);
    let _c = bb(C);
    let r = bb(M);
    sink(r);
}

#[test]
fn mat3_from_euler__const__op() {
    let a = bb(A);
    let b = bb(B);
    let c = bb(C);
    let _r = bb(M);
    sink(Mat3EulerTrait::from_euler(EulerRot::YXZ, a, b, c));
}

#[test]
fn alt_mat3_from_euler_glam__base() {
    let _a = bb(A);
    let _b = bb(B);
    let _c = bb(C);
    let r = bb(M);
    sink(r);
}

#[test]
fn alt_mat3_from_euler_glam__op() {
    let a = bb(A);
    let b = bb(B);
    let c = bb(C);
    let _r = bb(M);
    sink(alt::mat3_from_euler_glam(a, b, c));
}

#[test]
fn quat_from_euler__base() {
    let _o = bb(TAIT);
    let _a = bb(A);
    let _b = bb(B);
    let _c = bb(C);
    let r = bb(Q);
    sink(r);
}

#[test]
fn quat_from_euler__op() {
    let o = bb(TAIT);
    let a = bb(A);
    let b = bb(B);
    let c = bb(C);
    let _r = bb(Q);
    sink(QuatEulerTrait::from_euler(o, a, b, c));
}

#[test]
fn quat_from_euler__repeated__base() {
    let _o = bb(PROPER);
    let _a = bb(A);
    let _b = bb(B);
    let _c = bb(C);
    let r = bb(Q);
    sink(r);
}

#[test]
fn quat_from_euler__repeated__op() {
    let o = bb(PROPER);
    let a = bb(A);
    let b = bb(B);
    let c = bb(C);
    let _r = bb(Q);
    sink(QuatEulerTrait::from_euler(o, a, b, c));
}

#[test]
fn quat_from_euler__const__base() {
    let _a = bb(A);
    let _b = bb(B);
    let _c = bb(C);
    let r = bb(Q);
    sink(r);
}

#[test]
fn quat_from_euler__const__op() {
    let a = bb(A);
    let b = bb(B);
    let c = bb(C);
    let _r = bb(Q);
    sink(QuatEulerTrait::from_euler(EulerRot::YXZ, a, b, c));
}

#[test]
fn alt_quat_from_euler_glam__base() {
    let _a = bb(A);
    let _b = bb(B);
    let _c = bb(C);
    let r = bb(Q);
    sink(r);
}

#[test]
fn alt_quat_from_euler_glam__op() {
    let a = bb(A);
    let b = bb(B);
    let c = bb(C);
    let _r = bb(Q);
    sink(alt::quat_from_euler_glam(a, b, c));
}

#[test]
fn alt_quat_from_euler_compose__base() {
    let _a = bb(A);
    let _b = bb(B);
    let _c = bb(C);
    let r = bb(Q);
    sink(r);
}

#[test]
fn alt_quat_from_euler_compose__op() {
    let a = bb(A);
    let b = bb(B);
    let c = bb(C);
    let _r = bb(Q);
    sink(alt::quat_from_euler_compose(a, b, c));
}

#[test]
fn mat3_to_euler__base() {
    let _o = bb(TAIT);
    let m = bb(M);
    sink(m);
}

#[test]
fn mat3_to_euler__op() {
    let o = bb(TAIT);
    let m = bb(M);
    sink(m.to_euler(o));
}

#[test]
fn mat3_to_euler__repeated__base() {
    let _o = bb(PROPER);
    let m = bb(M);
    sink(m);
}

#[test]
fn mat3_to_euler__repeated__op() {
    let o = bb(PROPER);
    let m = bb(M);
    sink(m.to_euler(o));
}

#[test]
fn mat3_to_euler__gimbal__base() {
    let _o = bb(TAIT);
    let m = bb(G);
    sink(m);
}

#[test]
fn mat3_to_euler__gimbal__op() {
    let o = bb(TAIT);
    let m = bb(G);
    sink(m.to_euler(o));
}

#[test]
fn mat3_to_euler__const__base() {
    let m = bb(M);
    sink(m);
}

#[test]
fn mat3_to_euler__const__op() {
    let m = bb(M);
    sink(m.to_euler(EulerRot::YXZ));
}

#[test]
fn quat_to_euler__base() {
    let _o = bb(TAIT);
    let q = bb(Q);
    sink(q);
}

#[test]
fn quat_to_euler__op() {
    let o = bb(TAIT);
    let q = bb(Q);
    sink(q.to_euler(o));
}

#[test]
fn mat4_from_euler__base() {
    let _o = bb(TAIT);
    let _a = bb(A);
    let _b = bb(B);
    let _c = bb(C);
    let r = bb(M);
    sink(r);
}

#[test]
fn mat4_from_euler__op() {
    let o = bb(TAIT);
    let a = bb(A);
    let b = bb(B);
    let c = bb(C);
    let _r = bb(M);
    sink(Mat4EulerTrait::from_euler(o, a, b, c));
}

#[test]
fn mat4_to_euler__base() {
    let _o = bb(TAIT);
    let m = bb(Mat4Trait::from_mat3(M));
    sink(m);
}

#[test]
fn mat4_to_euler__op() {
    let o = bb(TAIT);
    let m = bb(Mat4Trait::from_mat3(M));
    sink(m.to_euler(o));
}

#[test]
fn mat3_from_euler__gimbal__base() {
    let _o = bb(TAIT);
    let _a = bb(A);
    let _c = bb(C);
    let r = bb(M);
    sink(r);
}

#[test]
fn mat3_from_euler__gimbal__op() {
    let o = bb(TAIT);
    let a = bb(A);
    let c = bb(C);
    let _r = bb(M);
    sink(Mat3EulerTrait::from_euler(o, a, HALF_PI, c));
}

#[test]
fn quat_from_euler__zero__base() {
    let _o = bb(TAIT);
    let r = bb(Q);
    sink(r);
}

#[test]
fn quat_from_euler__zero__op() {
    let o = bb(TAIT);
    let _r = bb(Q);
    sink(QuatEulerTrait::from_euler(o, ZERO, ZERO, ZERO));
}
