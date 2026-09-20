//! A: cubit-style signed Q32.32: `{ mag: u64, sign: bool }`.
//! Algorithms copied from influenceth/cubit `f64` (ops.cairo), default inlining as upstream.
use core::num::traits::{Sqrt, WideMul};
use super::Real;

pub const ONE: u64 = 0x100000000;
pub const HALF: u64 = 0x80000000;

#[derive(Copy, Drop)]
pub struct FMag {
    pub mag: u64,
    pub sign: bool,
}

pub impl FMagAdd of Add<FMag> {
    fn add(lhs: FMag, rhs: FMag) -> FMag {
        if lhs.sign == rhs.sign {
            return FMag { mag: lhs.mag + rhs.mag, sign: lhs.sign };
        }
        if lhs.mag == rhs.mag {
            return FMag { mag: 0, sign: false };
        }
        if lhs.mag > rhs.mag {
            FMag { mag: lhs.mag - rhs.mag, sign: lhs.sign }
        } else {
            FMag { mag: rhs.mag - lhs.mag, sign: rhs.sign }
        }
    }
}
pub impl FMagNeg of Neg<FMag> {
    fn neg(a: FMag) -> FMag {
        if a.mag == 0 {
            a
        } else {
            FMag { mag: a.mag, sign: !a.sign }
        }
    }
}
pub impl FMagSub of Sub<FMag> {
    fn sub(lhs: FMag, rhs: FMag) -> FMag {
        lhs + (-rhs)
    }
}
pub impl FMagMul of Mul<FMag> {
    fn mul(lhs: FMag, rhs: FMag) -> FMag {
        let prod: u128 = WideMul::wide_mul(lhs.mag, rhs.mag);
        FMag { mag: (prod / ONE.into()).try_into().unwrap(), sign: lhs.sign ^ rhs.sign }
    }
}
pub impl FMagDiv of Div<FMag> {
    fn div(lhs: FMag, rhs: FMag) -> FMag {
        let num: u128 = WideMul::wide_mul(lhs.mag, ONE);
        FMag { mag: (num / rhs.mag.into()).try_into().unwrap(), sign: lhs.sign ^ rhs.sign }
    }
}
pub impl FMagPartialEq of PartialEq<FMag> {
    fn eq(lhs: @FMag, rhs: @FMag) -> bool {
        (*lhs.mag == *rhs.mag) && (*lhs.sign == *rhs.sign)
    }
}
pub impl FMagPartialOrd of PartialOrd<FMag> {
    fn lt(lhs: FMag, rhs: FMag) -> bool {
        if lhs.sign != rhs.sign {
            lhs.sign
        } else {
            (lhs.mag != rhs.mag) && ((lhs.mag < rhs.mag) ^ lhs.sign)
        }
    }
    fn le(lhs: FMag, rhs: FMag) -> bool {
        if lhs.sign != rhs.sign {
            lhs.sign
        } else {
            (lhs.mag == rhs.mag) || ((lhs.mag < rhs.mag) ^ lhs.sign)
        }
    }
}

pub impl FMagReal of Real<FMag> {
    fn from_raw(raw: i64) -> FMag {
        if raw < 0 {
            FMag { mag: (-raw).try_into().unwrap(), sign: true }
        } else {
            FMag { mag: raw.try_into().unwrap(), sign: false }
        }
    }
    fn to_raw(self: FMag) -> i64 {
        let m: i64 = self.mag.try_into().unwrap();
        if self.sign {
            -m
        } else {
            m
        }
    }
    fn from_int(v: i32) -> FMag {
        if v < 0 {
            let m: u32 = (-v).try_into().unwrap();
            FMag { mag: m.into() * ONE, sign: true }
        } else {
            let m: u32 = v.try_into().unwrap();
            FMag { mag: m.into() * ONE, sign: false }
        }
    }
    fn to_int(self: FMag) -> i32 {
        let f = Self::floor(self);
        let i: i32 = (f.mag / ONE).try_into().unwrap();
        if f.sign {
            -i
        } else {
            i
        }
    }
    fn floor(self: FMag) -> FMag {
        let (div, rem) = DivRem::div_rem(self.mag, ONE.try_into().unwrap());
        if rem == 0 {
            self
        } else if !self.sign {
            FMag { mag: div * ONE, sign: false }
        } else {
            FMag { mag: (div + 1) * ONE, sign: true }
        }
    }
    fn round(self: FMag) -> FMag {
        let (div, rem) = DivRem::div_rem(self.mag, ONE.try_into().unwrap());
        if HALF <= rem {
            FMag { mag: (div + 1) * ONE, sign: self.sign }
        } else {
            FMag { mag: div * ONE, sign: self.sign }
        }
    }
    fn abs(self: FMag) -> FMag {
        FMag { mag: self.mag, sign: false }
    }
    fn sqrt(self: FMag) -> FMag {
        assert(!self.sign, 'must be positive');
        // cubit: `a.mag.into() * ONE.into()` (a checked u128 mul)
        let scaled: u128 = self.mag.into() * ONE.into();
        FMag { mag: Sqrt::sqrt(scaled), sign: false }
    }
}
pub impl FMagFused = super::naive::NaiveFused<FMag>;
