//! Tests of `fixed::trig`.
//!
//! Four layers: the exact identities and the axis values (which the implementation guarantees by
//! construction, not by approximation), one compact `*_table` test per function, the panic paths
//! with their exact messages, and six seeded fuzz properties.
//!
//! The expected values of the tables are produced by `scripts/gen_trig.py tables`, whose Python
//! mirror reproduces the Cairo code operation by operation; the mirror itself is swept against
//! 60-digit references by `scripts/gen_trig.py sweep` (max 1.02 ULP for `sin` / `cos` over a
//! turn, 3.22 ULP for `atan2`, 2.96 ULP for `acos`). The tables therefore pin the **bit-exact**
//! results - they are API, a change of any of them is a breaking change - while the sweep is what
//! proves them correct. The tolerances used by the property tests below are derived from those
//! figures.
use fixed::fixed::{FRAC_PI_2, FRAC_PI_4, MAX, MIN, PI};
use fixed::{Fixed, FixedTrait, ONE, TrigTrait, ZERO};

const FRAC_PI_2_RAW: i64 = 6746518852;
const FRAC_PI_4_RAW: i64 = 3373259426;
const PI_RAW: i64 = 13493037705;
const TAU_RAW: i64 = 26986075409;
const ONE_RAW: i64 = 0x100000000;

fn f(raw: i64) -> Fixed {
    FixedTrait::from_raw(raw)
}

/// `|a - b|` as an `i128`, to express a tolerance in ULP without risking an overflow.
fn diff(a: Fixed, b: Fixed) -> i128 {
    let d: i128 = a.raw.into() - b.raw.into();
    if d < 0 {
        -d
    } else {
        d
    }
}

// ------------------------------------------------------------------ exact identities

#[test]
fn test_exact_identities() {
    assert_eq!(ZERO.sin(), ZERO);
    assert_eq!(ZERO.cos(), ONE);
    assert_eq!(ZERO.tan(), ZERO);
    assert_eq!(FRAC_PI_2.sin(), ONE);
    assert_eq!(FRAC_PI_2.cos(), ZERO);
    // The final rescale of every polynomial rounds to nearest (`docs/DESIGN.md` section 2,
    // second exception), so `sin` and `cos` agree at pi / 4 and their quotient is exactly one.
    assert_eq!(FRAC_PI_4.tan(), ONE);
    assert_eq!((-FRAC_PI_4).tan(), -ONE);
    assert_eq!(FRAC_PI_4.sin(), FRAC_PI_4.cos());
    // The smallest positive angle: sin(2^-32) = 2^-32 and cos(2^-32) = 1, both to the nearest.
    assert_eq!(FixedTrait::from_raw(1).sin(), FixedTrait::from_raw(1));
    assert_eq!(FixedTrait::from_raw(1).cos(), ONE);
    assert_eq!(PI.cos(), -ONE);
    assert_eq!(ZERO.sin_cos(), (ZERO, ONE));
    assert_eq!(FRAC_PI_2.sin_cos(), (ONE, ZERO));
    assert_eq!(ONE.acos(), ZERO);
    assert_eq!(ZERO.acos(), FRAC_PI_2);
    assert_eq!((-ONE).acos(), PI);
    assert_eq!(ZERO.asin(), ZERO);
    assert_eq!(ONE.asin(), FRAC_PI_2);
    assert_eq!((-ONE).asin(), -FRAC_PI_2);
    assert_eq!(ZERO.atan(), ZERO);
    assert_eq!(ONE.atan(), FRAC_PI_4);
    assert_eq!((-ONE).atan(), -FRAC_PI_4);
    assert_eq!(ZERO.to_radians(), ZERO);
    assert_eq!(ZERO.to_degrees(), ZERO);
}

#[test]
fn test_atan2_axes_are_exact() {
    assert_eq!(ZERO.atan2(ZERO), ZERO);
    assert_eq!(ONE.atan2(ZERO), FRAC_PI_2);
    assert_eq!((-ONE).atan2(ZERO), -FRAC_PI_2);
    assert_eq!(MAX.atan2(ZERO), FRAC_PI_2);
    assert_eq!(ZERO.atan2(ONE), ZERO);
    assert_eq!(ZERO.atan2(-ONE), PI);
    assert_eq!(ZERO.atan2(MIN), PI);
    assert_eq!(ONE.atan2(ONE), FRAC_PI_4);
    assert_eq!((-ONE).atan2(ONE), -FRAC_PI_4);
    assert_eq!(MIN.atan2(MIN), -(PI - FRAC_PI_4));
}

