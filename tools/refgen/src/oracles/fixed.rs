//! Oracles of `fixed::fixed` (scalar tier A). Spec: `specs/fixed.toml`.
//!
//! Every oracle is an **integer oracle**: the Cairo result is exactly defined (floor / trunc /
//! round-half-away of an exact rational, DESIGN section 2), so it is computed on the raw values in
//! `i128` and compared with tolerance 0 over the whole `i64` range, where an f64 would lose up to
//! 2^10 raw ULPs. The Rust semantics the port mirrors (`round` half away from zero,
//! `signum(0) = +1`, `fract = x - trunc(x)`, ...) are pinned against `f64` in `mod tests` below.
//! A `None` from a helper (division by zero, result outside `i64`) skips the case: it is a panic
//! path, tested explicitly with `[[function.panics]]` in the spec.

use crate::prelude::*;

const ONE: i64 = 1 << FRAC_BITS;
const HALF: i128 = 1 << (FRAC_BITS - 1);

fn fit(v: i128) -> Option<i64> {
    i64::try_from(v).ok()
}

/// `Some(raw)` -> the exact result, `None` -> the case is skipped.
fn out(v: Option<i128>) -> Out {
    Out::raw_checked(v.and_then(fit))
}

fn wide(v: &Value) -> i128 {
    i128::from(v.raw())
}

/// `floor(a * b / 2^32)`: what `Fixed * Fixed` returns.
fn mul_raw(a: i64, b: i64) -> Option<i64> {
    fit((i128::from(a) * i128::from(b)) >> FRAC_BITS)
}

/// `trunc(a * 2^32 / b)`: what `Fixed / Fixed` and `from_ratio` return.
fn div_raw(a: i64, b: i64) -> Option<i64> {
    match b {
        0 => None,
        b => fit((i128::from(a) << FRAC_BITS) / i128::from(b)),
    }
}

/// `trunc(2^64 / b)`: what `recip` returns.
fn recip_raw(b: i64) -> Option<i64> {
    match b {
        0 => None,
        b => fit((1i128 << (2 * FRAC_BITS)) / i128::from(b)),
    }
}

/// `floor((a * 2^32 + (b - a) * t) / 2^32)`: what `lerp` returns.
fn lerp_raw(a: i64, b: i64, t: i64) -> Option<i64> {
    let slope = (i128::from(b) - i128::from(a)).checked_mul(i128::from(t))?;
    fit((slope + (i128::from(a) << FRAC_BITS)) >> FRAC_BITS)
}

/// `(v - a) / (b - a)` with the native (checked) subtractions of the Cairo code.
fn inverse_lerp_raw(a: i64, b: i64, v: i64) -> Option<i64> {
    div_raw(v.checked_sub(a)?, b.checked_sub(a)?)
}

/// `x` clamped to `[lo, hi]`, `lo <= hi`.
fn clamp_raw(x: i64, lo: i64, hi: i64) -> i64 {
    x.max(lo).min(hi)
}

/// Round half away from zero, as an integer count (not scaled).
fn round_int(x: i64) -> i128 {
    let x = i128::from(x);
    if x >= 0 {
        (x + HALF) >> FRAC_BITS
    } else {
        -((-x + HALF) >> FRAC_BITS)
    }
}

/// `x - trunc(x)`: keeps the sign of `x`.
fn fract_raw(x: i64) -> i64 {
    (i128::from(x) % i128::from(ONE)) as i64
}

/// `x - floor(x)`: in `[0, 2^32)`.
fn fract_gl_raw(x: i64) -> i64 {
    i128::from(x).rem_euclid(i128::from(ONE)) as i64
}

/// The unrolled and loop `powi` of the port (DESIGN: every product floors, DESIGN section 2):
/// `n = 2, 3`: floor of the exact power; `n = 4`: `floor(floor(x^2)^2)`; `n >= 5`: binary
/// exponentiation, least significant bit first, each product floored.
fn powi_raw(x: i64, n: i32) -> Option<i64> {
    let e = n.unsigned_abs();
    let p = match e {
        0 => ONE,
        1 => x,
        2 => mul_raw(x, x)?,
        3 => {
            let cube = i128::from(x)
                .checked_mul(i128::from(x))?
                .checked_mul(i128::from(x))?;
            fit(cube >> (2 * FRAC_BITS))?
        }
        4 => {
            let x2 = mul_raw(x, x)?;
            mul_raw(x2, x2)?
        }
        _ => {
            let (mut e, mut base, mut acc) = (e, x, ONE);
            while e != 0 {
                if e % 2 == 1 {
                    acc = mul_raw(acc, base)?;
                }
                e /= 2;
                if e != 0 {
                    base = mul_raw(base, base)?;
                }
            }
            acc
        }
    };
    if n < 0 {
        recip_raw(p)
    } else {
        Some(p)
    }
}

