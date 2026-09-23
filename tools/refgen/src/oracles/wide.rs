//! Oracles of `fixed::wide` (fused kernels). Spec: `specs/wide.toml`.
//!
//! Integer oracles again: a fused kernel sums the exact raw products and rescales once, so its
//! result is `floor(sum / 2^32)` (norms: `floor(sqrt(sum))`, `Recip::mul`: round to nearest, ties
//! toward +infinity of the product with the truncated 96-bit reciprocal). All of it is computed in
//! `i128` / `u128` with checked operations: an intermediate that leaves the 128-bit range means
//! the Cairo result does not fit `i64` either (a panic path, covered by `[[function.panics]]`), and
//! the case is skipped.

use std::cmp::Ordering;

use crate::prelude::*;

fn raw(a: &[Value], i: usize) -> i128 {
    i128::from(a[i].raw())
}

fn out(v: Option<i128>) -> Out {
    Out::raw_checked(v.and_then(|v| i64::try_from(v).ok()))
}

/// `sum_i a[2i] * a[2i + 1]` over `n` interleaved pairs, exact.
fn dot(a: &[Value], n: usize) -> Option<i128> {
    (0..n).try_fold(0i128, |acc, i| acc.checked_add(raw(a, 2 * i) * raw(a, 2 * i + 1)))
}

/// `sum_i a[i]^2` over the first `n` arguments, exact (a single square reaches 2^126).
fn sum_squares(a: &[Value], n: usize) -> Option<u128> {
    (0..n).try_fold(0u128, |acc, i| {
        let x = a[i].raw().unsigned_abs() as u128;
        acc.checked_add(x * x)
    })
}

/// `sum_i (a[i] - a[n + i])^2`: the differences are exact (65 bits).
fn distance_squares(a: &[Value], n: usize) -> Option<u128> {
    (0..n).try_fold(0u128, |acc, i| {
        let d = (raw(a, i) - raw(a, n + i)).unsigned_abs();
        acc.checked_add(d.checked_mul(d)?)
    })
}

/// `floor(sum / 2^32)` of a non-negative Q64.64 sum.
fn narrow_unsigned(sum: Option<u128>) -> Out {
    out(sum.and_then(|s| i128::try_from(s >> FRAC_BITS).ok()))
}

/// `floor(sqrt(sum))`: the raw length.
fn root(sum: Option<u128>) -> Out {
    out(sum.map(|s| s.isqrt() as i128))
}

/// The raw components `round(x_i / len)` through the truncated reciprocal `2^96 / len`, as
/// `normalize*` does; `None` when the length is zero or the sum overflows.
fn normalize(a: &[Value], n: usize) -> Option<Vec<i64>> {
    let len = sum_squares(a, n)?.isqrt();
    if len == 0 {
        return None;
    }
    let recip = i128::try_from((1u128 << 96) / len).ok()?;
    (0..n)
        .map(|i| i64::try_from(round_mul(recip, raw(a, i))?).ok())
        .collect()
}

/// `floor((x * recip + 2^63) / 2^64)`: what `Recip::mul` returns for `recip = trunc(2^96 / d)`.
fn round_mul(recip: i128, x: i128) -> Option<i128> {
    Some((x.checked_mul(recip)?.checked_add(1 << 63)?) >> 64)
}

/// `n / d` rounded to nearest (ties toward +infinity). `d != 0`.
fn div_round(n: i128, d: i128) -> i128 {
    // n = q * d + r with 0 <= r < |d|: the exact quotient is q + r / d.
    let (q, r) = (n.div_euclid(d), n.rem_euclid(d));
    match (2 * r).cmp(&d.abs()) {
        Ordering::Less => q,
        Ordering::Equal if d < 0 => q,
        _ if d > 0 => q + 1,
        _ => q - 1,
    }
}

/// `n / d` rounded to nearest, ties to even (the rounding of `f64 /`). `d != 0`.
fn div_half_even(n: i128, d: i128) -> i128 {
    let (n, d) = if d < 0 { (-n, -d) } else { (n, d) };
    // n = q * d + r with 0 <= r < d: the exact quotient is q + r / d, in [q, q + 1).
    let (q, r) = (n.div_euclid(d), n.rem_euclid(d));
    match (2 * r).cmp(&d) {
        Ordering::Less => q,
        Ordering::Equal => q + q.rem_euclid(2),
        Ordering::Greater => q + 1,
    }
}

