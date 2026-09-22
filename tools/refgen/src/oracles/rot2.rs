//! Oracles of `glamx::rot2`. The spec represents `DRot2 { re, im }` with refgen's two-leaf
//! `Vec2` layout slot, overridden to the Cairo `Rot2` path and field names.

use crate::prelude::*;
use glam::{DMat2, DVec2};
use glamx::DRot2;

fn rot(v: &Value) -> DRot2 {
    let v = v.dvec2();
    DRot2::from_cos_sin_unchecked(v.x, v.y)
}

fn out(r: DRot2) -> DVec2 {
    DVec2::new(r.re, r.im)
}

fn pair(v: &Value) -> (f64, f64) {
    let e = v.elems();
    (e[0].f(), e[1].f())
}

pub fn register(r: &mut Registry) {
    r.add("from_cos_sin_unchecked", |a| {
        out(DRot2::from_cos_sin_unchecked(a[0].f(), a[1].f()))
    });
    r.add("angle_constructors", |a| {
        (out(DRot2::new(a[0].f())), out(DRot2::from_angle(a[0].f())))
    });
    r.add("angle", |a| rot(&a[0]).angle());
    r.add("accessors_inverse", |a| {
        let p = rot(&a[0]);
        (p.cos(), p.sin(), out(p.inverse()))
    });
    r.add("mul", |a| out(rot(&a[0]) * rot(&a[1])));
    r.add("transform_vector", |a| {
        let (x, y) = pair(&a[1]);
        let v = rot(&a[0]).transform_vector(DVec2::new(x, y));
        (v.x, v.y)
    });
    r.add("inverse_transform_vector", |a| {
        let (x, y) = pair(&a[1]);
        let v = rot(&a[0]).inverse_transform_vector(DVec2::new(x, y));
        (v.x, v.y)
    });
    r.add("mul_vec2_alias", |a| {
        let p = rot(&a[0]);
        let (x, y) = pair(&a[1]);
        let v = DVec2::new(x, y);
        let x = p.transform_vector(v);
        let y = p * v;
        (x.x, x.y, y.x, y.y)
    });
    r.add("to_mat", |a| {
        let m = rot(&a[0]).to_mat();
        (m.x_axis.x, m.x_axis.y, m.y_axis.x, m.y_axis.y)
    });
    r.add("from_mat_pair", |a| {
        let p = rot(&a[0]);
        let m = DMat2::from_cols(DVec2::new(p.re, p.im), DVec2::new(-p.im, p.re));
        (out(DRot2::from_mat(m)), out(DRot2::from_mat_unchecked(m)))
    });
    r.add("normalize_pair", |a| {
        let p = rot(&a[0]);
        let mut q = p;
        q.normalize_mut();
        (out(p.normalize()), out(q))
    });
    r.add("length_pair", |a| {
        let p = rot(&a[0]);
        (p.length(), p.length_squared())
    });
    r.add("dot", |a| rot(&a[0]).dot(rot(&a[1])));
    r.add("is_normalized", |a| rot(&a[0]).is_normalized());
    r.add("lerp", |a| out(rot(&a[0]).lerp(rot(&a[1]), a[2].f())));
    r.add("slerp", |a| out(rot(&a[0]).slerp(&rot(&a[1]), a[2].f())));
    r.add("angle_between", |a| rot(&a[0]).angle_between(&rot(&a[1])));
    r.add("rotate_towards", |a| -> Out {
        let (p, q, max_angle) = (rot(&a[0]), rot(&a[1]), a[2].f());
        let angle = p.angle_between(&q);
        if (angle.abs() - max_angle.abs()).abs() < 1.0e-3 {
            return skip("rotate_towards: on the target branch boundary");
        }
        out(p.rotate_towards(&q, max_angle)).into()
    });
    r.add("from_rotation_arc", |a| {
        let (fx, fy) = pair(&a[0]);
        let (tx, ty) = pair(&a[1]);
        out(DRot2::from_rotation_arc(
            DVec2::new(fx, fy),
            DVec2::new(tx, ty),
        ))
    });
}
