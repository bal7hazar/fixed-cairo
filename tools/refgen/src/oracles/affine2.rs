//! Oracles of `glam::affine2`. Spec: `specs/affine2.toml`.

use crate::prelude::*;

pub fn register(r: &mut Registry) {
    r.add("transform_point2", |a| a[0].daffine2().transform_point2(a[1].dvec2()));
    r.add("transform_vector2", |a| a[0].daffine2().transform_vector2(a[1].dvec2()));
    r.add("mul", |a| a[0].daffine2() * a[1].daffine2());
    r.add("inverse", |a| a[0].daffine2().inverse());
    r.add("from_scale_angle_translation", |a| {
        DAffine2::from_scale_angle_translation(a[0].dvec2(), a[1].f(), a[2].dvec2())
    });
    r.add("from_angle_translation", |a| {
        DAffine2::from_angle_translation(a[0].f(), a[1].dvec2())
    });
    r.add("to_scale_angle_translation", |a| {
        a[0].daffine2().to_scale_angle_translation()
    });
    r.add("mul_mat3", |a| a[0].daffine2() * a[1].dmat3());
}
