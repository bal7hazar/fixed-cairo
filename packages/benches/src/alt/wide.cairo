//! Alternative implementations benchmarked against `fixed::wide`: the un-fused formulations a
//! straightforward port would write (one rescale per product, one signed division per
//! component). The fused kernels of the library win every comparison; these stay here with their
//! benches (`bench_wide::alt_*`) so that the comparison stays reproducible across compiler
//! upgrades. The bounded-int alternatives of the wide rescale (`triple_two_stage`,
//! `triple_single_downcast`) live in `benches::alt::fixed` with the rest of the generated
//! plumbing.
use fixed::{Fixed, FixedTrait, ONE};

/// `a0 * b0 + a1 * b1 + a2 * b2` with one rescale per product (3 rescales, 2 checked additions).
#[inline(always)]
pub fn dot3_unfused(a0: Fixed, b0: Fixed, a1: Fixed, b1: Fixed, a2: Fixed, b2: Fixed) -> Fixed {
    a0 * b0 + a1 * b1 + a2 * b2
}

/// `a * b - c * d` with one rescale per product.
#[inline(always)]
pub fn mul_sub_unfused(a: Fixed, b: Fixed, c: Fixed, d: Fixed) -> Fixed {
    a * b - c * d
}

/// `a . (b x c)` as glam-rs writes it: the cross product is rescaled (3 fused `mul_sub`), then
/// dotted (1 more rescale). 4 rescales instead of 1, and the rounding of the cross product is
/// amplified by `a`.
#[inline(always)]
pub fn det3_cross_dot(
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
    let x = fixed::wide::mul_sub(by, cz, cy, bz);
    let y = fixed::wide::mul_sub(bz, cx, cz, bx);
    let z = fixed::wide::mul_sub(bx, cy, cx, by);
    fixed::wide::dot3(ax, x, ay, y, az, z)
}

/// `sqrt(length_squared)`: rescales the sum of squares (losing 32 bits) before the square root.
#[inline(always)]
pub fn norm3_via_squared(x: Fixed, y: Fixed, z: Fixed) -> Fixed {
    fixed::wide::norm3_squared(x, y, z).sqrt()
}

/// glam-rs formulation of `normalize`: `v * (1 / length)`, i.e. one truncated Q32.32 reciprocal
/// and three `Fixed * Fixed`. The reciprocal only carries 32 fractional bits: the result is off
/// by `length * 2^-32` relative, and `normalize((3, 0, 0))` is `1 - 1 ULP`.
#[inline(always)]
pub fn normalize3_recip_mul(x: Fixed, y: Fixed, z: Fixed) -> (Fixed, Fixed, Fixed) {
    let inv = ONE / fixed::wide::norm3(x, y, z);
    (x * inv, y * inv, z * inv)
}

/// `normalize` with one signed division per component: accurate but three sign splits and three
/// 96-bit divisions.
#[inline(always)]
pub fn normalize3_div(x: Fixed, y: Fixed, z: Fixed) -> (Fixed, Fixed, Fixed) {
    let len = fixed::wide::norm3(x, y, z);
    (x / len, y / len, z / len)
}
