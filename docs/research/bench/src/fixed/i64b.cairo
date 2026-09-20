//! C/E: signed Q32.32 stored in a native `i64`; multiplication/division implemented with
//! `core::internal::bounded_int` (feature `bounded-int-utils`), plus fused kernels that accumulate
//! raw Q64.64 products and rescale ONCE ("lazy reduction"). All intermediate bounds are tracked
//! statically by the type system, so no intermediate range check is needed and the only runtime
//! overflow check is the final downcast to `i64`.
//! Rounding: floor (arithmetic shift), obtained branch-free with the bias trick
//! `((p + 2^k) div 2^32) - 2^(k-32)`.
#[feature("bounded-int-utils")]
use core::internal::bounded_int::{self, NegateHelper, UnitInt, downcast, upcast};
use core::num::traits::Sqrt;
use super::i64b_types::*;
use super::{Fused, Real};

pub const ONE: i64 = 0x100000000;

#[derive(Copy, Drop, PartialEq)]
pub struct FI64 {
    pub raw: i64,
}

/// Raw Q64.64 product, statically bounded, no range check (1 step).
#[inline(always)]
pub fn wide(a: FI64, b: FI64) -> Prod1 {
    bounded_int::mul(a.raw, b.raw)
}

pub impl FI64Add of Add<FI64> {
    #[inline(always)]
    fn add(lhs: FI64, rhs: FI64) -> FI64 {
        FI64 { raw: lhs.raw + rhs.raw }
    }
}
pub impl FI64Sub of Sub<FI64> {
    #[inline(always)]
    fn sub(lhs: FI64, rhs: FI64) -> FI64 {
        FI64 { raw: lhs.raw - rhs.raw }
    }
}
pub impl FI64Neg of Neg<FI64> {
    #[inline(always)]
    fn neg(a: FI64) -> FI64 {
        FI64 { raw: -a.raw }
    }
}
pub impl FI64Mul of Mul<FI64> {
    #[inline(always)]
    fn mul(lhs: FI64, rhs: FI64) -> FI64 {
        FI64 { raw: narrow_prod1(wide(lhs, rhs)) }
    }
}
pub impl FI64Div of Div<FI64> {
    /// Truncating division: sign-split with `constrain`, unsigned bounded div_rem.
    #[inline(always)]
    fn div(lhs: FI64, rhs: FI64) -> FI64 {
        let rhs_nz: NonZero<i64> = rhs.raw.try_into().expect('division by zero');
        let (n, n_neg): (AbsI64, bool) = match bounded_int::constrain::<i64, 0>(lhs.raw) {
            Ok(lt0) => (upcast(lt0.negate()), true),
            Err(ge0) => (upcast(ge0), false),
        };
        let num: Num = bounded_int::mul::<_, UnitInt<0x100000000>>(n, 0x100000000);
        let (q, neg): (Num, bool) = match bounded_int::constrain::<NonZero<i64>, 0>(rhs_nz) {
            Ok(lt0) => {
                let (q, _r) = bounded_int::div_rem(num, lt0.negate());
                (q, !n_neg)
            },
            Err(ge0) => {
                let (q, _r) = bounded_int::div_rem(num, ge0);
                (q, n_neg)
            },
        };
        if neg {
            FI64 { raw: downcast(q.negate()).expect('fixed overflow') }
        } else {
            FI64 { raw: downcast(q).expect('fixed overflow') }
        }
    }
}
pub impl FI64PartialOrd of PartialOrd<FI64> {
    #[inline(always)]
    fn lt(lhs: FI64, rhs: FI64) -> bool {
        lhs.raw < rhs.raw
    }
    #[inline(always)]
    fn le(lhs: FI64, rhs: FI64) -> bool {
        lhs.raw <= rhs.raw
    }
}

