//! Gas benchmarks of `glam::affine3` and the alternatives kept in `benches::alt::affine3`.
//! Every input passes through `bb` and every result through `sink`.

use benches::alt::affine3 as alt;
use benches::harness::{bb, sink};
use fixed::fixed::Fixed;
use glam::affine3::{Affine3, Affine3RigidTrait, Affine3Trait, quat_from_affine3};
use glam::mat3::Mat3;
use glam::mat4::Mat4;
use glam::quat::Quat;
use glam::vec3::Vec3;
use glam::vec4::Vec4;

const A: Affine3 = Affine3 {
    matrix3: Mat3 {
        x_axis: Vec3 {
            x: Fixed { raw: 10737418240 },
            y: Fixed { raw: 3221225472 },
            z: Fixed { raw: -1073741824 },
        },
        y_axis: Vec3 {
            x: Fixed { raw: 1073741824 },
            y: Fixed { raw: 15032385536 },
            z: Fixed { raw: 2147483648 },
        },
        z_axis: Vec3 {
            x: Fixed { raw: -2147483648 },
            y: Fixed { raw: 1073741824 },
            z: Fixed { raw: 7516192768 },
        },
    },
    translation: Vec3 {
        x: Fixed { raw: 12884901888 }, y: Fixed { raw: -8589934592 }, z: Fixed { raw: 6442450944 },
    },
};
const B: Affine3 = Affine3 {
    matrix3: Mat3 {
        x_axis: Vec3 {
            x: Fixed { raw: 6442450944 },
            y: Fixed { raw: -1073741824 },
            z: Fixed { raw: 2147483648 },
        },
        y_axis: Vec3 {
            x: Fixed { raw: -2684354560 },
            y: Fixed { raw: 8589934592 },
            z: Fixed { raw: 1073741824 },
        },
        z_axis: Vec3 {
            x: Fixed { raw: 1073741824 },
            y: Fixed { raw: -3221225472 },
            z: Fixed { raw: 5368709120 },
        },
    },
    translation: Vec3 {
        x: Fixed { raw: -6442450944 }, y: Fixed { raw: 2147483648 }, z: Fixed { raw: 9663676416 },
    },
};
const R: Affine3 = Affine3 {
    matrix3: Mat3 {
        x_axis: Vec3 {
            x: Fixed { raw: 1546188227 },
            y: Fixed { raw: 3435973837 },
            z: Fixed { raw: -2061584302 },
        },
        y_axis: Vec3 {
            x: Fixed { raw: -2061584302 },
            y: Fixed { raw: 2576980378 },
            z: Fixed { raw: 2748779069 },
        },
        z_axis: Vec3 {
            x: Fixed { raw: 3435973837 }, y: Fixed { raw: 0 }, z: Fixed { raw: 2576980378 },
        },
    },
    translation: Vec3 {
        x: Fixed { raw: 12884901888 }, y: Fixed { raw: -8589934592 }, z: Fixed { raw: 6442450944 },
    },
};
const S: Affine3 = Affine3 {
    matrix3: Mat3 {
        x_axis: Vec3 {
            x: Fixed { raw: 2576980378 }, y: Fixed { raw: 0 }, z: Fixed { raw: -3435973837 },
        },
        y_axis: Vec3 { x: Fixed { raw: 0 }, y: Fixed { raw: 4294967296 }, z: Fixed { raw: 0 } },
        z_axis: Vec3 {
            x: Fixed { raw: 3435973837 }, y: Fixed { raw: 0 }, z: Fixed { raw: 2576980378 },
        },
    },
    translation: Vec3 {
        x: Fixed { raw: -4294967296 }, y: Fixed { raw: 17179869184 }, z: Fixed { raw: 8589934592 },
    },
};
const TRS_W: Affine3 = Affine3 {
    matrix3: Mat3 {
        x_axis: Vec3 { x: Fixed { raw: 8589934592 }, y: Fixed { raw: 0 }, z: Fixed { raw: 0 } },
        y_axis: Vec3 { x: Fixed { raw: 0 }, y: Fixed { raw: 12884901888 }, z: Fixed { raw: 0 } },
        z_axis: Vec3 { x: Fixed { raw: 0 }, y: Fixed { raw: 0 }, z: Fixed { raw: 2147483648 } },
    },
    translation: Vec3 {
        x: Fixed { raw: 4294967296 }, y: Fixed { raw: 8589934592 }, z: Fixed { raw: 12884901888 },
    },
};
const TRS_X: Affine3 = Affine3 {
    matrix3: Mat3 {
        x_axis: Vec3 { x: Fixed { raw: 8589934592 }, y: Fixed { raw: 0 }, z: Fixed { raw: 0 } },
        y_axis: Vec3 { x: Fixed { raw: 0 }, y: Fixed { raw: -12884901888 }, z: Fixed { raw: 0 } },
        z_axis: Vec3 { x: Fixed { raw: 0 }, y: Fixed { raw: 0 }, z: Fixed { raw: -2147483648 } },
    },
    translation: Vec3 {
        x: Fixed { raw: 4294967296 }, y: Fixed { raw: 8589934592 }, z: Fixed { raw: 12884901888 },
    },
};
const V: Vec3 = Vec3 {
    x: Fixed { raw: 6442450944 }, y: Fixed { raw: -7516192768 }, z: Fixed { raw: 2147483648 },
};
const EYE: Vec3 = Vec3 {
    x: Fixed { raw: 4294967296 }, y: Fixed { raw: 8589934592 }, z: Fixed { raw: 12884901888 },
};
const DIR: Vec3 = Vec3 {
    x: Fixed { raw: 2576980378 }, y: Fixed { raw: 0 }, z: Fixed { raw: -3435973837 },
};
const UP: Vec3 = Vec3 { x: Fixed { raw: 0 }, y: Fixed { raw: 4294967296 }, z: Fixed { raw: 0 } };
const CENTER: Vec3 = Vec3 {
    x: Fixed { raw: -8589934592 }, y: Fixed { raw: 4294967296 }, z: Fixed { raw: 17179869184 },
};
const SCALE: Vec3 = Vec3 {
    x: Fixed { raw: 6442450944 }, y: Fixed { raw: 5368709120 }, z: Fixed { raw: 3221225472 },
};
const AXIS: Vec3 = Vec3 {
    x: Fixed { raw: 2576980378 }, y: Fixed { raw: 0 }, z: Fixed { raw: 3435973837 },
};
const ANGLE: Fixed = Fixed { raw: 3006477107 };
const EPS: Fixed = Fixed { raw: 8 };
const ROT: Quat = Quat {
    x: Fixed { raw: 858993459 },
    y: Fixed { raw: 1717986918 },
    z: Fixed { raw: 1717986918 },
    w: Fixed { raw: 3435973837 },
};
const M3: Mat3 = Mat3 {
    x_axis: Vec3 {
        x: Fixed { raw: 6442450944 }, y: Fixed { raw: -1073741824 }, z: Fixed { raw: 2147483648 },
    },
    y_axis: Vec3 {
        x: Fixed { raw: -2684354560 }, y: Fixed { raw: 8589934592 }, z: Fixed { raw: -1073741824 },
    },
    z_axis: Vec3 {
        x: Fixed { raw: 2147483648 }, y: Fixed { raw: -1073741824 }, z: Fixed { raw: 10737418240 },
    },
};
const M4: Mat4 = Mat4 {
    x_axis: Vec4 {
        x: Fixed { raw: 6442450944 },
        y: Fixed { raw: -1073741824 },
        z: Fixed { raw: 2147483648 },
        w: Fixed { raw: 0 },
    },
    y_axis: Vec4 {
        x: Fixed { raw: -2684354560 },
        y: Fixed { raw: 8589934592 },
        z: Fixed { raw: -1073741824 },
        w: Fixed { raw: 536870912 },
    },
    z_axis: Vec4 {
        x: Fixed { raw: 2147483648 },
        y: Fixed { raw: -1073741824 },
        z: Fixed { raw: 10737418240 },
        w: Fixed { raw: 0 },
    },
    w_axis: Vec4 {
        x: Fixed { raw: 4294967296 },
        y: Fixed { raw: -8589934592 },
        z: Fixed { raw: 12884901888 },
        w: Fixed { raw: 4294967296 },
    },
};