/// `sin(-x) = -sin(x)`, `cos(-x) = cos(x)`, `atan(-x) = -atan(x)` and `asin(-x) = -asin(x)` hold
/// for **every** input: the reduction runs on `|x|` and the sign is applied afterwards. This is
/// the property the `fast_cos` of Alexandria gets wrong for negative angles.
const SYMMETRY: [i64; 14] = [
    1, 7, 12345, 0x80000000, ONE_RAW, FRAC_PI_4_RAW, FRAC_PI_2_RAW, PI_RAW, TAU_RAW,
    PI_RAW + FRAC_PI_4_RAW, 1000 * TAU_RAW, 0x10000000000, 0x4000000000000000, 0x7fffffffffffffff,
];

#[test]
fn test_symmetry() {
    for raw in SYMMETRY.span() {
        let x = f(*raw);
        assert!(x.sin() == -(-x).sin(), "sin({})", *raw);
        assert!(x.cos() == (-x).cos(), "cos({})", *raw);
        assert!(x.atan() == -(-x).atan(), "atan({})", *raw);
        let (s, c) = x.sin_cos();
        assert!((s, c) == (x.sin(), x.cos()), "sin_cos({})", *raw);
        let (ns, nc) = (-x).sin_cos();
        assert!((ns, nc) == (-s, c), "sin_cos(-{})", *raw);
    }
    for raw in SYMMETRY.span() {
        let v = *raw % (ONE_RAW + 1);
        let x = f(v);
        assert!(x.asin() == -(-x).asin(), "asin({})", v);
        assert!(x.acos() + (-x).acos() == PI, "acos({})", v);
    }
}

/// `MIN` and `MAX` are reduced like any other angle (`abs` is never taken on the raw value).
#[test]
fn test_extreme_magnitudes() {
    for x in [MIN, MAX, -MAX, f(MIN.raw + 1)].span() {
        let (s, c) = (*x).sin_cos();
        assert!(s.abs() <= ONE && c.abs() <= ONE, "|sin|, |cos| <= 1");
        let n = fixed::wide::norm2_squared(s, c);
        assert!(diff(n, ONE) <= 16, "sin^2 + cos^2 at an extreme magnitude");
        assert!((*x).atan().abs() <= FRAC_PI_2, "|atan| <= pi/2");
    }
    // atan(2^31) = pi/2 - 4.66e-10, i.e. FRAC_PI_2 - 2 ULP once rounded.
    assert_eq!(MAX.atan(), FRAC_PI_2 - f(2));
    assert_eq!(MIN.atan(), -(FRAC_PI_2 - f(2)));
}

/// `sin` increases on `[0, pi/2]`, `cos` decreases, `acos` decreases, `atan` increases.
#[test]
fn test_monotonicity() {
    let mut prev_sin = f(-1);
    let mut prev_cos = f(ONE_RAW + 1);
    let mut i: i64 = 0;
    while i <= 64 {
        let x = f(i * FRAC_PI_2_RAW / 64);
        let (s, c) = x.sin_cos();
        assert!(s >= prev_sin, "sin decreased at {}", i);
        assert!(c <= prev_cos, "cos increased at {}", i);
        prev_sin = s;
        prev_cos = c;
        let y = f(i * ONE_RAW / 64);
        assert!(y.acos() <= (f((i - 1) * ONE_RAW / 64)).acos(), "acos increased at {}", i);
        assert!(y.atan() >= (f((i - 1) * ONE_RAW / 64)).atan(), "atan decreased at {}", i);
        i += 1;
    }
}

// ------------------------------------------------------------------ tables

/// `x`, `sin(x)`, `cos(x)` (raw). Covers 0, +-1 ULP, the octant boundaries, +-PI, +-TAU,
/// `1000 * TAU` and the extremes of the range.
const SIN_COS: [(i64, i64, i64); 25] = [
    (0x0, 0x0, 0x100000000), (0x1, 0x1, 0x100000000), (-0x1, -0x1, 0x100000000),
    (0x100000000, 0xd76aa478, 0x8a51407d), (-0x100000000, -0xd76aa478, 0x8a51407d),
    (0x80000000, 0x7abba1d1, 0xe0a94033), (0xc90fdaa2, 0xb504f334, 0xb504f334),
    (0x1921fb544, 0x100000000, 0x0), (-0x1921fb544, -0x100000000, 0x0),
    (0x3243f6a89, 0x0, -0x100000000), (-0x3243f6a89, 0x0, -0x100000000),
    (0x4b65f1fcd, -0x100000000, 0x0), (0x6487ed511, 0x0, 0x100000000),
    (-0x6487ed511, 0x0, 0x100000000), (0x25b2f8fe6, 0xb504f334, -0xb504f334),
    (0x3ed4f452a, -0xb504f333, -0xb504f335), (0x57f6efa6e, -0xb504f335, 0xb504f333),
    (0x188b2f704a68, -0x2c, 0x100000000), (-0x188b2f704a68, 0x2c, 0x100000000),
    (0x75bcd15, 0x75b8aad, 0xffe4ed69), (-0x3ade68b1, -0x3a59f085, 0xf942daf7),
    (0x10000000000, -0xffcc1904, -0xa2fba2c), (-0x200000000000, 0xf4c7c385, 0x4af50f44),
    (0x4000000000000000, -0x9e091a9c, 0xc965a354), (-0x4000000000000000, 0x9e091a9c, 0xc965a354),
];