pub impl FI64Real of Real<FI64> {
    fn from_raw(raw: i64) -> FI64 {
        FI64 { raw }
    }
    fn to_raw(self: FI64) -> i64 {
        self.raw
    }
    #[inline(always)]
    fn from_int(v: i32) -> FI64 {
        FI64 { raw: upcast(bounded_int::mul::<i32, UnitInt<0x100000000>>(v, 0x100000000)) }
    }
    #[inline(always)]
    fn to_int(self: FI64) -> i32 {
        let o = bounded_int::add::<i64, UnitInt<0x8000000000000000>>(self.raw, 0x8000000000000000);
        let (q, _r) = bounded_int::div_rem::<_, UnitInt<0x100000000>>(o, 0x100000000);
        upcast(bounded_int::sub::<_, UnitInt<0x80000000>>(q, 0x80000000))
    }
    #[inline(always)]
    fn floor(self: FI64) -> FI64 {
        let o = bounded_int::add::<i64, UnitInt<0x8000000000000000>>(self.raw, 0x8000000000000000);
        let (_q, r) = bounded_int::div_rem::<_, UnitInt<0x100000000>>(o, 0x100000000);
        // raw - frac is always within i64 (floor never leaves the range).
        FI64 { raw: downcast(bounded_int::sub(self.raw, r)).unwrap() }
    }
    fn round(self: FI64) -> FI64 {
        Self::floor(FI64 { raw: self.raw + 0x80000000 })
    }
    #[inline(always)]
    fn abs(self: FI64) -> FI64 {
        match bounded_int::constrain::<i64, 0>(self.raw) {
            Ok(lt0) => FI64 { raw: downcast(lt0.negate()).expect('fixed overflow') },
            Err(_) => self,
        }
    }
    fn sqrt(self: FI64) -> FI64 {
        let m: u64 = self.raw.try_into().expect('must be positive');
        let scaled: u128 = upcast(bounded_int::mul::<u64, UnitInt<0x100000000>>(m, 0x100000000));
        let r: u64 = Sqrt::sqrt(scaled);
        // sqrt(2^63 * 2^32) < 2^48: always fits.
        FI64 { raw: downcast(r).unwrap() }
    }
}

pub impl FI64Fused of Fused<FI64> {
    #[inline(always)]
    fn dot2(a0: FI64, b0: FI64, a1: FI64, b1: FI64) -> FI64 {
        FI64 { raw: narrow_prod2(bounded_int::add(wide(a0, b0), wide(a1, b1))) }
    }
    #[inline(always)]
    fn mul_sub(a0: FI64, b0: FI64, a1: FI64, b1: FI64) -> FI64 {
        FI64 { raw: narrow_proddiff(bounded_int::sub(wide(a0, b0), wide(a1, b1))) }
    }
    #[inline(always)]
    fn dot3(a0: FI64, b0: FI64, a1: FI64, b1: FI64, a2: FI64, b2: FI64) -> FI64 {
        let acc = bounded_int::add(bounded_int::add(wide(a0, b0), wide(a1, b1)), wide(a2, b2));
        FI64 { raw: narrow_prod3(acc) }
    }
    #[inline(always)]
    fn dot4(a0: FI64, b0: FI64, a1: FI64, b1: FI64, a2: FI64, b2: FI64, a3: FI64, b3: FI64) -> FI64 {
        let acc = bounded_int::add(
            bounded_int::add(bounded_int::add(wide(a0, b0), wide(a1, b1)), wide(a2, b2)), wide(a3, b3),
        );
        FI64 { raw: narrow_prod4(acc) }
    }
    /// sqrt of the raw Q64.64 sum of squares IS the Q32.32 length: zero rescale.
    #[inline(always)]
    fn norm3(x: FI64, y: FI64, z: FI64) -> FI64 {
        let acc = bounded_int::add(bounded_int::add(wide(x, x), wide(y, y)), wide(z, z));
        // The static lower bound is negative (the type system does not know x*x >= 0) but the value
        // never is; 3 * 2^126 < 2^128 so the conversion cannot fail.
        // (`downcast` rejects source ranges wider than 2^128, so go through felt252.)
        let f: felt252 = upcast(acc);
        let s: u128 = f.try_into().unwrap();
        let r: u64 = Sqrt::sqrt(s);
        FI64 { raw: downcast(r).expect('fixed overflow') }
    }
}
