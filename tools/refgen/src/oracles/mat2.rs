//! Oracles of `glam::mat2`. Spec: `specs/mat2.toml`. Every closure is the glam-rs `DMat2` method
//! of the same name.
//!
//! Functions of the same arguments are checked together as a tuple (`add_sub`, `transpose_abs`,
//! `diagonal_pair`): the generated file is capped at 1 500 lines and every entry costs a test
//! body.

use crate::prelude::*;

pub fn register(r: &mut Registry) {
    r.add("add_sub", |a| {
        let (m, n) = (a[0].dmat2(), a[1].dmat2());
        (m + n, m - n)
    });
    r.add("neg", |a| -a[0].dmat2());
    r.add("mul_mat2", |a| a[0].dmat2() * a[1].dmat2());
    r.add("mul_vec2", |a| a[0].dmat2() * a[1].dvec2());
    r.add("mul_transpose_vec2", |a| a[0].dmat2().mul_transpose_vec2(a[1].dvec2()));
    r.add("mul_scalar", |a| a[0].dmat2() * a[1].f());
    r.add("div_scalar", |a| a[0].dmat2() / a[1].f());
    r.add("mul_diagonal_scale", |a| a[0].dmat2().mul_diagonal_scale(a[1].dvec2()));
    r.add("determinant", |a| a[0].dmat2().determinant());
    r.add("inverse", |a| a[0].dmat2().inverse());
    r.add("transpose_abs", |a| {
        let m = a[0].dmat2();
        (m.transpose(), m.abs())
    });
    r.add("recip", |a| a[0].dmat2().recip());
    r.add("diagonal_pair", |a| {
        let m = a[0].dmat2();
        (DMat2::from_diagonal(m.diagonal()), m.diagonal())
    });
    r.add("from_angle", |a| DMat2::from_angle(a[0].f()));
    r.add("from_scale_angle", |a| DMat2::from_scale_angle(a[0].dvec2(), a[1].f()));
    r.add("from_mat3", |a| DMat2::from_mat3(a[0].dmat3()));
    r.add("from_mat3_minor", |a| {
        DMat2::from_mat3_minor(a[0].dmat3(), a[1].u32() as usize, a[2].u32() as usize)
    });
}
