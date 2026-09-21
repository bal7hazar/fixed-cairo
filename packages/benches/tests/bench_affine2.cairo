//! Gas benchmarks of `glam::affine2` and the inverse/composition alternatives kept in
//! `benches::alt::affine2`. Every input passes through `bb` and every result through `sink`.

use benches::alt::affine2 as alt;
use benches::harness::{bb, sink};
use fixed::fixed::Fixed;
use glam::affine2::{Affine2, Affine2Trait};
use glam::mat2::Mat2;
use glam::mat3::Mat3;
use glam::vec2::Vec2;
use glam::vec3::Vec3;

const A: Affine2 = Affine2 {
    matrix2: Mat2 {
        x_axis: Vec2 { x: Fixed { raw: 0x280000000 }, y: Fixed { raw: 0xc0000000 } },
        y_axis: Vec2 { x: Fixed { raw: 0x40000000 }, y: Fixed { raw: 0x380000000 } },
    },
    translation: Vec2 { x: Fixed { raw: 0x300000000 }, y: Fixed { raw: -0x200000000 } },
};
const B: Affine2 = Affine2 {
    matrix2: Mat2 {
        x_axis: Vec2 { x: Fixed { raw: 0x180000000 }, y: Fixed { raw: -0x40000000 } },
        y_axis: Vec2 { x: Fixed { raw: -0xa0000000 }, y: Fixed { raw: 0x200000000 } },
    },
    translation: Vec2 { x: Fixed { raw: -0x180000000 }, y: Fixed { raw: 0x80000000 } },
};
const V: Vec2 = Vec2 { x: Fixed { raw: 0x180000000 }, y: Fixed { raw: -0x1c0000000 } };
const SCALE: Vec2 = Vec2 { x: Fixed { raw: 0x180000000 }, y: Fixed { raw: 0x140000000 } };
const ANGLE: Fixed = Fixed { raw: 0xb3333333 };
const EPS: Fixed = Fixed { raw: 8 };
const M3: Mat3 = Mat3 {
    x_axis: Vec3 {
        x: Fixed { raw: 0x180000000 }, y: Fixed { raw: -0x40000000 }, z: Fixed { raw: 0x80000000 },
    },
    y_axis: Vec3 {
        x: Fixed { raw: -0xa0000000 }, y: Fixed { raw: 0x200000000 }, z: Fixed { raw: -0x40000000 },
    },
    z_axis: Vec3 {
        x: Fixed { raw: 0x80000000 }, y: Fixed { raw: -0x40000000 }, z: Fixed { raw: 0x280000000 },
    },
};

#[test]
fn from_cols__base() {
    let _x = bb(V);
    let _y = bb(SCALE);
    let _z = bb(B.translation);
    sink(bb(A));
}
#[test]
fn from_cols__op() {
    let x = bb(V);
    let y = bb(SCALE);
    let z = bb(B.translation);
    let _r = bb(A);
    sink(Affine2Trait::from_cols(x, y, z));
}

#[test]
fn from_cols_array__base() {
    let _a = bb(A);
    sink(bb(A));
}
#[test]
fn from_cols_array__op() {
    let a = bb(A);
    let _r = bb(A);
    sink(Affine2Trait::from_cols_array(a.to_cols_array()));
}

#[test]
fn to_cols_array__base() {
    let _a = bb(A);
    sink(bb(A.to_cols_array()));
}
#[test]
fn to_cols_array__op() {
    let a = bb(A);
    let _r = bb(A.to_cols_array());
    sink(a.to_cols_array());
}

#[test]
fn from_cols_array_2d__base() {
    let _a = bb(A);
    sink(bb(A));
}
#[test]
fn from_cols_array_2d__op() {
    let a = bb(A);
    let _r = bb(A);
    sink(Affine2Trait::from_cols_array_2d(a.to_cols_array_2d()));
}

#[test]
fn to_cols_array_2d__base() {
    let _a = bb(A);
    sink(bb(A.to_cols_array_2d()));
}
#[test]
fn to_cols_array_2d__op() {
    let a = bb(A);
    let _r = bb(A.to_cols_array_2d());
    sink(a.to_cols_array_2d());
}

#[test]
fn from_scale__base() {
    let _s = bb(SCALE);
    sink(bb(A));
}
#[test]
fn from_scale__op() {
    let s = bb(SCALE);
    let _r = bb(A);
    sink(Affine2Trait::from_scale(s));
}

#[test]
fn from_angle__base() {
    let _a = bb(ANGLE);
    sink(bb(A));
}
#[test]
fn from_angle__op() {
    let a = bb(ANGLE);
    let _r = bb(A);
    sink(Affine2Trait::from_angle(a));
}

#[test]
fn from_translation__base() {
    let _v = bb(V);
    sink(bb(A));
}
#[test]
fn from_translation__op() {
    let v = bb(V);
    let _r = bb(A);
    sink(Affine2Trait::from_translation(v));
}

#[test]
fn from_mat2__base() {
    let _m = bb(A.matrix2);
    sink(bb(A));
}
#[test]
fn from_mat2__op() {
    let m = bb(A.matrix2);
    let _r = bb(A);
    sink(Affine2Trait::from_mat2(m));
}