/// `(x.div_nearest(d), RecipNearestTrait::new(d).div_nearest(x))`: the same exact value twice.
fn div_nearest_pair(x: i128, d: i128) -> Out {
    match d {
        0 => skip("division by zero"),
        d => {
            let q = div_half_even(x << FRAC_BITS, d);
            Out::from((out(Some(q)), out(Some(q))))
        }
    }
}

fn tuple2(v: Option<Vec<i64>>) -> Out {
    match v {
        Some(v) => Out::from((Out::raw(v[0]), Out::raw(v[1]))),
        None => skip("normalize: zero length or overflow"),
    }
}

fn tuple3(v: Option<Vec<i64>>) -> Out {
    match v {
        Some(v) => Out::from((Out::raw(v[0]), Out::raw(v[1]), Out::raw(v[2]))),
        None => skip("normalize: zero length or overflow"),
    }
}

fn tuple4(v: Option<Vec<i64>>) -> Out {
    match v {
        Some(v) => Out::from((Out::raw(v[0]), Out::raw(v[1]), Out::raw(v[2]), Out::raw(v[3]))),
        None => skip("normalize: zero length or overflow"),
    }
}

/// `x * 2^32 / d` rounded to nearest through the truncated reciprocal of `Recip`.
fn recip_mul(a: &[Value]) -> Option<i128> {
    match raw(a, 0) {
        0 => None,
        d => round_mul((1i128 << 96) / d, raw(a, 1)),
    }
}

