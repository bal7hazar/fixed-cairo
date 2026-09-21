//! Oracles of `glam::mat3`. Spec: `specs/mat3.toml`. Every closure is the glam-rs `DMat3` method
//! of the same name.
//!
//! Functions of the same arguments are checked together as a tuple (`add_sub`, `transpose_abs`,
//! `diagonal_pair`, `transform2`): the generated file is capped at 1 500 lines and every entry
//! costs a test body.

use crate::prelude::*;

pub fn register(r: &mut Registry) {
    r.add("add_sub", |a| {
        let (m, n) = (a[0].dmat3(), a[1].dmat3());
        (m + n, m - n)
    });
    r.add("neg", |a| -a[0].dmat3());
    r.add("mul_mat3", |a| a[0].dmat3() * a[1].dmat3());
    r.add("mul_vec3", |a| a[0].dmat3() * a[1].dvec3());
    r.add("mul_transpose_vec3", |a| a[0].dmat3().mul_transpose_vec3(a[1].dvec3()));
    r.add("mul_scalar", |a| a[0].dmat3() * a[1].f());
    r.add("div_scalar", |a| a[0].dmat3() / a[1].f());
    r.add("mul_diagonal_scale", |a| a[0].dmat3().mul_diagonal_scale(a[1].dvec3()));
    r.add("determinant", |a| a[0].dmat3().determinant());
    r.add("inverse", |a| a[0].dmat3().inverse());
    r.add("transpose_abs", |a| {
        let m = a[0].dmat3();
        (m.transpose(), m.abs())
    });
    r.add("recip", |a| a[0].dmat3().recip());
    r.add("diagonal_pair", |a| {
        let m = a[0].dmat3();
        (DMat3::from_diagonal(m.diagonal()), m.diagonal())
    });
    r.add("transform2", |a| {
        let (m, v) = (a[0].dmat3(), a[1].dvec2());
        (m.transform_point2(v), m.transform_vector2(v))
    });
    r.add("from_axis_angle", |a| DMat3::from_axis_angle(a[0].dvec3(), a[1].f()));
    r.add("from_rotation_x", |a| DMat3::from_rotation_x(a[0].f()));
    r.add("from_rotation_y", |a| DMat3::from_rotation_y(a[0].f()));
    r.add("from_rotation_z", |a| DMat3::from_rotation_z(a[0].f()));
    r.add("from_angle", |a| DMat3::from_angle(a[0].f()));
    r.add("from_scale", |a| DMat3::from_scale(a[0].dvec2()));
    r.add("from_translation", |a| DMat3::from_translation(a[0].dvec2()));
    r.add("from_scale_angle_translation", |a| {
        DMat3::from_scale_angle_translation(a[0].dvec2(), a[1].f(), a[2].dvec2())
    });
    r.add("from_quat", |a| DMat3::from_quat(a[0].dquat()));
    r.add("from_mat2", |a| DMat3::from_mat2(a[0].dmat2()));
    r.add("from_mat4", |a| DMat3::from_mat4(a[0].dmat4()));
    r.add("from_mat4_minor", |a| {
        DMat3::from_mat4_minor(a[0].dmat4(), a[1].u32() as usize, a[2].u32() as usize)
    });
}
