//! Fused kernels: accumulate raw Q64.64 products and rescale once (dot, mul_sub, norm, ...).
//!
//! A `Fixed * Fixed` product costs one step when it is left un-rescaled; the expensive part of a
//! fixed-point multiplication is the rescale (one range check plus one `div_rem`). Every kernel of
//! this module therefore sums exact raw products and rescales **once per output scalar**.
//!
//! Two layers:
//!
//! * named kernels for the common shapes: [`dot2`], [`dot3`], [`dot4`], [`mul_sub`], [`mul_add`],
//!   [`dot2_add`], [`dot3_add`], [`det3`], [`norm2`], [`norm3`], [`norm4`], [`normalize2`],
//!   [`normalize3`], [`normalize4`], ...
//! * a composable accumulator API for everything else:
//!   `wide_mul(a, b).add(wide_mul(c, d)).sub(wide_mul(e, f)).narrow()`.
//!
//! #### Accumulator types
//!
//! | type | scale | holds | built by |
//! |---|---|---|---|
//! | `W1..W16` | Q64.64 | an exact sum of up to `n` products `Fixed * Fixed` | [`wide_mul`],
//! [`wide_from`], `add`, `sub`, `neg` |
//! | `T1..T16` | Q96.96 | an exact sum of up to `n` triple products `Fixed * Fixed * Fixed` |
//! `Wn.mul(Fixed)`, `Wn.lift()`, `add`, `sub`, `neg` |
//! | [`Recip`] | Q32.96 | a reciprocal `1 / d` with 96 fractional bits | [`RecipTrait::new`] |
//!
//! The index is a static bound, not a count the caller must respect at run time:
//! `Wn + Wm -> W(n+m)` and `Wn * Fixed -> Tn` are resolved by the type system (traits
//! [`WideAdd`], [`WideSub`], [`WideNeg`], [`WideMul`], [`WideLift`]), cost one step each and can
//! never overflow. A sum that would need more than 16 terms does not compile: narrow a partial
//! sum to `Fixed` and feed it back with [`wide_from`]. Quadruple products do not fit a felt252:
//! narrow the inner factor first.
//!
//! [`WideNarrow::narrow`] is the single rescale: `floor` (toward negative infinity) like
//! `Fixed * Fixed`, panicking with `'Fixed: overflow'` when the result does not fit. The
//! accumulators are opaque (`core::internal::bounded_int` values inside, never exposed).
#[feature("bounded-int-utils")]
use core::internal::bounded_int::upcast;
use crate::fixed::Fixed;
pub use crate::internal::acc::{
    T1, T10, T11, T12, T13, T14, T15, T16, T2, T3, T4, T5, T6, T7, T8, T9, W1, W10, W11, W12, W13,
    W14, W15, W16, W2, W3, W4, W5, W6, W7, W8, W9, WideAdd, WideLift, WideMul, WideNarrow, WideNeg,
    WideSqrt, WideSub,
};
use crate::internal::bounded::{self, BR};

/// Returns the exact raw Q64.64 product `a * b` (one step, no range check).
///
/// Mirrors nothing in glam-rs: this is the entry point of the accumulator API.
/// #### Panics
/// * Never.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn wide_mul(a: Fixed, b: Fixed) -> W1 {
    W1 { v: bounded::wide(a.raw, b.raw) }
}

/// Returns `x` at the Q64.64 scale (exact), to add a plain `Fixed` term to a sum of products.
///
/// #### Panics
/// * Never.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn wide_from(x: Fixed) -> W1 {
    W1 { v: bounded::lift(x.raw) }
}

/// Computes `a0 * b0 + a1 * b1` with a single rescale.
///
/// Mirrors `glam::Vec2::dot`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn dot2(a0: Fixed, b0: Fixed, a1: Fixed, b1: Fixed) -> Fixed {
    wide_mul(a0, b0).add(wide_mul(a1, b1)).narrow()
}

