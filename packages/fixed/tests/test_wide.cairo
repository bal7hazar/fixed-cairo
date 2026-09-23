//! Tests of `fixed::wide`.
//!
//! Four layers: the accumulator API and the named kernels on exact small values, the edge cases
//! of the wide intermediates (tiny vectors, differences that do not fit a `Fixed`, the narrowing
//! boundaries), one `#[should_panic(expected: ...)]` per panic path, and seeded fuzz properties
//! against an independent `i128` / `u128` reference written with the stable corelib. The
//! exhaustive numeric sweeps belong to `golden_wide.cairo`, generated from glam-rs by
//! `tools/refgen`, and are not duplicated here.
use fixed::fixed::{EPSILON, HALF, MAX, MIN, NEG_ONE, TWO};
use fixed::wide::{
    Acc, AccTrait, NormTrait, RecipTrait, WideAdd, WideLift, WideMul, WideNarrow, WideNeg, WideSqrt,
    WideSub, det3, distance2, distance2_squared, distance3, distance3_squared, distance4,
    distance4_squared, dot2, dot2_add, dot3, dot3_add, dot4, is_unit2, is_unit3, is_unit4, mul_add,
    mul_sub, norm2, norm2_squared, norm2_wide, norm3, norm3_squared, norm3_wide, norm4,
    norm4_squared, norm4_wide, normalize2, normalize3, normalize4, wide_from, wide_mul,
};
use fixed::{Fixed, FixedTrait, ONE, ONE_RAW, ZERO};

const I64_MIN: i64 = -0x8000000000000000;
const I64_MAX: i64 = 0x7fffffffffffffff;
const ONE_I128: i128 = 0x100000000;

fn f(raw: i64) -> Fixed {
    FixedTrait::from_raw(raw)
}

/// Hides a value from the constant folder (the exhaustive tests must reach Sierra).
#[inline(never)]
fn opaque(x: Fixed) -> Fixed {
    x
}

fn int(v: i32) -> Fixed {
    FixedTrait::from_int(v)
}

/// Floor division by 2^32 on the stable API (the corelib `/` truncates toward zero).
fn floor_shift(p: i128) -> i128 {
    let (q, r) = DivRem::div_rem(p, ONE_I128.try_into().unwrap());
    if r < 0 {
        q - 1
    } else {
        q
    }
}

// ------------------------------------------------------------------ accumulator API

#[test]
fn test_wide_mul_narrow_is_mul() {
    assert_eq!(wide_mul(f(-1), HALF).narrow().raw, -1); // floor
    assert_eq!(wide_mul(int(3), int(-7)).narrow(), int(-21));
    assert_eq!(wide_mul(MIN, ONE).narrow(), MIN);
    assert_eq!(wide_mul(MAX, ONE).narrow(), MAX);
    assert_eq!(wide_from(MIN).narrow(), MIN);
    assert_eq!(wide_from(MAX).narrow(), MAX);
}

#[test]
fn test_wide_add_sub_neg() {
    let p = wide_mul(int(3), int(5));
    let q = wide_mul(int(2), HALF);
    assert_eq!(p.add(q).narrow(), int(16));
    assert_eq!(p.sub(q).narrow(), int(14));
    assert_eq!(q.sub(p).narrow(), int(-14));
    assert_eq!(p.neg().narrow(), int(-15));
    assert_eq!(p.add(q).neg().narrow(), int(-16));
    assert_eq!(p.add(q.neg()).narrow(), p.sub(q).narrow());
    assert_eq!(p.add(wide_from(f(7))).narrow().raw, 15 * ONE_RAW + 7);
    // neg is exact, the floor happens once at the end: -(1/2 ULP) -> -1 ULP, +(1/2 ULP) -> 0
    assert_eq!(wide_mul(f(1), HALF).neg().narrow().raw, -1);
    assert_eq!(wide_mul(f(1), HALF).narrow().raw, 0);
    // two halves of an ULP add up before the rescale (two separate `*` would give 0)
    assert_eq!(wide_mul(f(1), HALF).add(wide_mul(f(1), HALF)).narrow().raw, 1);
}

#[test]
fn test_wide_sums_are_exact_up_to_16_products() {
    // Each product is +-2^126, far outside the Fixed range: the intermediate sums cannot
    // overflow, only the final narrow is range-checked.
    let p = wide_mul(MIN, MIN); // 2^126
    let s2 = p.add(p);
    let s4 = s2.add(s2);
    let s8 = s4.add(s4);
    assert_eq!(s8.sub(s8).narrow(), ZERO); // a W16 worth 0
    assert_eq!(s8.sub(s4).sub(s2).sub(p).sub(p).narrow(), ZERO);
    let n = wide_mul(MIN, MAX); // -(2^126 - 2^63)
    let n8 = n.add(n).add(n.add(n)).add(n.add(n).add(n.add(n)));
    // 8 * 2^126 - 8 * (2^126 - 2^63) = 2^66 -> 2^34 raw
    assert_eq!(s8.add(n8).narrow().raw, 0x400000000);
    // mixed widths: W3 + W5 + W7 + W1 = W16
    let w3 = p.add(p).add(n);
    let w5 = s4.add(n);
    let w7 = w5.add(s2);
    assert_eq!(w7.sub(w5).sub(p).add(n).narrow().raw, 0x80000000); // p + n = 2^63 -> 2^31
    assert_eq!(w3.add(w5).sub(w7).sub(n).narrow(), ZERO); // W3 + W5 + W7 + W1 = W16
}

#[test]
fn test_wide_narrow_boundaries() {
    // MAX * 2^32 + (2^32 - 1) is the largest Q64.64 value that narrows into range.
    let top = wide_from(MAX).add(wide_mul(f(0xffffffff), f(1)));
    assert_eq!(top.narrow(), MAX);
    assert_eq!(wide_from(MIN).narrow(), MIN);
    assert_eq!(wide_from(MIN).add(wide_mul(f(1), f(1))).narrow(), MIN);
}