#[test]
fn from_cols__base() {
    let _x = bb(V);
    let _y = bb(SCALE);
    let _z = bb(AXIS);
    let _w = bb(EYE);
    sink(bb(A));
}
#[test]
fn from_cols__op() {
    let x = bb(V);
    let y = bb(SCALE);
    let z = bb(AXIS);
    let w = bb(EYE);
    let _r = bb(A);
    sink(Affine3Trait::from_cols(x, y, z, w));
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
    sink(Affine3Trait::from_cols_array(a.to_cols_array()));
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
    sink(Affine3Trait::from_cols_array_2d(a.to_cols_array_2d()));
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
    sink(Affine3Trait::from_scale(s));
}

#[test]
fn from_quat__base() {
    let _q = bb(ROT);
    sink(bb(A));
}
#[test]
fn from_quat__op() {
    let q = bb(ROT);
    let _r = bb(A);
    sink(Affine3Trait::from_quat(q));
}

#[test]
fn from_axis_angle__base() {
    let _v = bb(AXIS);
    let _t = bb(ANGLE);
    sink(bb(A));
}
#[test]
fn from_axis_angle__op() {
    let v = bb(AXIS);
    let t = bb(ANGLE);
    let _r = bb(A);
    sink(Affine3Trait::from_axis_angle(v, t));
}

