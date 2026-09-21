//! Gas benchmarks of `glam::quat` and of the alternatives kept in `benches::alt::quat`
//! (the `alt_*` benches).
//!
//! Sierra gas is charged at the most expensive sibling branch, but steps depend on the path
//! taken: branching functions are measured on one input per branch (`__near` / `__far`,
//! `__zero`, `__short`, ...). Every input goes through `bb` (otherwise the computation is
//! constant-folded away) and every result through `sink`.
//!
//! The reference points of `gas/wide.snap` are `composite_quat_mul` (12 050) and
//! `composite_quat_rotate` (11 170): the two kernels below are the same expressions behind the
//! public API.

use benches::alt::quat as alt;
use benches::harness::{bb, sink};
use fixed::fixed::Fixed;
use glam::affine3::Affine3;
use glam::mat3::Mat3;
use glam::mat4::Mat4;
use glam::quat::{Quat, QuatTrait};
use glam::vec2::Vec2;
use glam::vec3::Vec3;
use glam::vec4::Vec4;

/// A unit quaternion: 0.7 rad around the normalized (1, 2, 3).
const A: Quat = Quat {
    x: Fixed { raw: 393604950 },
    y: Fixed { raw: 787209899 },
    z: Fixed { raw: 1180814849 },
    w: Fixed { raw: 4034575081 },
};
/// A unit quaternion: 2.4 rad around the normalized (-2, 1, 4).
const B: Quat = Quat {
    x: Fixed { raw: -1747086207 },
    y: Fixed { raw: 873543103 },
    z: Fixed { raw: 3494172412 },
    w: Fixed { raw: 1556314705 },
};
/// `A` again, 4.7e-5 rad further around the same axis: `dot(A, NEARBY) > NEAR_ONE`.
const NEARBY: Quat = Quat {
    x: Fixed { raw: 393630055 },
    y: Fixed { raw: 787260111 },
    z: Fixed { raw: 1180890166 },
    w: Fixed { raw: 4034540790 },
};
/// The identity.
const ID: Quat = Quat {
    x: Fixed { raw: 0 }, y: Fixed { raw: 0 }, z: Fixed { raw: 0 }, w: Fixed { raw: 0x100000000 },
};
/// A quaternion that is not normalized.
const WIDE: Quat = Quat {
    x: Fixed { raw: 0x100000000 },
    y: Fixed { raw: 0x200000000 },
    z: Fixed { raw: 0x300000000 },
    w: Fixed { raw: 0x400000000 },
};
/// A quaternion whose vector part is below the `AXIS_EPS` threshold of `to_axis_angle`.
const SHORT: Quat = Quat {
    x: Fixed { raw: 0x8000 },
    y: Fixed { raw: 0 },
    z: Fixed { raw: 0 },
    w: Fixed { raw: 0x100000000 },
};
const V: Vec3 = Vec3 {
    x: Fixed { raw: 0x180000000 }, y: Fixed { raw: -0x1c0000000 }, z: Fixed { raw: 0x160000000 },
};
/// The normalized (1, 2, 3).
const AXIS: Vec3 = Vec3 {
    x: Fixed { raw: 1147878294 }, y: Fixed { raw: 2295756587 }, z: Fixed { raw: 3443634881 },
};
/// The normalized (-2, 1, 4).
const AXIS2: Vec3 = Vec3 {
    x: Fixed { raw: -1874477404 }, y: Fixed { raw: 937238702 }, z: Fixed { raw: 3748954808 },
};
/// The opposite of `AXIS`: the 180 degree branch of `from_rotation_arc`.
const NEG_AXIS: Vec3 = Vec3 {
    x: Fixed { raw: -1147878294 }, y: Fixed { raw: -2295756587 }, z: Fixed { raw: -3443634881 },
};
/// `-B`: the long-path branch of `lerp` and `slerp` (a negative dot product).
const NEG_B: Quat = Quat {
    x: Fixed { raw: 1747086207 },
    y: Fixed { raw: -873543103 },
    z: Fixed { raw: -3494172412 },
    w: Fixed { raw: -1556314705 },
};
/// A scaled axis: 1.3 rad around the normalized (1, 2, 3).
const SCALED: Vec3 = Vec3 {
    x: Fixed { raw: 1592313648 }, y: Fixed { raw: 3184627296 }, z: Fixed { raw: 4776940944 },
};
const ZEROV: Vec3 = Vec3 { x: Fixed { raw: 0 }, y: Fixed { raw: 0 }, z: Fixed { raw: 0 } };
/// The normalized (1, 2) and (-2, 1): a quarter turn apart.
const P2: Vec2 = Vec2 { x: Fixed { raw: 1920767767 }, y: Fixed { raw: 3841535534 } };
const Q2: Vec2 = Vec2 { x: Fixed { raw: -3841535534 }, y: Fixed { raw: 1920767767 } };
/// 0.7 rad.
const ANGLE: Fixed = Fixed { raw: 3006477107 };
const K_ZERO: Fixed = Fixed { raw: 0 };
const K_ONE: Fixed = Fixed { raw: 0x100000000 };
const K_TWO: Fixed = Fixed { raw: 0x200000000 };
const K_HALF: Fixed = Fixed { raw: 0x80000000 };
const K_TENTH: Fixed = Fixed { raw: 429496730 };
const K_EPS: Fixed = Fixed { raw: 1024 };
const VEC4_ONE: Vec4 = Vec4 {
    x: Fixed { raw: 0x100000000 },
    y: Fixed { raw: 0x100000000 },
    z: Fixed { raw: 0x100000000 },
    w: Fixed { raw: 0x100000000 },
};
/// The rotation matrix of the unit quaternion (4, 2, 2, 1) / 5: the
/// `x^2 >= ..` branch of `from_rotation_axes`.
const ROT_X: Mat3 = Mat3 {
    x_axis: Vec3 {
        x: Fixed { raw: 0x5c28f5c2 }, y: Fixed { raw: 0xcccccccc }, z: Fixed { raw: 0x7ae147ae },
    },
    y_axis: Vec3 {
        x: Fixed { raw: 0x7ae147ae }, y: Fixed { raw: -0x9999999a }, z: Fixed { raw: 0xa3d70a3d },
    },
    z_axis: Vec3 {
        x: Fixed { raw: 0xcccccccc }, y: Fixed { raw: 0x0 }, z: Fixed { raw: -0x9999999a },
    },
};
/// The rotation matrix of the unit quaternion (2, 4, 2, 1) / 5: the
/// `y^2 >= ..` branch of `from_rotation_axes`.
const ROT_Y: Mat3 = Mat3 {
    x_axis: Vec3 {
        x: Fixed { raw: -0x9999999a }, y: Fixed { raw: 0xcccccccc }, z: Fixed { raw: 0x0 },
    },
    y_axis: Vec3 {
        x: Fixed { raw: 0x7ae147ae }, y: Fixed { raw: 0x5c28f5c2 }, z: Fixed { raw: 0xcccccccc },
    },
    z_axis: Vec3 {
        x: Fixed { raw: 0xa3d70a3d }, y: Fixed { raw: 0x7ae147ae }, z: Fixed { raw: -0x9999999a },
    },
};
/// The rotation matrix of the unit quaternion (1, 2, 4, 2) / 5: the
/// `z^2 >= ..` branch of `from_rotation_axes`.
const ROT_Z: Mat3 = Mat3 {
    x_axis: Vec3 {
        x: Fixed { raw: -0x9999999a }, y: Fixed { raw: 0xcccccccc }, z: Fixed { raw: 0x0 },
    },
    y_axis: Vec3 {
        x: Fixed { raw: -0x7ae147af }, y: Fixed { raw: -0x5c28f5c3 }, z: Fixed { raw: 0xcccccccc },
    },
    z_axis: Vec3 {
        x: Fixed { raw: 0xa3d70a3d }, y: Fixed { raw: 0x7ae147ae }, z: Fixed { raw: 0x99999999 },
    },
};
/// The rotation matrix of the unit quaternion (1, 2, 2, 4) / 5: the
/// `w^2 >= ..` branch of `from_rotation_axes`.
const ROT_W: Mat3 = Mat3 {
    x_axis: Vec3 {
        x: Fixed { raw: 0x5c28f5c2 }, y: Fixed { raw: 0xcccccccc }, z: Fixed { raw: -0x7ae147af },
    },
    y_axis: Vec3 {
        x: Fixed { raw: -0x7ae147af }, y: Fixed { raw: 0x99999999 }, z: Fixed { raw: 0xa3d70a3d },
    },
    z_axis: Vec3 {
        x: Fixed { raw: 0xcccccccc }, y: Fixed { raw: 0x0 }, z: Fixed { raw: 0x99999999 },
    },
};
/// `ROT_W` as the linear part of a homogeneous 4x4 matrix.
const ROT4: Mat4 = Mat4 {
    x_axis: Vec4 {
        x: Fixed { raw: 0x5c28f5c2 },
        y: Fixed { raw: 0xcccccccc },
        z: Fixed { raw: -0x7ae147af },
        w: Fixed { raw: 0x0 },
    },
    y_axis: Vec4 {
        x: Fixed { raw: -0x7ae147af },
        y: Fixed { raw: 0x99999999 },
        z: Fixed { raw: 0xa3d70a3d },
        w: Fixed { raw: 0x0 },
    },
    z_axis: Vec4 {
        x: Fixed { raw: 0xcccccccc },
        y: Fixed { raw: 0x0 },
        z: Fixed { raw: 0x99999999 },
        w: Fixed { raw: 0x0 },
    },
    w_axis: Vec4 {
        x: Fixed { raw: 0x0 },
        y: Fixed { raw: 0x0 },
        z: Fixed { raw: 0x0 },
        w: Fixed { raw: 0x100000000 },
    },
};
const AFFINE: Affine3 = Affine3 { matrix3: ROT_W, translation: ZEROV };
/// The y axis: the `up` of the `look_*` constructors.
const UP: Vec3 = Vec3 {
    x: Fixed { raw: 0x0 }, y: Fixed { raw: 0x100000000 }, z: Fixed { raw: 0x0 },
};
/// A camera position and a focal point for the `look_at_*` constructors.
const EYE: Vec3 = Vec3 {
    x: Fixed { raw: 0x100000000 }, y: Fixed { raw: 0x200000000 }, z: Fixed { raw: 0x300000000 },
};
const CENTER: Vec3 = Vec3 {
    x: Fixed { raw: 0x400000000 }, y: Fixed { raw: -0x100000000 }, z: Fixed { raw: 0x200000000 },
};


