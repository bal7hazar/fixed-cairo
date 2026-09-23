//! Tests of `fixed::fixed`.
//!
//! Three layers, in this order: hand-written behaviour and edge cases, one
//! `#[should_panic(expected: ...)]` per panic path, seeded fuzz properties against an independent
//! `i128` / `u128` reference written with the stable corelib, then one compact `*_table` test per
//! function. The expected values of the tables were computed offline with Python big integers
//! (exact arithmetic, the rounding of each operation is stated above its table) and cover the edge
//! values only: 0, +-1 ULP, +-1/2, ties, MIN, MAX and the negative operands that distinguish floor
//! from truncation. The exhaustive numeric sweeps belong to `golden_fixed.cairo`, generated from
//! glam-rs by `tools/refgen`.
use core::num::traits::{Bounded, One, Zero};
use fixed::fixed::{
    DEG_TO_RAD, E, EPSILON, FRAC_1_PI, FRAC_1_SQRT_2, FRAC_2_PI, FRAC_BITS, FRAC_PI_2,
    FRAC_PI_2_RAW, FRAC_PI_3, FRAC_PI_4, FRAC_PI_6, FRAC_PI_8, HALF, HALF_RAW, LN_10, LN_2, MAX,
    MIN, NEG_ONE, PI, PI_RAW, RAD_TO_DEG, SQRT_2, TAU, TAU_RAW, TWO,
};
use fixed::{Fixed, FixedTrait, ONE, ONE_RAW, ZERO};

const I64_MIN: i64 = -0x8000000000000000;
const I64_MAX: i64 = 0x7fffffffffffffff;
const ONE_I128: i128 = 0x100000000;