/// `floor(t^2 (3 - 2 t))`, `t` in `[0, 1]`, evaluated exactly at the Q96.96 scale.
fn smooth_raw(t: i64) -> i64 {
    let t = i128::from(t);
    ((t * t * (3 * i128::from(ONE) - 2 * t)) >> (2 * FRAC_BITS)) as i64
}

fn smoothstep_raw(x: i64, e0: i64, e1: i64) -> Option<i64> {
    let q = div_raw(x.checked_sub(e0)?, e1.checked_sub(e0)?)?;
    Some(smooth_raw(clamp_raw(q, 0, ONE)))
}

/// The branches of `move_towards`, with the checked native operations of the Cairo code.
fn move_towards_raw(s: i64, rhs: i64, d: i64) -> Option<i64> {
    let a = rhs.checked_sub(s)?;
    if a < 0 {
        if a >= d.checked_neg()? {
            Some(rhs)
        } else {
            s.checked_sub(d)
        }
    } else if a <= d {
        Some(rhs)
    } else {
        s.checked_add(d)
    }
}

/// The euclidean quotient of the raw values as a scaled integer (`q * 2^32`), and the remainder.
fn euclid(a: i64, b: i64) -> Option<(i128, i128)> {
    match i128::from(b) {
        0 => None,
        d => Some((
            i128::from(a).div_euclid(d) << FRAC_BITS,
            i128::from(a).rem_euclid(d),
        )),
    }
}