/// Computes `a0 * b0 + a1 * b1 + a2 * b2` with a single rescale.
///
/// Mirrors `glam::Vec3::dot`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn dot3(a0: Fixed, b0: Fixed, a1: Fixed, b1: Fixed, a2: Fixed, b2: Fixed) -> Fixed {
    wide_mul(a0, b0).add(wide_mul(a1, b1)).add(wide_mul(a2, b2)).narrow()
}

/// Computes `a0 * b0 + a1 * b1 + a2 * b2 + a3 * b3` with a single rescale.
///
/// Mirrors `glam::Vec4::dot`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn dot4(
    a0: Fixed, b0: Fixed, a1: Fixed, b1: Fixed, a2: Fixed, b2: Fixed, a3: Fixed, b3: Fixed,
) -> Fixed {
    wide_mul(a0, b0).add(wide_mul(a1, b1)).add(wide_mul(a2, b2)).add(wide_mul(a3, b3)).narrow()
}

/// Computes `a0 * b0 + a1 * b1 + c` with a single rescale (2D affine transform of a point).
///
/// Mirrors the per-component shape of `glam::Affine2::transform_point2`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn dot2_add(a0: Fixed, b0: Fixed, a1: Fixed, b1: Fixed, c: Fixed) -> Fixed {
    wide_mul(a0, b0).add(wide_mul(a1, b1)).add(wide_from(c)).narrow()
}

/// Computes `a0 * b0 + a1 * b1 + a2 * b2 + c` with a single rescale (3D affine transform of a
/// point).
///
/// Mirrors the per-component shape of `glam::Affine3A::transform_point3`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn dot3_add(
    a0: Fixed, b0: Fixed, a1: Fixed, b1: Fixed, a2: Fixed, b2: Fixed, c: Fixed,
) -> Fixed {
    wide_mul(a0, b0).add(wide_mul(a1, b1)).add(wide_mul(a2, b2)).add(wide_from(c)).narrow()
}

/// Computes `a * b + c` with a single rescale.
///
/// Mirrors `f32::mul_add` (`glam::f32::math::mul_add`).
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn mul_add(a: Fixed, b: Fixed, c: Fixed) -> Fixed {
    Fixed { raw: bounded::mul_add(a.raw, b.raw, c.raw) }
}

/// Computes `a * b - c * d` with a single rescale: the building block of cross products and 2x2
/// determinants.
///
/// Mirrors the per-component shape of `glam::Vec3::cross`, `glam::Vec2::perp_dot` and
/// `glam::Mat2::determinant`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn mul_sub(a: Fixed, b: Fixed, c: Fixed, d: Fixed) -> Fixed {
    wide_mul(a, b).sub(wide_mul(c, d)).narrow()
}

/// Computes the scalar triple product `a . (b x c)`, i.e. the determinant of the 3x3 matrix whose
/// columns are `a`, `b`, `c`, from the six exact Q96.96 triple products and a single rescale.
///
/// Mirrors `glam::Mat3::determinant` (`x_axis.dot(y_axis.cross(z_axis))`).
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * The cross product is not rounded before the dot product: the result is the floor of the
///   exact determinant.
#[inline(always)]
pub fn det3(
    ax: Fixed,
    ay: Fixed,
    az: Fixed,
    bx: Fixed,
    by: Fixed,
    bz: Fixed,
    cx: Fixed,
    cy: Fixed,
    cz: Fixed,
) -> Fixed {
    let x = wide_mul(by, cz).sub(wide_mul(cy, bz)).mul(ax);
    let y = wide_mul(bz, cx).sub(wide_mul(cz, bx)).mul(ay);
    let z = wide_mul(bx, cy).sub(wide_mul(cx, by)).mul(az);
    x.add(y).add(z).narrow()
}

/// Computes `x * x + y * y` with a single rescale.
///
/// Mirrors `glam::Vec2::length_squared`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn norm2_squared(x: Fixed, y: Fixed) -> Fixed {
    wide_mul(x, x).add(wide_mul(y, y)).narrow()
}

