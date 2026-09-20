//! F: signed Q64.64 `{ mag: u128, sign: bool }` -- only add/mul/div, to quantify the cost of
//! crossing the 128-bit boundary (products need 256 bits, which exceed a felt252).
#[feature("bounded-int-utils")]
use core::internal::bounded_int::{self, UnitInt, downcast, upcast};
use core::num::traits::WideMul;
use super::i64b_types::*;

pub const ONE: u128 = 0x10000000000000000;

#[derive(Copy, Drop)]
pub struct FQ64 {
    pub mag: u128,
    pub sign: bool,
}

pub fn from_raw(raw: i128) -> FQ64 {
    if raw < 0 {
        FQ64 { mag: (-raw).try_into().unwrap(), sign: true }
    } else {
        FQ64 { mag: raw.try_into().unwrap(), sign: false }
    }
}

pub fn add(a: FQ64, b: FQ64) -> FQ64 {
    if a.sign == b.sign {
        return FQ64 { mag: a.mag + b.mag, sign: a.sign };
    }
    if a.mag == b.mag {
        return FQ64 { mag: 0, sign: false };
    }
    if a.mag > b.mag {
        FQ64 { mag: a.mag - b.mag, sign: a.sign }
    } else {
        FQ64 { mag: b.mag - a.mag, sign: b.sign }
    }
}

/// cubit f128 style: u256 product, u256 division by ONE.
#[inline(always)]
pub fn mul_u256(a: FQ64, b: FQ64) -> FQ64 {
    let p: u256 = WideMul::wide_mul(a.mag, b.mag);
    let q: u256 = p / ONE.into();
    FQ64 { mag: q.try_into().unwrap(), sign: a.sign ^ b.sign }
}

/// Optimised: (hi, lo) = a * b ; result = hi * 2^64 + lo / 2^64 (hi must fit 64 bits).
#[inline(always)]
pub fn mul(a: FQ64, b: FQ64) -> FQ64 {
    let p: u256 = WideMul::wide_mul(a.mag, b.mag);
    let hi: u64 = downcast(p.high).expect('fixed overflow');
    let (lo_q, _r) = bounded_int::div_rem::<u128, UnitInt<0x10000000000000000>>(p.low, 0x10000000000000000);
    let his = bounded_int::mul::<u64, UnitInt<0x10000000000000000>>(hi, 0x10000000000000000);
    FQ64 { mag: upcast(bounded_int::add(his, lo_q)), sign: a.sign ^ b.sign }
}

/// (a << 64) / b through u256 division.
#[inline(always)]
pub fn div(a: FQ64, b: FQ64) -> FQ64 {
    let (a_hi, a_lo) = bounded_int::div_rem::<u128, UnitInt<0x10000000000000000>>(a.mag, 0x10000000000000000);
    let low: u128 = upcast(bounded_int::mul::<U64B, UnitInt<0x10000000000000000>>(a_lo, 0x10000000000000000));
    let num = u256 { low, high: upcast(a_hi) };
    let q: u256 = num / b.mag.into();
    FQ64 { mag: q.try_into().unwrap(), sign: a.sign ^ b.sign }
}
