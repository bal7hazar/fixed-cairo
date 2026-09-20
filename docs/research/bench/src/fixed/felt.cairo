//! D: signed Q32.32 stored in a `felt252` (negative values are `P - |x|`), with LAZY reduction.
//!
//! add / sub / neg are single field operations with NO range check. A value is only range-checked
//! when it is *consumed* by an operation that needs its integer value (mul rescale, compare, sqrt,
//! conversion): there, `felt252 -> i128` fails if |acc| >= 2^127.
//!
//! Soundness envelope: every rescaled result satisfies |raw| < 2^95. A raw product of two such
//! values is < 2^190 and the prime is ~2^251, so more than 2^60 products can be accumulated before
//! a field wrap-around could go undetected. Unchecked add/sub chains grow by one bit per doubling,
//! so they are equally safe in practice, but the type offers NO static guarantee: a `FFelt` built
//! from untrusted data (calldata, storage) must be validated once with `to_raw`.
#[feature("bounded-int-utils")]
use core::internal::bounded_int::{self, NegateHelper, UnitInt, upcast};
use core::num::traits::Sqrt;
use super::i64b::FI64;
use super::i64b_types::*;
use super::{Fused, Real};

pub const ONE: felt252 = 0x100000000;

#[derive(Copy, Drop, PartialEq)]
pub struct FFelt {
    pub raw: felt252,
}

/// floor(acc / 2^32) for a raw accumulator; panics if |acc| >= 2^127.
#[inline(always)]
pub fn narrow(acc: felt252) -> felt252 {
    let v: i128 = acc.try_into().expect('fixed overflow');
    let o = bounded_int::add::<_, UnitInt<0x80000000000000000000000000000000>>(
        v, 0x80000000000000000000000000000000,
    );
    let (q, _r) = bounded_int::div_rem::<_, UnitInt<0x100000000>>(o, 0x100000000);
    upcast(bounded_int::sub::<_, UnitInt<0x800000000000000000000000>>(q, 0x800000000000000000000000))
}

#[inline(always)]
fn is_neg(x: felt252) -> bool {
    let v: i128 = x.try_into().expect('fixed overflow');
    match bounded_int::constrain::<i128, 0>(v) {
        Ok(_) => true,
        Err(_) => false,
    }
}

pub impl FFeltAdd of Add<FFelt> {
    #[inline(always)]
    fn add(lhs: FFelt, rhs: FFelt) -> FFelt {
        FFelt { raw: lhs.raw + rhs.raw }
    }
}
pub impl FFeltSub of Sub<FFelt> {
    #[inline(always)]
    fn sub(lhs: FFelt, rhs: FFelt) -> FFelt {
        FFelt { raw: lhs.raw - rhs.raw }
    }
}
pub impl FFeltNeg of Neg<FFelt> {
    #[inline(always)]
    fn neg(a: FFelt) -> FFelt {
        FFelt { raw: -a.raw }
    }
}
pub impl FFeltMul of Mul<FFelt> {
    #[inline(always)]
    fn mul(lhs: FFelt, rhs: FFelt) -> FFelt {
        FFelt { raw: narrow(lhs.raw * rhs.raw) }
    }
}
pub impl FFeltDiv of Div<FFelt> {
    /// Division needs true integers: both operands are downcast to i64 and the i64 kernel is used.
    fn div(lhs: FFelt, rhs: FFelt) -> FFelt {
        let a = FI64 { raw: lhs.raw.try_into().expect('fixed overflow') };
        let b = FI64 { raw: rhs.raw.try_into().expect('fixed overflow') };
        FFelt { raw: (a / b).raw.into() }
    }
}
pub impl FFeltPartialOrd of PartialOrd<FFelt> {
    #[inline(always)]
    fn lt(lhs: FFelt, rhs: FFelt) -> bool {
        is_neg(lhs.raw - rhs.raw)
    }
    #[inline(always)]
    fn le(lhs: FFelt, rhs: FFelt) -> bool {
        !is_neg(rhs.raw - lhs.raw)
    }
}

pub impl FFeltReal of Real<FFelt> {
    fn from_raw(raw: i64) -> FFelt {
        FFelt { raw: raw.into() }
    }
    fn to_raw(self: FFelt) -> i64 {
        self.raw.try_into().expect('fixed overflow')
    }
    #[inline(always)]
    fn from_int(v: i32) -> FFelt {
        FFelt { raw: v.into() * ONE }
    }
    #[inline(always)]
    fn to_int(self: FFelt) -> i32 {
        narrow(self.raw).try_into().expect('int overflow')
    }
    #[inline(always)]
    fn floor(self: FFelt) -> FFelt {
        let v: i128 = self.raw.try_into().expect('fixed overflow');
        let o = bounded_int::add::<_, UnitInt<0x80000000000000000000000000000000>>(
            v, 0x80000000000000000000000000000000,
        );
        let (_q, r) = bounded_int::div_rem::<_, UnitInt<0x100000000>>(o, 0x100000000);
        FFelt { raw: self.raw - upcast(r) }
    }
    fn round(self: FFelt) -> FFelt {
        Self::floor(FFelt { raw: self.raw + 0x80000000 })
    }
    #[inline(always)]
    fn abs(self: FFelt) -> FFelt {
        if is_neg(self.raw) {
            FFelt { raw: -self.raw }
        } else {
            self
        }
    }
    fn sqrt(self: FFelt) -> FFelt {
        let m: u64 = self.raw.try_into().expect('must be positive');
        let scaled: u128 = upcast(bounded_int::mul::<u64, UnitInt<0x100000000>>(m, 0x100000000));
        let r: u64 = Sqrt::sqrt(scaled);
        FFelt { raw: r.into() }
    }
}

pub impl FFeltFused of Fused<FFelt> {
    #[inline(always)]
    fn dot2(a0: FFelt, b0: FFelt, a1: FFelt, b1: FFelt) -> FFelt {
        FFelt { raw: narrow(a0.raw * b0.raw + a1.raw * b1.raw) }
    }
    #[inline(always)]
    fn mul_sub(a0: FFelt, b0: FFelt, a1: FFelt, b1: FFelt) -> FFelt {
        FFelt { raw: narrow(a0.raw * b0.raw - a1.raw * b1.raw) }
    }
    #[inline(always)]
    fn dot3(a0: FFelt, b0: FFelt, a1: FFelt, b1: FFelt, a2: FFelt, b2: FFelt) -> FFelt {
        FFelt { raw: narrow(a0.raw * b0.raw + a1.raw * b1.raw + a2.raw * b2.raw) }
    }
    #[inline(always)]
    fn dot4(a0: FFelt, b0: FFelt, a1: FFelt, b1: FFelt, a2: FFelt, b2: FFelt, a3: FFelt, b3: FFelt) -> FFelt {
        FFelt { raw: narrow(a0.raw * b0.raw + a1.raw * b1.raw + a2.raw * b2.raw + a3.raw * b3.raw) }
    }
    #[inline(always)]
    fn norm3(x: FFelt, y: FFelt, z: FFelt) -> FFelt {
        let s: u128 = (x.raw * x.raw + y.raw * y.raw + z.raw * z.raw).try_into().expect('fixed overflow');
        let r: u64 = Sqrt::sqrt(s);
        FFelt { raw: r.into() }
    }
}
