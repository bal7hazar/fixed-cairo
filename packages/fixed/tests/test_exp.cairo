//! Tests of `fixed::exp`.
//!
//! Four layers: the exact identities (which the implementation guarantees by construction), one
//! compact `*_table` test per function, the edge cases and every panic path with its exact
//! message, and six seeded fuzz properties.
//!
//! The expected values of the tables are produced by `scripts/gen_exp.py tables`, whose Python
//! mirror reproduces the Cairo code operation by operation; the mirror itself is swept against
//! 50-digit references by `scripts/gen_exp.py sweep` (max 2.02 ULP for `exp2` / `exp` below
//! `2^16`, `7.2e-6 * 2^-30` relative above, 0.75 ULP for `log2`, 0.66 for `ln`). The tables
//! therefore pin the **bit-exact** results - they are API, a change of any of them is a breaking
//! change - while the sweep is what proves them correct. The tolerances used by the property
//! tests below are derived from those figures.
use fixed::exp::ExpTrait;
use fixed::fixed::{E, EPSILON, LN_2, MAX, MIN};
use fixed::{Fixed, FixedTrait, HALF, ONE, TWO, ZERO};

const ONE_RAW: i64 = 0x100000000;
/// The generated thresholds (see `fixed::exp`): the first input of `exp2` / `exp` that
/// overflows, and the first input of `exp` that does not flush to zero.
const EXP2_MAX_RAW: i64 = 0x1f00000000;
const EXP_MAX_RAW: i64 = 0x157cd0e703;
const EXP_MIN_RAW: i64 = -0x16dfb516f2;

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

/// `|x|` as an `i128`.
fn mag(x: Fixed) -> i128 {
    let v: i128 = x.raw.into();
    if v < 0 {
        -v
    } else {
        v
    }
}

// ------------------------------------------------------------------ exact identities

#[test]
fn test_exact_identities() {
    assert_eq!(ZERO.exp(), ONE);
    assert_eq!(ZERO.exp2(), ONE);
    assert_eq!(ZERO.exp_m1(), ZERO);
    assert_eq!(ONE.ln(), ZERO);
    assert_eq!(ONE.log2(), ZERO);
    assert_eq!(ONE.log10(), ZERO);
    assert_eq!(ZERO.ln_1p(), ZERO);
    assert_eq!(ONE.exp2(), TWO);
    assert_eq!((-ONE).exp2(), HALF);
    assert_eq!(TWO.log2(), ONE);
    assert_eq!(HALF.log2(), -ONE);
    // ln(2) and e agree with the constants of `fixed::fixed` (rounded to nearest there).
    assert_eq!(TWO.ln(), LN_2);
    assert_eq!(E.ln(), ONE);
    assert_eq!(f(10 * ONE_RAW).log10(), ONE);
    assert_eq!(f(100 * ONE_RAW + 7).log10(), TWO);
    // powf: 0^0 = 1, 0^n = 0, x^0 = 1, 1^n = 1, like Rust.
    assert_eq!(ZERO.powf(ZERO), ONE);
    assert_eq!(ZERO.powf(HALF), ZERO);
    assert_eq!(f(5 * ONE_RAW).powf(ZERO), ONE);
    assert_eq!(MAX.powf(ZERO), ONE);
    assert_eq!(ONE.powf(f(12345)), ONE);
    assert_eq!(ONE.powf(MAX), ONE);
    assert_eq!(f(8 * ONE_RAW).log(TWO), f(3 * ONE_RAW));
    assert_eq!(f(3 * ONE_RAW).log(f(3 * ONE_RAW)), ONE);
}

/// `exp2(k) = 2^k` and `log2(2^k) = k` for every integer `k` of the range, by construction (the
/// polynomials are pinned at the start of their segment and the table holds the exact powers).
#[test]
fn test_powers_of_two_are_exact() {
    let mut k: i64 = -32;
    let mut p: i64 = 1; // 2^k in raw units
    while k <= 30 {
        assert_eq!(f(k * ONE_RAW).exp2(), f(p));
        assert_eq!(f(p).log2(), f(k * ONE_RAW));
        k += 1;
        if k <= 30 {
            p *= 2;
        }
    }
}

