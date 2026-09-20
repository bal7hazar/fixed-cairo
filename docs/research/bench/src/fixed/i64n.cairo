//! B: signed Q32.32 stored in a native `i64`, using ONLY stable corelib operators
//! (`i64_wide_mul -> i128`, signed `i128` division, checked `i64` add/sub).
//! Rounding: truncation towards zero (that is what signed `/` does).
use core::num::traits::{Sqrt, WideMul};
use super::Real;

pub const ONE: i64 = 0x100000000;
const ONE_I128: i128 = 0x100000000;

#[derive(Copy, Drop, PartialEq)]
pub struct FI64N {
    pub raw: i64,
}

pub impl FI64NAdd of Add<FI64N> {
    #[inline(always)]
    fn add(lhs: FI64N, rhs: FI64N) -> FI64N {
        FI64N { raw: lhs.raw + rhs.raw }
    }
}
pub impl FI64NSub of Sub<FI64N> {
    #[inline(always)]
    fn sub(lhs: FI64N, rhs: FI64N) -> FI64N {
        FI64N { raw: lhs.raw - rhs.raw }
    }
}
pub impl FI64NNeg of Neg<FI64N> {
    #[inline(always)]
    fn neg(a: FI64N) -> FI64N {
        FI64N { raw: -a.raw }
    }
}
pub impl FI64NMul of Mul<FI64N> {
    #[inline(always)]
    fn mul(lhs: FI64N, rhs: FI64N) -> FI64N {
        let p: i128 = WideMul::wide_mul(lhs.raw, rhs.raw);
        FI64N { raw: (p / ONE_I128).try_into().unwrap() }
    }
}
pub impl FI64NDiv of Div<FI64N> {
    #[inline(always)]
    fn div(lhs: FI64N, rhs: FI64N) -> FI64N {
        let n: i128 = WideMul::wide_mul(lhs.raw, ONE);
        FI64N { raw: (n / rhs.raw.into()).try_into().unwrap() }
    }
}
pub impl FI64NPartialOrd of PartialOrd<FI64N> {
    #[inline(always)]
    fn lt(lhs: FI64N, rhs: FI64N) -> bool {
        lhs.raw < rhs.raw
    }
    #[inline(always)]
    fn le(lhs: FI64N, rhs: FI64N) -> bool {
        lhs.raw <= rhs.raw
    }
}

pub impl FI64NReal of Real<FI64N> {
    fn from_raw(raw: i64) -> FI64N {
        FI64N { raw }
    }
    fn to_raw(self: FI64N) -> i64 {
        self.raw
    }
    fn from_int(v: i32) -> FI64N {
        let w: i64 = v.into();
        FI64N { raw: w * ONE }
    }
    fn to_int(self: FI64N) -> i32 {
        (Self::floor(self).raw / ONE).try_into().unwrap()
    }
    fn floor(self: FI64N) -> FI64N {
        // signed `%` truncates: fix up negatives.
        let r = self.raw % ONE;
        if r == 0 {
            self
        } else if self.raw < 0 {
            FI64N { raw: self.raw - r - ONE }
        } else {
            FI64N { raw: self.raw - r }
        }
    }
    fn round(self: FI64N) -> FI64N {
        Self::floor(FI64N { raw: self.raw + 0x80000000 })
    }
    fn abs(self: FI64N) -> FI64N {
        if self.raw < 0 {
            FI64N { raw: -self.raw }
        } else {
            self
        }
    }
    fn sqrt(self: FI64N) -> FI64N {
        let m: u64 = self.raw.try_into().expect('must be positive');
        let scaled: u128 = WideMul::wide_mul(m, 0x100000000_u64);
        let r: u64 = Sqrt::sqrt(scaled);
        FI64N { raw: r.try_into().unwrap() }
    }
}
pub impl FI64NFused = super::naive::NaiveFused<FI64N>;