/// Computes `x * x + y * y + z * z` with a single rescale.
///
/// Mirrors `glam::Vec3::length_squared`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn norm3_squared(x: Fixed, y: Fixed, z: Fixed) -> Fixed {
    wide_mul(x, x).add(wide_mul(y, y)).add(wide_mul(z, z)).narrow()
}

/// Computes `x * x + y * y + z * z + w * w` with a single rescale.
///
/// Mirrors `glam::Vec4::length_squared`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn norm4_squared(x: Fixed, y: Fixed, z: Fixed, w: Fixed) -> Fixed {
    wide_mul(x, x).add(wide_mul(y, y)).add(wide_mul(z, z)).add(wide_mul(w, w)).narrow()
}

/// Computes the length `sqrt(x^2 + y^2)` as the integer square root of the raw Q64.64 sum of
/// squares: no rescale, no intermediate rounding, no `length_squared` underflow for tiny vectors.
///
/// Mirrors `glam::Vec2::length`.
/// #### Panics
/// * `'Fixed: overflow'` if the length does not fit the scalar range.
/// #### Deviations
/// * The result is the floor of the exact length (at most 1 ULP below it).
#[inline(always)]
pub fn norm2(x: Fixed, y: Fixed) -> Fixed {
    Fixed { raw: bounded::norm_le3(upcast(wide_mul(x, x).add(wide_mul(y, y)).v)) }
}

/// Computes the length `sqrt(x^2 + y^2 + z^2)` as the integer square root of the raw Q64.64 sum
/// of squares: no rescale, no intermediate rounding.
///
/// Mirrors `glam::Vec3::length`.
/// #### Panics
/// * `'Fixed: overflow'` if the length does not fit the scalar range.
/// #### Deviations
/// * The result is the floor of the exact length (at most 1 ULP below it).
#[inline(always)]
pub fn norm3(x: Fixed, y: Fixed, z: Fixed) -> Fixed {
    Fixed {
        raw: bounded::norm_le3(upcast(wide_mul(x, x).add(wide_mul(y, y)).add(wide_mul(z, z)).v)),
    }
}

/// Computes the length `sqrt(x^2 + y^2 + z^2 + w^2)` as the integer square root of the raw
/// Q64.64 sum of squares: no rescale, no intermediate rounding.
///
/// Mirrors `glam::Vec4::length`.
/// #### Panics
/// * `'Fixed: overflow'` if the length does not fit the scalar range (this includes the single
///   input whose sum of squares reaches 2^128: four components equal to `MIN`).
/// #### Deviations
/// * The result is the floor of the exact length (at most 1 ULP below it).
#[inline(always)]
pub fn norm4(x: Fixed, y: Fixed, z: Fixed, w: Fixed) -> Fixed {
    Fixed { raw: bounded::norm(upcast(sum_squares4(x, y, z, w).v)) }
}

#[inline(always)]
fn sum_squares3(x: Fixed, y: Fixed, z: Fixed) -> W3 {
    wide_mul(x, x).add(wide_mul(y, y)).add(wide_mul(z, z))
}

#[inline(always)]
fn sum_squares4(x: Fixed, y: Fixed, z: Fixed, w: Fixed) -> W4 {
    wide_mul(x, x).add(wide_mul(y, y)).add(wide_mul(z, z)).add(wide_mul(w, w))
}

/// Computes the distance `sqrt((ax - bx)^2 + (ay - by)^2)`. The differences are exact (65 bits):
/// unlike `(a - b).length()` it cannot overflow on the subtraction, and it saves the two range
/// checks of every native `-`.
///
/// Mirrors `glam::Vec2::distance`.
/// #### Panics
/// * `'Fixed: overflow'` if the distance does not fit the scalar range.
/// #### Deviations
/// * The result is the floor of the exact distance (at most 1 ULP below it).
#[inline(always)]
pub fn distance2(ax: Fixed, ay: Fixed, bx: Fixed, by: Fixed) -> Fixed {
    Fixed { raw: bounded::norm(bounded::dist_sq2(ax.raw, bx.raw, ay.raw, by.raw)) }
}