/// Monotonicity around the seams of the table of `exp2` (every `1/16`) and of the segments of
/// `log2` (every `1/32` of an octave), where a rounding artefact would show first; the generator
/// checks every seam of the mirror, this pins a sample in Cairo.
#[test]
fn test_monotone_across_seams() {
    for seam in [-0x1e00000000_i64, -0x10000000, 0, 0x10000000, 0x3f0000000, 0x1ef0000000].span() {
        let mut prev = f(*seam - 3).exp2();
        let mut d: i64 = -2;
        while d <= 3 {
            let cur = f(*seam + d).exp2();
            assert!(cur >= prev, "exp2 at seam {} + {}", seam, d);
            prev = cur;
            d += 1;
        }
    }
    for seam in [0x100000000_i64, 0x108000000, 0x1f8000000, 0x7c0000000000, 0x4000000000000000]
        .span() {
        let mut prev = f(*seam - 3).log2();
        let mut d: i64 = -2;
        while d <= 3 {
            let cur = f(*seam + d).log2();
            assert!(cur >= prev, "log2 at seam {} + {}", seam, d);
            prev = cur;
            d += 1;
        }
    }
}

// ------------------------------------------------------------------ tables

/// `(x, exp2(x))`, raw values.
const EXP2: [(i64, i64); 18] = [
    (0x0, 0x100000000), (0x1, 0x100000000), (-0x1, 0xffffffff), (0x100000000, 0x200000000),
    (-0x100000000, 0x80000000), (0x80000000, 0x16a09e667), (-0x80000000, 0xb504f333),
    (0x355555555, 0xa14517cc4), (0xa00000000, 0x40000000000), (-0xa00000000, 0x400000),
    (0x1000003039, 0x10000216ce914), (0x1e00000000, 0x4000000000000000),
    (0x1effffffff, 0x7fffffffa746f2f4), (-0x2000000000, 0x1), (-0x2100000000, 0x0),
    (-0x2100000001, 0x0), (0x75bcd15, 0x10526d8a4), (-0x3ade68b1, 0xda47fa21),
];

#[test]
fn test_exp2_table() {
    for case in EXP2.span() {
        let (x, e) = *case;
        assert_eq!(f(x).exp2(), f(e), "exp2({})", x);
    }
}

/// `(x, exp(x), exp_m1(x))`, raw values.
const EXP: [(i64, i64, i64); 17] = [
    (0x0, 0x100000000, 0x0), (0x1, 0x100000000, 0x0), (-0x1, 0xfffffffe, -0x2),
    (0x100000000, 0x2b7e15162, 0x1b7e15162), (-0x100000000, 0x5e2d58d7, -0xa1d2a729),
    (0x80000000, 0x1a61298e1, 0xa61298e1), (0x200000000, 0x763992e34, 0x663992e34),
    (-0x200000000, 0x22a55546, -0xdd5aaaba), (0xa00000000, 0x560a773e5414, 0x5609773e5414),
    (-0xa00000000, 0x2f9ae, -0xfffd0652), (0x1400000000, 0x1ceb088b68e80335, 0x1ceb088a68e80335),
    (0x157cd0e702, 0x7fffffffcbf01d51, 0x7ffffffecbf01d51), (-0x16dfb516f2, 0x0, -0x100000000),
    (-0x16dfb516f3, 0x0, -0x100000000), (-0x1600000000, 0x1, -0xffffffff),
    (0x75bcd15, 0x10777230a, 0x777230a), (-0x3ade68b1, 0xcb68d5da, -0x34972a26),
];

#[test]
fn test_exp_table() {
    for case in EXP.span() {
        let (x, e, em1) = *case;
        assert_eq!(f(x).exp(), f(e), "exp({})", x);
        assert_eq!(f(x).exp_m1(), f(em1), "exp_m1({})", x);
    }
}

/// `(x, log2(x), ln(x), log10(x))`, raw values.
const LOGS: [(i64, i64, i64, i64); 16] = [
    (0x1, -0x2000000000, -0x162e42fefa, -0x9a209a850),
    (0x2, -0x1f00000000, -0x157cd0e702, -0x954f95b0d),
    (0x3, -0x1e6a3fe5c6, -0x151504574f, -0x927e509f6),
    (0x3039, -0x12688a5514, -0xcc27beba3, -0x58a9db276),
    (0x55555555, -0x195c01a3b, -0x1193ea7ac, -0x7a249e5a),
    (0x80000000, -0x100000000, -0xb17217f8, -0x4d104d42), (0xffffffff, -0x1, -0x1, 0x0),
    (0x100000000, 0x0, 0x0, 0x0), (0x100000001, 0x1, 0x1, 0x0),
    (0x200000000, 0x100000000, 0xb17217f8, 0x4d104d42),
    (0x300000000, 0x195c01a3a, 0x1193ea7ab, 0x7a249e59),
    (0xa00000000, 0x35269e12f, 0x24d763777, 0x100000000),
    (0x2b7e15163, 0x171547653, 0x100000000, 0x6f2dec55),
    (0x6400000007, 0x6a4d3c25f, 0x49aec6eed, 0x200000000),
    (0x4000000000000, 0x1200000000, 0xc7a05af6d, 0x56b256ead),
    (0x7fffffffffffffff, 0x1f00000000, 0x157cd0e702, 0x954f95b0d),
];

