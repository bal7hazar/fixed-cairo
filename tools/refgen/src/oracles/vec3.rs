//! Oracles of `glam::vec3` (worked example, written before the Cairo module exists).
//! Spec: `specs/vec3.toml`. Every closure is the glam-rs `DVec3` method of the same name.

use crate::prelude::*;

pub fn register(r: &mut Registry) {
    r.add("new", |a| DVec3::new(a[0].f(), a[1].f(), a[2].f()));
    r.add("splat", |a| DVec3::splat(a[0].f()));
    r.add("add", |a| a[0].dvec3() + a[1].dvec3());
    r.add("sub", |a| a[0].dvec3() - a[1].dvec3());
    r.add("mul", |a| a[0].dvec3() * a[1].dvec3());
    r.add("div", |a| a[0].dvec3() / a[1].dvec3());
    r.add("neg", |a| -a[0].dvec3());
    r.add("mul_scalar", |a| a[0].dvec3() * a[1].f());
    r.add("div_scalar", |a| a[0].dvec3() / a[1].f());
    r.add("dot", |a| a[0].dvec3().dot(a[1].dvec3()));
    r.add("cross", |a| a[0].dvec3().cross(a[1].dvec3()));
    r.add("length", |a| a[0].dvec3().length());
    r.add("length_squared", |a| a[0].dvec3().length_squared());
    r.add("length_recip", |a| a[0].dvec3().length_recip());
    r.add("distance", |a| a[0].dvec3().distance(a[1].dvec3()));
    r.add("distance_squared", |a| a[0].dvec3().distance_squared(a[1].dvec3()));
    r.add("normalize", |a| a[0].dvec3().normalize());
    r.add("min", |a| a[0].dvec3().min(a[1].dvec3()));
    r.add("max", |a| a[0].dvec3().max(a[1].dvec3()));
    r.add("clamp", |a| {
        let (v, lo, hi) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        // glam precondition (`glam_assert!`): min <= max on every component.
        lo.cmple(hi).all().then(|| v.clamp(lo, hi))
    });
    r.add("abs", |a| a[0].dvec3().abs());
    r.add("signum", |a| a[0].dvec3().signum());
    r.add("min_element", |a| a[0].dvec3().min_element());
    r.add("max_element", |a| a[0].dvec3().max_element());
    r.add("lerp", |a| a[0].dvec3().lerp(a[1].dvec3(), a[2].f()));
    r.add("cmpeq", |a| a[0].dvec3().cmpeq(a[1].dvec3()));
    r.add("cmplt", |a| a[0].dvec3().cmplt(a[1].dvec3()));
    r.add("cmpge", |a| a[0].dvec3().cmpge(a[1].dvec3()));
    r.add("select", |a| DVec3::select(a[0].bvec3(), a[1].dvec3(), a[2].dvec3()));
    r.add("truncate", |a| a[0].dvec3().truncate());
    r.add("extend", |a| a[0].dvec3().extend(a[1].f()));
    // Tuple result.
    r.add("any_orthonormal_pair", |a| a[0].dvec3().any_orthonormal_pair());
}