/// Computes the distance between the points `a` and `b` (see [`distance2`]).
///
/// Mirrors `glam::Vec3::distance`.
/// #### Panics
/// * `'Fixed: overflow'` if the distance does not fit the scalar range.
/// #### Deviations
/// * The result is the floor of the exact distance (at most 1 ULP below it).
#[inline(always)]
pub fn distance3(ax: Fixed, ay: Fixed, az: Fixed, bx: Fixed, by: Fixed, bz: Fixed) -> Fixed {
    Fixed { raw: bounded::norm(bounded::dist_sq3(ax.raw, bx.raw, ay.raw, by.raw, az.raw, bz.raw)) }
}

/// Computes the distance between the points `a` and `b` (see [`distance2`]).
///
/// Mirrors `glam::Vec4::distance`.
/// #### Panics
/// * `'Fixed: overflow'` if the distance does not fit the scalar range.
/// #### Deviations
/// * The result is the floor of the exact distance (at most 1 ULP below it).
#[inline(always)]
pub fn distance4(
    ax: Fixed, ay: Fixed, az: Fixed, aw: Fixed, bx: Fixed, by: Fixed, bz: Fixed, bw: Fixed,
) -> Fixed {
    Fixed {
        raw: bounded::norm(
            bounded::dist_sq4(ax.raw, bx.raw, ay.raw, by.raw, az.raw, bz.raw, aw.raw, bw.raw),
        ),
    }
}

/// Computes the squared distance `(ax - bx)^2 + (ay - by)^2` with exact differences and a single
/// rescale.
///
/// Mirrors `glam::Vec2::distance_squared`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn distance2_squared(ax: Fixed, ay: Fixed, bx: Fixed, by: Fixed) -> Fixed {
    Fixed { raw: bounded::narrow32(bounded::dist_sq2(ax.raw, bx.raw, ay.raw, by.raw)) }
}

/// Computes the squared distance between the points `a` and `b` (see [`distance2_squared`]).
///
/// Mirrors `glam::Vec3::distance_squared`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn distance3_squared(
    ax: Fixed, ay: Fixed, az: Fixed, bx: Fixed, by: Fixed, bz: Fixed,
) -> Fixed {
    Fixed {
        raw: bounded::narrow32(bounded::dist_sq3(ax.raw, bx.raw, ay.raw, by.raw, az.raw, bz.raw)),
    }
}

/// Computes the squared distance between the points `a` and `b` (see [`distance2_squared`]).
///
/// Mirrors `glam::Vec4::distance_squared`.
/// #### Panics
/// * `'Fixed: overflow'` if the result does not fit the scalar range.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn distance4_squared(
    ax: Fixed, ay: Fixed, az: Fixed, aw: Fixed, bx: Fixed, by: Fixed, bz: Fixed, bw: Fixed,
) -> Fixed {
    Fixed {
        raw: bounded::narrow32(
            bounded::dist_sq4(ax.raw, bx.raw, ay.raw, by.raw, az.raw, bz.raw, aw.raw, bw.raw),
        ),
    }
}

/// A reciprocal `1 / d` kept with 96 fractional bits, to divide several values by the same
/// divisor with one division and one fused multiplication each (`normalize`, matrix inverse:
/// "divide the adjugate once by the determinant").
///
/// `RecipTrait::new(d).mul(x)` is `x / d` **rounded to nearest** (ties toward +infinity): it is
/// within `1/2 + |x| / 2^64 < 1` ULP of the exact quotient and exact whenever the quotient is
/// representable (in particular `normalize` of an axis-aligned vector returns exactly `+-1`),
/// which a truncated Q32.32 reciprocal followed by `Fixed * Fixed` is not.
#[derive(Copy, Drop)]
pub struct Recip {
    pub(crate) v: BR,
}