#[test]
fn test_log_table() {
    for case in LOGS.span() {
        let (x, l2, l, l10) = *case;
        assert_eq!(f(x).log2(), f(l2), "log2({})", x);
        assert_eq!(f(x).ln(), f(l), "ln({})", x);
        assert_eq!(f(x).log10(), f(l10), "log10({})", x);
    }
}

/// `(x, ln_1p(x))`, raw values.
const LN_1P: [(i64, i64); 7] = [
    (0x0, 0x0), (0x1, 0x1), (-0x1, -0x1), (0x100000000, 0xb17217f8), (-0x80000000, -0xb17217f8),
    (0x418937, 0x4180d5), (0x3e800000000, 0x6e8a42739),
];

#[test]
fn test_ln_1p_table() {
    for case in LN_1P.span() {
        let (x, e) = *case;
        assert_eq!(f(x).ln_1p(), f(e), "ln_1p({})", x);
    }
}

/// `(x, n, powf(x, n))`, raw values.
const POWF: [(i64, i64, i64); 15] = [
    (0x200000000, 0x80000000, 0x16a09e667), (0x200000000, -0x100000000, 0x80000000),
    (0x300000000, 0x200000000, 0x8ffffffff), (0x80000000, 0xa00000000, 0x400000),
    (0xa00000000, 0x340000000, 0x6f247876aeb), (0x100000001, 0x3e800000000, 0x1000003e8),
    (-0x200000000, 0x300000000, -0x800000000), (-0x200000000, -0x200000000, 0x40000000),
    (-0x80000000, 0x500000000, -0x8000000), (0x0, 0x80000000, 0x0), (0x0, 0x0, 0x100000000),
    (0x500000000, 0x0, 0x100000000), (0x40000000, -0x80000000, 0x200000000),
    (0x700000000, 0xb00000000, 0x75db9c9703c73f20), (0x418937, 0x500000000, 0x0),
];

#[test]
fn test_powf_table() {
    for case in POWF.span() {
        let (x, n, e) = *case;
        assert_eq!(f(x).powf(f(n)), f(e), "powf({}, {})", x, n);
    }
}

/// `(x, base, log(x, base))`, raw values.
const LOG_BASE: [(i64, i64, i64); 7] = [
    (0x800000000, 0x200000000, 0x300000000), (0x3e800000000, 0xa00000000, 0x2ffffffff),
    (0x20000000, 0x200000000, -0x300000000), (0x500000000, 0x80000000, -0x25269e12f),
    (0x300000000, 0x300000000, 0x100000000), (0x100000000, 0x700000000, 0x0),
    (0x6400000000, 0x2b7e15163, 0x49aec6eec),
];

#[test]
fn test_log_base_table() {
    for case in LOG_BASE.span() {
        let (x, b, e) = *case;
        assert_eq!(f(x).log(f(b)), f(e), "log({}, {})", x, b);
    }
}

// ------------------------------------------------------------------ edge cases

