//! Oracles of `fixed::fixed` (scalar tier A). Spec: `specs/fixed.toml`.
//!
//! Two styles coexist on purpose:
//! * **integer oracles** (`raw()` + `Out::raw*`) compute the real result in `i128` and round it
//!   to nearest. They are exact over the whole `i64` range, where an f64 quotient or product
//!   would lose up to 2^10 raw ULPs, so they are used for the operators, the fused
//!   multiply-adds and `sqrt`;
//! * **f64 oracles** (`f()` + plain Rust `f64` methods) pin the Rust semantics the port mirrors
//!   (`round` half away from zero, `signum(0) = +1`, `fract = x - trunc(x)`, ...). They are exact
//!   as long as the inputs stay below 2^21 (`Value::f` enforces it).

use crate::prelude::*;

/// `p / 2^32` rounded to nearest (ties toward +infinity).
fn rescale(p: i128) -> i128 {
    (p + (1 << (FRAC_BITS - 1))) >> FRAC_BITS
}

/// `n / d` rounded to nearest. `d != 0`.
fn div_round(n: i128, d: i128) -> i128 {
    let (q, r) = (n.div_euclid(d), n.rem_euclid(d));
    if 2 * r < d.abs() {
        q
    } else if d > 0 {
        q + 1
    } else {
        q - 1
    }
}

fn wide(v: &Value) -> i128 {
    i128::from(v.raw())
}

pub fn register(r: &mut Registry) {
    // --- available today -------------------------------------------------------------------
    r.add("from_raw", |a| Out::raw(a[0].i64()));
    r.add("add", |a| Out::raw_checked(a[0].raw().checked_add(a[1].raw())));
    r.add("sub", |a| Out::raw_checked(a[0].raw().checked_sub(a[1].raw())));
    r.add("neg", |a| Out::raw_checked(a[0].raw().checked_neg()));

    // --- tier A, pending in `fixed` (spec entries are `enabled = false`) --------------------
    // Real product / quotient rounded to nearest: the Cairo side floors (mul) or truncates
    // (div), hence the 1 ULP tolerance in the spec.
    r.add("mul", |a| Out::raw_wide(rescale(wide(&a[0]) * wide(&a[1]))));
    r.add("div", |a| match a[1].raw() {
        0 => skip("division by zero"),
        d => Out::raw_wide(div_round(wide(&a[0]) << FRAC_BITS, i128::from(d))),
    });
    r.add("rem", |a| match a[1].raw() {
        0 => skip("division by zero"),
        d => Out::raw_checked(a[0].raw().checked_rem(d)),
    });
    r.add("recip", |a| match a[0].raw() {
        0 => skip("division by zero"),
        d => Out::raw_wide(div_round(1 << (2 * FRAC_BITS), i128::from(d))),
    });
    r.add("mul_add", |a| {
        Out::raw_wide(rescale(wide(&a[0]) * wide(&a[1]) + (wide(&a[2]) << FRAC_BITS)))
    });
    // glam `FloatExt::lerp`: `self + (rhs - self) * t`.
    r.add("lerp", |a| {
        let (from, to, t) = (wide(&a[0]), wide(&a[1]), wide(&a[2]));
        Out::raw_wide(from + rescale((to - from) * t))
    });
    // Euclidean division: the quotient is an integer, returned as a `Fixed`.
    r.add("div_euclid", |a| match a[1].raw() {
        0 => skip("division by zero"),
        d => match a[0].raw().checked_div_euclid(d) {
            Some(q) => Out::raw_wide(i128::from(q) << FRAC_BITS),
            None => Out::raw_checked(None),
        },
    });
    r.add("rem_euclid", |a| match a[1].raw() {
        0 => skip("division by zero"),
        d => Out::raw_checked(a[0].raw().checked_rem_euclid(d)),
    });

    r.add("abs", |a| a[0].f().abs());
    r.add("signum", |a| a[0].f().signum()); // f64: signum(+0.0) = +1.0
    r.add("copysign", |a| a[0].f().copysign(a[1].f()));
    r.add("floor", |a| a[0].f().floor());
    r.add("ceil", |a| a[0].f().ceil());
    r.add("round", |a| a[0].f().round()); // half away from zero
    r.add("trunc", |a| a[0].f().trunc());
    r.add("fract", |a| a[0].f().fract()); // x - trunc(x)
    r.add("fract_gl", |a| a[0].f() - a[0].f().floor()); // glam `fract_gl`
    // Exact over the whole range: sqrt(raw * 2^32) rounded to nearest, in integers.
    r.add("sqrt", |a| match a[0].raw() {
        x if x < 0 => skip("sqrt of a negative number"),
        x => {
            let n = (x as u128) << FRAC_BITS;
            let s = n.isqrt();
            // (s + 1/2)^2 = s^2 + s + 1/4: round up iff n > s^2 + s.
            Out::raw_wide((s + u128::from(n - s * s > s)) as i128)
        }
    });
    r.add("min", |a| a[0].f().min(a[1].f()));
    r.add("max", |a| a[0].f().max(a[1].f()));
    r.add("clamp", |a| {
        let (x, lo, hi) = (a[0].f(), a[1].f(), a[2].f());
        if lo > hi {
            return skip("clamp: min > max");
        }
        Out::from(x.clamp(lo, hi))
    });
    r.add("lt", |a| a[0].raw() < a[1].raw());
    r.add("le", |a| a[0].raw() <= a[1].raw());
    r.add("gt", |a| a[0].raw() > a[1].raw());
    r.add("ge", |a| a[0].raw() >= a[1].raw());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rounding_helpers() {
        assert_eq!(rescale(3 << 31), 2); // 1.5 -> 2
        assert_eq!(rescale(-(3 << 31)), -1); // -1.5 -> -1 (ties toward +inf)
        assert_eq!(rescale((1 << 31) - 1), 0);
        assert_eq!(div_round(7, 2), 4);
        assert_eq!(div_round(-7, 2), -3);
        assert_eq!(div_round(7, -2), -4);
        assert_eq!(div_round(-7, -2), 3);
        assert_eq!(div_round(6, 4), 2);
        assert_eq!(div_round(5, 4), 1);
        assert_eq!(div_round(-5, 4), -1);
    }
}
