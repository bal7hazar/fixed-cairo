//! Oracles of `glam::mat4`. Spec: `specs/mat4.toml`. Every closure is the glam-rs `DMat4` method
//! of the same name.
//!
//! `look_to_*` / `look_at_*` are deprecated in glam-rs 0.33.1 (moved to `glam::camera`, task C1
//! of `docs/PLAN.md`); they are still the oracle of the `Mat4` methods of the same name.
//! The `skip` guards drop the cases where the Cairo result is dominated by an amplified error
//! (a perspective divide by a tiny `w`, a view matrix whose `dir` and `up` are nearly parallel).
#![allow(deprecated)]

use crate::prelude::*;

pub fn register(r: &mut Registry) {
    r.add("add_sub", |a| {
        let (m, n) = (a[0].dmat4(), a[1].dmat4());
        (m + n, m - n)
    });
    r.add("neg", |a| -a[0].dmat4());
    r.add("mul_mat4", |a| a[0].dmat4() * a[1].dmat4());
    r.add("mul_vec4", |a| a[0].dmat4() * a[1].dvec4());
    r.add("mul_transpose_vec4", |a| a[0].dmat4().mul_transpose_vec4(a[1].dvec4()));
    r.add("mul_scalar", |a| a[0].dmat4() * a[1].f());
    r.add("div_scalar", |a| a[0].dmat4() / a[1].f());
    r.add("mul_diagonal_scale", |a| a[0].dmat4().mul_diagonal_scale(a[1].dvec4()));
    r.add("determinant", |a| a[0].dmat4().determinant());
    r.add("from_quat", |a| DMat4::from_quat(a[0].dquat()));
    r.add("from_rotation_translation", |a| {
        DMat4::from_rotation_translation(a[0].dquat(), a[1].dvec3())
    });
    r.add("from_scale_rotation_translation", |a| {
        DMat4::from_scale_rotation_translation(a[0].dvec3(), a[1].dquat(), a[2].dvec3())
    });
    // The decomposition is only well posed when the columns are long enough to normalize and
    // the scale is not degenerate; `constraint = "trs"` guarantees both, the guard below drops
    // the draws where the oracle itself would lose the rotation.
    r.add("to_scale_rotation_translation", |a| -> Out {
        let m = a[0].dmat4();
        let (s, q, t) = m.to_scale_rotation_translation();
        if s.abs().min_element() < 0.05 {
            return skip("to_scale_rotation_translation: a degenerate scale");
        }
        (s, q, t).into()
    });
    r.add("inverse", |a| a[0].dmat4().inverse());
    r.add("transpose_abs", |a| {
        let m = a[0].dmat4();
        (m.transpose(), m.abs())
    });
    r.add("recip", |a| a[0].dmat4().recip());
    r.add("diagonal_pair", |a| {
        let m = a[0].dmat4();
        (DMat4::from_diagonal(m.diagonal()), m.diagonal())
    });
    r.add("transform3", |a| {
        let (m, v) = (a[0].dmat4(), a[1].dvec3());
        (m.transform_point3(v), m.transform_vector3(v))
    });
    r.add("project_point3", |a| -> Out {
        let (m, v) = (a[0].dmat4(), a[1].dvec3());
        let w = m.x_axis.w * v.x + m.y_axis.w * v.y + m.z_axis.w * v.z + m.w_axis.w;
        if w.abs() < 1.0 {
            return skip("project_point3: |w| < 1 amplifies the error of the perspective divide");
        }
        let p = m.project_point3(v);
        if p.abs().max_element() > 100.0 {
            return skip("project_point3: |result| > 100");
        }
        p.into()
    });
    r.add("from_translation", |a| DMat4::from_translation(a[0].dvec3()));
    r.add("from_scale", |a| DMat4::from_scale(a[0].dvec3()));
    r.add("from_rotation_x", |a| DMat4::from_rotation_x(a[0].f()));
    r.add("from_rotation_y", |a| DMat4::from_rotation_y(a[0].f()));
    r.add("from_rotation_z", |a| DMat4::from_rotation_z(a[0].f()));
    r.add("from_axis_angle", |a| DMat4::from_axis_angle(a[0].dvec3(), a[1].f()));
    r.add("from_mat3", |a| DMat4::from_mat3(a[0].dmat3()));
    r.add("from_mat3_translation", |a| {
        DMat4::from_mat3_translation(a[0].dmat3(), a[1].dvec3())
    });
    r.add("look_to_rh", |a| -> Out {
        let (eye, dir, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        if dir.cross(up).length() < 0.5 {
            return skip("look_to_rh: dir and up are nearly parallel");
        }
        DMat4::look_to_rh(eye, dir, up).into()
    });
    r.add("look_to_lh", |a| -> Out {
        let (eye, dir, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        if dir.cross(up).length() < 0.5 {
            return skip("look_to_lh: dir and up are nearly parallel");
        }
        DMat4::look_to_lh(eye, dir, up).into()
    });
    r.add("look_at_rh", |a| -> Out {
        let (eye, center, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        let d = center - eye;
        if d.length() < 1.0 {
            return skip("look_at_rh: |center - eye| < 1 amplifies the error of `normalize`");
        }
        if d.normalize().cross(up).length() < 0.5 {
            return skip("look_at_rh: the view direction and up are nearly parallel");
        }
        DMat4::look_at_rh(eye, center, up).into()
    });
    r.add("look_at_lh", |a| -> Out {
        let (eye, center, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        let d = center - eye;
        if d.length() < 1.0 {
            return skip("look_at_lh: |center - eye| < 1 amplifies the error of `normalize`");
        }
        if d.normalize().cross(up).length() < 0.5 {
            return skip("look_at_lh: the view direction and up are nearly parallel");
        }
        DMat4::look_at_lh(eye, center, up).into()
    });
}