#[test]
fn test_triple_products() {
    // (3 * 5 - 2 * 4) * -6 = -42
    assert_eq!(
        wide_mul(int(3), int(5)).sub(wide_mul(int(2), int(4))).mul(int(-6)).narrow(), int(-42),
    );
    // exact: (1/2 ULP-scale products) accumulate before the single rescale
    assert_eq!(wide_mul(f(1), f(1)).mul(f(1)).narrow().raw, 0);
    assert_eq!(wide_mul(f(-1), f(1)).mul(f(1)).narrow().raw, -1);
    assert_eq!(wide_mul(HALF, HALF).mul(HALF).narrow().raw, ONE_RAW / 8);
    // x * y * z with one rescale keeps the bits that two rescales lose: 3 ULP * 1/2 * 2
    assert_eq!(wide_mul(f(3), HALF).mul(TWO).narrow().raw, 3);
    assert_eq!((f(3) * HALF * TWO).raw, 2);
}

#[test]
fn test_triple_lift_and_sums() {
    // a*b*c + d*e: the Q64.64 term is lifted to Q96.96
    let t = wide_mul(int(2), int(3)).mul(int(4)).add(wide_mul(int(5), int(6)).lift());
    assert_eq!(t.narrow(), int(54));
    assert_eq!(wide_mul(f(-1), HALF).lift().narrow().raw, -1); // lift is exact, floor at the end
    assert_eq!(wide_from(MAX).lift().narrow(), MAX);
    assert_eq!(wide_from(MIN).lift().narrow(), MIN);
    // largest Q96.96 value that narrows into range: MAX * 2^64 + (2^64 - 1)
    let frac = wide_mul(f(0xffffffff), f(0x100000001)).mul(f(1)); // 2^64 - 1
    assert_eq!(wide_from(MAX).lift().add(frac).narrow(), MAX);
    // 16 extreme triple products cancel exactly
    let t1 = wide_mul(MIN, MIN).mul(MIN); // -2^189
    let t2 = t1.add(t1);
    let t4 = t2.add(t2);
    let t8 = t4.add(t4);
    assert_eq!(t8.sub(t8).narrow(), ZERO);
    assert_eq!(t8.add(t8.neg()).narrow(), ZERO);
    assert_eq!(t4.sub(t2).sub(t1).sub(t1).narrow(), ZERO);
}

#[test]
fn test_wide_sqrt() {
    assert_eq!(wide_mul(int(-5), int(-5)).sqrt(), int(5));
    assert_eq!(wide_mul(int(3), int(3)).add(wide_mul(int(4), int(4))).sqrt(), int(5));
    assert_eq!(
        wide_mul(int(2), int(2)).add(wide_mul(int(3), int(3))).add(wide_mul(int(6), int(6))).sqrt(),
        int(7),
    );
    // discriminant b^2 - 4ac = 25 - 16 = 9
    assert_eq!(wide_mul(int(5), int(5)).sub(wide_mul(int(4), int(4))).sqrt(), int(3));
    assert_eq!(wide_mul(ZERO, ONE).sqrt(), ZERO);
    assert_eq!(wide_mul(f(1), f(1)).sqrt().raw, 1); // sqrt(2^-64) = 2^-32: no underflow
    assert_eq!(wide_mul(TWO, ONE).sqrt().raw, 6074000999); // floor(sqrt(2) * 2^32)
    assert_eq!(wide_mul(MAX, MAX).sqrt(), MAX);
}

#[test]
fn test_acc_operations_match_typed_kernels() {
    assert_eq!(AccTrait::zero().narrow(), ZERO);
    let a = AccTrait::zero()
        .add_prod(int(3), int(5))
        .sub_prod(int(2), HALF)
        .add(int(4))
        .sub(int(1));
    let w = wide_mul(int(3), int(5))
        .sub(wide_mul(int(2), HALF))
        .add(wide_from(int(4)))
        .sub(wide_from(int(1)));
    assert_eq!(a.narrow(), w.narrow());
    assert_eq!(a.mul_narrow(HALF), w.mul(HALF).narrow());
    assert_eq!(a.sqrt(), w.sqrt());

    let left = AccTrait::zero().add_prod(int(7), int(9)).sub(int(3));
    let right = AccTrait::zero().sub_prod(int(2), int(5)).add(int(1));
    assert_eq!((left + right).narrow(), int(51));
    assert_eq!((left - right).narrow(), int(69));
    assert_eq!((-left).narrow(), int(-60));
}

#[test]
fn test_acc_extreme_sums_cancel_exactly() {
    let p = AccTrait::zero().add_prod(MIN, MIN);
    let n = AccTrait::zero().add_prod(MIN, MAX);
    let pair = p + n;
    let eight_pairs = ((pair + pair) + (pair + pair)) + ((pair + pair) + (pair + pair));
    assert_eq!(eight_pairs.narrow().raw, 0x400000000);
    assert_eq!((eight_pairs - eight_pairs).narrow(), ZERO);
    assert_eq!(AccTrait::zero().add_prod(MIN, MIN).sub_prod(MIN, MIN).narrow(), ZERO);
}

#[test]
fn test_wide_sqrt_all_widths_at_extremes() {
    let p = wide_mul(MIN, MIN);
    let n = wide_mul(MIN, MAX);
    let z = wide_mul(MIN, ZERO);
    let x2 = p.add(n);
    let x3 = x2.add(z);
    let x4 = x2.add(x2);
    let x5 = x4.add(z);
    let x6 = x4.add(x2);
    let x7 = x6.add(z);
    let x8 = x4.add(x4);
    let x9 = x8.add(z);
    let x10 = x8.add(x2);
    let x11 = x10.add(z);
    let x12 = x8.add(x4);
    let x13 = x12.add(z);
    let x14 = x12.add(x2);
    let x15 = x14.add(z);
    let x16 = x8.add(x8);
    assert_eq!(wide_mul(MAX, MAX).sqrt(), MAX);
    assert_eq!((x2.sqrt().raw, x3.sqrt().raw), (3037000499, 3037000499));
    assert_eq!((x4.sqrt().raw, x5.sqrt().raw), (ONE_RAW, ONE_RAW));
    assert_eq!((x6.sqrt().raw, x7.sqrt().raw), (5260239168, 5260239168));
    assert_eq!((x8.sqrt().raw, x9.sqrt().raw), (6074000999, 6074000999));
    assert_eq!((x10.sqrt().raw, x11.sqrt().raw), (6790939565, 6790939565));
    assert_eq!((x12.sqrt().raw, x13.sqrt().raw), (7439101573, 7439101573));
    assert_eq!((x14.sqrt().raw, x15.sqrt().raw), (8035148054, 8035148054));
    assert_eq!(x16.sqrt().raw, 8589934592);
}

