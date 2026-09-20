//! The `Fixed` scalar: a signed Q32.32 number stored as a raw two's-complement `i64`.

/// Raw representation of `1.0` (2^32).
pub const ONE_RAW: i64 = 0x100000000;
/// `0.0`.
pub const ZERO: Fixed = Fixed { raw: 0 };
/// `1.0`.
pub const ONE: Fixed = Fixed { raw: ONE_RAW };

/// Signed Q32.32 fixed-point number. `value = raw / 2^32`.
#[derive(Copy, Drop, Serde, PartialEq, Debug, Default, Hash)]
pub struct Fixed {
    pub raw: i64,
}

pub trait FixedTrait {
    /// Builds a `Fixed` from its raw Q32.32 representation.
    fn from_raw(raw: i64) -> Fixed;
}

pub impl FixedImpl of FixedTrait {
    #[inline(always)]
    fn from_raw(raw: i64) -> Fixed {
        Fixed { raw }
    }
}

pub impl FixedAdd of Add<Fixed> {
    #[inline(always)]
    fn add(lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed { raw: lhs.raw + rhs.raw }
    }
}

pub impl FixedSub of Sub<Fixed> {
    #[inline(always)]
    fn sub(lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed { raw: lhs.raw - rhs.raw }
    }
}

pub impl FixedNeg of Neg<Fixed> {
    #[inline(always)]
    fn neg(a: Fixed) -> Fixed {
        Fixed { raw: -a.raw }
    }
}
