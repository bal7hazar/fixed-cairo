//! Alternative implementations benchmarked against `fixed::wide`: the un-fused formulations a
//! straightforward port would write (one rescale per product, one signed division per
//! component). The fused kernels of the library win every comparison; these stay here with their
//! benches (`bench_wide::alt_*`) so that the comparison stays reproducible across compiler
//! upgrades. The bounded-int alternatives of the wide rescale (`triple_two_stage`,
//! `triple_single_downcast`) live in `benches::alt::fixed` with the rest of the generated
//! plumbing.
use fixed::{Fixed, FixedTrait, ONE};

const TWO_POW_64: NonZero<u128> = 0x10000000000000000;
const W16_BOUND: u256 = 0x400000000000000000000000000000000;
const PRIME_MINUS_W16_BOUND: u256 =
    0x800000000000010fffffffffffffffc00000000000000000000000000000001;

#[derive(Copy, Drop)]
struct AbsorbingW16 {
    value: felt252,
}

#[inline(always)]
fn w16_add_prod(acc: AbsorbingW16, a: Fixed, b: Fixed) -> AbsorbingW16 {
    let value = acc.value + a.raw.into() * b.raw.into();
    let canonical: u256 = value.into();
    assert(canonical <= W16_BOUND || canonical >= PRIME_MINUS_W16_BOUND, 'alt W16: overflow');
    AbsorbingW16 { value }
}

#[inline(always)]
fn w16_narrow(acc: AbsorbingW16) -> Fixed {
    let u: u128 = ((acc.value + 0x800000000000000000000000) * 0x100000000)
        .try_into()
        .expect('Fixed: overflow');
    let (q, _r) = DivRem::div_rem(u, TWO_POW_64);
    Fixed { raw: (Into::<u128, felt252>::into(q) - 0x8000000000000000).try_into().unwrap() }
}

/// Three products accumulated in an absorbing `W16`, with a dynamic `W16` range check per term.
#[inline(always)]
pub fn w16_dot3(a: Fixed, b: Fixed, c: Fixed, d: Fixed) -> Fixed {
    let acc = w16_add_prod(AbsorbingW16 { value: 0 }, a, b);
    let acc = w16_add_prod(acc, c, d);
    w16_narrow(w16_add_prod(acc, a, c))
}

/// Six products accumulated in an absorbing `W16`, with a dynamic `W16` range check per term.
#[inline(always)]
pub fn w16_dot6(a: Fixed, b: Fixed, c: Fixed, d: Fixed) -> Fixed {
    let acc = w16_add_prod(AbsorbingW16 { value: 0 }, a, b);
    let acc = w16_add_prod(acc, c, d);
    let acc = w16_add_prod(acc, a, c);
    let acc = w16_add_prod(acc, b, d);
    let acc = w16_add_prod(acc, a, d);
    w16_narrow(w16_add_prod(acc, b, c))
}

/// Sixteen products accumulated in an absorbing `W16`, with a dynamic range check per term.
#[inline(always)]
pub fn w16_dot16(a: Fixed, b: Fixed, c: Fixed, d: Fixed) -> Fixed {
    let acc = w16_add_prod(AbsorbingW16 { value: 0 }, a, b);
    let acc = w16_add_prod(acc, c, d);
    let acc = w16_add_prod(acc, a, c);
    let acc = w16_add_prod(acc, b, d);
    let acc = w16_add_prod(acc, a, d);
    let acc = w16_add_prod(acc, b, c);
    let acc = w16_add_prod(acc, a, b);
    let acc = w16_add_prod(acc, c, d);
    let acc = w16_add_prod(acc, a, c);
    let acc = w16_add_prod(acc, b, d);
    let acc = w16_add_prod(acc, a, d);
    let acc = w16_add_prod(acc, b, c);
    let acc = w16_add_prod(acc, a, b);
    let acc = w16_add_prod(acc, c, d);
    let acc = w16_add_prod(acc, a, c);
    w16_narrow(w16_add_prod(acc, b, d))
}

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

/// The old `is_normalized` formulation: narrow the sum of squares before comparing it with one.
/// It panics instead of returning `false` when the squared length does not fit `Fixed`.
#[inline(always)]
pub fn is_unit3_narrowed(x: Fixed, y: Fixed, z: Fixed, max_abs_diff_raw: i64) -> bool {
    fixed::wide::norm3_squared(x, y, z).abs_diff_eq(ONE, Fixed { raw: max_abs_diff_raw })
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