pub trait RecipTrait {
    /// Computes the wide reciprocal of `d` (one sign split, one division).
    ///
    /// Mirrors `f32::recip`, kept wide.
    /// #### Panics
    /// * `'Fixed: division by zero'` if `d` is zero.
    /// #### Deviations
    /// * Not a `Fixed`: consume it with `mul`.
    fn new(d: Fixed) -> Recip;
    /// Computes `x / d`, rounded to nearest, where `self` is the reciprocal of `d`.
    ///
    /// #### Panics
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    /// #### Deviations
    /// * Rounds to nearest (ties toward +infinity) while `Fixed / Fixed` truncates: the two may
    ///   differ by 1 ULP.
    fn mul(self: Recip, x: Fixed) -> Fixed;
}

pub impl RecipImpl of RecipTrait {
    #[inline(always)]
    fn new(d: Fixed) -> Recip {
        Recip { v: bounded::recip_wide(d.raw) }
    }
    #[inline(always)]
    fn mul(self: Recip, x: Fixed) -> Fixed {
        Fixed { raw: bounded::recip_mul(self.v, x.raw) }
    }
}

/// A vector length kept as an unsigned 64-bit raw value: twice the range of `Fixed`, no range
/// check. It lets `normalize`, `try_normalize`, `normalize_or_zero` and `normalize_and_length`
/// share one square root: test it with `is_zero`, turn it into a [`Recip`] or into a `Fixed`.
#[derive(Copy, Drop)]
pub struct Norm {
    pub(crate) raw: u64,
}

pub trait NormTrait {
    /// Returns `true` if the length is zero (raw sum of squares below 1).
    ///
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn is_zero(self: Norm) -> bool;
    /// Converts the length to a `Fixed`.
    ///
    /// Mirrors `glam::Vec3::length`.
    /// #### Panics
    /// * `'Fixed: overflow'` if the length does not fit the scalar range.
    /// #### Deviations
    /// * None.
    fn to_fixed(self: Norm) -> Fixed;
    /// Computes the wide reciprocal of the length (one division, no sign split).
    ///
    /// Mirrors `glam::Vec3::length_recip`, kept wide.
    /// #### Panics
    /// * `'Fixed: division by zero'` if the length is zero.
    /// #### Deviations
    /// * Not a `Fixed`: consume it with `RecipTrait::mul`.
    fn recip(self: Norm) -> Recip;
    /// Computes the wide reciprocal of the length, or `None` if the length is zero.
    ///
    /// Mirrors the zero test of `glam::Vec3::try_normalize`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn try_recip(self: Norm) -> Option<Recip>;
}

pub impl NormImpl of NormTrait {
    #[inline(always)]
    fn is_zero(self: Norm) -> bool {
        self.raw == 0
    }
    #[inline(always)]
    fn to_fixed(self: Norm) -> Fixed {
        Fixed { raw: bounded::norm_to_i64(self.raw) }
    }
    #[inline(always)]
    fn recip(self: Norm) -> Recip {
        Recip { v: bounded::recip_wide_u64(self.raw) }
    }
    #[inline(always)]
    fn try_recip(self: Norm) -> Option<Recip> {
        match self.raw.try_into() {
            Some(nz) => Some(Recip { v: bounded::recip_wide_nz(nz) }),
            None => None,
        }
    }
}

/// Computes the length of `(x, y)` as a [`Norm`] (see [`norm2`] for the `Fixed` form).
///
/// Mirrors `glam::Vec2::length`.
/// #### Panics
/// * Never.
/// #### Deviations
/// * The result is the floor of the exact length (at most 1 ULP below it).
#[inline(always)]
pub fn norm2_wide(x: Fixed, y: Fixed) -> Norm {
    Norm { raw: bounded::norm_u64_le3(upcast(wide_mul(x, x).add(wide_mul(y, y)).v)) }
}