#[test]
fn test_sin_cos_table() {
    for case in SIN_COS.span() {
        let (x, s, c) = *case;
        assert!(f(x).sin().raw == s, "sin({}) = {} expected {}", x, f(x).sin().raw, s);
        assert!(f(x).cos().raw == c, "cos({}) = {} expected {}", x, f(x).cos().raw, c);
        assert!(f(x).sin_cos() == (f(s), f(c)), "sin_cos({})", x);
    }
}

/// `x`, `tan(x)` (raw). `tan(PI)` is 1 ULP because `PI` itself is 1.1e-10 past pi.
const TAN: [(i64, i64); 9] = [
    (0x0, 0x0), (0x1, 0x1), (-0x1, -0x1), (0x100000000, 0x18eb245cd), (-0x100000000, -0x18eb245cd),
    (0xc90fdaa2, 0x100000000), (-0xc90fdaa2, -0x100000000), (0x3243f6a89, 0x0),
    (0x55555555, 0x58a41296),
];

#[test]
fn test_tan_table() {
    for case in TAN.span() {
        let (x, want) = *case;
        assert!(f(x).tan().raw == want, "tan({}) = {} expected {}", x, f(x).tan().raw, want);
    }
}

/// `y`, `x`, `atan2(y, x)` (raw): the four quadrants, the axes, the `MIN` magnitudes.
const ATAN2: [(i64, i64, i64); 16] = [
    (0x0, 0x0, 0x0), (0x100000000, 0x0, 0x1921fb544), (-0x100000000, 0x0, -0x1921fb544),
    (0x0, 0x100000000, 0x0), (0x0, -0x100000000, 0x3243f6a89),
    (0x100000000, 0x100000000, 0xc90fdaa2), (0x100000000, -0x100000000, 0x25b2f8fe7),
    (-0x100000000, 0x100000000, -0xc90fdaa2), (-0x100000000, -0x100000000, -0x25b2f8fe7),
    (0x100000000, 0x200000000, 0x76b19c16), (-0x300000000, 0x400000000, -0xa4bc7d19),
    (0x1, 0x100000000, 0x1), (0x100000000, 0x1, 0x1921fb543),
    (0x10000000000, 0x20000000000, 0x76b19c16),
    (-0x4000000000000000, 0x4000000000000000, -0xc90fdaa2), (0x55555555, 0x700000000, 0xc2e6800),
];

#[test]
fn test_atan2_table() {
    for case in ATAN2.span() {
        let (y, x, want) = *case;
        let got = f(y).atan2(f(x)).raw;
        assert!(got == want, "atan2({}, {}) = {} expected {}", y, x, got, want);
    }
}

/// `x`, `atan(x)` (raw).
const ATAN: [(i64, i64); 10] = [
    (0x0, 0x0), (0x1, 0x1), (-0x1, -0x1), (0x100000000, 0xc90fdaa2), (-0x100000000, -0xc90fdaa2),
    (0x80000000, 0x76b19c16), (0x400000000, 0x15368c951), (-0x400000000, -0x15368c951),
    (0x10000000000, 0x1911fb599), (-0x4000000000000000, -0x1921fb540),
];

#[test]
fn test_atan_table() {
    for case in ATAN.span() {
        let (x, want) = *case;
        let got = f(x).atan().raw;
        assert!(got == want, "atan({}) = {} expected {}", x, got, want);
        // atan(x) and atan2(x, 1) agree (the second one divides by 1 first).
        assert!(f(x).atan2(ONE).raw == want, "atan2({}, 1)", x);
    }
}