#[test]
fn test_domain_edges() {
    // The largest inputs that still fit, and the first ones that flush to zero.
    assert_eq!(f(EXP2_MAX_RAW - 1).exp2(), f(0x7fffffffa746f2f4));
    assert_eq!(f(EXP_MAX_RAW - 1).exp(), f(0x7fffffffcbf01d51));
    assert_eq!(f(EXP_MIN_RAW).exp(), ZERO); // e^-22.873 = 0.5 ULP, floored
    assert_eq!(f(EXP_MIN_RAW - 1).exp(), ZERO);
    assert_eq!(MIN.exp(), ZERO);
    assert_eq!(MIN.exp2(), ZERO);
    assert_eq!(MIN.exp_m1(), -ONE);
    assert_eq!(f(-32 * ONE_RAW).exp2(), EPSILON);
    // The extremes of the logarithms: EPSILON = 2^-32 and MAX < 2^31.
    assert_eq!(EPSILON.log2(), f(-32 * ONE_RAW));
    assert_eq!(MAX.log2(), f(31 * ONE_RAW));
    assert!(MAX.ln() > f(21 * ONE_RAW) && MAX.ln() < f(22 * ONE_RAW));
    // EPSILON and MAX as exponents.
    assert_eq!(EPSILON.exp2(), ONE);
    assert_eq!(EPSILON.powf(ONE), EPSILON);
    assert_eq!(MAX.powf(-ONE), f(2)); // 2^-31, floored at 2 ULP
    assert_eq!(f(-3 * ONE_RAW).powf(ZERO), ONE);
}

// ------------------------------------------------------------------ panics

#[test]
#[should_panic(expected: 'Fixed: exp overflow')]
fn test_exp_overflow_panics() {
    f(EXP_MAX_RAW).exp();
}

#[test]
#[should_panic(expected: 'Fixed: exp overflow')]
fn test_exp2_overflow_panics() {
    f(EXP2_MAX_RAW).exp2();
}

#[test]
#[should_panic(expected: 'Fixed: exp overflow')]
fn test_exp2_max_panics() {
    MAX.exp2();
}

#[test]
#[should_panic(expected: 'Fixed: exp overflow')]
fn test_exp_m1_overflow_panics() {
    MAX.exp_m1();
}

#[test]
#[should_panic(expected: 'Fixed: ln domain')]
fn test_ln_zero_panics() {
    ZERO.ln();
}

#[test]
#[should_panic(expected: 'Fixed: ln domain')]
fn test_log2_negative_panics() {
    (-ONE).log2();
}

#[test]
#[should_panic(expected: 'Fixed: ln domain')]
fn test_log10_min_panics() {
    MIN.log10();
}

#[test]
#[should_panic(expected: 'Fixed: ln domain')]
fn test_ln_1p_minus_one_panics() {
    (-ONE).ln_1p();
}

#[test]
#[should_panic(expected: 'i64_add Overflow')]
fn test_ln_1p_overflow_panics() {
    MAX.ln_1p();
}

#[test]
#[should_panic(expected: 'Fixed: ln domain')]
fn test_log_zero_base_panics() {
    TWO.log(ZERO);
}