#[test]
fn from_rotation_x__base() {
    let _t = bb(ANGLE);
    sink(bb(A));
}
#[test]
fn from_rotation_x__op() {
    let t = bb(ANGLE);
    let _r = bb(A);
    sink(Affine3Trait::from_rotation_x(t));
}

#[test]
fn from_rotation_y__base() {
    let _t = bb(ANGLE);
    sink(bb(A));
}
#[test]
fn from_rotation_y__op() {
    let t = bb(ANGLE);
    let _r = bb(A);
    sink(Affine3Trait::from_rotation_y(t));
}

#[test]
fn from_rotation_z__base() {
    let _t = bb(ANGLE);
    sink(bb(A));
}
#[test]
fn from_rotation_z__op() {
    let t = bb(ANGLE);
    let _r = bb(A);
    sink(Affine3Trait::from_rotation_z(t));
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
    sink(Affine3Trait::from_translation(v));
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
    sink(Affine3Trait::from_mat3(m));
}

#[test]
fn from_mat3_translation__base() {
    let _m = bb(M3);
    let _v = bb(V);
    sink(bb(A));
}
#[test]
fn from_mat3_translation__op() {
    let m = bb(M3);
    let v = bb(V);
    let _r = bb(A);
    sink(Affine3Trait::from_mat3_translation(m, v));
}

#[test]
fn from_scale_rotation_translation__base() {
    let _s = bb(SCALE);
    let _q = bb(ROT);
    let _v = bb(V);
    sink(bb(A));
}
#[test]
fn from_scale_rotation_translation__op() {
    let s = bb(SCALE);
    let q = bb(ROT);
    let v = bb(V);
    let _r = bb(A);
    sink(Affine3Trait::from_scale_rotation_translation(s, q, v));
}

#[test]
fn from_rotation_translation__base() {
    let _q = bb(ROT);
    let _v = bb(V);
    sink(bb(A));
}
#[test]
fn from_rotation_translation__op() {
    let q = bb(ROT);
    let v = bb(V);
    let _r = bb(A);
    sink(Affine3Trait::from_rotation_translation(q, v));
}

#[test]
fn from_mat4__base() {
    let _m = bb(M4);
    sink(bb(A));
}
#[test]
fn from_mat4__op() {
    let m = bb(M4);
    let _r = bb(A);
    sink(Affine3Trait::from_mat4(m));
}

#[test]
fn to_scale_rotation_translation_w__base() {
    let _a = bb(TRS_W);
    sink(bb((SCALE, ROT, V)));
}
#[test]
fn to_scale_rotation_translation_w__op() {
    let a = bb(TRS_W);
    let _r = bb((SCALE, ROT, V));
    sink(a.to_scale_rotation_translation());
}

#[test]
fn to_scale_rotation_translation_x__base() {
    let _a = bb(TRS_X);
    sink(bb((SCALE, ROT, V)));
}
#[test]
fn to_scale_rotation_translation_x__op() {
    let a = bb(TRS_X);
    let _r = bb((SCALE, ROT, V));
    sink(a.to_scale_rotation_translation());
}

#[test]
fn look_to_lh__base() {
    let _e = bb(EYE);
    let _d = bb(DIR);
    let _u = bb(UP);
    sink(bb(A));
}
#[test]
fn look_to_lh__op() {
    let e = bb(EYE);
    let d = bb(DIR);
    let u = bb(UP);
    let _r = bb(A);
    sink(Affine3Trait::look_to_lh(e, d, u));
}

#[test]
fn look_to_rh__base() {
    let _e = bb(EYE);
    let _d = bb(DIR);
    let _u = bb(UP);
    sink(bb(A));
}
#[test]
fn look_to_rh__op() {
    let e = bb(EYE);
    let d = bb(DIR);
    let u = bb(UP);
    let _r = bb(A);
    sink(Affine3Trait::look_to_rh(e, d, u));
}

#[test]
fn look_at_lh__base() {
    let _e = bb(EYE);
    let _c = bb(CENTER);
    let _u = bb(UP);
    sink(bb(A));
}
#[test]
fn look_at_lh__op() {
    let e = bb(EYE);
    let c = bb(CENTER);
    let u = bb(UP);
    let _r = bb(A);
    sink(Affine3Trait::look_at_lh(e, c, u));
}

