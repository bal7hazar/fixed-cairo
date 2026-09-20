//! Oracles of `glam::euler`. Spec: `specs/euler.toml`.
//!
//! One closure per (function, order): `EulerRot` is an enum, not a bundle of `Fixed` leaves, so
//! refgen cannot draw it as an argument and the order is baked into the name.
//!
//! The `to_euler` closures skip the cases that sit on the gimbal-lock branch boundary. The
//! middle angle `j` that comes back is `atan2(sy, ..)` for a repeated order and
//! `atan2(.., cy)` for a Tait-Bryan one, so `sy = |sin j|` and `cy = |cos j|` are recovered
//! from it without re-deriving the axis permutation.

use crate::prelude::*;

/// Below this residual, glam-rs (`sqrt(..) > 16 * f64::EPSILON`) and glam.cairo
/// (`> 16 * 2^-32`) can pick different branches of `to_euler`. It is eleven orders of magnitude
/// above the Cairo threshold, so both sides are always in the general branch.
const BRANCH: f64 = 1.0e-6;

/// `Quat::to_euler` builds the rotation matrix first, and its entries differ from the f64 ones
/// by up to 2 ULP; the first and third angles amplify that by `1 / cy`. Cases below this keep
/// the amplification under four.
const MIN_RESIDUAL: f64 = 0.25;

/// The residual of the singular branch: `|sin j|` for a proper Euler order (singular at `j = 0`
/// or `pi`), `|cos j|` for a Tait-Bryan one (singular at `j = +-pi/2`).
fn residual(repeated: bool, j: f64) -> f64 {
    if repeated {
        j.sin().abs()
    } else {
        j.cos().abs()
    }
}