// ------------------------------------------------------------------ named kernels

#[test]
fn test_named_kernels_small_integers() {
    assert_eq!(dot2(int(1), int(2), int(3), int(4)), int(14));
    assert_eq!(dot3(int(1), int(2), int(3), int(4), int(5), int(-6)), int(-16));
    assert_eq!(dot4(int(1), int(2), int(3), int(4), int(5), int(6), int(7), int(8)), int(100));
    assert_eq!(dot2_add(int(1), int(2), int(3), int(4), int(-4)), int(10));
    assert_eq!(dot3_add(int(1), int(2), int(3), int(4), int(5), int(6), int(1)), int(45));
    assert_eq!(mul_add(int(3), int(4), int(5)), int(17));
    assert_eq!(mul_sub(int(3), int(4), int(5), int(6)), int(-18));
    // det of [[2,0,0],[0,3,0],[0,0,4]] and of a singular matrix
    assert_eq!(det3(int(2), ZERO, ZERO, ZERO, int(3), ZERO, ZERO, ZERO, int(4)), int(24));
    assert_eq!(det3(int(1), int(2), int(3), int(4), int(5), int(6), int(7), int(8), int(9)), ZERO);
    assert_eq!(
        det3(int(2), int(-1), ZERO, int(1), int(3), int(1), ZERO, int(5), int(-4)), int(-38),
    );
    assert_eq!(norm2_squared(int(3), int(4)), int(25));
    assert_eq!(norm3_squared(int(1), int(2), int(2)), int(9));
    assert_eq!(norm4_squared(int(1), int(1), int(1), int(1)), int(4));
    assert_eq!(norm2(int(3), int(-4)), int(5));
    assert_eq!(norm3(int(2), int(3), int(6)), int(7));
    assert_eq!(norm4(int(2), int(4), int(5), int(6)), int(9));
    assert_eq!(distance2(int(1), int(1), int(4), int(5)), int(5));
    assert_eq!(distance3(int(1), int(2), int(3), int(3), int(5), int(9)), int(7));
    assert_eq!(distance4(int(1), int(1), int(1), int(1), int(3), int(5), int(6), int(7)), int(9));
    assert_eq!(distance2_squared(int(1), int(1), int(4), int(5)), int(25));
    assert_eq!(distance3_squared(int(1), int(2), int(3), int(3), int(5), int(9)), int(49));
    assert_eq!(
        distance4_squared(int(1), int(1), int(1), int(1), int(3), int(5), int(6), int(7)), int(81),
    );
}

#[test]
fn test_norm_of_tiny_vectors_does_not_underflow() {
    // length_squared of (3, 4) ULP underflows to 0; the length is still exact.
    assert_eq!(norm2_squared(f(3), f(4)), ZERO);
    assert_eq!(norm2(f(3), f(4)).raw, 5);
    assert_eq!(norm3(f(2), f(3), f(6)).raw, 7);
    assert_eq!(norm4(f(2), f(4), f(5), f(6)).raw, 9);
    assert_eq!(distance2(f(1), f(1), f(4), f(5)).raw, 5);
    assert_eq!(norm3(ZERO, ZERO, ZERO), ZERO);
}

#[test]
fn test_is_unit_preserves_floored_length_squared_threshold() {
    // These exact Q64.64 sums floor to 1 - 1025, 1 - 1024, 1 + 1024 and 1 + 1025 raw ULP.
    let below = f(0xfffffdff);
    let lower = f(0xfffffe00);
    let upper = f(0x100000200);
    let fill = f(0x10000);
    assert!(!is_unit2(below, fill, 1024));
    assert!(is_unit2(lower, ZERO, 1024));
    assert!(is_unit2(upper, ZERO, 1024));
    assert!(!is_unit2(upper, fill, 1024));
    assert!(is_unit3(lower, ZERO, ZERO, 1024));
    assert!(is_unit4(upper, ZERO, ZERO, ZERO, 1024));
    assert!(is_unit2(ONE, ZERO, 0));
}

#[test]
fn test_is_unit_long_vectors_return_false() {
    assert!(!is_unit2(MAX, MAX, 1024));
    assert!(!is_unit2(MIN, MIN, 1024));
    assert!(!is_unit3(MAX, MIN, MAX, 1024));
    assert!(!is_unit3(MIN, MIN, MIN, 1024));
    assert!(!is_unit4(MAX, MIN, MAX, MIN, 1024));
    // The sum is exactly 2^128, which does not fit `u128`; the predicate is still total.
    assert!(!is_unit4(MIN, MIN, MIN, MIN, 1024));
}

#[test]
fn test_distance_differences_cannot_overflow() {
    // MAX - MIN overflows a Fixed; the kernel computes it on 65 bits.
    assert_eq!(distance2_squared(f(1), ZERO, f(-1), ZERO).raw, 0);
    assert_eq!(distance2(f(0x4000000000000000), ZERO, f(-0x3fffffffffffffff), ZERO), MAX);
    assert_eq!(distance3(MAX, ZERO, ZERO, ZERO, ZERO, ZERO), MAX);
}

#[test]
fn test_norm_type() {
    let zero = norm3_wide(ZERO, ZERO, ZERO);
    assert!(zero.is_zero());
    assert!(zero.try_recip().is_none());
    assert_eq!(zero.to_fixed(), ZERO);
    let n = norm3_wide(int(2), int(3), int(6));
    assert!(!n.is_zero());
    assert_eq!(n.to_fixed(), int(7));
    assert_eq!(n.recip().mul(int(14)), int(2));
    assert_eq!(n.try_recip().unwrap().mul(int(-21)), int(-3));
    assert_eq!(norm2_wide(int(3), int(4)).to_fixed(), int(5));
    assert_eq!(norm4_wide(int(2), int(4), int(5), int(6)).to_fixed(), int(9));
    assert!(!norm2_wide(f(1), ZERO).is_zero());
}