pub fn register(r: &mut Registry) {
    // --- sums of products: one rescale, floor -----------------------------------------------
    r.add("dot2", |a| out(dot(a, 2).map(|s| s >> FRAC_BITS)));
    r.add("dot3", |a| out(dot(a, 3).map(|s| s >> FRAC_BITS)));
    r.add("dot4", |a| out(dot(a, 4).map(|s| s >> FRAC_BITS)));
    r.add("dot2_add", |a| {
        out(dot(a, 2).and_then(|s| Some(s.checked_add(raw(a, 4) << FRAC_BITS)? >> FRAC_BITS)))
    });
    r.add("dot3_add", |a| {
        out(dot(a, 3).and_then(|s| Some(s.checked_add(raw(a, 6) << FRAC_BITS)? >> FRAC_BITS)))
    });
    // a * b + c
    r.add("mul_add", |a| {
        out(Some((raw(a, 0) * raw(a, 1) + (raw(a, 2) << FRAC_BITS)) >> FRAC_BITS))
    });
    // a * b - c * d
    r.add("mul_sub", |a| {
        out((raw(a, 0) * raw(a, 1)).checked_sub(raw(a, 2) * raw(a, 3)).map(|s| s >> FRAC_BITS))
    });
    // a . (b x c), the six triple products summed exactly at the Q96.96 scale.
    r.add("det3", |a| {
        let cross = |p: usize, q: usize, r: usize, s: usize| -> Option<i128> {
            (raw(a, p) * raw(a, q)).checked_sub(raw(a, r) * raw(a, s))
        };
        let det = || -> Option<i128> {
            // columns a = (0, 1, 2), b = (3, 4, 5), c = (6, 7, 8)
            let x = cross(4, 8, 7, 5)?.checked_mul(raw(a, 0))?;
            let y = cross(5, 6, 8, 3)?.checked_mul(raw(a, 1))?;
            let z = cross(3, 7, 6, 4)?.checked_mul(raw(a, 2))?;
            Some(x.checked_add(y)?.checked_add(z)? >> (2 * FRAC_BITS))
        };
        out(det())
    });

    // --- squared norms: floor(sum / 2^32) ---------------------------------------------------
    r.add("norm2_squared", |a| narrow_unsigned(sum_squares(a, 2)));
    r.add("norm3_squared", |a| narrow_unsigned(sum_squares(a, 3)));
    r.add("norm4_squared", |a| narrow_unsigned(sum_squares(a, 4)));
    r.add("distance2_squared", |a| narrow_unsigned(distance_squares(a, 2)));
    r.add("distance3_squared", |a| narrow_unsigned(distance_squares(a, 3)));
    r.add("distance4_squared", |a| narrow_unsigned(distance_squares(a, 4)));

    // --- norms and distances: floor of the exact root of the raw Q64.64 sum -----------------
    r.add("norm2", |a| root(sum_squares(a, 2)));
    r.add("norm3", |a| root(sum_squares(a, 3)));
    r.add("norm4", |a| root(sum_squares(a, 4)));
    r.add("distance2", |a| root(distance_squares(a, 2)));
    r.add("distance3", |a| root(distance_squares(a, 3)));
    r.add("distance4", |a| root(distance_squares(a, 4)));

    // --- normalize: floored length, truncated 96-bit reciprocal, rounded products -----------
    r.add("normalize2", |a| tuple2(normalize(a, 2)));
    r.add("normalize3", |a| tuple3(normalize(a, 3)));
    r.add("normalize4", |a| tuple4(normalize(a, 4)));

    // --- Recip ------------------------------------------------------------------------------
    // The algorithm of the port: r = trunc(2^96 / d), result = round(x * r / 2^64).
    r.add("recip_mul", |a| out(recip_mul(a)));
    // Its accuracy claim: within 1/2 + |x| / 2^64 < 1 ULP of the exact quotient x / d, so at most
    // 1 ULP away from that quotient rounded to nearest.
    r.add("recip_mul_ideal", |a| match raw(a, 0) {
        0 => skip("division by zero"),
        d => out(Some(div_round(raw(a, 1) << FRAC_BITS, d))),
    });

    // --- correctly rounded division: round half to even of the exact quotient --------------
    // (x.div_nearest(d), RecipNearestTrait::new(d).div_nearest(x)): bit-identical by contract.
    r.add("div_nearest", |a| div_nearest_pair(raw(a, 0), raw(a, 1)));
    // (d.recip_nearest(), RecipNearestTrait::new(d).div_nearest(ONE)).
    r.add("recip_nearest", |a| div_nearest_pair(1 << FRAC_BITS, raw(a, 0)));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixed(raws: &[i64]) -> Vec<Value> {
        raws.iter().map(|r| Value::fixed_raw(*r)).collect()
    }

    fn one() -> i64 {
        1 << FRAC_BITS
    }

    #[test]
    fn helpers_on_exact_values() {
        // 3-4-5 triangle.
        let v = fixed(&[3 * one(), 4 * one()]);
        assert_eq!(sum_squares(&v, 2), Some(25 << 64));
        assert_eq!(root(sum_squares(&v, 2)).res.unwrap().leaves, vec![5 * one()]);
        // Axis-aligned normalize is exactly +-1.
        let v = fixed(&[-7 * one(), 0, 0]);
        assert_eq!(normalize(&v, 3), Some(vec![-one(), 0, 0]));
        assert_eq!(normalize(&fixed(&[0, 0]), 2), None);
        // Recip: 6 / 3 = 2 exactly, and 1 / 3 rounds to the nearest raw value.
        assert_eq!(recip_mul(&fixed(&[3 * one(), 6 * one()])), Some(2 << FRAC_BITS));
        assert_eq!(recip_mul(&fixed(&[3 * one(), one()])), Some(1431655765));
        assert_eq!(div_round(-7, 2), -3); // ties toward +infinity
        assert_eq!(div_round(7, -2), -3);
        assert_eq!(div_round(-7, -2), 4); // 3.5 -> 4
        assert_eq!(div_round(5, -2), -2); // -2.5 -> -2
        assert_eq!(div_round(-5, 3), -2);
        // Ties to even, both signs, odd and even truncated quotients.
        assert_eq!(div_half_even(1, 2), 0); // 0.5 -> 0
        assert_eq!(div_half_even(3, 2), 2); // 1.5 -> 2
        assert_eq!(div_half_even(5, 2), 2); // 2.5 -> 2
        assert_eq!(div_half_even(-1, 2), 0); // -0.5 -> 0
        assert_eq!(div_half_even(-3, 2), -2); // -1.5 -> -2
        assert_eq!(div_half_even(3, -2), -2);
        assert_eq!(div_half_even(-5, -2), 2);
        assert_eq!(div_half_even(-7, 3), -2); // -2.33 -> -2
        assert_eq!(div_half_even(-8, 3), -3); // -2.67 -> -3
        assert_eq!(div_half_even(12, -4), -3); // exact
        // det3 of the identity is 1.
        let id = fixed(&[one(), 0, 0, 0, one(), 0, 0, 0, one()]);
        let mut reg = Registry::default();
        register(&mut reg);
        let det = reg.oracles["det3"](&id).res.unwrap();
        assert_eq!(det.leaves, vec![one()]);
    }
}