pub fn register(r: &mut Registry) {
    r.add("mat3_from_euler_zyx", |a| {
        DMat3::from_euler(EulerRot::ZYX, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_zxy", |a| {
        DMat3::from_euler(EulerRot::ZXY, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_yxz", |a| {
        DMat3::from_euler(EulerRot::YXZ, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_yzx", |a| {
        DMat3::from_euler(EulerRot::YZX, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_xyz", |a| {
        DMat3::from_euler(EulerRot::XYZ, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_xzy", |a| {
        DMat3::from_euler(EulerRot::XZY, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_zyz", |a| {
        DMat3::from_euler(EulerRot::ZYZ, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_zxz", |a| {
        DMat3::from_euler(EulerRot::ZXZ, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_yxy", |a| {
        DMat3::from_euler(EulerRot::YXY, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_yzy", |a| {
        DMat3::from_euler(EulerRot::YZY, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_xyx", |a| {
        DMat3::from_euler(EulerRot::XYX, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_xzx", |a| {
        DMat3::from_euler(EulerRot::XZX, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_zyx_ex", |a| {
        DMat3::from_euler(EulerRot::ZYXEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_zxy_ex", |a| {
        DMat3::from_euler(EulerRot::ZXYEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_yxz_ex", |a| {
        DMat3::from_euler(EulerRot::YXZEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_yzx_ex", |a| {
        DMat3::from_euler(EulerRot::YZXEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_xyz_ex", |a| {
        DMat3::from_euler(EulerRot::XYZEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_xzy_ex", |a| {
        DMat3::from_euler(EulerRot::XZYEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_zyz_ex", |a| {
        DMat3::from_euler(EulerRot::ZYZEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_zxz_ex", |a| {
        DMat3::from_euler(EulerRot::ZXZEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_yxy_ex", |a| {
        DMat3::from_euler(EulerRot::YXYEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_yzy_ex", |a| {
        DMat3::from_euler(EulerRot::YZYEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_xyx_ex", |a| {
        DMat3::from_euler(EulerRot::XYXEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat3_from_euler_xzx_ex", |a| {
        DMat3::from_euler(EulerRot::XZXEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("to_euler_xyz", |a| -> Out {
        let (i, j, k) = a[0].dmat3().to_euler(EulerRot::XYZ);
        if residual(false, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
    r.add("to_euler_xyx_ex", |a| -> Out {
        let (i, j, k) = a[0].dmat3().to_euler(EulerRot::XYXEx);
        if residual(true, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
    r.add("to_euler_xzy_ex", |a| -> Out {
        let (i, j, k) = a[0].dmat3().to_euler(EulerRot::XZYEx);
        if residual(false, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
    r.add("to_euler_yzy", |a| -> Out {
        let (i, j, k) = a[0].dmat3().to_euler(EulerRot::YZY);
        if residual(true, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
    r.add("to_euler_zxy", |a| -> Out {
        let (i, j, k) = a[0].dmat3().to_euler(EulerRot::ZXY);
        if residual(false, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
    r.add("to_euler_zxz_ex", |a| -> Out {
        let (i, j, k) = a[0].dmat3().to_euler(EulerRot::ZXZEx);
        if residual(true, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
    r.add("to_euler_yzx_ex", |a| -> Out {
        let (i, j, k) = a[0].dmat3().to_euler(EulerRot::YZXEx);
        if residual(false, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
    r.add("to_euler_xzx", |a| -> Out {
        let (i, j, k) = a[0].dmat3().to_euler(EulerRot::XZX);
        if residual(true, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
    r.add("to_euler_yxz", |a| -> Out {
        let (i, j, k) = a[0].dmat3().to_euler(EulerRot::YXZ);
        if residual(false, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
    r.add("to_euler_yxy_ex", |a| -> Out {
        let (i, j, k) = a[0].dmat3().to_euler(EulerRot::YXYEx);
        if residual(true, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
    r.add("to_euler_xyz_ex", |a| -> Out {
        let (i, j, k) = a[0].dmat3().to_euler(EulerRot::XYZEx);
        if residual(false, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
    r.add("to_euler_zyz", |a| -> Out {
        let (i, j, k) = a[0].dmat3().to_euler(EulerRot::ZYZ);
        if residual(true, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
    r.add("quat_from_euler_xyz", |a| {
        DQuat::from_euler(EulerRot::XYZ, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("quat_from_euler_yxy", |a| {
        DQuat::from_euler(EulerRot::YXY, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("quat_from_euler_zxy", |a| {
        DQuat::from_euler(EulerRot::ZXY, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("quat_from_euler_xzy", |a| {
        DQuat::from_euler(EulerRot::XZY, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("quat_from_euler_yxz_ex", |a| {
        DQuat::from_euler(EulerRot::YXZEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("quat_from_euler_zyz_ex", |a| {
        DQuat::from_euler(EulerRot::ZYZEx, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("quat_to_euler_xyz", |a| -> Out {
        let (i, j, k) = a[0].dquat().to_euler(EulerRot::XYZ);
        if residual(false, j) < MIN_RESIDUAL {
            return skip("quat_to_euler: too close to gimbal lock");
        }
        (i, j, k).into()
    });
    r.add("quat_to_euler_yxy", |a| -> Out {
        let (i, j, k) = a[0].dquat().to_euler(EulerRot::YXY);
        if residual(true, j) < MIN_RESIDUAL {
            return skip("quat_to_euler: too close to gimbal lock");
        }
        (i, j, k).into()
    });
    r.add("quat_to_euler_zxy", |a| -> Out {
        let (i, j, k) = a[0].dquat().to_euler(EulerRot::ZXY);
        if residual(false, j) < MIN_RESIDUAL {
            return skip("quat_to_euler: too close to gimbal lock");
        }
        (i, j, k).into()
    });
    r.add("quat_to_euler_yxz_ex", |a| -> Out {
        let (i, j, k) = a[0].dquat().to_euler(EulerRot::YXZEx);
        if residual(false, j) < MIN_RESIDUAL {
            return skip("quat_to_euler: too close to gimbal lock");
        }
        (i, j, k).into()
    });
    r.add("mat4_from_euler_yxz", |a| {
        DMat4::from_euler(EulerRot::YXZ, a[0].f(), a[1].f(), a[2].f())
    });
    r.add("mat4_to_euler_yxz", |a| -> Out {
        let (i, j, k) = a[0].dmat4().to_euler(EulerRot::YXZ);
        if residual(false, j) < BRANCH {
            return skip("to_euler: on the gimbal-lock branch boundary");
        }
        (i, j, k).into()
    });
}
