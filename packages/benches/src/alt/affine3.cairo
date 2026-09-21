//! Alternative implementations benchmarked against `affine3`.

use fixed::fixed::Fixed;
use fixed::wide::{RecipTrait, det3, dot3, mul_sub};
use glam::affine3::{Affine3, Affine3RigidTrait};
use glam::mat3::{Mat3, Mat3Trait};
use glam::mat4::{Mat4, Mat4Trait};
use glam::vec3::Vec3;

/// The literal glam-rs formulation of `Affine3::inverse`: `Mat3::inverse` (a call boundary),
/// then `-(inverse * translation)` with three `dot3` and an exact negation. The translation is
/// computed from the rounded inverse.
#[inline(never)]
pub fn inverse_two_stage(m: Affine3) -> Affine3 {
    if m.matrix3.determinant() == F_ZERO {
        core::panic_with_felt252('Affine3: singular');
    }
    let matrix3 = m.matrix3.inverse();
    let translation = -matrix3.mul_vec3(m.translation);
    Affine3 { matrix3, translation }
}

/// The translation by Cramer's rule through the same shared `Recip`: with `X, Y, Z` the
/// columns and `T` the translation, `-(adj(M) T)` has the components `-det(T, Y, Z)`,
/// `-det(X, T, Z)`, `-det(X, Y, T)`, i.e. `det(Y, T, Z)`, `det(X, Z, T)`, `det(Y, X, T)` (a
/// column swap negates exactly): one `det3` (one floor) and one `Recip::mul` each. Two roundings
/// instead of the `|T|`-amplified error of the rounded inverse, but three `det3` cost more than
/// three `dot3`; the numerator `det * result` must also fit the scalar range.
#[inline(never)]
pub fn inverse_cramer(a: Affine3) -> Affine3 {
    let x = a.matrix3.x_axis;
    let y = a.matrix3.y_axis;
    let z = a.matrix3.z_axis;
    let t = a.translation;
    let det = det3(x.x, x.y, x.z, y.x, y.y, y.z, z.x, z.y, z.z);
    if det == F_ZERO {
        core::panic_with_felt252('Affine3: singular');
    }
    let r = RecipTrait::new(det);
    Affine3 {
        matrix3: Mat3 {
            x_axis: Vec3 {
                x: r.mul(mul_sub(y.y, z.z, y.z, z.y)),
                y: r.mul(mul_sub(z.y, x.z, z.z, x.y)),
                z: r.mul(mul_sub(x.y, y.z, x.z, y.y)),
            },
            y_axis: Vec3 {
                x: r.mul(mul_sub(y.z, z.x, y.x, z.z)),
                y: r.mul(mul_sub(z.z, x.x, z.x, x.z)),
                z: r.mul(mul_sub(x.z, y.x, x.x, y.z)),
            },
            z_axis: Vec3 {
                x: r.mul(mul_sub(y.x, z.y, y.y, z.x)),
                y: r.mul(mul_sub(z.x, x.y, z.y, x.x)),
                z: r.mul(mul_sub(x.x, y.y, x.y, y.x)),
            },
        },
        translation: Vec3 {
            x: r.mul(det3(y.x, y.y, y.z, t.x, t.y, t.z, z.x, z.y, z.z)),
            y: r.mul(det3(x.x, x.y, x.z, z.x, z.y, z.z, t.x, t.y, t.z)),
            z: r.mul(det3(y.x, y.y, y.z, x.x, x.y, x.z, t.x, t.y, t.z)),
        },
    }
}

/// Composition with a separately rounded matrix-vector product followed by an exact
/// translation add. The shipped implementation uses `dot3_add`, rescaling once.
#[inline(always)]
pub fn mul_unfused(lhs: Affine3, rhs: Affine3) -> Affine3 {
    Affine3 {
        matrix3: lhs.matrix3 * rhs.matrix3,
        translation: lhs.matrix3.mul_vec3(rhs.translation) + lhs.translation,
    }
}

/// The literal glam-rs `Affine3 * Mat4`: embed in a `Mat4`, then the sixteen-`dot4` product.
#[inline(always)]
pub fn mul_mat4_embed(lhs: Affine3, rhs: Mat4) -> Mat4 {
    Mat4Trait::mul_mat4(lhs.into(), rhs)
}

/// `inv_mul` as the composition of its two steps: two roundings on the translation and an
/// intermediate `-(R^T t)` that can overflow.
#[inline(always)]
pub fn inv_mul_composed(lhs: Affine3, rhs: Affine3) -> Affine3 {
    lhs.inverse_rigid() * rhs
}

/// `inv_mul` with the translation difference taken first (exact, but it can overflow), then
/// one `dot3` per component.
#[inline(always)]
pub fn inv_mul_sub_first(lhs: Affine3, rhs: Affine3) -> Affine3 {
    let r = lhs.matrix3;
    let d = rhs.translation - lhs.translation;
    Affine3 {
        matrix3: Mat3 {
            x_axis: r.mul_transpose_vec3(rhs.matrix3.x_axis),
            y_axis: r.mul_transpose_vec3(rhs.matrix3.y_axis),
            z_axis: r.mul_transpose_vec3(rhs.matrix3.z_axis),
        },
        translation: r.mul_transpose_vec3(d),
    }
}

/// `inverse_rigid` with a rounded `dot3` negated afterwards (`-floor(x)` instead of the
/// `floor(-x)` of the shipped wide negation).
#[inline(always)]
pub fn inverse_rigid_neg_after(a: Affine3) -> Affine3 {
    let x = a.matrix3.x_axis;
    let y = a.matrix3.y_axis;
    let z = a.matrix3.z_axis;
    let t = a.translation;
    Affine3 {
        matrix3: a.matrix3.transpose(),
        translation: Vec3 {
            x: -dot3(x.x, t.x, x.y, t.y, x.z, t.z),
            y: -dot3(y.x, t.x, y.y, t.y, y.z, t.z),
            z: -dot3(z.x, t.x, z.y, t.y, z.z, t.z),
        },
    }
}

const F_ZERO: Fixed = Fixed { raw: 0 };