pub fn register(r: &mut Registry) {
    // --- constructors and conversions -------------------------------------------------------
    r.add("from_raw", |a| Out::raw(a[0].i64()));
    r.add("from_int", |a| Out::raw(i64::from(a[0].i32()) << FRAC_BITS));
    r.add("from_ratio", |a| out(div_raw(a[0].i64(), a[1].i64()).map(i128::from)));
    // (to_int, to_int_trunc): floor and toward zero, both total.
    r.add("to_int_pair", |a| ((a[0].raw() >> FRAC_BITS) as i32, (a[0].raw() / ONE) as i32));
    r.add("to_int_round", |a| match i32::try_from(round_int(a[0].raw())) {
        Ok(v) => Out::from(v),
        Err(_) => Out::raw_checked(None),
    });

    // --- native operators (checked i64 on the raw values) -----------------------------------
    r.add("add", |a| Out::raw_checked(a[0].raw().checked_add(a[1].raw())));
    r.add("sub", |a| Out::raw_checked(a[0].raw().checked_sub(a[1].raw())));
    r.add("neg", |a| Out::raw_checked(a[0].raw().checked_neg()));

    // --- rescaling operators ----------------------------------------------------------------
    r.add("mul", |a| out(mul_raw(a[0].raw(), a[1].raw()).map(i128::from)));
    // (a / b, a % b): truncated quotient and remainder. The remainder is computed in i128:
    // `MIN % -1` is a plain 0 (Rust's i64 overflows).
    r.add("div_rem", |a| match wide(&a[1]) {
        0 => skip("division by zero"),
        d => Out::from((
            out(div_raw(a[0].raw(), a[1].raw()).map(i128::from)),
            Out::raw_wide(wide(&a[0]) % d),
        )),
    });
    r.add("recip", |a| out(recip_raw(a[0].raw()).map(i128::from)));
    r.add("mul_add", |a| {
        Out::raw_wide((wide(&a[0]) * wide(&a[1]) + (wide(&a[2]) << FRAC_BITS)) >> FRAC_BITS)
    });
    r.add("lerp", |a| {
        out(lerp_raw(a[0].raw(), a[1].raw(), a[2].raw()).map(i128::from))
    });
    // `(v - a) / (b - a)`: the call is `inverse_lerp(a, b, v)`.
    r.add("inverse_lerp", |a| {
        out(inverse_lerp_raw(a[0].raw(), a[1].raw(), a[2].raw()).map(i128::from))
    });
    // `x.remap(in_start, in_end, out_start, out_end)` = `out_start.lerp(out_end, t)`.
    r.add("remap", |a| {
        let t = inverse_lerp_raw(a[1].raw(), a[2].raw(), a[0].raw());
        out(t.and_then(|t| lerp_raw(a[3].raw(), a[4].raw(), t)).map(i128::from))
    });
    r.add("powi", |a| out(powi_raw(a[0].raw(), a[1].i32()).map(i128::from)));
    r.add("smoothstep", |a| {
        out(smoothstep_raw(a[0].raw(), a[1].raw(), a[2].raw()).map(i128::from))
    });
    r.add("move_towards", |a| {
        out(move_towards_raw(a[0].raw(), a[1].raw(), a[2].raw()).map(i128::from))
    });

    // --- euclidean division: exact on the raw integers --------------------------------------
    // (div_euclid, rem_euclid): the quotient is an integer returned as a `Fixed` (`q * 2^32`).
    r.add("euclid", |a| match euclid(a[0].raw(), a[1].raw()) {
        Some((q, rem)) => Out::from((Out::raw_wide(q), Out::raw_wide(rem))),
        None => skip("division by zero"),
    });

    // --- sign, min / max, clamp -------------------------------------------------------------
    r.add("abs", |a| Out::raw_checked(a[0].raw().checked_abs()));
    r.add("signum", |a| Out::raw(if a[0].raw() < 0 { -ONE } else { ONE }));
    // |x| with the sign of `s`; zero counts as positive.
    r.add("copysign", |a| {
        let mag = wide(&a[0]).abs();
        Out::raw_wide(if a[1].raw() < 0 { -mag } else { mag })
    });
    r.add("min_max", |a| {
        Out::from((Out::raw(a[0].raw().min(a[1].raw())), Out::raw(a[0].raw().max(a[1].raw()))))
    });
    r.add("clamp", |a| {
        let (x, lo, hi) = (a[0].raw(), a[1].raw(), a[2].raw());
        if lo > hi {
            return skip("clamp: min > max");
        }
        Out::raw(clamp_raw(x, lo, hi))
    });
    r.add("saturate", |a| Out::raw(clamp_raw(a[0].raw(), 0, ONE)));
    // `edge.step(value)`: 0 if value < edge, else 1.
    r.add("step", |a| Out::raw(if a[1].raw() < a[0].raw() { 0 } else { ONE }));

    // --- rounding to integers ---------------------------------------------------------------
    // (floor, trunc): never overflow.
    r.add("floor_trunc", |a| {
        let floor = (wide(&a[0]) >> FRAC_BITS) << FRAC_BITS;
        let trunc = wide(&a[0]) / i128::from(ONE) * i128::from(ONE);
        Out::from((Out::raw_wide(floor), Out::raw_wide(trunc)))
    });
    r.add("ceil", |a| {
        let up = (wide(&a[0]) + i128::from(ONE - 1)) >> FRAC_BITS;
        Out::raw_wide(up << FRAC_BITS)
    });
    r.add("round", |a| Out::raw_wide(round_int(a[0].raw()) << FRAC_BITS));
    // (fract, fract_gl): `x - trunc(x)` and `x - floor(x)`.
    r.add("fract_pair", |a| {
        Out::from((Out::raw(fract_raw(a[0].raw())), Out::raw(fract_gl_raw(a[0].raw()))))
    });

    // --- square root: floor of the exact root of raw * 2^32 ---------------------------------
    r.add("sqrt", |a| match a[0].raw() {
        x if x < 0 => skip("sqrt of a negative number"),
        x => Out::raw_wide(((x as u128) << FRAC_BITS).isqrt() as i128),
    });

    // --- comparisons and approximate equality -----------------------------------------------
    // (lt, le, gt, ge)
    r.add("cmp", |a| {
        let (x, y) = (a[0].raw(), a[1].raw());
        (x < y, x <= y, x > y, x >= y)
    });
    r.add("abs_diff_eq", |a| (wide(&a[0]) - wide(&a[1])).abs() <= wide(&a[2]));
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A spread of raw values: small, around integers and halves, large.
    fn samples() -> Vec<i64> {
        let mut xs = vec![0, 1, -1, 2, -2, ONE, -ONE, ONE / 2, -ONE / 2, ONE + 1, -ONE - 1];
        let mut rng = Rng::from_label("fixed::oracle-tests");
        for _ in 0..2000 {
            let raw = rng.range_i64(-(1 << 52), 1 << 52);
            xs.push(raw);
            xs.push(raw >> rng.below(45));
            xs.push(raw - raw.rem_euclid(ONE / 2));
        }
        xs
    }

    fn f(raw: i64) -> f64 {
        raw_to_f64(raw)
    }

    fn q(x: f64) -> i64 {
        quantize(x).expect("in range")
    }

    /// The integer helpers agree with the f64 (Rust `f32`-like) semantics on exact inputs.
    #[test]
    fn rounding_helpers_match_f64_semantics() {
        for x in samples() {
            let v = f(x);
            assert_eq!(fract_raw(x), q(v.fract()), "fract {x}");
            assert_eq!(fract_gl_raw(x), q(v - v.floor()), "fract_gl {x}");
            assert_eq!(round_int(x) as f64, v.round(), "round {x}");
            assert_eq!(i128::from(x) >> FRAC_BITS, v.floor() as i128, "floor {x}");
            assert_eq!(i128::from(x) / i128::from(ONE), v.trunc() as i128, "trunc {x}");
            assert_eq!(clamp_raw(x, -ONE, ONE), q(v.clamp(-1.0, 1.0)), "clamp {x}");
            let signum = if x < 0 { -ONE } else { ONE };
            assert_eq!(signum, q(v.signum()), "signum {x}");
        }
    }

    #[test]
    fn arithmetic_helpers_match_exact_rationals() {
        assert_eq!(mul_raw(3 << 31, -(5 << 31)), Some(-(15 << 30))); // 1.5 * -2.5 = -3.75
        assert_eq!(mul_raw(1, -1), Some(-1)); // floor(-2^-32)
        assert_eq!(div_raw(-1, 2 * ONE), Some(0)); // trunc toward zero
        assert_eq!(div_raw(ONE, 3 * ONE), Some(1431655765)); // 1 / 3, truncated
        assert_eq!(div_raw(1, 0), None);
        assert_eq!(recip_raw(3), Some(6148914691236517205));
        assert_eq!(recip_raw(2), None); // 2^63 does not fit
        assert_eq!(recip_raw(-2), Some(i64::MIN));
        assert_eq!(lerp_raw(0, 10 * ONE, ONE / 2), Some(5 * ONE));
        assert_eq!(lerp_raw(i64::MIN, i64::MAX, ONE), Some(i64::MAX));
    }

    #[test]
    fn powi_is_the_documented_algorithm() {
        let x = 3 * ONE / 2; // 1.5
        assert_eq!(powi_raw(x, 0), Some(ONE));
        assert_eq!(powi_raw(x, 1), Some(x));
        assert_eq!(powi_raw(x, 2), Some(9 * ONE / 4));
        assert_eq!(powi_raw(x, 3), Some(27 * ONE / 8));
        assert_eq!(powi_raw(x, 4), Some(81 * ONE / 16));
        assert_eq!(powi_raw(x, 5), Some(243 * ONE / 32));
        assert_eq!(powi_raw(2 * ONE, -2), Some(ONE / 4));
        assert_eq!(powi_raw(1, -2), None); // 1 ULP squared floors to 0
    }

    #[test]
    fn smoothstep_and_move_towards() {
        assert_eq!(smoothstep_raw(ONE / 2, 0, ONE), Some(ONE / 2));
        assert_eq!(smoothstep_raw(-ONE, 0, ONE), Some(0));
        assert_eq!(smoothstep_raw(2 * ONE, 0, ONE), Some(ONE));
        assert_eq!(smoothstep_raw(0, ONE, ONE), None);
        assert_eq!(move_towards_raw(0, 10 * ONE, 3 * ONE), Some(3 * ONE));
        assert_eq!(move_towards_raw(0, -10 * ONE, 3 * ONE), Some(-3 * ONE));
        assert_eq!(move_towards_raw(0, ONE, 3 * ONE), Some(ONE));
        assert_eq!(move_towards_raw(0, 10 * ONE, -ONE), Some(-ONE)); // moves away
        assert_eq!(move_towards_raw(5, 5, -ONE), Some(5 - ONE)); // a = 0 counts as positive
    }
}