#[test]
#[should_panic(expected: 'Fixed: ln domain')]
fn test_log_negative_argument_panics() {
    (-TWO).log(TWO);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_log_base_one_panics() {
    TWO.log(ONE);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_log_base_near_one_overflows() {
    MAX.log(f(ONE_RAW + 1));
}

#[test]
#[should_panic(expected: 'Fixed: powf domain')]
fn test_powf_negative_base_fractional_exponent_panics() {
    (-TWO).powf(HALF);
}

#[test]
#[should_panic(expected: 'Fixed: division by zero')]
fn test_powf_zero_negative_exponent_panics() {
    ZERO.powf(-ONE);
}

#[test]
#[should_panic(expected: 'Fixed: overflow')]
fn test_powf_overflow_panics() {
    TWO.powf(f(31 * ONE_RAW));
}

#[test]
#[should_panic(expected: 'i64_neg Underflow')]
fn test_powf_min_base_panics() {
    MIN.powf(ONE);
}

// ------------------------------------------------------------------ properties (seeded fuzzing)

/// Tolerances, from the sweeps of `scripts/gen_exp.py`: `exp2` / `exp` are within 2.02 ULP
/// (floored) plus `7.2e-6 * 2^-30` relative, `log2` within 0.75 ULP. A 0.75 ULP error of the
/// exponent moves `2^t` by `0.52 * 2^-32` relative, hence the `x / 2^31` terms below.
const TOL_EXP: i128 = 3;
const TWO_POW_31: i128 = 0x80000000;
const TWO_POW_40: i128 = 0x10000000000;

#[test]
#[fuzzer(runs: 128, seed: 401)]
fn fuzz_exp2_log2_roundtrip(x: i64) {
    let v = if x > 0 {
        f(x)
    } else if x == 0 {
        EPSILON
    } else {
        f(-(x / 2))
    };
    let l = v.log2();
    assert!(l >= f(-32 * ONE_RAW) && l <= f(31 * ONE_RAW), "log2 range at {}", v.raw);
    if l.raw < EXP2_MAX_RAW {
        let r = l.exp2();
        assert!(diff(r, v) <= mag(v) / TWO_POW_31 + TOL_EXP, "exp2(log2({}))", v.raw);
    }
}

#[test]
#[fuzzer(runs: 128, seed: 402)]
fn fuzz_exp_add(a: i64, b: i64) {
    // a, b in (-10, 10): a + b stays inside the domain.
    let (x, y) = (f(a % (10 * ONE_RAW)), f(b % (10 * ONE_RAW)));
    let (ex, ey, exy) = (x.exp(), y.exp(), (x + y).exp());
    // The product of two results floored within 2.02 ULP (+ one floor for `*`), plus the
    // relative error of `exp(x + y)` itself.
    let tol = (mag(ex) + mag(ey) + ONE_RAW.into()) * TOL_EXP / ONE_RAW.into()
        + mag(exy) / TWO_POW_40
        + TOL_EXP;
    assert!(diff(ex * ey, exy) <= tol, "exp({} + {})", x.raw, y.raw);
    assert_eq!(x.exp_m1(), ex - ONE);
}

#[test]
#[fuzzer(runs: 128, seed: 403)]
fn fuzz_exp_monotone(a: i64, b: i64) {
    let (x, y) = (f(a % (22 * ONE_RAW)), f(b % (22 * ONE_RAW)));
    let (lo, hi) = if x <= y {
        (x, y)
    } else {
        (y, x)
    };
    if hi.raw < EXP_MAX_RAW {
        assert!(lo.exp() <= hi.exp(), "exp not monotone at {}, {}", lo.raw, hi.raw);
    }
    assert!(lo.exp2() <= hi.exp2(), "exp2 not monotone at {}, {}", lo.raw, hi.raw);
    assert!(lo.exp2() >= ZERO && lo.exp() >= ZERO);
}

#[test]
#[fuzzer(runs: 128, seed: 404)]
fn fuzz_log_monotone(a: i64, b: i64) {
    let (x, y) = (f(if a > 0 {
        a
    } else {
        1
    }), f(if b > 0 {
        b
    } else {
        1
    }));
    let (lo, hi) = if x <= y {
        (x, y)
    } else {
        (y, x)
    };
    assert!(lo.ln() <= hi.ln(), "ln not monotone at {}, {}", lo.raw, hi.raw);
    assert!(lo.log2() <= hi.log2(), "log2 not monotone at {}, {}", lo.raw, hi.raw);
    assert!(lo.log10() <= hi.log10(), "log10 not monotone at {}, {}", lo.raw, hi.raw);
    // log(x, 2) agrees with log2 to within the truncation of the division and the rounding of
    // log2 (0.75 + 1 ULP).
    assert!(diff(hi.log(TWO), hi.log2()) <= 2, "log(x, 2) at {}", hi.raw);
}

#[test]
#[fuzzer(runs: 128, seed: 405)]
fn fuzz_powf_integer_exponents(x: i64) {
    // x in [1/256, 256): x^2 < 2^16 and the relative error of powf is below 2^-31 there.
    let v = f(0x1000000 + (if x < 0 {
        -(x / 2)
    } else {
        x
    }) % 0xffff000000);
    let sq = v.powf(TWO);
    assert!(diff(sq, v * v) <= mag(sq) / TWO_POW_31 + TOL_EXP, "powf({}, 2)", v.raw);
    // A negative base with an integer exponent: the sign of powi, the magnitude of |x|^n.
    assert_eq!((-v).powf(TWO), sq);
    assert_eq!((-v).powf(-ONE), -(v.powf(-ONE)));
    assert_eq!(v.powf(ZERO), ONE);
}

#[test]
#[fuzzer(runs: 128, seed: 406)]
fn fuzz_ln_1p_and_scales(x: i64) {
    // ln_1p(x) = ln(x + 1) exactly, for x in (-1, 2^31 - 1).
    let v = f(x % (0x7ffffffe * ONE_RAW));
    let v = if v <= -ONE {
        -(v + ONE)
    } else {
        v
    };
    assert_eq!(v.ln_1p(), (v + ONE).ln());
    // ln and log10 are log2 rescaled: all three are rounded once from the same accumulator.
    let w = v + ONE;
    assert!(diff(w.ln(), w.log2() * LN_2) <= 21, "ln vs log2 at {}", w.raw);
}
