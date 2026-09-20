//! Oracles of `glam::vec2` (worked example, written before the Cairo module exists).
//! Spec: `specs/vec2.toml`. Every closure is the glam-rs `DVec2` method of the same name.

use crate::prelude::*;

pub fn register(r: &mut Registry) {
    r.add("new", |a| DVec2::new(a[0].f(), a[1].f()));
    r.add("splat", |a| DVec2::splat(a[0].f()));
    r.add("add", |a| a[0].dvec2() + a[1].dvec2());
    r.add("sub", |a| a[0].dvec2() - a[1].dvec2());
    r.add("mul", |a| a[0].dvec2() * a[1].dvec2());
    r.add("div", |a| a[0].dvec2() / a[1].dvec2());
    r.add("neg", |a| -a[0].dvec2());
    r.add("mul_scalar", |a| a[0].dvec2() * a[1].f());
    r.add("div_scalar", |a| a[0].dvec2() / a[1].f());
    r.add("dot", |a| a[0].dvec2().dot(a[1].dvec2()));
    r.add("perp", |a| a[0].dvec2().perp());
    r.add("perp_dot", |a| a[0].dvec2().perp_dot(a[1].dvec2()));
    r.add("length", |a| a[0].dvec2().length());
    r.add("length_squared", |a| a[0].dvec2().length_squared());
    r.add("distance", |a| a[0].dvec2().distance(a[1].dvec2()));
    r.add("normalize", |a| a[0].dvec2().normalize());
    r.add("min", |a| a[0].dvec2().min(a[1].dvec2()));
    r.add("max", |a| a[0].dvec2().max(a[1].dvec2()));
    r.add("abs", |a| a[0].dvec2().abs());
    r.add("lerp", |a| a[0].dvec2().lerp(a[1].dvec2(), a[2].f()));
    r.add("cmplt", |a| a[0].dvec2().cmplt(a[1].dvec2()));
    r.add("select", |a| DVec2::select(a[0].bvec2(), a[1].dvec2(), a[2].dvec2()));
    r.add("extend", |a| a[0].dvec2().extend(a[1].f()));
    // `self` is a unit vector (cos, sin): rotation without trigonometry.
    r.add("rotate", |a| a[0].dvec2().rotate(a[1].dvec2()));
    // Transcendental (needs `fixed::trig`): glam is built with `libm`, so sin/cos are the same
    // on every platform.
    r.add("from_angle", |a| DVec2::from_angle(a[0].f()));
}
