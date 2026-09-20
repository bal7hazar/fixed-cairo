//! Oracles of `glam::quat`. Spec: `specs/quat.toml`. Every closure is the glam-rs `DQuat`
//! method of the same name.
//!
//! The `skip` guards drop the cases where the two implementations legitimately take different
//! branches (the singular bands of `from_rotation_arc*` and of `slerp` are re-derived for
//! Q32.32, `docs/DESIGN.md` section 3) and the ill-conditioned ones (`acos` near a dot product
//! of one, the normalization of a vector part that Cairo floors before dividing by it).

use crate::prelude::*;
use glam::{DMat3, DQuat, DVec3};

/// Below this, the axis `xyz / |xyz|` of `to_axis_angle` carries more than `1 / 0.25 = 4` raw
/// ULP from the floored length: the spec budgets that bound, not a larger one.
const MIN_AXIS: f64 = 0.25;

/// The singular bands of `from_rotation_arc` differ between glam-rs (`1 - 2 f32::EPSILON`) and
/// glam.cairo (`1 - 2^-20`), and the general branch normalizes a vector of length
/// `sqrt(2 (1 + dot))`: cases closer to a dot product of `+-1` than this are dropped.
const ARC_BAND: f64 = 1.0e-3;

/// `acos` is ill-conditioned near one: `1 ULP` of the dot product becomes
/// `1 / sqrt(1 - dot^2)` ULP on the angle. The entries that go through `acos` keep
/// `|dot| <= 0.99`, i.e. an amplification of at most 7.1.
const MAX_DOT: f64 = 0.99;

pub fn register(r: &mut Registry) {
    r.add("mul_quat", |a| a[0].dquat() * a[1].dquat());
    r.add("mul_vec3", |a| a[0].dquat().mul_vec3(a[1].dvec3()));
    // The same rotation through the 3x3 matrix of the quaternion: a different expression of the
    // same value, which cross-checks the 15-multiplication kernel against `Mat3::from_quat`.
    r.add("mul_vec3_mat3", |a| DMat3::from_quat(a[0].dquat()) * a[1].dvec3());
    r.add("conjugate", |a| a[0].dquat().conjugate());
    r.add("inverse", |a| a[0].dquat().inverse());
    r.add("add_sub", |a| {
        let (p, q) = (a[0].dquat(), a[1].dquat());
        (p + q, p - q)
    });
    r.add("mul_div_scalar", |a| {
        let (q, k) = (a[0].dquat(), a[1].f());
        (q * k, q / k)
    });
    r.add("dot", |a| a[0].dquat().dot(a[1].dquat()));
    r.add("length_pair", |a| {
        let q = a[0].dquat();
        (q.length(), q.length_squared())
    });
    r.add("length_recip", |a| a[0].dquat().length_recip());
    r.add("normalize", |a| a[0].dquat().normalize());
    r.add("from_axis_angle", |a| DQuat::from_axis_angle(a[0].dvec3(), a[1].f()));
    r.add("from_rotation_x", |a| DQuat::from_rotation_x(a[0].f()));
    r.add("from_rotation_y", |a| DQuat::from_rotation_y(a[0].f()));
    r.add("from_rotation_z", |a| DQuat::from_rotation_z(a[0].f()));
    r.add("from_scaled_axis", |a| DQuat::from_scaled_axis(a[0].dvec3()));
    r.add("to_axis_angle", |a| -> Out {
        let q = a[0].dquat();
        if q.xyz().length() < MIN_AXIS {
            return skip("to_axis_angle: the vector part is too short to normalize accurately");
        }
        q.to_axis_angle().into()
    });
    r.add("to_scaled_axis", |a| -> Out {
        let q = a[0].dquat();
        if q.xyz().length() < MIN_AXIS {
            return skip("to_scaled_axis: the vector part is too short to normalize accurately");
        }
        q.to_scaled_axis().into()
    });
    r.add("angle_between", |a| -> Out {
        let (p, q) = (a[0].dquat(), a[1].dquat());
        if p.dot(q).abs() > MAX_DOT {
            return skip("angle_between: acos is ill-conditioned near a dot product of one");
        }
        p.angle_between(q).into()
    });
    r.add("lerp", |a| a[0].dquat().lerp(a[1].dquat(), a[2].f()));
    r.add("slerp", |a| -> Out {
        let (p, q, s) = (a[0].dquat(), a[1].dquat(), a[2].f());
        if p.dot(q).abs() > MAX_DOT {
            // Above it the two ports take different branches (`1 - f32::EPSILON` against the
            // re-derived `1 - 2^-20`) and `1 / sin(theta)` amplifies every rounding.
            return skip("slerp: too close to the nlerp band");
        }
        p.slerp(q, s).into()
    });
    r.add("rotate_towards", |a| -> Out {
        let (p, q, m) = (a[0].dquat(), a[1].dquat(), a[2].f());
        if p.dot(q).abs() > MAX_DOT {
            return skip("rotate_towards: too close to the nlerp band");
        }
        let angle = p.angle_between(q);
        if (angle - 1.0e-4).abs() < 1.0e-5 || (m / angle).abs() > 0.999 {
            return skip("rotate_towards: on a branch or clamp boundary");
        }
        p.rotate_towards(q, m).into()
    });
    r.add("from_rotation_arc", |a| -> Out {
        let (from, to) = (a[0].dvec3(), a[1].dvec3());
        arc_guard(from.dot(to)).unwrap_or_else(|| DQuat::from_rotation_arc(from, to).into())
    });
    r.add("from_rotation_arc_colinear", |a| -> Out {
        let (from, to) = (a[0].dvec3(), a[1].dvec3());
        arc_guard(from.dot(to).abs())
            .unwrap_or_else(|| DQuat::from_rotation_arc_colinear(from, to).into())
    });
    r.add("from_rotation_arc_2d", |a| -> Out {
        let (from, to) = (a[0].dvec2(), a[1].dvec2());
        arc_guard(from.dot(to)).unwrap_or_else(|| DQuat::from_rotation_arc_2d(from, to).into())
    });
    // A unit quaternion whose vector part is long enough for `to_axis_angle` to normalize it:
    // an axis-angle rotation with an angle away from zero and from a half turn.
    r.generator("turned", |rng| {
        let mut axis = DVec3::ZERO;
        while axis.length() < 0.1 {
            let mut leaf = || raw_to_f64(rng.range_i64(-ONE_RAW, ONE_RAW));
            axis = DVec3::new(leaf(), leaf(), leaf());
        }
        // `|xyz| = sin(angle / 2) >= 0.29` for an angle in `[0.6, 2.5]` rad.
        let angle = raw_to_f64(rng.range_i64(ONE_RAW * 3 / 5, ONE_RAW * 5 / 2));
        value_of(DQuat::from_axis_angle(axis.normalize(), angle))
    });
}

/// `None` outside the singular bands of `from_rotation_arc*`, a skip inside them.
fn arc_guard(dot: f64) -> Option<Out> {
    if dot > 1.0 - ARC_BAND {
        return Some(skip("from_rotation_arc: inside the 0 degree band"));
    }
    if dot < -1.0 + ARC_BAND {
        return Some(skip("from_rotation_arc: inside the 180 degree band"));
    }
    None
}