#[test]
fn from_mat2_translation__base() {
    let _m = bb(A.matrix2);
    let _t = bb(V);
    sink(bb(A));
}
#[test]
fn from_mat2_translation__op() {
    let m = bb(A.matrix2);
    let t = bb(V);
    let _r = bb(A);
    sink(Affine2Trait::from_mat2_translation(m, t));
}

#[test]
fn from_scale_angle_translation__base() {
    let _s = bb(SCALE);
    let _a = bb(ANGLE);
    let _t = bb(V);
    sink(bb(A));
}
#[test]
fn from_scale_angle_translation__op() {
    let s = bb(SCALE);
    let a = bb(ANGLE);
    let t = bb(V);
    let _r = bb(A);
    sink(Affine2Trait::from_scale_angle_translation(s, a, t));
}

#[test]
fn to_scale_angle_translation__base() {
    let _a = bb(A);
    sink(bb((SCALE, ANGLE, V)));
}
#[test]
fn to_scale_angle_translation__op() {
    let a = bb(A);
    let _r = bb((SCALE, ANGLE, V));
    sink(a.to_scale_angle_translation());
}

#[test]
fn from_angle_translation__base() {
    let _a = bb(ANGLE);
    let _t = bb(V);
    sink(bb(A));
}
#[test]
fn from_angle_translation__op() {
    let a = bb(ANGLE);
    let t = bb(V);
    let _r = bb(A);
    sink(Affine2Trait::from_angle_translation(a, t));
}

#[test]
fn from_mat3__base() {
    let _m = bb(M3);
    sink(bb(A));
}
#[test]
fn from_mat3__op() {
    let m = bb(M3);
    let _r = bb(A);
    sink(Affine2Trait::from_mat3(m));
}

#[test]
fn transform_point2__base() {
    let _a = bb(A);
    let _v = bb(V);
    sink(bb(V));
}
#[test]
fn transform_point2__op() {
    let a = bb(A);
    let v = bb(V);
    let _r = bb(V);
    sink(a.transform_point2(v));
}

#[test]
fn transform_vector2__base() {
    let _a = bb(A);
    let _v = bb(V);
    sink(bb(V));
}
#[test]
fn transform_vector2__op() {
    let a = bb(A);
    let v = bb(V);
    let _r = bb(V);
    sink(a.transform_vector2(v));
}

#[test]
fn inverse__base() {
    let _a = bb(A);
    sink(bb(A));
}
#[test]
fn inverse__op() {
    let a = bb(A);
    let _r = bb(A);
    sink(a.inverse());
}

#[test]
fn alt_inverse_two_stage__base() {
    let _a = bb(A);
    sink(bb(A));
}
#[test]
fn alt_inverse_two_stage__op() {
    let a = bb(A);
    let _r = bb(A);
    sink(alt::inverse_two_stage(a));
}

#[test]
fn abs_diff_eq_true__base() {
    let _a = bb(A);
    let _b = bb(A);
    let _e = bb(EPS);
    sink(bb(true));
}
#[test]
fn abs_diff_eq_true__op() {
    let a = bb(A);
    let b = bb(A);
    let e = bb(EPS);
    let _r = bb(true);
    sink(a.abs_diff_eq(b, e));
}

#[test]
fn abs_diff_eq_false__base() {
    let _a = bb(A);
    let _b = bb(B);
    let _e = bb(EPS);
    sink(bb(false));
}
#[test]
fn abs_diff_eq_false__op() {
    let a = bb(A);
    let b = bb(B);
    let e = bb(EPS);
    let _r = bb(false);
    sink(a.abs_diff_eq(b, e));
}

#[test]
fn mul_affine2__base() {
    let _a = bb(A);
    let _b = bb(B);
    sink(bb(A));
}
#[test]
fn mul_affine2__op() {
    let a = bb(A);
    let b = bb(B);
    let _r = bb(A);
    sink(a * b);
}

#[test]
fn alt_mul_unfused__base() {
    let _a = bb(A);
    let _b = bb(B);
    sink(bb(A));
}
#[test]
fn alt_mul_unfused__op() {
    let a = bb(A);
    let b = bb(B);
    let _r = bb(A);
    sink(alt::mul_unfused(a, b));
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
fn into_mat3__base() {
    let _a = bb(A);
    sink(bb(M3));
}
#[test]
fn into_mat3__op() {
    let a = bb(A);
    let _r = bb(M3);
    let m: Mat3 = a.into();
    sink(m);
}

#[test]
fn into_affine2__base() {
    let _m = bb(M3);
    sink(bb(A));
}
#[test]
fn into_affine2__op() {
    let m = bb(M3);
    let _r = bb(A);
    let a: Affine2 = m.into();
    sink(a);
}

#[test]
fn mul_mat3__base() {
    let _a = bb(A);
    let _m = bb(M3);
    sink(bb(M3));
}
#[test]
fn mul_mat3__op() {
    let a = bb(A);
    let m = bb(M3);
    let _r = bb(M3);
    sink(a.mul_mat3(m));
}
