//! Oracles of `glam::vec3`. Spec: `specs/vec3.toml`. Every closure is the glam-rs `DVec3` method
//! of the same name.
//!
//! Functions of the same arguments are checked together as a tuple (`min_max`, `div_rem`,
//! `rounding`, ...): the generated file is capped at 1 500 lines and every entry costs a test
//! body. The `skip` guards drop the cases where the two implementations legitimately take
//! different branches (a `glam_assert!` precondition, or a comparison against a length that
//! Cairo floors).

use crate::prelude::*;

pub fn register(r: &mut Registry) {
    r.add("add_sub", |a| {
        let (v, w) = (a[0].dvec3(), a[1].dvec3());
        (v + w, v - w)
    });
    r.add("mul", |a| a[0].dvec3() * a[1].dvec3());
    r.add("div_rem", |a| {
        let (v, w) = (a[0].dvec3(), a[1].dvec3());
        (v / w, v % w)
    });
    r.add("mul_scalar", |a| a[0].dvec3() * a[1].f());
    r.add("div_scalar", |a| a[0].dvec3() / a[1].f());
    r.add("dot", |a| a[0].dvec3().dot(a[1].dvec3()));
    r.add("cross", |a| a[0].dvec3().cross(a[1].dvec3()));
    r.add("sum_product", |a| {
        let v = a[0].dvec3();
        (v.element_sum(), v.element_product())
    });
    r.add("min_max", |a| {
        let (v, w) = (a[0].dvec3(), a[1].dvec3());
        (v.min(w), v.max(w))
    });
    r.add("clamp", |a| {
        let (v, lo, hi) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        // glam precondition (`glam_assert!`): min <= max on every component.
        lo.cmple(hi).all().then(|| v.clamp(lo, hi))
    });
    r.add("elements", |a| {
        let v = a[0].dvec3();
        (v.min_element(), v.max_element())
    });
    r.add("cmp", |a| {
        let (v, w) = (a[0].dvec3(), a[1].dvec3());
        (v.cmpeq(w), v.cmplt(w), v.cmpge(w))
    });
    r.add("sign", |a| {
        let v = a[0].dvec3();
        (v.abs(), v.signum())
    });
    r.add("is_negative_bitmask", |a| a[0].dvec3().is_negative_bitmask());
    r.add("round_floor", |a| {
        let v = a[0].dvec3();
        (v.round(), v.floor())
    });
    r.add("ceil_trunc", |a| {
        let v = a[0].dvec3();
        (v.ceil(), v.trunc())
    });
    r.add("fract_pair", |a| {
        let v = a[0].dvec3();
        (v.fract(), v.fract_gl())
    });
    r.add("recip", |a| a[0].dvec3().recip());
    r.add("euclid", |a| {
        let (v, w) = (a[0].dvec3(), a[1].dvec3());
        (v.div_euclid(w), v.rem_euclid(w))
    });
    r.add("length_pair", |a| {
        let v = a[0].dvec3();
        (v.length(), v.length_squared())
    });
    r.add("length_recip", |a| a[0].dvec3().length_recip());
    r.add("distance_pair", |a| {
        let (v, w) = (a[0].dvec3(), a[1].dvec3());
        (v.distance(w), v.distance_squared(w))
    });
    r.add("normalize", |a| a[0].dvec3().normalize());
    r.add("normalize_and_length", |a| a[0].dvec3().normalize_and_length());
    r.add("lerp", |a| a[0].dvec3().lerp(a[1].dvec3(), a[2].f()));
    r.add("midpoint", |a| a[0].dvec3().midpoint(a[1].dvec3()));
    r.add("mul_add", |a| a[0].dvec3().mul_add(a[1].dvec3(), a[2].dvec3()));
    r.add("project_reject", |a| {
        let (v, w) = (a[0].dvec3(), a[1].dvec3());
        (v.project_onto(w), v.reject_from(w))
    });
    r.add("project_onto_normalized", |a| {
        a[0].dvec3().project_onto_normalized(a[1].dvec3())
    });
    r.add("reject_from_normalized", |a| {
        a[0].dvec3().reject_from_normalized(a[1].dvec3())
    });
    r.add("reflect", |a| a[0].dvec3().reflect(a[1].dvec3()));
    r.add("refract", |a| a[0].dvec3().refract(a[1].dvec3(), a[2].f()));
    // `move_towards` and `clamp_length` branch on a comparison with a length; Cairo compares the
    // floored length, so a case sitting on the boundary may legitimately take the other branch.
    r.add("move_towards", |a| -> Out {
        let (v, w, d) = (a[0].dvec3(), a[1].dvec3(), a[2].f());
        let len = (w - v).length();
        if len < 1e-3 || (len - d).abs() < 1e-3 {
            return skip("move_towards: on the `len <= d` branch boundary");
        }
        v.move_towards(w, d).into()
    });
    r.add("clamp_length", |a| -> Out {
        let (v, min, max) = (a[0].dvec3(), a[1].f(), a[2].f());
        let len = v.length();
        if min > max {
            return skip("clamp_length: min > max is a glam_assert! precondition");
        }
        if (len - min).abs() < 1e-3 || (len - max).abs() < 1e-3 {
            return skip("clamp_length: on a branch boundary");
        }
        v.clamp_length(min, max).into()
    });
    r.add("as_ivec3", |a| a[0].dvec3().as_ivec3());
    r.add("as_uvec3", |a| a[0].dvec3().as_uvec3());
    // Tuple results.
    r.add("any_orthonormal_vector", |a| a[0].dvec3().any_orthonormal_vector());
    r.add("any_orthonormal_pair", |a| a[0].dvec3().any_orthonormal_pair());
    // Angles. glam-rs computes `angle_between` as `acos(cos)`, ill-conditioned near 0 and pi
    // (one f64 ULP of the cosine is 1.5e-8 rad there, 64 Q32.32 ULP): those cases are skipped and
    // pinned by exact tests in `tests/test_vec3.cairo` instead. `angle_to` is an `atan2`, but its
    // error budget assumes the `atan2` arguments are not tiny (`skip` below).
    r.add("angle_between", |a| -> Out {
        let angle = a[0].dvec3().angle_between(a[1].dvec3());
        if angle < 1e-3 || angle > std::f64::consts::PI - 1e-3 {
            return skip("angle_between: acos is ill-conditioned near 0 and pi");
        }
        angle.into()
    });
    r.add("angle_to", |a| -> Out {
        let (v, w, axis) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        if v.cross(w).dot(axis).hypot(v.dot(w)) < 1.0 {
            return skip("angle_to: the atan2 arguments are too small for the error budget");
        }
        v.angle_to(w, axis).into()
    });
    r.add("rotate_xyz", |a| {
        let (v, angle) = (a[0].dvec3(), a[1].f());
        (v.rotate_x(angle), v.rotate_y(angle), v.rotate_z(angle))
    });
}