fn f(raw: i64) -> Fixed {
    FixedTrait::from_raw(raw)
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

/// Maps a fuzzed `i64` to a magnitude class chosen by `sel` so that small, medium and large
/// operands are all exercised (a uniform `i64` is almost always huge).
fn scale(x: i64, sel: u8) -> i64 {
    match sel % 4 {
        0 => x % 0x10000, // below 2^-16
        1 => x % 0x1000000000, // below 16.0
        2 => x % 0x1000000000000, // below 2^16
        _ => x,
    }
}

// ------------------------------------------------------------------ constants and conversions

#[test]
fn test_constants() {
    assert_eq!(FRAC_BITS, 32);
    assert_eq!(ZERO.raw, 0);
    assert_eq!(ONE.raw, 4294967296);
    assert_eq!(ONE_RAW, 4294967296);
    assert_eq!(NEG_ONE.raw, -4294967296);
    assert_eq!(HALF.raw, 2147483648);
    assert_eq!(HALF_RAW, 2147483648);
    assert_eq!(TWO.raw, 8589934592);
    assert_eq!(MIN.raw, I64_MIN);
    assert_eq!(MAX.raw, I64_MAX);
    assert_eq!(EPSILON.raw, 1);
    // round(x * 2^32), x evaluated with 80 significant digits.
    assert_eq!(PI.raw, 13493037705);
    assert_eq!(PI_RAW, 13493037705);
    assert_eq!(TAU.raw, 26986075409);
    assert_eq!(TAU_RAW, 26986075409);
    assert_eq!(FRAC_PI_2.raw, 6746518852);
    assert_eq!(FRAC_PI_2_RAW, 6746518852);
    assert_eq!(FRAC_PI_3.raw, 4497679235);
    assert_eq!(FRAC_PI_4.raw, 3373259426);
    assert_eq!(FRAC_PI_6.raw, 2248839617);
    assert_eq!(FRAC_PI_8.raw, 1686629713);
    assert_eq!(FRAC_1_PI.raw, 1367130551);
    assert_eq!(FRAC_2_PI.raw, 2734261102);
    assert_eq!(E.raw, 11674931555);
    assert_eq!(SQRT_2.raw, 6074001000);
    assert_eq!(FRAC_1_SQRT_2.raw, 3037000500);
    assert_eq!(LN_2.raw, 2977044472);
    assert_eq!(LN_10.raw, 9889527671);
    assert_eq!(DEG_TO_RAD.raw, 74961321);
    assert_eq!(RAD_TO_DEG.raw, 246083499208);
}

#[test]
fn test_constants_are_consistent() {
    // Each constant is rounded to nearest independently: relations hold within 1 ULP.
    assert!((PI + PI).abs_diff_eq(TAU, EPSILON));
    assert!((FRAC_PI_2 + FRAC_PI_2).abs_diff_eq(PI, EPSILON));
    assert!((SQRT_2 * SQRT_2).abs_diff_eq(TWO, f(2)));
    assert!((SQRT_2 * FRAC_1_SQRT_2).abs_diff_eq(ONE, f(2)));
    assert!((PI * FRAC_1_PI).abs_diff_eq(ONE, f(4)));
    assert!((DEG_TO_RAD * RAD_TO_DEG).abs_diff_eq(ONE, f(64)));
}

#[test]
fn test_from_raw_to_raw() {
    assert_eq!(f(-5).to_raw(), -5);
    assert_eq!(FixedTrait::from_raw(I64_MIN), MIN);
    assert_eq!(MAX.to_raw(), I64_MAX);
    let d: Fixed = Default::default();
    assert_eq!(d, ZERO);
}

#[test]
fn test_from_int() {
    assert_eq!(FixedTrait::from_int(0), ZERO);
    assert_eq!(FixedTrait::from_int(1), ONE);
    assert_eq!(FixedTrait::from_int(-1), NEG_ONE);
    assert_eq!(FixedTrait::from_int(-7).raw, -30064771072);
    assert_eq!(FixedTrait::from_int(0x7fffffff).raw, 0x7fffffff00000000);
    assert_eq!(FixedTrait::from_int(-0x80000000), MIN);
}

#[test]
fn test_into_and_try_into() {
    let a: Fixed = (-128_i8).into();
    assert_eq!(a.raw, -128 * ONE_RAW);
    let b: Fixed = (-32768_i16).into();
    assert_eq!(b.raw, -32768 * ONE_RAW);
    let c: Fixed = (-0x80000000_i32).into();
    assert_eq!(c, MIN);
    let d: Fixed = 255_u8.into();
    assert_eq!(d.raw, 255 * ONE_RAW);
    let e: Fixed = 65535_u16.into();
    assert_eq!(e.raw, 65535 * ONE_RAW);
    let g: Option<Fixed> = 0x7fffffff_u32.try_into();
    assert_eq!(g, Some(f(0x7fffffff00000000)));
    let h: Option<Fixed> = 0x80000000_u32.try_into();
    assert_eq!(h, None);
    let i: Option<Fixed> = (-0x80000000_i64).try_into();
    assert_eq!(i, Some(MIN));
    let j: Option<Fixed> = (-0x80000001_i64).try_into();
    assert_eq!(j, None);
    let k: Option<Fixed> = 0x80000000_i64.try_into();
    assert_eq!(k, None);
    let l: Option<Fixed> = 3_u64.try_into();
    assert_eq!(l, Some(f(3 * ONE_RAW)));
    let m: Option<Fixed> = 0x80000000_u64.try_into();
    assert_eq!(m, None);
}

#[test]
fn test_zero_one_bounded() {
    assert_eq!(Zero::<Fixed>::zero(), ZERO);
    assert!(ZERO.is_zero());
    assert!(!EPSILON.is_zero());
    assert!(EPSILON.is_non_zero());
    assert!(!ZERO.is_non_zero());
    assert_eq!(One::<Fixed>::one(), ONE);
    assert!(ONE.is_one());
    assert!(!f(1).is_one());
    assert!(f(1).is_non_one());
    assert!(!ONE.is_non_one());
    assert_eq!(Bounded::<Fixed>::MIN, MIN);
    assert_eq!(Bounded::<Fixed>::MAX, MAX);
}

#[test]
fn test_partial_ord_and_eq() {
    let a = f(-3);
    let b = f(2);
    assert!(a < b && !(b < a) && !(a < a));
    assert!(a <= b && !(b <= a) && a <= a);
    assert!(b > a && !(a > b) && !(a > a));
    assert!(b >= a && !(a >= b) && a >= a);
    assert!(MIN < MAX && MAX > MIN && MIN <= MIN && MAX >= MAX);
    assert!(a == f(-3) && a != b);
}

#[test]
fn test_assign_operators() {
    let mut x = f(5 * ONE_RAW);
    x += f(HALF_RAW);
    assert_eq!(x.raw, 11 * HALF_RAW);
    x -= ONE;
    assert_eq!(x.raw, 9 * HALF_RAW);
    x *= f(-2 * ONE_RAW);
    assert_eq!(x.raw, -9 * ONE_RAW);
    x /= f(4 * ONE_RAW);
    assert_eq!(x.raw, -9 * ONE_RAW / 4);
    x %= ONE;
    assert_eq!(x.raw, -ONE_RAW / 4);
}

#[test]
fn test_sign_predicates() {
    assert!(f(-1).is_negative() && !ZERO.is_negative() && !f(1).is_negative());
    assert!(f(1).is_positive() && !ZERO.is_positive() && !f(-1).is_positive());
    assert!(f(-1).is_sign_negative() && !ZERO.is_sign_negative());
    assert!(ZERO.is_sign_positive() && f(1).is_sign_positive() && !f(-1).is_sign_positive());
    assert!(MIN.is_negative() && MAX.is_positive());
}

#[test]
fn test_lerp_end_points_are_exact() {
    assert_eq!(MIN.lerp(MAX, ZERO), MIN);
    assert_eq!(MIN.lerp(MAX, ONE), MAX);
    assert_eq!(MAX.lerp(MIN, ONE), MIN);
    assert_eq!(MAX.lerp(MIN, HALF).raw, -1);
    // Extrapolation is allowed.
    assert_eq!(ONE.lerp(TWO, TWO).raw, 3 * ONE_RAW);
    assert_eq!(ONE.lerp(TWO, NEG_ONE), ZERO);
}

#[test]
fn test_rounding_direction_of_mul_and_div() {
    // -1 ULP * 1/2 = -1/2 ULP: floor gives -1 ULP, truncation would give 0.
    assert_eq!((f(-1) * HALF).raw, -1);
    assert_eq!((f(1) * HALF).raw, 0);
    // `/` rounds to nearest, ties to even: +-1/2 -> 0, +-3/2 -> +-2, +-5/2 -> +-2, all four signs.
    let ties: [(i64, i64, i64); 8] = [
        (-1, 2, 0), (1, 2, 0), (3, 2, 2), (-3, 2, -2), (5, 2, 2), (5, -2, -2), (-5, -2, 2),
        (-3, -2, 2),
    ];
    for (a, k, q) in ties.span() {
        assert_eq!((f(*a) / f(*k * ONE_RAW)).raw, *q);
        assert_eq!(f(*a).div_nearest(f(*k * ONE_RAW)).raw, *q);
    }
    // not a tie: to the nearest raw value, up or down
    assert_eq!((ONE / f(3 * ONE_RAW)).raw, 0x55555555);
    assert_eq!((TWO / f(3 * ONE_RAW)).raw, 0xaaaaaaab);
    assert_eq!((TWO / f(-3 * ONE_RAW)).raw, -0xaaaaaaab);
    assert_eq!(FixedTrait::from_ratio(2, 3).raw, 0xaaaaaaab);
    assert_eq!(f(-3 * ONE_RAW).recip().raw, -1431655765);
    assert_eq!(f(6).recip().raw, 3074457345618258603); // 2^64 / 6 = ...602.67
}

#[test]
fn test_mul_extremes() {
    assert_eq!(MIN * ONE, MIN);
    assert_eq!(MAX * ONE, MAX);
    assert_eq!(MAX * NEG_ONE, f(-I64_MAX));
    assert_eq!(MIN * ZERO, ZERO);
    assert_eq!((MIN * HALF).raw, I64_MIN / 2);
    // Largest positive product that fits: MIN * (-1 + 1 ULP) = 2^31 - 1/2.
    assert_eq!((MIN * f(-ONE_RAW + 1)).raw, 0x7fffffff80000000);
}

// ------------------------------------------------------------------ panics

#[test]
#[should_panic(expected: 'i64_add Overflow')]
fn test_add_overflow_panics() {
    let _ = MAX + f(1);
}

#[test]
#[should_panic(expected: 'i64_add Underflow')]
fn test_add_underflow_panics() {
    let _ = MIN + f(-1);
}

#[test]
#[should_panic(expected: 'i64_sub Overflow')]
fn test_sub_overflow_panics() {
    let _ = MAX - f(-1);
}

#[test]
#[should_panic(expected: 'i64_sub Underflow')]
fn test_sub_underflow_panics() {
    let _ = MIN - f(1);
}

#[test]
#[should_panic(expected: 'i64_neg Underflow')]
fn test_neg_min_panics() {
    let _ = -MIN;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_overflow_panics() {
    let _ = MIN * NEG_ONE;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_overflow_by_one_ulp_panics() {
    // MAX * (1 + 1 ULP) = MAX + (MAX >> 32) > MAX
    let _ = MAX * f(ONE_RAW + 1);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_underflow_panics() {
    let _ = MIN * f(ONE_RAW + 1);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_min_min_panics() {
    let _ = MIN * MIN;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_assign_overflow_panics() {
    let mut x = MAX;
    x *= TWO;
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_div_by_zero_panics() {
    let _ = ONE / ZERO;
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_div_negative_by_zero_panics() {
    let _ = NEG_ONE / ZERO;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_div_overflow_panics() {
    let _ = MAX / HALF;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_div_min_by_neg_one_panics() {
    let _ = MIN / NEG_ONE;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_div_negative_overflow_panics() {
    let _ = MIN / HALF;
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_div_by_negative_overflow_panics() {
    let _ = MAX / f(-1);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_rem_by_zero_panics() {
    let _ = ONE % ZERO;
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_from_ratio_zero_den_panics() {
    let _ = FixedTrait::from_ratio(1, 0);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_from_ratio_overflow_panics() {
    let _ = FixedTrait::from_ratio(0x80000000, 1);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_abs_min_panics() {
    let _ = MIN.abs();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_copysign_min_panics() {
    let _ = MIN.copysign(ONE);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_ceil_overflow_panics() {
    let _ = f(0x7fffffff00000001).ceil();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_round_overflow_panics() {
    let _ = f(0x7fffffff80000000).round();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_to_int_round_overflow_panics() {
    let _ = f(0x7fffffff80000000).to_int_round();
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_recip_zero_panics() {
    let _ = ZERO.recip();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_recip_overflow_panics() {
    let _ = f(2).recip();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_recip_negative_overflow_panics() {
    let _ = f(-1).recip();
}

#[test]
#[should_panic(expected: 'Fixed: sqrt negative')]
fn test_sqrt_negative_panics() {
    let _ = f(-1).sqrt();
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_div_euclid_by_zero_panics() {
    let _ = ONE.div_euclid(ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_div_euclid_overflow_panics() {
    let _ = MAX.div_euclid(HALF);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_div_euclid_negative_overflow_panics() {
    let _ = MIN.div_euclid(f(-1));
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_rem_euclid_by_zero_panics() {
    let _ = ONE.rem_euclid(ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_mul_add_overflow_panics() {
    let _ = MAX.mul_add(ONE, f(1));
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_lerp_overflow_panics() {
    let _ = ZERO.lerp(MAX, TWO);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_powi_overflow_panics() {
    let _ = f(65536 * ONE_RAW).powi(2);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_powi_cube_overflow_panics() {
    let _ = f(-2048 * ONE_RAW).powi(3);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_powi_loop_overflow_panics() {
    let _ = TWO.powi(31);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_powi_negative_of_zero_panics() {
    let _ = ZERO.powi(-1);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_inverse_lerp_degenerate_panics() {
    let _ = FixedTrait::inverse_lerp(ONE, ONE, TWO);
}

#[test]
#[should_panic(expected: 'i64_sub Overflow')]
fn test_inverse_lerp_range_overflow_panics() {
    let _ = FixedTrait::inverse_lerp(MIN, MAX, ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_smoothstep_degenerate_panics() {
    let _ = ONE.smoothstep(TWO, TWO);
}

#[test]
#[should_panic(expected: 'i64_sub Overflow')]
fn test_move_towards_range_overflow_panics() {
    let _ = MIN.move_towards(MAX, ONE);
}

#[test]
#[should_panic(expected: 'i64_neg Underflow')]
fn test_move_towards_min_step_panics() {
    let _ = ONE.move_towards(ZERO, MIN);
}

#[test]
#[should_panic(expected: 'i64_sub Overflow')]
fn test_move_towards_away_overflow_panics() {
    let _ = MAX.move_towards(ZERO, f(-1)); // self - d = MAX + 1 ULP
}

// ------------------------------------------------------------------ properties (seeded fuzzing)

#[test]
#[fuzzer(runs: 256, seed: 101)]
fn fuzz_add_sub_neg_match_i64(x: i64, y: i64) {
    let (a, b) = (x / 2, y / 2);
    assert_eq!((f(a) + f(b)).raw, a + b);
    assert_eq!((f(a) - f(b)).raw, a - b);
    assert_eq!((-f(a)).raw, -a);
    assert_eq!(f(a) + f(b), f(b) + f(a));
}

#[test]
#[fuzzer(runs: 256, seed: 102)]
fn fuzz_mul_is_floor_of_exact_product(x: i64, y: i64, sel: u8) {
    let (a, b) = (scale(x, sel), scale(y, sel / 4));
    let exact: i128 = floor_shift(a.into() * b.into());
    let fits: Option<i64> = exact.try_into();
    if let Some(e) = fits {
        assert_eq!((f(a) * f(b)).raw, e);
        assert_eq!(f(a) * f(b), f(b) * f(a));
        assert_eq!(f(a).mul_add(f(b), ZERO).raw, e);
    }
}

#[test]
#[fuzzer(runs: 256, seed: 103)]
fn fuzz_div_is_round_half_even_of_exact_quotient(x: i64, y: i64, sel: u8) {
    let (a, b) = (scale(x, sel), scale(y, sel / 4));
    if b != 0 {
        // n = q d + r, 0 <= r < d (d > 0): the exact quotient is in [q, q + 1)
        let (n, d): (i128, i128) = if b < 0 {
            (-a.into() * ONE_I128, -b.into())
        } else {
            (a.into() * ONE_I128, b.into())
        };
        let (mut q, mut r) = (n / d, n % d);
        if r < 0 {
            q -= 1;
            r += d;
        }
        let exact = if 2 * r > d || (2 * r == d && q % 2 != 0) {
            q + 1
        } else {
            q
        };
        let fits: Option<i64> = exact.try_into();
        if let Some(e) = fits {
            assert_eq!((f(a) / f(b)).raw, e);
            assert_eq!(FixedTrait::from_ratio(a, b).raw, e);
        }
    }
}

#[test]
#[fuzzer(runs: 256, seed: 104)]
fn fuzz_recip_is_one_over_x(x: i64, sel: u8) {
    let a = scale(x, sel);
    if a > 2 || a < -2 {
        assert_eq!(f(a).recip(), ONE / f(a));
    }
}

#[test]
#[fuzzer(runs: 256, seed: 105)]
fn fuzz_rem_matches_i64_rem(x: i64, y: i64, sel: u8) {
    let (a, b) = (scale(x, sel / 4), scale(y, sel));
    if b != 0 {
        assert_eq!((f(a) % f(b)).raw, a % b);
    }
}

#[test]
#[fuzzer(runs: 256, seed: 106)]
fn fuzz_euclid_decomposition(x: i64, y: i64, sel: u8) {
    let (a, b) = (scale(x, sel / 4), scale(y, sel));
    if b != 0 {
        let r = f(a).rem_euclid(f(b)).raw;
        assert!(r >= 0);
        let r_wide: i128 = r.into();
        let b_wide: i128 = b.into();
        let b_abs = if b_wide < 0 {
            -b_wide
        } else {
            b_wide
        };
        assert!(r_wide < b_abs);
        // a = n * b + r with an integer n
        let (n, zero) = DivRem::div_rem(a.into() - r_wide, b_wide.try_into().unwrap());
        assert_eq!(zero, 0);
        let fits: Option<i64> = (n * ONE_I128).try_into();
        if let Some(e) = fits {
            assert_eq!(f(a).div_euclid(f(b)).raw, e);
        }
    }
}

#[test]
#[fuzzer(runs: 256, seed: 107)]
fn fuzz_rounding_family(x: i64, sel: u8) {
    let a = f(scale(x, sel));
    let fl = a.floor();
    let tr = a.trunc();
    assert!(fl <= a && fl.raw % ONE_RAW == 0);
    assert_eq!(fl.raw + a.fract_gl().raw, a.raw);
    assert!(a.fract_gl() >= ZERO && a.fract_gl() < ONE);
    assert_eq!(tr.raw + a.fract().raw, a.raw);
    assert!(tr.raw % ONE_RAW == 0);
    assert_eq!(tr.raw, (a.raw / ONE_RAW) * ONE_RAW);
    let int_floor: i64 = a.to_int().into();
    let int_trunc: i64 = a.to_int_trunc().into();
    assert_eq!(int_floor * ONE_RAW, fl.raw);
    assert_eq!(int_trunc * ONE_RAW, tr.raw);
    if a.raw < 0x7fffffff00000000 {
        let ce = a.ceil();
        assert!(ce >= a && ce.raw - fl.raw <= ONE_RAW && ce.raw % ONE_RAW == 0);
        let ro = a.round();
        assert!(ro.abs_diff_eq(a, HALF) && ro.raw % ONE_RAW == 0);
        let int_round: i64 = a.to_int_round().into();
        assert_eq!(int_round * ONE_RAW, ro.raw);
        if a.raw > -0x7fffffff00000000 {
            // symmetric: ties away from zero
            assert_eq!((-a).round(), -ro);
        }
    }
}

#[test]
#[fuzzer(runs: 256, seed: 108)]
fn fuzz_abs_signum_copysign(x: i64, y: i64) {
    if x != I64_MIN {
        let a = f(x);
        assert!(a.abs() >= ZERO);
        assert_eq!(a.abs().raw * (a.signum().raw / ONE_RAW), a.raw);
        assert_eq!(a.copysign(f(y)).abs(), a.abs());
        assert_eq!(a.copysign(f(y)).is_negative(), y < 0 && x != 0);
        assert_eq!(a.is_negative(), x < 0);
    }
}

#[test]
#[fuzzer(runs: 256, seed: 109)]
fn fuzz_min_max_clamp(x: i64, y: i64, z: i64) {
    let (a, b, c) = (f(x), f(y), f(z));
    let (lo, hi) = (a.min(b), a.max(b));
    assert!(lo <= hi && (lo == a || lo == b) && (hi == a || hi == b));
    let k = c.clamp(lo, hi);
    assert!(k >= lo && k <= hi);
    if c >= lo && c <= hi {
        assert_eq!(k, c);
    }
    let s = c.saturate();
    assert!(s >= ZERO && s <= ONE);
}

#[test]
#[fuzzer(runs: 256, seed: 110)]
fn fuzz_sqrt_is_integer_root(x: i64, sel: u8) {
    let a = scale(x, sel);
    if a >= 0 {
        let r: u128 = f(a).sqrt().raw.try_into().unwrap();
        let s: u128 = a.try_into().unwrap() * 0x100000000;
        assert!(r * r <= s && s < (r + 1) * (r + 1));
    }
}

#[test]
#[fuzzer(runs: 256, seed: 111)]
fn fuzz_lerp(x: i64, y: i64, t: u32) {
    let (a, b) = (f(x), f(y));
    assert_eq!(a.lerp(b, ZERO), a);
    assert_eq!(a.lerp(b, ONE), b);
    // t in [0, 1): the result stays between the end points
    let r = a.lerp(b, f(t.into()));
    assert!(r >= a.min(b) && r <= a.max(b));
}

#[test]
#[fuzzer(runs: 256, seed: 112)]
fn fuzz_smoothstep_and_step(x: i64, sel: u8) {
    let v = f(scale(x, sel) / 4);
    let s = v.smoothstep(NEG_ONE, TWO);
    assert!(s >= ZERO && s <= ONE);
    if v <= NEG_ONE {
        assert_eq!(s, ZERO);
    }
    if v >= TWO {
        assert_eq!(s, ONE);
    }
    assert_eq!(ONE.step(v) == ONE, v >= ONE);
}

#[test]
#[fuzzer(runs: 256, seed: 113)]
fn fuzz_move_towards(x: i64, y: i64, d: u32) {
    let (a, b) = (f(x / 4), f(y / 4));
    let step = f(d.into() * 0x10000);
    let m = a.move_towards(b, step);
    assert!(m.abs_diff_eq(b, (b - a).abs()));
    if (b - a).abs() <= step {
        assert_eq!(m, b);
    } else {
        assert!(m.abs_diff_eq(a, step) && !m.abs_diff_eq(a, step - EPSILON));
    }
}

#[test]
#[fuzzer(runs: 256, seed: 114)]
fn fuzz_abs_diff_eq(x: i64, y: i64, m: i64) {
    let d: i128 = x.into() - y.into();
    let expected = (if d < 0 {
        -d
    } else {
        d
    }) <= m.into();
    assert_eq!(f(x).abs_diff_eq(f(y), f(m)), expected);
    assert_eq!(f(y).abs_diff_eq(f(x), f(m)), expected);
}

#[test]
#[fuzzer(runs: 256, seed: 115)]
fn fuzz_int_round_trip(v: i32) {
    let a = FixedTrait::from_int(v);
    assert_eq!(a.to_int(), v);
    assert_eq!(a.to_int_trunc(), v);
    assert_eq!(a.to_int_round(), v);
    assert_eq!(a.floor(), a);
    assert_eq!(a.trunc(), a);
    assert_eq!(a.fract(), ZERO);
    let b: Fixed = v.into();
    assert_eq!(a, b);
}

#[test]
#[fuzzer(runs: 256, seed: 116)]
fn fuzz_powi_small_exponents(x: i64) {
    let a = f(x % 0x2000000000); // |a| < 32: a^4 fits
    assert_eq!(a.powi(0), ONE);
    assert_eq!(a.powi(1), a);
    assert_eq!(a.powi(2), a * a);
    assert_eq!(a.powi(4), (a * a) * (a * a));
    assert_eq!(a.powi(5), (a * a) * (a * a) * a);
    if a.powi(2).raw > 2 {
        assert_eq!(a.powi(-2), (a * a).recip());
    }
}

// ------------------------------------------------------------------ value tables
//
// Hand-picked edge cases with their exact expected raw value (computed offline with Python big
// integers): 0, +-1 ULP, +-1/2 (the tie), +-1, +-1.5, MIN, MAX and the negative operands that
// distinguish floor from truncation. Random operands of every magnitude are the job of
// `golden_fixed.cairo` (generated from glam-rs by `tools/refgen`) and of the fuzz properties
// above; they are deliberately *not* duplicated here, so that the test crate stays within the
// compile budget of CI.

/// `a`, `b`, `floor(a b / 2^32)`.
const MUL: [(i64, i64, i64); 14] = [
    (4294967296, 4294967296, 4294967296), (2147483648, 2147483648, 1073741824),
    (-1, 2147483648, -1), (1, 2147483648, 0),
    (9223372036854775807, 4294967296, 9223372036854775807),
    (-9223372036854775808, 4294967296, -9223372036854775808), (12345, -12345, -1),
    (6442450944, -2147483648, -3221225472), (4294967297, 4294967296, 4294967297),
    (9223372036854775807, -4294967296, -9223372036854775807), (0, -9223372036854775808, 0),
    (-1, -1, 0), (1, -1, -1), (2147483648, -2147483648, -1073741824),
];

#[test]
fn test_mul_table() {
    for case in MUL.span() {
        let (a, b, want) = *case;
        let got = (f(a) * f(b)).raw;
        assert!(got == want, "{} * {} = {} expected {}", a, b, got, want);
    }
}

/// `a`, `b`, `round_half_even(a 2^32 / b)`, `a - b trunc(a / b)`: the quotient to nearest (ties to
/// even), the remainder of the truncated division (exact, like Rust's float `%`).
const DIV_REM: [(i64, i64, i64, i64); 13] = [
    (4294967296, 8589934592, 2147483648, 4294967296),
    (-4294967296, 12884901888, -1431655765, -4294967296),
    (9223372036854775807, 4294967296, 9223372036854775807, 4294967295),
    (-9223372036854775808, 4294967296, -9223372036854775808, 0), (1, 8589934592, 0, 1),
    (-1, 8589934592, 0, -1), (6442450944, -2147483648, -12884901888, 0),
    (9223372036854775807, -9223372036854775808, -4294967296, 9223372036854775807),
    (-9223372036854775808, 9223372036854775807, -4294967296, -1), (12345, -7, -7574481609874, 4),
    (6442450944, 6442450944, 4294967296, 0), (0, -9223372036854775808, 0, 0),
    (-12345, 7, -7574481609874, -4),
];

#[test]
fn test_div_rem_table() {
    for case in DIV_REM.span() {
        let (a, b, q, r) = *case;
        let (gq, gr) = ((f(a) / f(b)).raw, (f(a) % f(b)).raw);
        assert!(gq == q, "{} / {} = {} expected {}", a, b, gq, q);
        assert!(gr == r, "{} % {} = {} expected {}", a, b, gr, r);
    }
}

/// `a`, `b`, `div_euclid`, `rem_euclid`: the quotient floors, the remainder is in `[0, |b|)`.
const EUCLID: [(i64, i64, i64, i64); 13] = [
    (4294967296, 8589934592, 0, 4294967296), (-4294967296, 8589934592, -4294967296, 4294967296),
    (6442450944, 4294967296, 4294967296, 2147483648),
    (-6442450944, 4294967296, -8589934592, 2147483648),
    (-6442450944, -4294967296, 8589934592, 2147483648),
    (9223372036854775807, 4294967296, 9223372032559808512, 4294967295),
    (-9223372036854775808, 4294967296, -9223372036854775808, 0), (12345, -7, -7572027342848, 4),
    (0, -9223372036854775808, 0, 0),
    (9223372036854775807, -9223372036854775808, 0, 9223372036854775807),
    (-9223372036854775808, 9223372036854775807, -8589934592, 9223372036854775806),
    (-1, 4294967296, -4294967296, 4294967295), (1, -4294967296, 0, 1),
];

#[test]
fn test_euclid_table() {
    for case in EUCLID.span() {
        let (a, b, q, r) = *case;
        let (gq, gr) = (f(a).div_euclid(f(b)).raw, f(a).rem_euclid(f(b)).raw);
        assert!(gq == q, "div_euclid({} {}) = {} expected {}", a, b, gq, q);
        assert!(gr == r, "rem_euclid({} {}) = {} expected {}", a, b, gr, r);
        // a = b * div_euclid + rem_euclid, exactly
        assert!(gr >= 0, "rem_euclid({} {}) is negative", a, b);
    }
}

/// `a`, `floor`, `ceil`, `round` (half away from zero), `trunc`, `fract` (truncated),
/// `fract_gl` (floored), `to_int`, `to_int_trunc`, `to_int_round`. The three integer columns are
/// widened to `i64` so that one table drives all ten functions.
const ROUND: [(i64, i64, i64, i64, i64, i64, i64, i64, i64, i64); 16] = [
    (0, 0, 0, 0, 0, 0, 0, 0, 0, 0), (1, 0, 4294967296, 0, 0, 1, 1, 0, 0, 0),
    (-1, -4294967296, 0, 0, 0, -1, 4294967295, -1, 0, 0),
    (2147483647, 0, 4294967296, 0, 0, 2147483647, 2147483647, 0, 0, 0),
    (2147483648, 0, 4294967296, 4294967296, 0, 2147483648, 2147483648, 0, 0, 1),
    (-2147483648, -4294967296, 0, -4294967296, 0, -2147483648, 2147483648, -1, 0, -1),
    (4294967296, 4294967296, 4294967296, 4294967296, 4294967296, 0, 0, 1, 1, 1),
    (-4294967296, -4294967296, -4294967296, -4294967296, -4294967296, 0, 0, -1, -1, -1),
    (6442450944, 4294967296, 8589934592, 8589934592, 4294967296, 2147483648, 2147483648, 1, 1, 2),
    (
        -6442450944,
        -8589934592,
        -4294967296,
        -8589934592,
        -4294967296,
        -2147483648,
        2147483648,
        -2,
        -1,
        -2,
    ),
    (12345, 0, 4294967296, 0, 0, 12345, 12345, 0, 0, 0),
    (-12345, -4294967296, 0, 0, 0, -12345, 4294954951, -1, 0, 0),
    (
        -9223372036854775808,
        -9223372036854775808,
        -9223372036854775808,
        -9223372036854775808,
        -9223372036854775808,
        0,
        0,
        -2147483648,
        -2147483648,
        -2147483648,
    ),
    (4294967297, 4294967296, 8589934592, 4294967296, 4294967296, 1, 1, 1, 1, 1),
    (-4294967297, -8589934592, -4294967296, -4294967296, -4294967296, -1, 4294967295, -2, -1, -1),
    (
        9223372032559808512,
        9223372032559808512,
        9223372032559808512,
        9223372032559808512,
        9223372032559808512,
        0,
        0,
        2147483647,
        2147483647,
        2147483647,
    ),
];

#[test]
fn test_rounding_table() {
    for case in ROUND.span() {
        let (a, fl, ce, ro, tr, fr, fg, ti, tt, tro) = *case;
        let x = f(a);
        assert!(x.floor().raw == fl, "floor({}) = {} expected {}", a, x.floor().raw, fl);
        assert!(x.ceil().raw == ce, "ceil({}) = {} expected {}", a, x.ceil().raw, ce);
        assert!(x.round().raw == ro, "round({}) = {} expected {}", a, x.round().raw, ro);
        assert!(x.trunc().raw == tr, "trunc({}) = {} expected {}", a, x.trunc().raw, tr);
        assert!(x.fract().raw == fr, "fract({}) = {} expected {}", a, x.fract().raw, fr);
        assert!(x.fract_gl().raw == fg, "fract_gl({}) = {} expected {}", a, x.fract_gl().raw, fg);
        let (gi, gt, gr): (i64, i64, i64) = (
            x.to_int().into(), x.to_int_trunc().into(), x.to_int_round().into(),
        );
        assert!(gi == ti, "to_int({}) = {} expected {}", a, gi, ti);
        assert!(gt == tt, "to_int_trunc({}) = {} expected {}", a, gt, tt);
        assert!(gr == tro, "to_int_round({}) = {} expected {}", a, gr, tro);
        // the identities that tie the family together
        assert!(x.fract() == x - x.trunc() && x.fract_gl() == x - x.floor(), "fract({})", a);
    }
}

/// `a`, `round_half_even(2^64 / a)`: the reciprocal rounds like `/`.
const RECIP: [(i64, i64); 14] = [
    (3, 6148914691236517205), (-3, -6148914691236517205), (12345, 1494268454735484),
    (-12345, -1494268454735484), (2147483647, 8589934596), (2147483648, 8589934592),
    (-2147483648, -8589934592), (4294967296, 4294967296), (-4294967296, -4294967296),
    (6442450944, 2863311531), (-6442450944, -2863311531), (9223372036854775807, 2),
    (-9223372036854775808, -2), (4294967297, 4294967295),
];

#[test]
fn test_recip_table() {
    for case in RECIP.span() {
        let (a, want) = *case;
        let got = f(a).recip().raw;
        assert!(got == want, "recip({}) = {} expected {}", a, got, want);
    }
}

/// `a`, `isqrt(a 2^32)`: the raw square root of a raw Q32.32 value, floored.
const SQRT: [(i64, i64); 13] = [
    (0, 0), (1, 65536), (2, 92681), (3, 113511), (2147483647, 3037000499), (2147483648, 3037000499),
    (4294967296, 4294967296), (6442450944, 5260239168), (8589934592, 6074000999), (12345, 7281577),
    (9223372036854775807, 199032864766430), (4294967297, 4294967296), (17179869184, 8589934592),
];

#[test]
fn test_sqrt_table() {
    for case in SQRT.span() {
        let (a, want) = *case;
        let got = f(a).sqrt().raw;
        assert!(got == want, "sqrt({}) = {} expected {}", a, got, want);
        // floor: want^2 <= a 2^32 < (want + 1)^2
        let (w, x): (i128, i128) = (want.into(), a.into());
        assert!(w * w <= x * ONE_I128 && x * ONE_I128 < (w + 1) * (w + 1), "sqrt({}) floor", a);
    }
}

/// `a`, `b`, `|a|`, `signum(a)` (`+1` at zero), `copysign(a, b)` (zero counts as positive).
const SIGN: [(i64, i64, i64, i64, i64); 11] = [
    (0, 4294967296, 0, 4294967296, 0), (1, -1, 1, 4294967296, -1), (-1, 1, 1, -4294967296, 1),
    (2147483648, -2147483648, 2147483648, 4294967296, -2147483648),
    (
        9223372036854775807,
        -9223372036854775808,
        9223372036854775807,
        4294967296,
        -9223372036854775807,
    ),
    (
        -9223372036854775807,
        9223372036854775807,
        9223372036854775807,
        -4294967296,
        9223372036854775807,
    ),
    (12345, 0, 12345, 4294967296, 12345), (-12345, -1, 12345, -4294967296, -12345),
    (4294967296, 4294967296, 4294967296, 4294967296, 4294967296),
    (-4294967296, 0, 4294967296, -4294967296, 4294967296),
    (9223372036854775807, 0, 9223372036854775807, 4294967296, 9223372036854775807),
];

#[test]
fn test_sign_table() {
    for case in SIGN.span() {
        let (a, b, ab, sg, cs) = *case;
        assert!(f(a).abs().raw == ab, "abs({}) = {} expected {}", a, f(a).abs().raw, ab);
        assert!(f(a).signum().raw == sg, "signum({})", a);
        let got = f(a).copysign(f(b)).raw;
        assert!(got == cs, "copysign({} {}) = {} expected {}", a, b, got, cs);
    }
}

/// `a`, `b`, `min`, `max`, `step(a, b)` (`1` when `b >= a`), `saturate(a)` (clamp to `[0, 1]`).
const SELECT: [(i64, i64, i64, i64, i64, i64); 10] = [
    (0, 0, 0, 0, 4294967296, 0), (1, -1, -1, 1, 0, 1), (-1, 1, -1, 1, 4294967296, 0),
    (
        9223372036854775807,
        -9223372036854775808,
        -9223372036854775808,
        9223372036854775807,
        0,
        4294967296,
    ),
    (
        -9223372036854775808,
        9223372036854775807,
        -9223372036854775808,
        9223372036854775807,
        4294967296,
        0,
    ),
    (2147483648, 4294967296, 2147483648, 4294967296, 4294967296, 2147483648),
    (4294967296, 2147483648, 2147483648, 4294967296, 0, 4294967296),
    (-4294967296, -4294967296, -4294967296, -4294967296, 4294967296, 0),
    (12345, 12345, 12345, 12345, 4294967296, 12345),
    (6442450944, 4294967296, 4294967296, 6442450944, 0, 4294967296),
];

#[test]
fn test_select_table() {
    for case in SELECT.span() {
        let (a, b, mn, mx, st, sa) = *case;
        assert!(f(a).min(f(b)).raw == mn, "min({} {})", a, b);
        assert!(f(a).max(f(b)).raw == mx, "max({} {})", a, b);
        assert!(f(a).step(f(b)).raw == st, "step({} {})", a, b);
        assert!(f(a).saturate().raw == sa, "saturate({})", a);
    }
}

/// `a`, `min`, `max`, `clamp(a, min, max)` (the precondition `min <= max` holds in every row).
const CLAMP: [(i64, i64, i64, i64); 9] = [
    (0, 0, 4294967296, 0), (-1, 0, 4294967296, 0), (8589934592, 0, 4294967296, 4294967296),
    (2147483648, 0, 4294967296, 2147483648),
    (-9223372036854775808, -4294967296, 4294967296, -4294967296),
    (9223372036854775807, -4294967296, 4294967296, 4294967296), (5, 5, 5, 5),
    (-12345, -9223372036854775808, 9223372036854775807, -12345),
    (4294967296, 4294967296, 4294967296, 4294967296),
];

#[test]
fn test_clamp_table() {
    for case in CLAMP.span() {
        let (a, lo, hi, want) = *case;
        let got = f(a).clamp(f(lo), f(hi)).raw;
        assert!(got == want, "clamp({} {} {}) = {} expected {}", a, lo, hi, got, want);
    }
}

/// `a`, `b`, `c`, `mul_add(a, b, c) = floor((a b + c 2^32) / 2^32)`,
/// `lerp(a, b, c) = floor((a 2^32 + (b - a) c) / 2^32)`: one rescale each, floored.
const FUSED: [(i64, i64, i64, i64, i64); 13] = [
    (12884901888, 17179869184, 21474836480, 73014444032, 34359738368),
    (4294967296, 4294967296, 0, 4294967296, 4294967296), (-1, 2147483648, 0, -1, -1),
    (1, 2147483648, 0, 0, 1), (0, -9223372036854775808, 0, 0, 0),
    (2147483648, 2147483648, -4294967296, -3221225472, 2147483648),
    (9223372036854775807, 4294967296, 0, 9223372036854775807, 9223372036854775807),
    (-9223372036854775808, 4294967296, 0, -9223372036854775808, -9223372036854775808),
    (12345, -12345, 4294967296, 4294967295, -12345),
    (6442450944, -2147483648, 6442450944, 3221225472, -6442450944),
    (0, 0, 9223372036854775807, 9223372036854775807, 0),
    (0, 0, -9223372036854775808, -9223372036854775808, 0),
    (-4294967296, -4294967296, -4294967296, 0, -4294967296),
];

#[test]
fn test_fused_table() {
    for case in FUSED.span() {
        let (a, b, c, ma, lp) = *case;
        let got = f(a).mul_add(f(b), f(c)).raw;
        assert!(got == ma, "mul_add({} {} {}) = {} expected {}", a, b, c, got, ma);
        let got = f(a).lerp(f(b), f(c)).raw;
        assert!(got == lp, "lerp({} {} {}) = {} expected {}", a, b, c, got, lp);
    }
}

/// `x`, `edge0`, `edge1`, `smoothstep = floor(t^2 (3 - 2 t))` with `t` the saturated
/// `(x - edge0) / (edge1 - edge0)`, evaluated at the Q96.96 scale with a single rescale.
const SMOOTHSTEP: [(i64, i64, i64, i64); 9] = [
    (0, 0, 4294967296, 0), (4294967296, 0, 4294967296, 4294967296),
    (2147483648, 0, 4294967296, 2147483648), (-4294967296, 0, 4294967296, 0),
    (8589934592, 0, 4294967296, 4294967296), (1073741824, 0, 4294967296, 671088640),
    (4294967296, 8589934592, 0, 2147483648), (12884901888, 4294967296, 21474836480, 2147483648),
    (0, -4294967296, 4294967296, 2147483648),
];

#[test]
fn test_smoothstep_table() {
    for case in SMOOTHSTEP.span() {
        let (x, e0, e1, want) = *case;
        let got = f(x).smoothstep(f(e0), f(e1)).raw;
        assert!(got == want, "smoothstep({} {} {}) = {} expected {}", x, e0, e1, got, want);
    }
}

/// `a`, `b`, `v`, `inverse_lerp(a, b, v) = (v - a) / (b - a)` (truncated, like `/`).
const INVERSE_LERP: [(i64, i64, i64, i64); 8] = [
    (0, 4294967296, 0, 0), (0, 4294967296, 4294967296, 4294967296),
    (0, 4294967296, 2147483648, 2147483648), (4294967296, 8589934592, 6442450944, 2147483648),
    (-4294967296, 4294967296, 0, 2147483648), (8589934592, 0, 2147483648, 3221225472),
    (0, 4294967296, -4294967296, -4294967296), (4294967296, -4294967296, 0, 2147483648),
];

#[test]
fn test_inverse_lerp_table() {
    for case in INVERSE_LERP.span() {
        let (a, b, v, want) = *case;
        let got = FixedTrait::inverse_lerp(f(a), f(b), f(v)).raw;
        assert!(got == want, "inverse_lerp({} {} {}) = {} expected {}", a, b, v, got, want);
    }
}

/// `x`, `in_start`, `in_end`, `out_start`, `out_end`, `remap = lerp(out, inverse_lerp(in, x))`.
const REMAP: [(i64, i64, i64, i64, i64, i64); 6] = [
    (0, 0, 4294967296, 0, 42949672960, 0), (2147483648, 0, 4294967296, 0, 42949672960, 21474836480),
    (4294967296, 0, 4294967296, -4294967296, 4294967296, 4294967296),
    (0, 0, 4294967296, -4294967296, 4294967296, -4294967296),
    (12884901888, 4294967296, 21474836480, 0, 4294967296, 2147483648),
    (-4294967296, 0, 4294967296, 0, 4294967296, -4294967296),
];

#[test]
fn test_remap_table() {
    for case in REMAP.span() {
        let (x, i0, i1, o0, o1, want) = *case;
        let got = f(x).remap(f(i0), f(i1), f(o0), f(o1)).raw;
        assert!(
            got == want, "remap({} {} {} {} {}) = {} expected {}", x, i0, i1, o0, o1, got, want,
        );
    }
}

/// `self`, `rhs`, `d`, `move_towards`: `self` stepped by at most `d`, never past `rhs`.
const MOVE_TOWARDS: [(i64, i64, i64, i64); 9] = [
    (0, 4294967296, 2147483648, 2147483648), (0, 4294967296, 8589934592, 4294967296),
    (4294967296, 0, 2147483648, 2147483648), (4294967296, 0, 8589934592, 0),
    (0, -4294967296, 2147483648, -2147483648), (-4294967296, 4294967296, 0, -4294967296),
    (5, 5, 0, 5), (0, 4294967296, 0, 0), (-4294967296, -8589934592, 2147483648, -6442450944),
];

#[test]
fn test_move_towards_table() {
    for case in MOVE_TOWARDS.span() {
        let (s, r, d, want) = *case;
        let got = f(s).move_towards(f(r), f(d)).raw;
        assert!(got == want, "move_towards({} {} {}) = {} expected {}", s, r, d, got, want);
    }
}

/// `a`, `n`, `a^n`: `n = 0..4` are unrolled, `|n| >= 5` goes through binary exponentiation,
/// `n < 0` takes the reciprocal of the positive power. Every product floors.
const POWI: [(i64, i32, i64); 15] = [
    (6442450944, 0, 4294967296), (6442450944, 1, 6442450944), (6442450944, 2, 9663676416),
    (6442450944, 3, 14495514624), (6442450944, 4, 21743271936), (6442450944, 5, 32614907904),
    (4294967296, 100, 4294967296), (2147483648, 3, 536870912), (-6442450944, 3, -14495514624),
    (2147483648, -2, 17179869184), (4294967296, -1, 4294967296), (8589934592, 10, 4398046511104),
    (-4294967296, 7, -4294967296), (0, 5, 0), (8589934592, -3, 536870912),
];

#[test]
fn test_powi_table() {
    for case in POWI.span() {
        let (a, n, want) = *case;
        let got = f(a).powi(n).raw;
        assert!(got == want, "powi({} {}) = {} expected {}", a, n, got, want);
    }
}

/// `num`, `den`, `from_ratio = trunc(num 2^32 / den)`: plain integers, not raw values.
const FROM_RATIO: [(i64, i64, i64); 12] = [
    (1, 3, 1431655765), (-1, 3, -1431655765), (1, -3, -1431655765), (-1, -3, 1431655765),
    (7, 2, 15032385536), (0, 5, 0), (2147483647, 1, 9223372032559808512),
    (-2147483648, 1, -9223372036854775808), (5, 4294967296, 5),
    (9223372036854775807, 9223372036854775807, 4294967296),
    (-9223372036854775808, -9223372036854775808, 4294967296), (-7, 2, -15032385536),
];

#[test]
fn test_from_ratio_table() {
    for case in FROM_RATIO.span() {
        let (n, d, want) = *case;
        let got = FixedTrait::from_ratio(n, d).raw;
        assert!(got == want, "from_ratio({} {}) = {} expected {}", n, d, got, want);
    }
}

/// `a`, `b`, `max_abs_diff`, `|a - b| <= max_abs_diff`. The difference is exact on 65 bits, so
/// `MAX` against `MIN` does not overflow, it simply exceeds every threshold.
const ABS_DIFF_EQ: [(i64, i64, i64, bool); 11] = [
    (0, 0, 0, true), (1, 0, 0, false), (1, 0, 1, true),
    (9223372036854775807, -9223372036854775808, 9223372036854775807, false),
    (-9223372036854775808, -9223372036854775808, 0, true), (4294967296, 4294967297, 1, true),
    (-1, 1, 1, false), (-1, 1, 2, true), (0, -1, 0, false), (5, 5, -1, false),
    (9223372036854775807, 9223372036854775807, 0, true),
];

#[test]
fn test_abs_diff_eq_table() {
    for case in ABS_DIFF_EQ.span() {
        let (a, b, m, want) = *case;
        let got = f(a).abs_diff_eq(f(b), f(m));
        assert!(got == want, "abs_diff_eq({} {} {}) = {} expected {}", a, b, m, got, want);
        assert!(f(b).abs_diff_eq(f(a), f(m)) == want, "abs_diff_eq is symmetric");
    }
}