/// Computes the length of `(x, y, z)` as a [`Norm`] (see [`norm3`] for the `Fixed` form).
///
/// Mirrors `glam::Vec3::length`.
/// #### Panics
/// * Never.
/// #### Deviations
/// * The result is the floor of the exact length (at most 1 ULP below it).
#[inline(always)]
pub fn norm3_wide(x: Fixed, y: Fixed, z: Fixed) -> Norm {
    Norm { raw: bounded::norm_u64_le3(upcast(sum_squares3(x, y, z).v)) }
}

/// Computes the length of `(x, y, z, w)` as a [`Norm`] (see [`norm4`] for the `Fixed` form).
///
/// Mirrors `glam::Vec4::length`.
/// #### Panics
/// * `'Fixed: overflow'` for the single input whose sum of squares reaches 2^128 (four
///   components equal to `MIN`).
/// #### Deviations
/// * The result is the floor of the exact length (at most 1 ULP below it).
#[inline(always)]
pub fn norm4_wide(x: Fixed, y: Fixed, z: Fixed, w: Fixed) -> Norm {
    Norm { raw: bounded::norm_u64(upcast(sum_squares4(x, y, z, w).v)) }
}

/// Normalizes `(x, y)`: one integer square root, one division, one fused multiplication per
/// component. Works for the whole scalar range (the length itself may exceed it).
///
/// Mirrors `glam::Vec2::normalize`.
/// #### Panics
/// * `'Fixed: division by zero'` if the length is zero (raw sum of squares below 1).
/// #### Deviations
/// * The length is floored to 1 ULP, so each component carries a relative error of at most
///   `1 ULP / length` plus 1 ULP of rounding (exact for axis-aligned vectors); a zero vector
///   panics instead of returning NaN.
#[inline(always)]
pub fn normalize2(x: Fixed, y: Fixed) -> (Fixed, Fixed) {
    let r = norm2_wide(x, y).recip();
    (r.mul(x), r.mul(y))
}

/// Normalizes `(x, y, z)`: one integer square root, one division, one fused multiplication per
/// component. Works for the whole scalar range (the length itself may exceed it).
///
/// Mirrors `glam::Vec3::normalize`.
/// #### Panics
/// * `'Fixed: division by zero'` if the length is zero (raw sum of squares below 1).
/// #### Deviations
/// * The length is floored to 1 ULP, so each component carries a relative error of at most
///   `1 ULP / length` plus 1 ULP of rounding (exact for axis-aligned vectors); a zero vector
///   panics instead of returning NaN.
#[inline(always)]
pub fn normalize3(x: Fixed, y: Fixed, z: Fixed) -> (Fixed, Fixed, Fixed) {
    let r = norm3_wide(x, y, z).recip();
    (r.mul(x), r.mul(y), r.mul(z))
}

/// Normalizes `(x, y, z, w)`: one integer square root, one division, one fused multiplication
/// per component.
///
/// Mirrors `glam::Vec4::normalize` and `glam::Quat::normalize`.
/// #### Panics
/// * `'Fixed: division by zero'` if the length is zero (raw sum of squares below 1).
/// * `'Fixed: overflow'` if the four components are all `MIN` (sum of squares of 2^128).
/// #### Deviations
/// * The length is floored to 1 ULP, so each component carries a relative error of at most
///   `1 ULP / length` plus 1 ULP of rounding (exact for axis-aligned vectors); a zero vector
///   panics instead of returning NaN.
#[inline(always)]
pub fn normalize4(x: Fixed, y: Fixed, z: Fixed, w: Fixed) -> (Fixed, Fixed, Fixed, Fixed) {
    let r = norm4_wide(x, y, z, w).recip();
    (r.mul(x), r.mul(y), r.mul(z), r.mul(w))
}
