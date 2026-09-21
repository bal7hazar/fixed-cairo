//! Oracles of `glam::affine3`. Spec: `specs/affine3.toml`. Every closure is the glam-rs
//! `DAffine3` method of the same name, except the rigid-body helpers (`inverse_rigid`,
//! `inv_mul`, not in glam-rs), whose oracle is their defining formula evaluated in f64.
//!
//! `look_to_*` / `look_at_*` are deprecated in glam-rs 0.33.1 (moved to `glam::camera`); they
//! are still the oracle of the `Affine3` methods of the same name. The `skip` guards drop the
//! cases where the Cairo result is dominated by an amplified error (a short view direction, a
//! direction nearly parallel to `up`).
#![allow(deprecated)]

use crate::prelude::*;

/// The guard of the view transforms: `|d| >= 1` and `|normalize(d) x up| >= 1/2`.
fn view_ok(d: DVec3, up: DVec3) -> bool {
    d.length() >= 1.0 && d.normalize().cross(up).length() >= 0.5
}

pub fn register(r: &mut Registry) {
    r.add("transform_point3", |a| a[0].daffine3().transform_point3(a[1].dvec3()));
    r.add("transform_vector3", |a| a[0].daffine3().transform_vector3(a[1].dvec3()));
    r.add("mul", |a| a[0].daffine3() * a[1].daffine3());
    r.add("mul_mat4", |a| a[0].daffine3() * a[1].dmat4());
    r.add("inverse", |a| a[0].daffine3().inverse());
    r.add("from_quat", |a| DAffine3::from_quat(a[0].dquat()));
    r.add("from_rotation_translation", |a| {
        DAffine3::from_rotation_translation(a[0].dquat(), a[1].dvec3())
    });
    r.add("from_axis_angle", |a| DAffine3::from_axis_angle(a[0].dvec3(), a[1].f()));
    r.add("from_rotation_x", |a| DAffine3::from_rotation_x(a[0].f()));
    r.add("from_rotation_y", |a| DAffine3::from_rotation_y(a[0].f()));
    r.add("from_rotation_z", |a| DAffine3::from_rotation_z(a[0].f()));
    r.add("from_mat4", |a| DAffine3::from_mat4(a[0].dmat4()));
    r.add("from_scale_rotation_translation", |a| {
        DAffine3::from_scale_rotation_translation(a[0].dvec3(), a[1].dquat(), a[2].dvec3())
    });
    // As `Mat4::to_scale_rotation_translation`: drop the draws where the oracle itself would
    // lose the rotation.
    r.add("to_scale_rotation_translation", |a| -> Out {
        let (s, q, t) = a[0].daffine3().to_scale_rotation_translation();
        if s.abs().min_element() < 0.05 {
            return skip("to_scale_rotation_translation: a degenerate scale");
        }
        (s, q, t).into()
    });
    r.add("look_to_rh", |a| -> Out {
        let (eye, dir, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        if !view_ok(dir, up) {
            return skip("look_to_rh: short direction, or nearly parallel to up");
        }
        DAffine3::look_to_rh(eye, dir, up).into()
    });
    r.add("look_to_lh", |a| -> Out {
        let (eye, dir, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        if !view_ok(dir, up) {
            return skip("look_to_lh: short direction, or nearly parallel to up");
        }
        DAffine3::look_to_lh(eye, dir, up).into()
    });
    r.add("look_at_rh", |a| -> Out {
        let (eye, center, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        if !view_ok(center - eye, up) {
            return skip("look_at_rh: short direction, or nearly parallel to up");
        }
        DAffine3::look_at_rh(eye, center, up).into()
    });
    r.add("look_at_lh", |a| -> Out {
        let (eye, center, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        if !view_ok(center - eye, up) {
            return skip("look_at_lh: short direction, or nearly parallel to up");
        }
        DAffine3::look_at_lh(eye, center, up).into()
    });
    r.add("quat_from_affine3", |a| DQuat::from_affine3(&a[0].daffine3()));
    r.add("inverse_rigid", |a| {
        let m = a[0].daffine3();
        let rt = m.matrix3.transpose();
        DAffine3::from_mat3_translation(rt, -(rt * m.translation))
    });
    r.add("inv_mul", |a| {
        let (m, n) = (a[0].daffine3(), a[1].daffine3());
        let rt = m.matrix3.transpose();
        DAffine3::from_mat3_translation(rt * n.matrix3, rt * (n.translation - m.translation))
    });
}