/// `x`, `acos(x)`, `asin(x)` (raw): the domain bounds, +-1 ULP, the halves, `1/sqrt(2)`.
const ACOS_ASIN: [(i64, i64, i64); 15] = [
    (0x0, 0x1921fb544, 0x0), (0x1, 0x1921fb542, 0x2), (-0x1, 0x1921fb547, -0x2),
    (0x100000000, 0x0, 0x1921fb544), (-0x100000000, 0x3243f6a89, -0x1921fb544),
    (0x80000000, 0x10c152381, 0x860a91c3), (-0x80000000, 0x2182a4708, -0x860a91c3),
    (0x40000000, 0x151700e0b, 0x40afa739), (0xc0000000, 0xb9051c96, 0xd91a98ae),
    (0xffffffff, 0x16a0a, 0x1921e4b3a), (-0xffffffff, 0x3243e007f, -0x1921e4b3a),
    (0xb504f334, 0xc90fdaa1, 0xc90fdaa3), (-0xb504f334, 0x25b2f8fe8, -0xc90fdaa3),
    (0x80000000, 0x10c152381, 0x860a91c3), (0x75bcd15, 0x18ac3a5be, 0x75c0f86),
];

#[test]
fn test_acos_asin_table() {
    for case in ACOS_ASIN.span() {
        let (x, want_acos, want_asin) = *case;
        let (ga, gs) = (f(x).acos().raw, f(x).asin().raw);
        assert!(ga == want_acos, "acos({}) = {} expected {}", x, ga, want_acos);
        assert!(gs == want_asin, "asin({}) = {} expected {}", x, gs, want_asin);
        assert!(f(x).acos_clamped().raw == want_acos, "acos_clamped({})", x);
        assert!(f(x).asin_clamped().raw == want_asin, "asin_clamped({})", x);
    }
}

/// `x`, `to_radians(x)`, `to_degrees(x)` (raw). Both rescale once from a 57-bit constant.
const DEGREES: [(i64, i64, i64); 8] = [
    (0x0, 0x0, 0x0), (0x100000000, 0x477d1a8, 0x394bb834c7),
    (-0x100000000, -0x477d1a9, -0x394bb834c8), (0x5a00000000, 0x1921fb544, 0x14249ec28e24),
    (0xb400000000, 0x3243f6a88, 0x28493d851c48), (-0x2d00000000, -0xc90fdaa3, -0xa124f614713),
    (0x1, 0x0, 0x39), (0x10000000000, 0x477d1a894, 0x394bb834c783),
];

#[test]
fn test_degrees_table() {
    for case in DEGREES.span() {
        let (x, rad, deg) = *case;
        assert!(f(x).to_radians().raw == rad, "to_radians({})", x);
        assert!(f(x).to_degrees().raw == deg, "to_degrees({})", x);
    }
    // 90 degrees is FRAC_PI_2 to the ULP, 180 degrees is PI to the ULP (floor).
    assert_eq!(f(90 * ONE_RAW).to_radians(), FRAC_PI_2);
    assert!(diff(f(180 * ONE_RAW).to_radians(), PI) <= 1);
    // PI is 1.1e-10 above pi, which 180 / pi amplifies to 27 ULP: the conversion is exact, the
    // constant is not.
    assert!(diff(PI.to_degrees(), f(180 * ONE_RAW)) <= 32);
}

/// Outside `[-1, 1]` the clamped variants saturate instead of panicking.
#[test]
fn test_clamped_outside_the_domain() {
    assert_eq!(f(ONE_RAW + 1).acos_clamped(), ZERO);
    assert_eq!(MAX.acos_clamped(), ZERO);
    assert_eq!(MIN.acos_clamped(), PI);
    assert_eq!(f(-ONE_RAW - 1).asin_clamped(), -FRAC_PI_2);
    assert_eq!(MAX.asin_clamped(), FRAC_PI_2);
}

// ------------------------------------------------------------------ panics

#[test]
#[should_panic(expected: 'Fixed: acos domain')]
fn test_acos_above_one_panics() {
    ZERO.sin_cos(); // keeps the test non-constant
    f(ONE_RAW + 1).acos();
}

#[test]
#[should_panic(expected: 'Fixed: acos domain')]
fn test_acos_below_minus_one_panics() {
    f(-ONE_RAW - 1).acos();
}

#[test]
#[should_panic(expected: 'Fixed: asin domain')]
fn test_asin_above_one_panics() {
    MAX.asin();
}

#[test]
#[should_panic(expected: 'Fixed: asin domain')]
fn test_asin_below_minus_one_panics() {
    MIN.asin();
}

#[test]
#[should_panic(expected: 'Fixed: tan overflow')]
fn test_tan_at_half_pi_panics() {
    FRAC_PI_2.tan();
}