#[test]
fn look_at_rh__base() {
    let _e = bb(EYE);
    let _c = bb(CENTER);
    let _u = bb(UP);
    sink(bb(A));
}
#[test]
fn look_at_rh__op() {
    let e = bb(EYE);
    let c = bb(CENTER);
    let u = bb(UP);
    let _r = bb(A);
    sink(Affine3Trait::look_at_rh(e, c, u));
}

#[test]
fn transform_point3__base() {
    let _a = bb(A);
    let _v = bb(V);
    sink(bb(V));
}
#[test]
fn transform_point3__op() {
    let a = bb(A);
    let v = bb(V);
    let _r = bb(V);
    sink(a.transform_point3(v));
}

#[test]
fn transform_vector3__base() {
    let _a = bb(A);
    let _v = bb(V);
    sink(bb(V));
}
#[test]
fn transform_vector3__op() {
    let a = bb(A);
    let v = bb(V);
    let _r = bb(V);
    sink(a.transform_vector3(v));
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
fn alt_inverse_cramer__base() {
    let _a = bb(A);
    sink(bb(A));
}
#[test]
fn alt_inverse_cramer__op() {
    let a = bb(A);
    let _r = bb(A);
    sink(alt::inverse_cramer(a));
}

#[test]
fn mul_affine3__base() {
    let _a = bb(A);
    let _b = bb(B);
    sink(bb(A));
}
#[test]
fn mul_affine3__op() {
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
fn into_mat4__base() {
    let _a = bb(A);
    sink(bb(M4));
}
#[test]
fn into_mat4__op() {
    let a = bb(A);
    let _r = bb(M4);
    sink(Into::<Affine3, Mat4>::into(a));
}

#[test]
fn mul_mat4__base() {
    let _a = bb(A);
    let _m = bb(M4);
    sink(bb(M4));
}
#[test]
fn mul_mat4__op() {
    let a = bb(A);
    let m = bb(M4);
    let _r = bb(M4);
    sink(a.mul_mat4(m));
}

#[test]
fn alt_mul_mat4_embed__base() {
    let _a = bb(A);
    let _m = bb(M4);
    sink(bb(M4));
}
#[test]
fn alt_mul_mat4_embed__op() {
    let a = bb(A);
    let m = bb(M4);
    let _r = bb(M4);
    sink(alt::mul_mat4_embed(a, m));
}

#[test]
fn quat_from_affine3_w__base() {
    let _a = bb(R);
    sink(bb(ROT));
}
#[test]
fn quat_from_affine3_w__op() {
    let a = bb(R);
    let _r = bb(ROT);
    sink(quat_from_affine3(a));
}

#[test]
fn quat_from_affine3_x__base() {
    let _a = bb(TRS_X);
    sink(bb(ROT));
}
#[test]
fn quat_from_affine3_x__op() {
    let a = bb(TRS_X);
    let _r = bb(ROT);
    sink(quat_from_affine3(a));
}

#[test]
fn inverse_rigid__base() {
    let _a = bb(R);
    sink(bb(A));
}
#[test]
fn inverse_rigid__op() {
    let a = bb(R);
    let _r = bb(A);
    sink(a.inverse_rigid());
}

#[test]
fn alt_inverse_rigid_neg_after__base() {
    let _a = bb(R);
    sink(bb(A));
}
#[test]
fn alt_inverse_rigid_neg_after__op() {
    let a = bb(R);
    let _r = bb(A);
    sink(alt::inverse_rigid_neg_after(a));
}

#[test]
fn inv_mul__base() {
    let _a = bb(R);
    let _b = bb(S);
    sink(bb(A));
}
#[test]
fn inv_mul__op() {
    let a = bb(R);
    let b = bb(S);
    let _r = bb(A);
    sink(a.inv_mul(b));
}

#[test]
fn alt_inv_mul_composed__base() {
    let _a = bb(R);
    let _b = bb(S);
    sink(bb(A));
}
#[test]
fn alt_inv_mul_composed__op() {
    let a = bb(R);
    let b = bb(S);
    let _r = bb(A);
    sink(alt::inv_mul_composed(a, b));
}

#[test]
fn alt_inv_mul_sub_first__base() {
    let _a = bb(R);
    let _b = bb(S);
    sink(bb(A));
}
#[test]
fn alt_inv_mul_sub_first__op() {
    let a = bb(R);
    let b = bb(S);
    let _r = bb(A);
    sink(alt::inv_mul_sub_first(a, b));
}