#[test]
fn from_axis_angle__base() {
    let _a = bb(AXIS);
    let _k = bb(ANGLE);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_axis_angle__op() {
    let a = bb(AXIS);
    let k = bb(ANGLE);
    let _r = bb(A);
    sink(QuatTrait::from_axis_angle(a, k));
}

#[test]
fn from_scaled_axis__base() {
    let _a = bb(SCALED);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_scaled_axis__op() {
    let a = bb(SCALED);
    let _r = bb(A);
    sink(QuatTrait::from_scaled_axis(a));
}

#[test]
fn from_scaled_axis__zero__base() {
    let _a = bb(ZEROV);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_scaled_axis__zero__op() {
    let a = bb(ZEROV);
    let _r = bb(A);
    sink(QuatTrait::from_scaled_axis(a));
}

#[test]
fn from_rotation_x__base() {
    let _k = bb(ANGLE);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_x__op() {
    let k = bb(ANGLE);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_x(k));
}

#[test]
fn from_rotation_y__base() {
    let _k = bb(ANGLE);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_y__op() {
    let k = bb(ANGLE);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_y(k));
}

#[test]
fn from_rotation_z__base() {
    let _k = bb(ANGLE);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_z__op() {
    let k = bb(ANGLE);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_z(k));
}

#[test]
fn from_rotation_axes__x__base() {
    let _m = bb(ROT_X);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_axes__x__op() {
    let m = bb(ROT_X);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_axes(m.x_axis, m.y_axis, m.z_axis));
}

#[test]
fn from_rotation_axes__y__base() {
    let _m = bb(ROT_Y);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_axes__y__op() {
    let m = bb(ROT_Y);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_axes(m.x_axis, m.y_axis, m.z_axis));
}

#[test]
fn from_rotation_axes__z__base() {
    let _m = bb(ROT_Z);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_axes__z__op() {
    let m = bb(ROT_Z);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_axes(m.x_axis, m.y_axis, m.z_axis));
}

#[test]
fn from_rotation_axes__w__base() {
    let _m = bb(ROT_W);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_axes__w__op() {
    let m = bb(ROT_W);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_axes(m.x_axis, m.y_axis, m.z_axis));
}

#[test]
fn from_mat3__base() {
    let _m = bb(ROT_W);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_mat3__op() {
    let m = bb(ROT_W);
    let _r = bb(A);
    sink(QuatTrait::from_mat3(m));
}

#[test]
fn from_mat4__base() {
    let _m = bb(ROT4);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_mat4__op() {
    let m = bb(ROT4);
    let _r = bb(A);
    sink(QuatTrait::from_mat4(m));
}

#[test]
fn from_affine3__base() {
    let _a = bb(AFFINE);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_affine3__op() {
    let a = bb(AFFINE);
    let _r = bb(A);
    sink(QuatTrait::from_affine3(a));
}

#[test]
fn look_to_rh__base() {
    let _d = bb(AXIS);
    let _u = bb(UP);
    let r = bb(A);
    sink(r);
}

#[test]
fn look_to_rh__op() {
    let d = bb(AXIS);
    let u = bb(UP);
    let _r = bb(A);
    sink(QuatTrait::look_to_rh(d, u));
}

#[test]
fn look_at_rh__base() {
    let _e = bb(EYE);
    let _c = bb(CENTER);
    let _u = bb(UP);
    let r = bb(A);
    sink(r);
}

#[test]
fn look_at_rh__op() {
    let e = bb(EYE);
    let c = bb(CENTER);
    let u = bb(UP);
    let _r = bb(A);
    sink(QuatTrait::look_at_rh(e, c, u));
}

#[test]
fn look_to_lh__base() {
    let _d = bb(AXIS);
    let _u = bb(UP);
    let r = bb(A);
    sink(r);
}

#[test]
fn look_to_lh__op() {
    let d = bb(AXIS);
    let u = bb(UP);
    let _r = bb(A);
    sink(QuatTrait::look_to_lh(d, u));
}

#[test]
fn look_at_lh__base() {
    let _e = bb(EYE);
    let _c = bb(CENTER);
    let _u = bb(UP);
    let r = bb(A);
    sink(r);
}

#[test]
fn look_at_lh__op() {
    let e = bb(EYE);
    let c = bb(CENTER);
    let u = bb(UP);
    let _r = bb(A);
    sink(QuatTrait::look_at_lh(e, c, u));
}

#[test]
fn from_rotation_arc__base() {
    let _a = bb(AXIS);
    let _b = bb(AXIS2);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_arc__op() {
    let a = bb(AXIS);
    let b = bb(AXIS2);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_arc(a, b));
}

#[test]
fn from_rotation_arc__same__base() {
    let _a = bb(AXIS);
    let _b = bb(AXIS);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_arc__same__op() {
    let a = bb(AXIS);
    let b = bb(AXIS);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_arc(a, b));
}

#[test]
fn from_rotation_arc__opposite__base() {
    let _a = bb(AXIS);
    let _b = bb(NEG_AXIS);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_arc__opposite__op() {
    let a = bb(AXIS);
    let b = bb(NEG_AXIS);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_arc(a, b));
}

#[test]
fn from_rotation_arc_colinear__base() {
    let _a = bb(AXIS);
    let _b = bb(AXIS2);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_arc_colinear__op() {
    let a = bb(AXIS);
    let b = bb(AXIS2);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_arc_colinear(a, b));
}

#[test]
fn from_rotation_arc_2d__base() {
    let _a = bb(P2);
    let _b = bb(Q2);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_arc_2d__op() {
    let a = bb(P2);
    let b = bb(Q2);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_arc_2d(a, b));
}

#[test]
fn from_rotation_arc_2d__same__base() {
    let _a = bb(P2);
    let _b = bb(P2);
    let r = bb(A);
    sink(r);
}

#[test]
fn from_rotation_arc_2d__same__op() {
    let a = bb(P2);
    let b = bb(P2);
    let _r = bb(A);
    sink(QuatTrait::from_rotation_arc_2d(a, b));
}

#[test]
fn to_axis_angle__base() {
    let _a = bb(A);
    let r = bb((AXIS, ANGLE));
    sink(r);
}

#[test]
fn to_axis_angle__op() {
    let a = bb(A);
    let _r = bb((AXIS, ANGLE));
    sink(a.to_axis_angle());
}

#[test]
fn to_axis_angle__short__base() {
    let _a = bb(SHORT);
    let r = bb((AXIS, ANGLE));
    sink(r);
}

#[test]
fn to_axis_angle__short__op() {
    let a = bb(SHORT);
    let _r = bb((AXIS, ANGLE));
    sink(a.to_axis_angle());
}

#[test]
fn to_scaled_axis__base() {
    let _a = bb(A);
    let r = bb(AXIS);
    sink(r);
}

#[test]
fn to_scaled_axis__op() {
    let a = bb(A);
    let _r = bb(AXIS);
    sink(a.to_scaled_axis());
}

#[test]
fn to_scaled_axis__short__base() {
    let _a = bb(SHORT);
    let r = bb(AXIS);
    sink(r);
}

#[test]
fn to_scaled_axis__short__op() {
    let a = bb(SHORT);
    let _r = bb(AXIS);
    sink(a.to_scaled_axis());
}

#[test]
fn conjugate__base() {
    let _a = bb(A);
    let r = bb(A);
    sink(r);
}

#[test]
fn conjugate__op() {
    let a = bb(A);
    let _r = bb(A);
    sink(a.conjugate());
}

#[test]
fn inverse__base() {
    let _a = bb(A);
    let r = bb(A);
    sink(r);
}

#[test]
fn inverse__op() {
    let a = bb(A);
    let _r = bb(A);
    sink(a.inverse());
}

#[test]
fn dot__base() {
    let _a = bb(A);
    let _b = bb(B);
    let r = bb(K_ONE);
    sink(r);
}

#[test]
fn dot__op() {
    let a = bb(A);
    let b = bb(B);
    let _r = bb(K_ONE);
    sink(a.dot(b));
}

#[test]
fn length__base() {
    let _a = bb(A);
    let r = bb(K_ONE);
    sink(r);
}

#[test]
fn length__op() {
    let a = bb(A);
    let _r = bb(K_ONE);
    sink(a.length());
}

#[test]
fn length_squared__base() {
    let _a = bb(A);
    let r = bb(K_ONE);
    sink(r);
}

#[test]
fn length_squared__op() {
    let a = bb(A);
    let _r = bb(K_ONE);
    sink(a.length_squared());
}

#[test]
fn length_recip__base() {
    let _a = bb(A);
    let r = bb(K_ONE);
    sink(r);
}

#[test]
fn length_recip__op() {
    let a = bb(A);
    let _r = bb(K_ONE);
    sink(a.length_recip());
}

#[test]
fn normalize__base() {
    let _a = bb(WIDE);
    let r = bb(A);
    sink(r);
}

#[test]
fn normalize__op() {
    let a = bb(WIDE);
    let _r = bb(A);
    sink(a.normalize());
}

#[test]
fn is_normalized__base() {
    let _a = bb(A);
    let r = bb(true);
    sink(r);
}

#[test]
fn is_normalized__op() {
    let a = bb(A);
    let _r = bb(true);
    sink(a.is_normalized());
}

#[test]
fn is_near_identity__true__base() {
    let _a = bb(ID);
    let r = bb(true);
    sink(r);
}

#[test]
fn is_near_identity__true__op() {
    let a = bb(ID);
    let _r = bb(true);
    sink(a.is_near_identity());
}

#[test]
fn is_near_identity__false__base() {
    let _a = bb(A);
    let r = bb(true);
    sink(r);
}

#[test]
fn is_near_identity__false__op() {
    let a = bb(A);
    let _r = bb(true);
    sink(a.is_near_identity());
}

#[test]
fn angle_between__base() {
    let _a = bb(A);
    let _b = bb(B);
    let r = bb(K_ONE);
    sink(r);
}

#[test]
fn angle_between__op() {
    let a = bb(A);
    let b = bb(B);
    let _r = bb(K_ONE);
    sink(a.angle_between(b));
}

#[test]
fn rotate_towards__base() {
    let _a = bb(A);
    let _b = bb(B);
    let _k = bb(K_TENTH);
    let r = bb(A);
    sink(r);
}

#[test]
fn rotate_towards__op() {
    let a = bb(A);
    let b = bb(B);
    let k = bb(K_TENTH);
    let _r = bb(A);
    sink(a.rotate_towards(b, k));
}

#[test]
fn rotate_towards__aligned__base() {
    let _a = bb(A);
    let _b = bb(A);
    let _k = bb(K_TENTH);
    let r = bb(A);
    sink(r);
}

#[test]
fn rotate_towards__aligned__op() {
    let a = bb(A);
    let b = bb(A);
    let k = bb(K_TENTH);
    let _r = bb(A);
    sink(a.rotate_towards(b, k));
}

#[test]
fn abs_diff_eq__true__base() {
    let _a = bb(A);
    let _b = bb(A);
    let _k = bb(K_EPS);
    let r = bb(true);
    sink(r);
}

#[test]
fn abs_diff_eq__true__op() {
    let a = bb(A);
    let b = bb(A);
    let k = bb(K_EPS);
    let _r = bb(true);
    sink(a.abs_diff_eq(b, k));
}

#[test]
fn abs_diff_eq__false__base() {
    let _a = bb(A);
    let _b = bb(B);
    let _k = bb(K_EPS);
    let r = bb(true);
    sink(r);
}

#[test]
fn abs_diff_eq__false__op() {
    let a = bb(A);
    let b = bb(B);
    let k = bb(K_EPS);
    let _r = bb(true);
    sink(a.abs_diff_eq(b, k));
}

#[test]
fn lerp__base() {
    let _a = bb(A);
    let _b = bb(B);
    let _k = bb(K_HALF);
    let r = bb(A);
    sink(r);
}

#[test]
fn lerp__op() {
    let a = bb(A);
    let b = bb(B);
    let k = bb(K_HALF);
    let _r = bb(A);
    sink(a.lerp(b, k));
}

#[test]
fn lerp__long_path__base() {
    let _a = bb(A);
    let _b = bb(NEG_B);
    let _k = bb(K_HALF);
    let r = bb(A);
    sink(r);
}

#[test]
fn lerp__long_path__op() {
    let a = bb(A);
    let b = bb(NEG_B);
    let k = bb(K_HALF);
    let _r = bb(A);
    sink(a.lerp(b, k));
}

#[test]
fn slerp__base() {
    let _a = bb(A);
    let _b = bb(B);
    let _k = bb(K_HALF);
    let r = bb(A);
    sink(r);
}

#[test]
fn slerp__op() {
    let a = bb(A);
    let b = bb(B);
    let k = bb(K_HALF);
    let _r = bb(A);
    sink(a.slerp(b, k));
}

#[test]
fn slerp__near__base() {
    let _a = bb(A);
    let _b = bb(NEARBY);
    let _k = bb(K_HALF);
    let r = bb(A);
    sink(r);
}

#[test]
fn slerp__near__op() {
    let a = bb(A);
    let b = bb(NEARBY);
    let k = bb(K_HALF);
    let _r = bb(A);
    sink(a.slerp(b, k));
}

#[test]
fn slerp__long_path__base() {
    let _a = bb(A);
    let _b = bb(NEG_B);
    let _k = bb(K_HALF);
    let r = bb(A);
    sink(r);
}

#[test]
fn slerp__long_path__op() {
    let a = bb(A);
    let b = bb(NEG_B);
    let k = bb(K_HALF);
    let _r = bb(A);
    sink(a.slerp(b, k));
}

#[test]
fn slerp_long__base() {
    let _a = bb(A);
    let _b = bb(NEG_B);
    let _k = bb(K_HALF);
    let r = bb(A);
    sink(r);
}

#[test]
fn slerp_long__op() {
    let a = bb(A);
    let b = bb(NEG_B);
    let k = bb(K_HALF);
    let _r = bb(A);
    sink(a.slerp_long(b, k));
}

#[test]
fn slerp_long__near__base() {
    let _a = bb(A);
    let _b = bb(NEARBY);
    let _k = bb(K_HALF);
    let r = bb(A);
    sink(r);
}

#[test]
fn slerp_long__near__op() {
    let a = bb(A);
    let b = bb(NEARBY);
    let k = bb(K_HALF);
    let _r = bb(A);
    sink(a.slerp_long(b, k));
}

#[test]
fn mul_quat__base() {
    let _a = bb(A);
    let _b = bb(B);
    let r = bb(A);
    sink(r);
}

#[test]
fn mul_quat__op() {
    let a = bb(A);
    let b = bb(B);
    let _r = bb(A);
    sink(a.mul_quat(b));
}

#[test]
fn mul__base() {
    let _a = bb(A);
    let _b = bb(B);
    let r = bb(A);
    sink(r);
}

#[test]
fn mul__op() {
    let a = bb(A);
    let b = bb(B);
    let _r = bb(A);
    sink(a * b);
}

#[test]
fn mul_vec3__base() {
    let _a = bb(A);
    let _v = bb(V);
    let r = bb(V);
    sink(r);
}

#[test]
fn mul_vec3__op() {
    let a = bb(A);
    let v = bb(V);
    let _r = bb(V);
    sink(a.mul_vec3(v));
}

#[test]
fn mul_scalar__base() {
    let _a = bb(A);
    let _k = bb(K_TWO);
    let r = bb(A);
    sink(r);
}

#[test]
fn mul_scalar__op() {
    let a = bb(A);
    let k = bb(K_TWO);
    let _r = bb(A);
    sink(a.mul_scalar(k));
}

#[test]
fn div_scalar__base() {
    let _a = bb(A);
    let _k = bb(K_TWO);
    let r = bb(A);
    sink(r);
}

#[test]
fn div_scalar__op() {
    let a = bb(A);
    let k = bb(K_TWO);
    let _r = bb(A);
    sink(a.div_scalar(k));
}

#[test]
fn add__base() {
    let _a = bb(A);
    let _b = bb(B);
    let r = bb(A);
    sink(r);
}

#[test]
fn add__op() {
    let a = bb(A);
    let b = bb(B);
    let _r = bb(A);
    sink(a + b);
}

#[test]
fn sub__base() {
    let _a = bb(A);
    let _b = bb(B);
    let r = bb(A);
    sink(r);
}

#[test]
fn sub__op() {
    let a = bb(A);
    let b = bb(B);
    let _r = bb(A);
    sink(a - b);
}

#[test]
fn add_assign__base() {
    let _a = bb(A);
    let _b = bb(B);
    sink(bb(A));
}

#[test]
fn add_assign__op() {
    let mut a = bb(A);
    let b = bb(B);
    let _r = bb(A);
    a += b;
    sink(a);
}

#[test]
fn sub_assign__base() {
    let _a = bb(A);
    let _b = bb(B);
    sink(bb(A));
}

#[test]
fn sub_assign__op() {
    let mut a = bb(A);
    let b = bb(B);
    let _r = bb(A);
    a -= b;
    sink(a);
}

#[test]
fn mul_assign__base() {
    let _a = bb(A);
    let _b = bb(B);
    sink(bb(A));
}

#[test]
fn mul_assign__op() {
    let mut a = bb(A);
    let b = bb(B);
    let _r = bb(A);
    a *= b;
    sink(a);
}

#[test]
fn mul_assign_scalar__base() {
    let _a = bb(A);
    let _k = bb(K_TWO);
    sink(bb(A));
}

#[test]
fn mul_assign_scalar__op() {
    let mut a = bb(A);
    let k = bb(K_TWO);
    let _r = bb(A);
    a *= k;
    sink(a);
}

#[test]
fn div_assign_scalar__base() {
    let _a = bb(A);
    let _k = bb(K_TWO);
    sink(bb(A));
}

#[test]
fn div_assign_scalar__op() {
    let mut a = bb(A);
    let k = bb(K_TWO);
    let _r = bb(A);
    a /= k;
    sink(a);
}

#[test]
fn neg__base() {
    let _a = bb(A);
    let r = bb(A);
    sink(r);
}

#[test]
fn neg__op() {
    let a = bb(A);
    let _r = bb(A);
    sink(-a);
}

#[test]
fn into_vec4__base() {
    let _a = bb(A);
    let r = bb(VEC4_ONE);
    sink(r);
}

#[test]
fn into_vec4__op() {
    let a = bb(A);
    let _r = bb(VEC4_ONE);
    sink({
        let v: Vec4 = a.into();
        v
    });
}

#[test]
fn alt_from_rotation_axes_fixed_recip__x__base() {
    let _m = bb(ROT_X);
    let r = bb(A);
    sink(r);
}

#[test]
fn alt_from_rotation_axes_fixed_recip__x__op() {
    let m = bb(ROT_X);
    let _r = bb(A);
    sink(alt::from_rotation_axes_fixed_recip(m.x_axis, m.y_axis, m.z_axis));
}

#[test]
fn alt_from_rotation_axes_fixed_recip__y__base() {
    let _m = bb(ROT_Y);
    let r = bb(A);
    sink(r);
}

#[test]
fn alt_from_rotation_axes_fixed_recip__y__op() {
    let m = bb(ROT_Y);
    let _r = bb(A);
    sink(alt::from_rotation_axes_fixed_recip(m.x_axis, m.y_axis, m.z_axis));
}

#[test]
fn alt_from_rotation_axes_fixed_recip__z__base() {
    let _m = bb(ROT_Z);
    let r = bb(A);
    sink(r);
}

#[test]
fn alt_from_rotation_axes_fixed_recip__z__op() {
    let m = bb(ROT_Z);
    let _r = bb(A);
    sink(alt::from_rotation_axes_fixed_recip(m.x_axis, m.y_axis, m.z_axis));
}

#[test]
fn alt_from_rotation_axes_fixed_recip__w__base() {
    let _m = bb(ROT_W);
    let r = bb(A);
    sink(r);
}

#[test]
fn alt_from_rotation_axes_fixed_recip__w__op() {
    let m = bb(ROT_W);
    let _r = bb(A);
    sink(alt::from_rotation_axes_fixed_recip(m.x_axis, m.y_axis, m.z_axis));
}

#[test]
fn alt_mul_quat_unfused__base() {
    let _a = bb(A);
    let _b = bb(B);
    let r = bb(A);
    sink(r);
}

#[test]
fn alt_mul_quat_unfused__op() {
    let a = bb(A);
    let b = bb(B);
    let _r = bb(A);
    sink(alt::mul_quat_unfused(a, b));
}

#[test]
fn alt_mul_vec3_two_cross__base() {
    let _a = bb(A);
    let _v = bb(V);
    let r = bb(V);
    sink(r);
}

#[test]
fn alt_mul_vec3_two_cross__op() {
    let a = bb(A);
    let v = bb(V);
    let _r = bb(V);
    sink(alt::mul_vec3_two_cross(a, v));
}

#[test]
fn alt_from_scaled_axis_fused__base() {
    let _a = bb(SCALED);
    let r = bb(A);
    sink(r);
}

#[test]
fn alt_from_scaled_axis_fused__op() {
    let a = bb(SCALED);
    let _r = bb(A);
    sink(alt::from_scaled_axis_fused(a));
}

#[test]
fn alt_to_scaled_axis_fused__base() {
    let _a = bb(A);
    let r = bb(AXIS);
    sink(r);
}

#[test]
fn alt_to_scaled_axis_fused__op() {
    let a = bb(A);
    let _r = bb(AXIS);
    sink(alt::to_scaled_axis_fused(a));
}

#[test]
fn alt_from_axis_angle_two_calls__base() {
    let _a = bb(AXIS);
    let _k = bb(ANGLE);
    let r = bb(A);
    sink(r);
}

#[test]
fn alt_from_axis_angle_two_calls__op() {
    let a = bb(AXIS);
    let k = bb(ANGLE);
    let _r = bb(A);
    sink(alt::from_axis_angle_two_calls(a, k));
}

#[test]
fn alt_slerp_fixed_recip__base() {
    let _a = bb(A);
    let _b = bb(B);
    let _k = bb(K_HALF);
    let r = bb(A);
    sink(r);
}

#[test]
fn alt_slerp_fixed_recip__op() {
    let a = bb(A);
    let b = bb(B);
    let k = bb(K_HALF);
    let _r = bb(A);
    sink(alt::slerp_fixed_recip(a, b, k));
}

#[test]
fn alt_lerp_glam__base() {
    let _a = bb(A);
    let _b = bb(B);
    let _k = bb(K_HALF);
    let r = bb(A);
    sink(r);
}

#[test]
fn alt_lerp_glam__op() {
    let a = bb(A);
    let b = bb(B);
    let k = bb(K_HALF);
    let _r = bb(A);
    sink(alt::lerp_glam(a, b, k));
}

#[test]
fn alt_is_near_identity_angle__base() {
    let _a = bb(A);
    let r = bb(true);
    sink(r);
}

#[test]
fn alt_is_near_identity_angle__op() {
    let a = bb(A);
    let _r = bb(true);
    sink(alt::is_near_identity_angle(a));
}
