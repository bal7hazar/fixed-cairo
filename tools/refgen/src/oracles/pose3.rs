//! Oracles of `glamx::pose3`. Spec: `specs/pose3.toml`. Every closure is the glamx 0.3.1
//! `DPose3` method (or operator) of the same name; `nlerp` (a glamx.cairo addition) is the same
//! composition with `DQuat::lerp` in place of `DQuat::slerp`.
//!
//! The pose arguments come from the `pose` generator: a unit rotation (quantized, so unit to
//! within a few ULP on the squared length, and both sides see the same quantized input) and a
//! translation within `|x| <= 500`, so that every quadratic term of the rotation of a point keeps
//! half a raw ULP of f64 resolution.

use crate::prelude::*;
use glamx::DPose3;

/// `acos` is ill-conditioned near one and the two ports switch to nlerp at different
/// thresholds (`1 - f32::EPSILON` in glam-rs, `1 - 2^-20` in glam.cairo): as the `slerp` entry
/// of `specs/quat.toml`, `lerp` keeps `|dot| <= 0.99`.
const MAX_DOT: f64 = 0.99;

/// Largest translation component drawn by the generators.
const MAX_T: i64 = 500 * ONE_RAW;

/// A unit quaternion from uniform raw leaves, before quantization.
fn unit_quat(rng: &mut Rng) -> DQuat {
    loop {
        let mut leaf = || raw_to_f64(rng.range_i64(-ONE_RAW, ONE_RAW));
        let q = DQuat::from_xyzw(leaf(), leaf(), leaf(), leaf());
        if q.length() > 0.1 {
            return q.normalize();
        }
    }
}

fn translation(rng: &mut Rng) -> DVec3 {
    let mut leaf = || raw_to_f64(rng.range_i64(-MAX_T, MAX_T));
    DVec3::new(leaf(), leaf(), leaf())
}

pub fn register(r: &mut Registry) {
    r.generator("pose", |rng| {
        let q = unit_quat(rng);
        let t = translation(rng);
        value_of(DPose3::from_parts(t, q))
    });
    r.generator("rigid", |rng| {
        let q = unit_quat(rng);
        let t = translation(rng);
        value_of(DMat4::from_rotation_translation(q, t))
    });

    r.add("mul", |a| a[0].dpose3() * a[1].dpose3());
    r.add("inv_mul", |a| a[0].dpose3().inv_mul(&a[1].dpose3()));
    r.add("inverse", |a| a[0].dpose3().inverse());
    r.add("transform_point", |a| a[0].dpose3().transform_point(a[1].dvec3()));
    r.add("transform_vector", |a| a[0].dpose3().transform_vector(a[1].dvec3()));
    r.add("inverse_transform_point", |a| {
        a[0].dpose3().inverse_transform_point(a[1].dvec3())
    });
    r.add("inverse_transform_vector", |a| {
        a[0].dpose3().inverse_transform_vector(a[1].dvec3())
    });
    r.add("mul_vec3", |a| a[0].dpose3() * a[1].dvec3());
    r.add("prepend_translation", |a| a[0].dpose3().prepend_translation(a[1].dvec3()));
    r.add("append_translation", |a| a[0].dpose3().append_translation(a[1].dvec3()));
    r.add("mul_rot3", |a| a[0].dpose3() * a[1].dquat());
    r.add("mul_pose3", |a| a[0].dquat() * a[1].dpose3());
    r.add("new", |a| DPose3::new(a[0].dvec3(), a[1].dvec3()));
    r.add("rotation", |a| DPose3::rotation(a[0].dvec3()));
    r.add("lerp", |a| -> Out {
        let (p, q, t) = (a[0].dpose3(), a[1].dpose3(), a[2].f());
        if p.rotation.dot(q.rotation).abs() > MAX_DOT {
            return skip("lerp: too close to the nlerp band of slerp");
        }
        p.lerp(&q, t).into()
    });
    r.add("nlerp", |a| {
        let (p, q, t) = (a[0].dpose3(), a[1].dpose3(), a[2].f());
        DPose3::from_parts(
            p.translation.lerp(q.translation, t),
            p.rotation.lerp(q.rotation, t),
        )
    });
    r.add("to_mat4", |a| a[0].dpose3().to_mat4());
    r.add("from_mat4", |a| DPose3::from_mat4(a[0].dmat4()));
}