#[test]
#[should_panic(expected: 'Fixed: tan overflow')]
fn test_tan_at_three_half_pi_panics() {
    f(-3 * FRAC_PI_2_RAW).tan();
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_to_degrees_overflow_panics() {
    MAX.to_degrees();
}

// ------------------------------------------------------------------ properties (seeded fuzzing)

/// Tolerances in ULP, from the sweeps of `scripts/gen_trig.py`: 1.02 for `sin` / `cos`, 3.22 for
/// `atan2`, 3.50 for `acos`. `sin^2 + cos^2` accumulates `2 (|ds| + |dc|) + 1`, rounded up to 16.
const TOL_PYTHAGORAS: i128 = 16;
const TOL_ROUNDTRIP: i128 = 24;

#[test]
#[fuzzer(runs: 128, seed: 301)]
fn fuzz_sin_cos_pythagoras(x: i64) {
    let (s, c) = f(x).sin_cos();
    assert!(s.abs() <= ONE && c.abs() <= ONE, "|sin|, |cos| <= 1 at {}", x);
    let n = fixed::wide::norm2_squared(s, c);
    assert!(diff(n, ONE) <= TOL_PYTHAGORAS, "sin^2 + cos^2 at {} = {}", x, n.raw);
    assert!((s, c) == (f(x).sin(), f(x).cos()), "sin_cos at {}", x);
}

#[test]
#[fuzzer(runs: 128, seed: 302)]
fn fuzz_sin_cos_symmetry_and_period(x: i64) {
    let a = x / 8; // room for +- TAU without overflowing the raw range
    assert_eq!(f(a).sin(), -f(-a).sin());
    assert_eq!(f(a).cos(), f(-a).cos());
    // One turn later the angle is the same to within the ULP of TAU itself.
    assert!(diff(f(a + TAU_RAW).sin(), f(a).sin()) <= TOL_PYTHAGORAS, "sin period at {}", a);
    assert!(diff(f(a + TAU_RAW).cos(), f(a).cos()) <= TOL_PYTHAGORAS, "cos period at {}", a);
}

#[test]
#[fuzzer(runs: 128, seed: 303)]
fn fuzz_atan2_quadrants(y: i64, x: i64) {
    let a = f(y).atan2(f(x));
    assert!(a.abs() <= PI, "|atan2| <= pi at ({}, {})", y, x);
    // The sign of the result follows y, its magnitude follows the half plane of x.
    if y > 0 {
        assert!(a > ZERO, "atan2 sign at ({}, {})", y, x);
    } else if y < 0 {
        assert!(a < ZERO, "atan2 sign at ({}, {})", y, x);
    }
    if x > 0 && y != 0 {
        assert!(a.abs() < FRAC_PI_2, "|atan2| < pi/2 for x > 0");
    } else if x < 0 && y != 0 {
        assert!(a.abs() > FRAC_PI_2, "|atan2| > pi/2 for x < 0");
    }
    assert_eq!(f(-y).atan2(f(x)), -a);
}

#[test]
#[fuzzer(runs: 128, seed: 304)]
fn fuzz_atan2_matches_atan(y: i64) {
    let v = y / 4;
    let a = f(v).atan();
    assert!(a.abs() <= FRAC_PI_2, "|atan| <= pi/2 at {}", v);
    assert_eq!(f(v).atan2(ONE), a);
    // atan(x) = pi/2 - atan(1/x) for a positive x (both sides go through one division).
    if v > 0x10000 {
        let r = ONE / f(v);
        assert!(diff(a + r.atan(), FRAC_PI_2) <= TOL_ROUNDTRIP, "atan reflection at {}", v);
    }
}

#[test]
#[fuzzer(runs: 128, seed: 305)]
fn fuzz_acos_asin_complement(x: i64) {
    let v = f(x % (ONE_RAW + 1));
    let (a, s) = (v.acos(), v.asin());
    assert!(a >= ZERO && a <= PI, "acos range at {}", x);
    assert!(s.abs() <= FRAC_PI_2, "asin range at {}", x);
    // asin + acos = pi/2, to the 1 ULP by which PI and 2 FRAC_PI_2 differ.
    assert!(diff(a + s, FRAC_PI_2) <= 1, "asin + acos at {}", x);
    assert_eq!(v.acos_clamped(), a);
    assert_eq!(v.asin_clamped(), s);
}

#[test]
#[fuzzer(runs: 128, seed: 306)]
fn fuzz_cos_acos_roundtrip(x: i64) {
    let v = f(x % (ONE_RAW + 1));
    assert!(diff(v.acos().cos(), v) <= TOL_ROUNDTRIP, "cos(acos({}))", x);
    assert!(diff(v.asin().sin(), v) <= TOL_ROUNDTRIP, "sin(asin({}))", x);
}