#[test]
fn test_normalize_axis_aligned_is_exact() {
    assert_eq!(normalize3(int(3), ZERO, ZERO), (ONE, ZERO, ZERO));
    assert_eq!(normalize3(ZERO, int(-3), ZERO), (ZERO, NEG_ONE, ZERO));
    assert_eq!(normalize2(ZERO, f(1)), (ZERO, ONE));
    assert_eq!(normalize2(f(-1), ZERO), (NEG_ONE, ZERO));
    assert_eq!(normalize4(ZERO, ZERO, ZERO, MAX), (ZERO, ZERO, ZERO, ONE));
    assert_eq!(normalize3(MIN, ZERO, ZERO), (NEG_ONE, ZERO, ZERO));
    // 3-4-5: 0.6 and 0.8 rounded to nearest
    assert_eq!(normalize2(int(3), int(4)), (f(2576980378), f(3435973837)));
    assert_eq!(normalize3(int(-3), ZERO, int(4)), (f(-2576980378), ZERO, f(3435973837)));
}

#[test]
fn test_normalize_works_beyond_the_length_range() {
    // |(MIN, MIN)| = 2^31.5 does not fit a Fixed, the normalized vector does.
    let (x, y) = normalize2(MIN, MIN);
    assert_eq!(x.raw, -3037000499); // -1/sqrt(2) = -3037000499.97: within 1 ULP
    assert_eq!(y.raw, -3037000499);
    let (a, b, c) = normalize3(MAX, MIN, MAX);
    assert_eq!((a.raw, b.raw, c.raw), (2479700524, -2479700524, 2479700524)); // 1/sqrt(3)
    let (p, q, r, s) = normalize4(MAX, MAX, MAX, MAX);
    assert_eq!((p.raw, q.raw, r.raw, s.raw), (2147483648, 2147483648, 2147483648, 2147483648));
}

#[test]
fn test_recip_is_exact_on_representable_quotients() {
    assert_eq!(RecipTrait::new(int(3)).mul(int(3)), ONE);
    assert_eq!(RecipTrait::new(int(3)).mul(int(-9)), int(-3));
    assert_eq!(RecipTrait::new(int(-3)).mul(int(9)), int(-3));
    assert_eq!(RecipTrait::new(int(-7)).mul(int(-7)), ONE);
    assert_eq!(RecipTrait::new(f(7)).mul(f(21)), int(3));
    assert_eq!(RecipTrait::new(MIN).mul(MIN), ONE);
    assert_eq!(RecipTrait::new(MAX).mul(MAX), ONE);
    assert_eq!(RecipTrait::new(f(1)).mul(f(0x7fffffff)).raw, 0x7fffffff00000000);
    // Truncated division and Q32.32 reciprocal both miss 1: they give 1 - 1 ULP or 1 + ...
    assert_eq!((int(3) * (ONE / int(3))).raw, ONE_RAW - 1);
    // Rounds to nearest: 1/3 -> 0x55555555, 2/3 -> 0xaaaaaaab
    assert_eq!(RecipTrait::new(int(3)).mul(ONE).raw, 0x55555555);
    assert_eq!(RecipTrait::new(int(3)).mul(TWO).raw, 0xaaaaaaab);
    assert_eq!(RecipTrait::new(int(-3)).mul(TWO).raw, -0xaaaaaaab);
    // ties round toward +infinity: 1 ULP / 2 -> 1, -1 ULP / 2 -> 0
    assert_eq!(RecipTrait::new(TWO).mul(f(1)).raw, 1);
    assert_eq!(RecipTrait::new(TWO).mul(f(-1)).raw, 0);
}

// ------------------------------------------------------------------ panics

// panics: WideNarrow::narrow
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_overflow_panics() {
    let _ = wide_from(MAX).add(wide_mul(f(0xffffffff), f(1))).add(wide_mul(f(1), f(1))).narrow();
}

// panics: WideNarrow::narrow
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_underflow_panics() {
    let _ = wide_from(MIN).sub(wide_mul(f(1), f(1))).narrow();
}

// panics: WideNarrow::narrow
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_w16_positive_extreme_panics() {
    let p = wide_mul(MIN, MIN);
    let s4 = p.add(p).add(p.add(p));
    let s8 = s4.add(s4);
    let _ = s8.add(s8).narrow(); // 2^130
}

// panics: WideNarrow::narrow
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_w16_negative_extreme_panics() {
    let p = wide_mul(MIN, MIN);
    let s4 = p.add(p).add(p.add(p));
    let s8 = s4.add(s4);
    let _ = s8.neg().sub(s8).narrow(); // -2^130
}

// panics: WideNarrow::narrow
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_triple_overflow_panics() {
    let frac = wide_mul(f(0xffffffff), f(0x100000001)).mul(f(1)); // 2^64 - 1
    let one = wide_mul(f(1), f(1)).mul(f(1));
    let _ = wide_from(MAX).lift().add(frac).add(one).narrow();
}

// panics: WideNarrow::narrow
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_triple_underflow_panics() {
    let one = wide_mul(f(1), f(1)).mul(f(1));
    let _ = wide_from(MIN).lift().sub(one).narrow();
}

// panics: WideNarrow::narrow
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_t16_positive_extreme_panics() {
    let t = wide_mul(MIN, MIN).mul(MIN).neg(); // 2^189
    let t4 = t.add(t).add(t.add(t));
    let t8 = t4.add(t4);
    let _ = t8.add(t8).narrow(); // 2^193
}

// panics: WideNarrow::narrow
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_narrow_t16_negative_extreme_panics() {
    let t = wide_mul(MIN, MIN).mul(MIN); // -2^189
    let t4 = t.add(t).add(t.add(t));
    let t8 = t4.add(t4);
    let _ = t8.add(t8).narrow(); // -2^193
}

// panics: WideSqrt::sqrt
#[test]
#[should_panic(expected: 'Fixed: sqrt negative')]
fn test_wide_sqrt_negative_panics() {
    let _ = wide_mul(ONE, NEG_ONE).sqrt();
}

// panics: WideSqrt::sqrt
#[test]
#[should_panic(expected: 'Fixed: sqrt negative')]
fn test_wide_sqrt_negative_discriminant_panics() {
    let _ = wide_mul(int(2), int(2)).sub(wide_mul(int(4), int(4))).sqrt();
}

// panics: WideSqrt::sqrt
#[test]
#[should_panic(expected: 'Fixed: sqrt negative')]
fn test_wide_sqrt_w3_negative_panics() {
    let _ = wide_mul(f(1), f(1)).sub(wide_mul(f(1), f(1))).sub(wide_mul(f(1), f(1))).sqrt();
}

// panics: WideSqrt::sqrt
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_wide_sqrt_overflow_panics() {
    let _ = wide_mul(MIN, MIN).sqrt(); // 2^63
}

// panics: Acc::narrow
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_acc_narrow_overflow_panics() {
    let _ = AccTrait::zero().add_prod(MIN, MIN).narrow();
}

// panics: Acc::sqrt
#[test]
#[should_panic(expected: 'Fixed: sqrt negative')]
fn test_acc_sqrt_negative_panics() {
    let _ = AccTrait::zero().sub_prod(MIN, MIN).sqrt();
}

// panics: Acc::sqrt
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_acc_sqrt_overflow_panics() {
    let _ = AccTrait::zero().add_prod(MIN, MIN).sqrt();
}

// panics: Acc::mul_narrow
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_acc_mul_narrow_overflow_panics() {
    let _ = AccTrait::zero().add_prod(MAX, MAX).mul_narrow(TWO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_dot2_overflow_panics() {
    let _ = dot2(MAX, ONE, f(1), ONE);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_dot3_overflow_panics() {
    let _ = dot3(MIN, ONE, ZERO, ZERO, f(-1), ONE);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_dot4_overflow_panics() {
    let _ = dot4(MIN, MIN, MIN, MIN, MIN, MIN, MIN, MIN);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_dot2_add_overflow_panics() {
    let _ = dot2_add(MAX, ONE, ZERO, ZERO, f(1));
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_dot3_add_overflow_panics() {
    let _ = dot3_add(MIN, ONE, ZERO, ZERO, ZERO, ZERO, f(-1));
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_add_overflow_panics() {
    let _ = mul_add(MAX, ONE, f(1));
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_sub_overflow_panics() {
    let _ = mul_sub(MAX, ONE, MIN, ONE);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_det3_overflow_panics() {
    let big = int(2048);
    let _ = det3(big, ZERO, ZERO, ZERO, big, ZERO, ZERO, ZERO, big); // 2^33
}

// panics: fixed::wide::norm3_squared
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm_squared_overflow_panics() {
    let _ = norm3_squared(int(40000), int(40000), ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm2_overflow_panics() {
    let _ = norm2(MAX, MAX);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm3_overflow_panics() {
    let _ = norm3(MIN, ZERO, ZERO); // 2^31 exactly
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm4_overflow_panics() {
    let _ = norm4(MAX, MAX, MAX, MAX);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm4_sum_of_squares_2_pow_128_panics() {
    let _ = norm4(MIN, MIN, MIN, MIN);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm4_wide_sum_of_squares_2_pow_128_panics() {
    let _ = norm4_wide(MIN, MIN, MIN, MIN);
}

// panics: Norm::to_fixed
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_norm_to_fixed_overflow_panics() {
    let _ = norm2_wide(MIN, MIN).to_fixed();
}

// panics: fixed::wide::distance2
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_distance_overflow_panics() {
    let _ = distance2(MIN, ZERO, MAX, ZERO); // 2^64 - 1
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_distance3_sum_above_2_pow_128_panics() {
    let _ = distance3(MIN, MIN, MIN, MAX, MAX, MAX);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_distance4_overflow_panics() {
    let _ = distance4(MIN, MIN, MIN, MIN, MAX, MAX, MAX, MAX);
}

// panics: fixed::wide::distance2_squared
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_distance_squared_overflow_panics() {
    let _ = distance2_squared(int(-30000), ZERO, int(30000), ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_distance3_squared_overflow_panics() {
    let _ = distance3_squared(MIN, MIN, MIN, MAX, MAX, MAX);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_distance4_squared_overflow_panics() {
    let _ = distance4_squared(MIN, MIN, MIN, MIN, MAX, MAX, MAX, MAX);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_normalize2_zero_panics() {
    let _ = normalize2(ZERO, ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_normalize3_zero_panics() {
    let _ = normalize3(ZERO, ZERO, ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_normalize4_zero_panics() {
    let _ = normalize4(ZERO, ZERO, ZERO, ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_normalize4_sum_of_squares_2_pow_128_panics() {
    let _ = normalize4(MIN, MIN, MIN, MIN);
}

// panics: Norm::recip
#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_norm_recip_zero_panics() {
    let _ = norm2_wide(ZERO, ZERO).recip();
}

// panics: Recip::new
#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_recip_new_zero_panics() {
    let _ = RecipTrait::new(ZERO);
}

// panics: Recip::mul
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_recip_mul_overflow_panics() {
    let _ = RecipTrait::new(HALF).mul(MAX);
}

// panics: Recip::mul
#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_recip_mul_negative_overflow_panics() {
    let _ = RecipTrait::new(f(-1)).mul(MAX);
}

// ------------------------------------------------------------------ properties (seeded fuzzing)

fn sq(v: i64) -> u128 {
    let w: i128 = v.into();
    (w * w).try_into().unwrap()
}

/// Keeps 46 bits: three or four products of such values fit an `i128` with room to spare.
fn small(x: i64) -> i64 {
    x % 0x400000000000
}

#[test]
#[fuzzer(runs: 256, seed: 201)]
fn fuzz_dot_is_floor_of_exact_sum(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64) {
    let (a, b, c, d, e, g) = (small(a), small(b), small(c), small(d), small(e), small(g));
    let (a_, b_, c_): (i128, i128, i128) = (a.into(), b.into(), c.into());
    let (d_, e_, g_): (i128, i128, i128) = (d.into(), e.into(), g.into());
    let want2: i64 = floor_shift(a_ * b_ + c_ * d_).try_into().unwrap();
    let want3: i64 = floor_shift(a_ * b_ + c_ * d_ + e_ * g_).try_into().unwrap();
    let want4: i64 = floor_shift(a_ * b_ + c_ * d_ + e_ * g_ + a_ * g_).try_into().unwrap();
    let wantsub: i64 = floor_shift(a_ * b_ - c_ * d_).try_into().unwrap();
    let wantadd: i64 = floor_shift(a_ * b_ + c_ * d_ + e_ * ONE_I128).try_into().unwrap();
    let wantadd3: i64 = floor_shift(a_ * b_ + c_ * d_ + e_ * g_ + a_ * ONE_I128)
        .try_into()
        .unwrap();
    assert_eq!(dot2(f(a), f(b), f(c), f(d)).raw, want2);
    assert_eq!(dot3(f(a), f(b), f(c), f(d), f(e), f(g)).raw, want3);
    assert_eq!(dot4(f(a), f(b), f(c), f(d), f(e), f(g), f(a), f(g)).raw, want4);
    assert_eq!(mul_sub(f(a), f(b), f(c), f(d)).raw, wantsub);
    assert_eq!(dot2_add(f(a), f(b), f(c), f(d), f(e)).raw, wantadd);
    assert_eq!(dot3_add(f(a), f(b), f(c), f(d), f(e), f(g), f(a)).raw, wantadd3);
    // the accumulator API composes to the same values
    assert_eq!(wide_mul(f(a), f(b)).add(wide_mul(f(c), f(d))).narrow().raw, want2);
    assert_eq!(wide_mul(f(a), f(b)).sub(wide_mul(f(c), f(d))).narrow().raw, wantsub);
    assert_eq!(wide_mul(f(c), f(d)).neg().add(wide_mul(f(a), f(b))).narrow().raw, wantsub);
    assert_eq!(wide_mul(f(a), f(b)).narrow(), f(a) * f(b));
    assert_eq!(mul_add(f(a), f(b), f(c)), f(a).mul_add(f(b), f(c)));
}

#[test]
#[fuzzer(runs: 256, seed: 202)]
fn fuzz_lift_and_unit_mul_are_neutral(a: i64, b: i64, c: i64, d: i64) {
    let (a, b, c, d) = (small(a), small(b), small(c), small(d));
    let w = wide_mul(f(a), f(b)).sub(wide_mul(f(c), f(d)));
    assert_eq!(w.lift().narrow(), w.narrow());
    assert_eq!(w.mul(ONE).narrow(), w.narrow());
    assert_eq!(w.mul(NEG_ONE).narrow(), w.neg().narrow());
}

#[test]
#[fuzzer(runs: 256, seed: 203)]
fn fuzz_det3_is_floor_of_exact_determinant(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64) {
    // 9 entries of 38 bits: six triple products stay below 2^117.
    let m = 0x4000000000_i64;
    let (a, b, c, d, e, g) = (a % m, b % m, c % m, d % m, e % m, g % m);
    let (h, i, j) = ((a + d) % m, (b - e) % m, (c + g) % m);
    let (a_, b_, c_): (i128, i128, i128) = (a.into(), b.into(), c.into());
    let (d_, e_, g_): (i128, i128, i128) = (d.into(), e.into(), g.into());
    let (h_, i_, j_): (i128, i128, i128) = (h.into(), i.into(), j.into());
    let exact = a_ * (e_ * j_ - i_ * g_) + b_ * (g_ * h_ - j_ * d_) + c_ * (d_ * i_ - h_ * e_);
    let want: i64 = floor_shift(floor_shift(exact)).try_into().unwrap();
    assert_eq!(det3(f(a), f(b), f(c), f(d), f(e), f(g), f(h), f(i), f(j)).raw, want);
    // swapping two columns flips the sign of the exact determinant
    let swapped = det3(f(d), f(e), f(g), f(a), f(b), f(c), f(h), f(i), f(j)).raw;
    let want_swapped: i64 = floor_shift(floor_shift(-exact)).try_into().unwrap();
    assert_eq!(swapped, want_swapped);
}

#[test]
#[fuzzer(runs: 256, seed: 204)]
fn fuzz_norm_is_integer_root_of_sum_of_squares(x: i64, y: i64, z: i64, sel: u8) {
    let m: i64 = if sel % 2 == 0 {
        0x1000000000000
    } else {
        0x2000000000000000
    };
    let (x, y, z) = (x % m, y % m, z % m);
    let s3 = sq(x) + sq(y) + sq(z);
    let r3: u128 = norm3(f(x), f(y), f(z)).raw.try_into().unwrap();
    assert!(r3 * r3 <= s3 && s3 < (r3 + 1) * (r3 + 1));
    let s2 = sq(x) + sq(y);
    let r2: u128 = norm2(f(x), f(y)).raw.try_into().unwrap();
    assert!(r2 * r2 <= s2 && s2 < (r2 + 1) * (r2 + 1));
    let s4 = s3 + sq(x / 2);
    let r4: u128 = norm4(f(x), f(y), f(z), f(x / 2)).raw.try_into().unwrap();
    assert!(r4 * r4 <= s4 && s4 < (r4 + 1) * (r4 + 1));
    assert_eq!(norm3_wide(f(x), f(y), f(z)).to_fixed(), norm3(f(x), f(y), f(z)));
    assert_eq!(wide_mul(f(x), f(x)).sqrt(), f(x).abs());
    assert_eq!(wide_mul(f(x), f(x)).add(wide_mul(f(y), f(y))).sqrt(), norm2(f(x), f(y)));
}

#[test]
#[fuzzer(runs: 256, seed: 205)]
fn fuzz_distance_is_norm_of_difference(a: i64, b: i64, c: i64, d: i64, e: i64, g: i64) {
    let (a, b, c, d, e, g) = (a / 8, b / 8, c / 8, d / 8, e / 8, g / 8);
    assert_eq!(distance2(f(a), f(b), f(c), f(d)), norm2(f(a - c), f(b - d)));
    assert_eq!(distance3(f(a), f(b), f(c), f(d), f(e), f(g)), norm3(f(a - d), f(b - e), f(c - g)));
    assert_eq!(
        distance4(f(a), f(b), f(c), f(d), f(e), f(g), f(a), f(b)),
        norm4(f(a - e), f(b - g), f(c - a), f(d - b)),
    );
    // 40 bits: the squared differences fit the scalar range
    let m = 0x10000000000_i64;
    let (a, b, c, d) = (a % m, b % m, c % m, d % m);
    assert_eq!(distance2_squared(f(a), f(b), f(c), f(d)), norm2_squared(f(a - c), f(b - d)));
    assert_eq!(
        distance3_squared(f(a), f(b), f(c), f(d), f(a), f(b)),
        norm3_squared(f(a - d), f(b - a), f(c - b)),
    );
    assert_eq!(
        distance4_squared(f(a), f(b), f(c), f(d), f(d), f(c), f(b), f(a)),
        norm4_squared(f(a - d), f(b - c), f(c - b), f(d - a)),
    );
}

#[test]
#[fuzzer(runs: 256, seed: 206)]
fn fuzz_recip_mul_is_within_one_ulp_of_the_quotient(x: i64, d: i64, sel: u8) {
    let d = if sel % 2 == 0 {
        d % 0x1000000000000
    } else {
        d
    };
    let x = small(x);
    if d != 0 {
        // exact on representable quotients
        assert_eq!(RecipTrait::new(f(d)).mul(f(d)), ONE);
        let num: i128 = x.into() * ONE_I128;
        let trunc: i128 = num / d.into();
        let fits: Option<i64> = trunc.try_into();
        if let Some(t) = fits {
            if t > I64_MIN + 1 && t < I64_MAX - 1 {
                // |round-to-nearest - trunc| <= 1
                assert!(RecipTrait::new(f(d)).mul(f(x)).abs_diff_eq(f(t), EPSILON));
            }
        }
    }
}

#[test]
#[fuzzer(runs: 256, seed: 207)]
fn fuzz_normalize_has_unit_length(x: i64, y: i64, z: i64, w: i64, sel: u8) {
    // lengths >= 1.0 (raw 2^32): the floor of the length costs at most 2^-32 relative
    let m: i64 = if sel % 2 == 0 {
        0x100000000000
    } else {
        0x4000000000000000
    };
    let (x, y, z, w) = (x % m + ONE_RAW, y % m, z % m, w % m);
    let (x, y, z, w) = (f(x), f(y), f(z), f(w));
    if norm2_wide(x, y).to_fixed() >= ONE {
        let (nx, ny) = normalize2(x, y);
        assert!(norm2(nx, ny).abs_diff_eq(ONE, f(6)));
        assert!(nx.abs() <= f(ONE_RAW + 1) && ny.abs() <= f(ONE_RAW + 1));
        let (nx, ny, nz) = normalize3(x, y, z);
        assert!(norm3(nx, ny, nz).abs_diff_eq(ONE, f(6)));
        assert_eq!(nx.is_negative(), x.is_negative() && nx != ZERO);
        let (nx, ny, nz, nw) = normalize4(x, y, z, w);
        assert!(norm4(nx, ny, nz, nw).abs_diff_eq(ONE, f(6)));
        // composing Norm + Recip by hand gives the same bits as the fused kernel
        let r = norm4_wide(x, y, z, w).recip();
        assert_eq!((r.mul(x), r.mul(y), r.mul(z), r.mul(w)), (nx, ny, nz, nw));
    }
}

#[test]
#[fuzzer(runs: 128, seed: 208)]
fn fuzz_acc_chains_match_typed(
    a: i64, b: i64, c: i64, d: i64, e: i64, g: i64, h: i64, i: i64, sel: u8,
) {
    let m = 0x10000000000_i64;
    let (a, b, c, d) = (f(a % m), f(b % m), f(c % m), f(d % m));
    let (e, g, h, i) = (f(e % m), f(g % m), f(h % m), f(i % m));
    let p1 = wide_mul(a, b);
    let p2 = wide_mul(c, d);
    let p3 = wide_mul(e, g);
    let p4 = wide_mul(h, i);
    let w2 = p1.add(p2);
    let w4 = w2.add(p3.add(p4));
    let w8 = w4.add(w4);
    let w16 = w8.add(w8);
    let a1 = AccTrait::zero().add_prod(a, b);
    let a2 = a1.add_prod(c, d);
    let a4 = a2.add_prod(e, g).add_prod(h, i);
    let a8 = a4 + a4;
    let a16 = a8 + a8;
    let (actual, expected) = match sel % 5 {
        0 => (a1.narrow(), p1.narrow()),
        1 => (a2.narrow(), w2.narrow()),
        2 => (a4.narrow(), w4.narrow()),
        3 => (a8.narrow(), w8.narrow()),
        _ => (a16.narrow(), w16.narrow()),
    };
    assert_eq!(actual, expected);
}

// ------------------------------------------------------------- generated accumulator impls
//
// `scripts/gen_bounded.py` emits the `WideAdd` / `WideSub` impls of every pair `(Wn, Wm)` and
// `(Tn, Tm)` with `n + m <= 16`, plus `neg` / `narrow` / `mul` / `lift` / `sqrt` for `W1..W16` and
// `T1..T16`. All the bodies are the same `bounded_int` libfunc call (one step, no range check);
// only the statically tracked bound differs, and a bound that is too small does not compile while
// a bound that is too large is caught by the range check of `narrow`. Instantiating the ~1 000
// impls costs more compile time and memory than the CI runner grants the test crate, so the tests
// below walk the whole width ladder `W1..W16` / `T1..T16` once, consume every width with `narrow`
// and `neg`, and cover the widest sums (`n + m = 16`) with a representative set of pairs.

/// The ladder `W1..W16`: `Wn` is worth exactly `n`, so every `narrow` is exact.
#[test]
fn test_generated_w_ladder() {
    let x1 = wide_mul(opaque(ONE), opaque(ONE));
    let x2 = x1.add(x1);
    let x3 = x2.add(x1);
    let x4 = x3.add(x1);
    let x5 = x4.add(x1);
    let x6 = x5.add(x1);
    let x7 = x6.add(x1);
    let x8 = x7.add(x1);
    let x9 = x8.add(x1);
    let x10 = x9.add(x1);
    let x11 = x10.add(x1);
    let x12 = x11.add(x1);
    let x13 = x12.add(x1);
    let x14 = x13.add(x1);
    let x15 = x14.add(x1);
    let x16 = x15.add(x1);
    assert_eq!((x1.narrow(), x1.neg().narrow()), (int(1), int(-1)));
    assert_eq!((x2.narrow(), x2.neg().narrow()), (int(2), int(-2)));
    assert_eq!((x3.narrow(), x3.neg().narrow()), (int(3), int(-3)));
    assert_eq!((x4.narrow(), x4.neg().narrow()), (int(4), int(-4)));
    assert_eq!((x5.narrow(), x5.neg().narrow()), (int(5), int(-5)));
    assert_eq!((x6.narrow(), x6.neg().narrow()), (int(6), int(-6)));
    assert_eq!((x7.narrow(), x7.neg().narrow()), (int(7), int(-7)));
    assert_eq!((x8.narrow(), x8.neg().narrow()), (int(8), int(-8)));
    assert_eq!((x9.narrow(), x9.neg().narrow()), (int(9), int(-9)));
    assert_eq!((x10.narrow(), x10.neg().narrow()), (int(10), int(-10)));
    assert_eq!((x11.narrow(), x11.neg().narrow()), (int(11), int(-11)));
    assert_eq!((x12.narrow(), x12.neg().narrow()), (int(12), int(-12)));
    assert_eq!((x13.narrow(), x13.neg().narrow()), (int(13), int(-13)));
    assert_eq!((x14.narrow(), x14.neg().narrow()), (int(14), int(-14)));
    assert_eq!((x15.narrow(), x15.neg().narrow()), (int(15), int(-15)));
    assert_eq!((x16.narrow(), x16.neg().narrow()), (int(16), int(-16)));
    let a1: Acc = x1.into();
    let a2: Acc = x2.into();
    let a3: Acc = x3.into();
    let a4: Acc = x4.into();
    let a5: Acc = x5.into();
    let a6: Acc = x6.into();
    let a7: Acc = x7.into();
    let a8: Acc = x8.into();
    let a9: Acc = x9.into();
    let a10: Acc = x10.into();
    let a11: Acc = x11.into();
    let a12: Acc = x12.into();
    let a13: Acc = x13.into();
    let a14: Acc = x14.into();
    let a15: Acc = x15.into();
    let a16: Acc = x16.into();
    assert_eq!(a1.narrow(), int(1));
    assert_eq!(a2.narrow(), int(2));
    assert_eq!(a3.narrow(), int(3));
    assert_eq!(a4.narrow(), int(4));
    assert_eq!(a5.narrow(), int(5));
    assert_eq!(a6.narrow(), int(6));
    assert_eq!(a7.narrow(), int(7));
    assert_eq!(a8.narrow(), int(8));
    assert_eq!(a9.narrow(), int(9));
    assert_eq!(a10.narrow(), int(10));
    assert_eq!(a11.narrow(), int(11));
    assert_eq!(a12.narrow(), int(12));
    assert_eq!(a13.narrow(), int(13));
    assert_eq!(a14.narrow(), int(14));
    assert_eq!(a15.narrow(), int(15));
    assert_eq!(a16.narrow(), int(16));
    // the widest sums, reached from unbalanced and balanced pairs
    assert_eq!(x1.add(x15).narrow(), int(16));
    assert_eq!(x2.add(x14).narrow(), int(16));
    assert_eq!(x4.add(x12).narrow(), int(16));
    assert_eq!(x6.add(x10).narrow(), int(16));
    assert_eq!(x8.add(x8).narrow(), int(16));
    assert_eq!(x8.sub(x8).narrow(), ZERO);
    assert_eq!(x4.sub(x12).narrow(), int(-8));
    assert_eq!(x12.sub(x4).narrow(), int(8));
    assert_eq!(x15.sub(x1).narrow(), int(14));
    // `test_wide_sqrt_all_widths_at_extremes` covers `WideSqrt` at every width.
    // `mul` and `lift` cross over to the Q96.96 ladder at both ends and in the middle
    assert_eq!(x1.mul(int(-3)).narrow(), int(-3));
    assert_eq!(x8.mul(int(2)).narrow(), int(16));
    assert_eq!(x16.mul(ONE).narrow(), int(16));
    assert_eq!(x1.lift().narrow(), int(1));
    assert_eq!(x8.lift().narrow(), int(8));
    assert_eq!(x16.lift().narrow(), int(16));
}

/// The ladder `T1..T16`: `Tn` is worth exactly `n` at the Q96.96 scale.
#[test]
fn test_generated_t_ladder() {
    let t1 = wide_mul(opaque(ONE), opaque(ONE)).mul(opaque(ONE));
    let t2 = t1.add(t1);
    let t3 = t2.add(t1);
    let t4 = t3.add(t1);
    let t5 = t4.add(t1);
    let t6 = t5.add(t1);
    let t7 = t6.add(t1);
    let t8 = t7.add(t1);
    let t9 = t8.add(t1);
    let t10 = t9.add(t1);
    let t11 = t10.add(t1);
    let t12 = t11.add(t1);
    let t13 = t12.add(t1);
    let t14 = t13.add(t1);
    let t15 = t14.add(t1);
    let t16 = t15.add(t1);
    assert_eq!((t1.narrow(), t1.neg().narrow()), (int(1), int(-1)));
    assert_eq!((t2.narrow(), t2.neg().narrow()), (int(2), int(-2)));
    assert_eq!((t3.narrow(), t3.neg().narrow()), (int(3), int(-3)));
    assert_eq!((t4.narrow(), t4.neg().narrow()), (int(4), int(-4)));
    assert_eq!((t5.narrow(), t5.neg().narrow()), (int(5), int(-5)));
    assert_eq!((t6.narrow(), t6.neg().narrow()), (int(6), int(-6)));
    assert_eq!((t7.narrow(), t7.neg().narrow()), (int(7), int(-7)));
    assert_eq!((t8.narrow(), t8.neg().narrow()), (int(8), int(-8)));
    assert_eq!((t9.narrow(), t9.neg().narrow()), (int(9), int(-9)));
    assert_eq!((t10.narrow(), t10.neg().narrow()), (int(10), int(-10)));
    assert_eq!((t11.narrow(), t11.neg().narrow()), (int(11), int(-11)));
    assert_eq!((t12.narrow(), t12.neg().narrow()), (int(12), int(-12)));
    assert_eq!((t13.narrow(), t13.neg().narrow()), (int(13), int(-13)));
    assert_eq!((t14.narrow(), t14.neg().narrow()), (int(14), int(-14)));
    assert_eq!((t15.narrow(), t15.neg().narrow()), (int(15), int(-15)));
    assert_eq!((t16.narrow(), t16.neg().narrow()), (int(16), int(-16)));
    assert_eq!(t1.add(t15).narrow(), int(16));
    assert_eq!(t4.add(t12).narrow(), int(16));
    assert_eq!(t8.add(t8).narrow(), int(16));
    assert_eq!(t8.sub(t8).narrow(), ZERO);
    assert_eq!(t4.sub(t12).narrow(), int(-8));
    assert_eq!(t15.sub(t1).narrow(), int(14));
}
