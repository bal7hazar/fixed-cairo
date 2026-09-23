//! The `Fixed` scalar: a signed Q32.32 number stored as a raw two's-complement `i64`.
//!
//! * `value = raw / 2^32`, range `[-2^31, 2^31)`, resolution `2^-32` (1 ULP, [`EPSILON`]).
//! * Rounding: `*`, [`FixedTrait::mul_add`], [`FixedTrait::lerp`] and every fused kernel round
//!   toward negative infinity (floor); `/`, [`FixedTrait::recip`] and [`FixedTrait::from_ratio`]
//!   are correctly rounded (to nearest, ties to even) like `f64 /` in Rust
//!   ([`FixedTrait::div_nearest`] and [`FixedTrait::recip_nearest`] are named aliases); `%` is the
//!   exact remainder of the truncated division, like Rust's float `%`.
//! * Overflow panics, it never wraps nor saturates: `'Fixed: overflow'` for everything that
//!   rescales, the corelib messages for the native `+`, `-` and unary `-` (`'i64_add Overflow'` /
//!   `'i64_add Underflow'`, `'i64_sub Overflow'` / `'i64_sub Underflow'`, `'i64_neg Underflow'`):
//!   they are the cheapest checked operations available (840 gas).
//!
//! Method names mirror Rust's `f32` and glam's `FloatExt` so that glam-rs code ports mechanically.
use core::num::traits::{Bounded, One, Zero};
use core::ops::{AddAssign, DivAssign, MulAssign, RemAssign, SubAssign};
use crate::internal::bounded;

/// Number of fractional bits.
pub const FRAC_BITS: u8 = 32;
/// Raw representation of `1.0` (2^32).
pub const ONE_RAW: i64 = 0x100000000;
/// Raw representation of `0.5` (2^31).
pub const HALF_RAW: i64 = 0x80000000;
/// Raw representation of pi, rounded to nearest (error 1.1e-10).
pub const PI_RAW: i64 = 13493037705;
/// Raw representation of 2 pi, rounded to nearest (error -1.0e-11).
pub const TAU_RAW: i64 = 26986075409;
/// Raw representation of pi / 2, rounded to nearest (error -6.1e-11).
pub const FRAC_PI_2_RAW: i64 = 6746518852;

/// `0.0`.
pub const ZERO: Fixed = Fixed { raw: 0 };
/// `1.0`.
pub const ONE: Fixed = Fixed { raw: ONE_RAW };
/// `-1.0`.
pub const NEG_ONE: Fixed = Fixed { raw: -ONE_RAW };
/// `0.5`.
pub const HALF: Fixed = Fixed { raw: HALF_RAW };
/// `2.0`.
pub const TWO: Fixed = Fixed { raw: 0x200000000 };
/// Smallest value: `-2^31` (mirrors `f32::MIN`).
pub const MIN: Fixed = Fixed { raw: -0x8000000000000000 };
/// Largest value: `2^31 - 2^-32` (mirrors `f32::MAX`).
pub const MAX: Fixed = Fixed { raw: 0x7fffffffffffffff };
/// The resolution of the format, `2^-32` = 1 ULP. Unlike `f32::EPSILON` it is uniform over the
/// whole range.
pub const EPSILON: Fixed = Fixed { raw: 1 };
/// Archimedes' constant (pi), rounded to nearest (error 1.1e-10).
pub const PI: Fixed = Fixed { raw: PI_RAW };
/// The full circle constant (tau = 2 pi), rounded to nearest (error -1.0e-11).
pub const TAU: Fixed = Fixed { raw: TAU_RAW };
/// pi / 2, rounded to nearest (error -6.1e-11).
pub const FRAC_PI_2: Fixed = Fixed { raw: FRAC_PI_2_RAW };
/// pi / 3, rounded to nearest (error 3.7e-11).
pub const FRAC_PI_3: Fixed = Fixed { raw: 4497679235 };
/// pi / 4, rounded to nearest (error -3.0e-11).
pub const FRAC_PI_4: Fixed = Fixed { raw: 3373259426 };
/// pi / 6, rounded to nearest (error -9.8e-11).
pub const FRAC_PI_6: Fixed = Fixed { raw: 2248839617 };
/// pi / 8, rounded to nearest (error -1.5e-11).
pub const FRAC_PI_8: Fixed = Fixed { raw: 1686629713 };
/// 1 / pi, rounded to nearest (error -3.6e-11).
pub const FRAC_1_PI: Fixed = Fixed { raw: 1367130551 };
/// 2 / pi, rounded to nearest (error -7.1e-11).
pub const FRAC_2_PI: Fixed = Fixed { raw: 2734261102 };
/// Euler's number (e), rounded to nearest (error 1.1e-10).
pub const E: Fixed = Fixed { raw: 11674931555 };
/// sqrt(2), rounded to nearest (error 1.1e-11).
pub const SQRT_2: Fixed = Fixed { raw: 6074001000 };
/// 1 / sqrt(2), rounded to nearest (error 5.6e-12).
pub const FRAC_1_SQRT_2: Fixed = Fixed { raw: 3037000500 };
/// ln(2), rounded to nearest (error 4.2e-11).
pub const LN_2: Fixed = Fixed { raw: 2977044472 };
/// ln(10), rounded to nearest (error 7.8e-11).
pub const LN_10: Fixed = Fixed { raw: 9889527671 };
/// pi / 180: degrees to radians factor, rounded to nearest (error 9.8e-11, i.e. 5.6e-9 relative:
/// prefer dividing by [`RAD_TO_DEG`] when precision matters).
pub const DEG_TO_RAD: Fixed = Fixed { raw: 74961321 };
/// 180 / pi: radians to degrees factor, rounded to nearest (error 1.1e-10).
pub const RAD_TO_DEG: Fixed = Fixed { raw: 246083499208 };

/// Signed Q32.32 fixed-point number. `value = raw / 2^32`.
#[derive(Copy, Drop, Serde, PartialEq, Debug, Default, Hash)]
pub struct Fixed {
    pub raw: i64,
}

pub trait FixedTrait {
    /// Builds a `Fixed` from its raw Q32.32 representation.
    ///
    /// Mirrors `f32::from_bits` in spirit.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_raw(raw: i64) -> Fixed;
    /// Returns the raw Q32.32 representation.
    ///
    /// Mirrors `f32::to_bits` in spirit.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn to_raw(self: Fixed) -> i64;
    /// Converts an integer (exact, every `i32` is representable; one step, no range check).
    ///
    /// Mirrors `i32 as f32`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_int(v: i32) -> Fixed;
    /// Builds `num / den` from two integers, rounded to nearest (ties to even) like `/`. The
    /// operands are plain integers, not raw values: `from_ratio(1, 3)` is one third.
    ///
    /// Convenience for literals; no glam-rs counterpart.
    /// #### Panics
    /// * `'Fixed: division by zero'` if `den` is zero.
    /// * `'Fixed: overflow'` if the quotient does not fit the scalar range.
    /// #### Deviations
    /// * Division by zero or overflow panics where floating-point division returns infinity or a
    ///   larger finite value: docs/DESIGN.md section 3, "division by zero" and "overflow".
    fn from_ratio(num: i64, den: i64) -> Fixed;
    /// Converts to an integer, rounding toward negative infinity. Never fails: the integer part of
    /// every `Fixed` fits an `i32`.
    ///
    /// Mirrors `f32::floor() as i32`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn to_int(self: Fixed) -> i32;
    /// Converts to an integer, rounding toward zero.
    ///
    /// Mirrors `f32 as i32`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn to_int_trunc(self: Fixed) -> i32;
    /// Converts to the nearest integer, ties away from zero.
    ///
    /// Mirrors `f32::round() as i32`.
    /// #### Panics
    /// * `'Fixed: overflow'` if `self >= 2^31 - 1/2`.
    /// #### Deviations
    /// * Panics instead of saturating.
    fn to_int_round(self: Fixed) -> i32;
    /// Computes the absolute value.
    ///
    /// Mirrors `f32::abs`.
    /// #### Panics
    /// * `'Fixed: overflow'` if `self` is `MIN`.
    /// #### Deviations
    /// * Overflow panics where `f32` returns the finite value `2^31`: docs/DESIGN.md section 3,
    ///   "overflow".
    fn abs(self: Fixed) -> Fixed;
    /// Returns `-1` if `self` is negative, `+1` otherwise.
    ///
    /// Mirrors `f32::signum`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * `signum(0) = +1`, as for `+0.0` in Rust (there is no negative zero).
    fn signum(self: Fixed) -> Fixed;
    /// Returns the magnitude of `self` with the sign of `sign` (zero counts as positive).
    ///
    /// Mirrors `f32::copysign`.
    /// #### Panics
    /// * `'Fixed: overflow'` if `self` is `MIN` and `sign` is not negative.
    /// #### Deviations
    /// * Overflow panics where `f32` returns the finite value `2^31`: docs/DESIGN.md section 3,
    ///   "overflow".
    fn copysign(self: Fixed, sign: Fixed) -> Fixed;
    /// Returns `true` if `self < 0`.
    ///
    /// Mirrors `i64::is_negative`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn is_negative(self: Fixed) -> bool;
    /// Returns `true` if `self > 0`.
    ///
    /// Mirrors `i64::is_positive`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn is_positive(self: Fixed) -> bool;
    /// Returns `true` if `self < 0`.
    ///
    /// Mirrors `f32::is_sign_negative`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * There is no negative zero: identical to `is_negative`.
    fn is_sign_negative(self: Fixed) -> bool;
    /// Returns `true` if `self >= 0`.
    ///
    /// Mirrors `f32::is_sign_positive`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * Zero is positive (there is no negative zero).
    fn is_sign_positive(self: Fixed) -> bool;
    /// Returns the smaller of two values.
    ///
    /// Mirrors `f32::min`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn min(self: Fixed, other: Fixed) -> Fixed;
    /// Returns the larger of two values.
    ///
    /// Mirrors `f32::max`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn max(self: Fixed, other: Fixed) -> Fixed;
    /// Restricts `self` to the interval `[min, max]`. Precondition: `min <= max`.
    ///
    /// Mirrors `f32::clamp`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * Rust panics when `min > max`; the precondition is not checked here. For a reversed range,
    ///   this branch order returns `min` when `self < min`, `max` when `self > max`, and `self`
    ///   otherwise. In particular, values below both bounds select `min`, whereas
    ///   `self.max(min).min(max)` selects `max`.
    fn clamp(self: Fixed, min: Fixed, max: Fixed) -> Fixed;
    /// Returns the largest integer less than or equal to `self`.
    ///
    /// Mirrors `f32::floor`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn floor(self: Fixed) -> Fixed;
    /// Returns the smallest integer greater than or equal to `self`.
    ///
    /// Mirrors `f32::ceil`.
    /// #### Panics
    /// * `'Fixed: overflow'` if `self > 2^31 - 1`.
    /// #### Deviations
    /// * Overflow panics where `f32` returns the finite value `2^31`: docs/DESIGN.md section 3,
    ///   "overflow".
    fn ceil(self: Fixed) -> Fixed;
    /// Returns the nearest integer, ties away from zero.
    ///
    /// Mirrors `f32::round`.
    /// #### Panics
    /// * `'Fixed: overflow'` if `self >= 2^31 - 1/2`.
    /// #### Deviations
    /// * Overflow panics where `f32` returns the finite value `2^31`: docs/DESIGN.md section 3,
    ///   "overflow".
    fn round(self: Fixed) -> Fixed;
    /// Returns the integer part, rounding toward zero.
    ///
    /// Mirrors `f32::trunc`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn trunc(self: Fixed) -> Fixed;
    /// Returns `self - self.trunc()`: the fractional part with the sign of `self`.
    ///
    /// Mirrors `f32::fract`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn fract(self: Fixed) -> Fixed;
    /// Returns `self - self.floor()`: the fractional part in `[0, 1)` (GLSL `fract`).
    ///
    /// Mirrors `glam::FloatExt::fract_gl`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn fract_gl(self: Fixed) -> Fixed;
    /// Returns `1 / self`, rounded to nearest, ties to even, like `1.0 / x` in Rust (one sign split
    /// instead of the two of `/`; the exact `2^64 / raw` is never a tie).
    ///
    /// Mirrors `f32::recip`.
    /// #### Panics
    /// * `'Fixed: division by zero'` if `self` is zero.
    /// * `'Fixed: overflow'` if `self` is `-1`, `1` or `2` raw (`2^64 / raw` does not fit; `-2`
    ///   raw gives `MIN`).
    /// #### Deviations
    /// * Panics instead of returning infinity.
    fn recip(self: Fixed) -> Fixed;
    /// Named alias of `self / rhs`: the exact quotient `self.raw * 2^32 / rhs.raw` rounded to the
    /// nearest raw value, ties to even (the rounding of `f64 /`). Exact whenever the quotient is
    /// representable. [`crate::wide::RecipNearestTrait::div_nearest`] returns the same bits for a
    /// divisor shared by several quotients.
    ///
    /// Mirrors `f32 / f32` (`Div::div`), rounding included.
    /// #### Panics
    /// * `'Fixed: division by zero'` if `rhs` is zero.
    /// * `'Fixed: overflow'` if the rounded quotient does not fit the scalar range.
    /// #### Deviations
    /// * None on the rounding (`/` is the same kernel; up to 0.2 it truncated toward zero).
    ///   Division by zero or overflow panics where floating-point division returns infinity:
    ///   docs/DESIGN.md section 3, "division by zero" and "overflow".
    fn div_nearest(self: Fixed, rhs: Fixed) -> Fixed;
    /// Named alias of [`FixedTrait::recip`]: `1 / self` correctly rounded (to nearest, ties to
    /// even), bit-identical to `ONE / self`, with one sign split instead of two.
    ///
    /// Mirrors `f32::recip`, rounding included.
    /// #### Panics
    /// * `'Fixed: division by zero'` if `self` is zero.
    /// * `'Fixed: overflow'` if `self` is `-1`, `1` or `2` raw (`2^64 / raw` does not fit; `-2`
    ///   raw gives `MIN`).
    /// #### Deviations
    /// * None on the rounding (up to 0.2 `recip` truncated toward zero). Panics instead of
    ///   returning infinity.
    fn recip_nearest(self: Fixed) -> Fixed;
    /// Returns the square root, rounded toward zero (exact integer square root of `raw * 2^32`).
    ///
    /// Mirrors `f32::sqrt`.
    /// #### Panics
    /// * `'Fixed: sqrt negative'` if `self < 0`.
    /// #### Deviations
    /// * Panics instead of returning NaN.
    fn sqrt(self: Fixed) -> Fixed;
    /// Returns the integer `n` such that `self = n * rhs + self.rem_euclid(rhs)`.
    ///
    /// Mirrors `f32::div_euclid` (`glam::f32::math::div_euclid`).
    /// #### Panics
    /// * `'Fixed: division by zero'` if `rhs` is zero.
    /// * `'Fixed: overflow'` if `n` does not fit the scalar range.
    /// #### Deviations
    /// * Exact (computed on the raw integers, no intermediate rounding).
    fn div_euclid(self: Fixed, rhs: Fixed) -> Fixed;
    /// Returns the least non-negative remainder of `self` modulo `|rhs|`, in `[0, |rhs|)`.
    ///
    /// Implementation notes:
    /// * Exact: always strictly below `|rhs|` (the f32 version can round up to `|rhs|`).
    ///
    /// Mirrors `f32::rem_euclid` (`glam::f32::math::rem_euclid`).
    /// #### Panics
    /// * `'Fixed: division by zero'` if `rhs` is zero.
    /// #### Deviations
    /// * Division by zero panics where `f32` returns NaN: docs/DESIGN.md section 3, "division by
    ///   zero".
    fn rem_euclid(self: Fixed, rhs: Fixed) -> Fixed;
    /// Computes `self * a + b` with a single rescale (floor of the exact value).
    ///
    /// Mirrors `f32::mul_add`.
    /// #### Panics
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    /// #### Deviations
    /// * Overflow panics where `f32` returns infinity or a larger finite value:
    ///   docs/DESIGN.md section 3, "overflow".
    fn mul_add(self: Fixed, a: Fixed, b: Fixed) -> Fixed;
    /// Computes `self` to an integer power. `|n| <= 4` is unrolled (`n = 2, 3`: floor of the
    /// exact power, `n = 4`: `floor(floor(x^2)^2)`); larger exponents use binary exponentiation
    /// (least significant bit first, every product rounded toward negative infinity). A negative
    /// `n` returns `recip` (rounded to nearest, ties to even) of the positive power. Not inlined
    /// (loop): prefer `x * x` for a constant exponent, it is 3.6x cheaper.
    ///
    /// Mirrors `f32::powi`.
    /// #### Panics
    /// * `'Fixed: overflow'` if an intermediate power does not fit the scalar range.
    /// * `'Fixed: division by zero'` if `n < 0` and `self^|n|` rounds to zero.
    /// #### Deviations
    /// * `powi(0, 0) = 1` as in Rust; panics where Rust returns infinity.
    fn powi(self: Fixed, n: i32) -> Fixed;
    /// Linear interpolation `self + (rhs - self) * t` with a single rescale; `t` is not clamped.
    /// `rhs - self` is computed exactly: it cannot overflow.
    ///
    /// Mirrors `glam::FloatExt::lerp`.
    /// #### Panics
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    /// #### Deviations
    /// * Floor of the exact value: `lerp(a, b, 0) = a` and `lerp(a, b, 1) = b` exactly.
    fn lerp(self: Fixed, rhs: Fixed, t: Fixed) -> Fixed;
    /// Returns `t` such that `a.lerp(b, t) ~= v`: `(v - a) / (b - a)`.
    ///
    /// Mirrors `glam::FloatExt::inverse_lerp`.
    /// #### Panics
    /// * `'Fixed: division by zero'` if `a == b`.
    /// * `'i64_sub Overflow'` / `'i64_sub Underflow'` if `v - a` or `b - a` does not fit the
    ///   scalar range.
    /// * `'Fixed: overflow'` if the quotient does not fit the scalar range.
    /// #### Deviations
    /// * Panics instead of returning NaN / infinity.
    fn inverse_lerp(a: Fixed, b: Fixed, v: Fixed) -> Fixed;
    /// Remaps `self` from the range `[in_start, in_end]` to `[out_start, out_end]` (unclamped).
    ///
    /// Mirrors `glam::FloatExt::remap`.
    /// #### Panics
    /// * As `inverse_lerp` and `lerp`.
    /// #### Deviations
    /// * Division by zero or overflow panics where floating-point arithmetic returns NaN,
    ///   infinity or a larger finite value: docs/DESIGN.md section 3, "division by zero" and
    ///   "overflow".
    fn remap(
        self: Fixed, in_start: Fixed, in_end: Fixed, out_start: Fixed, out_end: Fixed,
    ) -> Fixed;
    /// GLSL `step`: `0` if `value < self` (the edge), `1` otherwise.
    ///
    /// Mirrors `glam::FloatExt::step`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn step(self: Fixed, value: Fixed) -> Fixed;
    /// Clamps `self` to `[0, 1]`.
    ///
    /// Mirrors `glam::FloatExt::saturate`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn saturate(self: Fixed) -> Fixed;
    /// GLSL `smoothstep`: `t * t * (3 - 2 t)` with `t = saturate((self - edge0) / (edge1 -
    /// edge0))`. The polynomial is evaluated exactly and rescaled once.
    ///
    /// Mirrors `glam::FloatExt::smoothstep`.
    /// #### Panics
    /// * `'Fixed: division by zero'` if `edge0 == edge1`.
    /// * `'i64_sub Overflow'` / `'i64_sub Underflow'` / `'Fixed: overflow'` if `self - edge0`,
    ///   `edge1 - edge0` or their quotient does not fit the scalar range.
    /// #### Deviations
    /// * Panics instead of returning NaN when the edges are equal.
    fn smoothstep(self: Fixed, edge0: Fixed, edge1: Fixed) -> Fixed;
    /// Moves `self` toward `rhs` by at most `d` (a negative `d` moves away).
    ///
    /// Mirrors `glam::FloatExt::move_towards`.
    /// #### Panics
    /// * `'i64_sub Overflow'` / `'i64_sub Underflow'` if `rhs - self` does not fit the scalar
    ///   range.
    /// * `'i64_add Underflow'` / `'i64_sub Overflow'` if `self +- d` does not fit the scalar
    ///   range, only reachable on the away branches (a negative `d`): the towards branches
    ///   cannot leave the range, since `self + d < rhs` / `self - d > rhs` there (R1
    ///   panic-coverage audit, escalation 2).
    /// * `'i64_neg Underflow'` if `d` is `MIN`.
    /// #### Deviations
    /// * Overflow panics where `f32` returns infinity or a larger finite value:
    ///   docs/DESIGN.md section 3, "overflow".
    fn move_towards(self: Fixed, rhs: Fixed, d: Fixed) -> Fixed;
    /// Returns `true` if `|self - other| <= max_abs_diff`. The difference is computed exactly: it
    /// never overflows.
    ///
    /// Mirrors `glam`'s `abs_diff_eq` (as on `Vec3`), for scalars.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn abs_diff_eq(self: Fixed, other: Fixed, max_abs_diff: Fixed) -> bool;
}

pub impl FixedImpl of FixedTrait {
    #[inline(always)]
    fn from_raw(raw: i64) -> Fixed {
        Fixed { raw }
    }
    #[inline(always)]
    fn to_raw(self: Fixed) -> i64 {
        self.raw
    }
    #[inline(always)]
    fn from_int(v: i32) -> Fixed {
        Fixed { raw: bounded::from_int(v) }
    }
    #[inline(always)]
    fn from_ratio(num: i64, den: i64) -> Fixed {
        Fixed { raw: bounded::div_nearest(num, den) }
    }
    #[inline(always)]
    fn to_int(self: Fixed) -> i32 {
        bounded::to_int_floor(self.raw)
    }
    #[inline(always)]
    fn to_int_trunc(self: Fixed) -> i32 {
        bounded::to_int_trunc(self.raw)
    }
    #[inline(always)]
    fn to_int_round(self: Fixed) -> i32 {
        bounded::to_int_round(self.raw)
    }
    #[inline(always)]
    fn abs(self: Fixed) -> Fixed {
        Fixed { raw: bounded::abs(self.raw) }
    }
    #[inline(always)]
    fn signum(self: Fixed) -> Fixed {
        if bounded::is_negative(self.raw) {
            NEG_ONE
        } else {
            ONE
        }
    }
    #[inline(always)]
    fn copysign(self: Fixed, sign: Fixed) -> Fixed {
        Fixed { raw: bounded::copysign(self.raw, sign.raw) }
    }
    #[inline(always)]
    fn is_negative(self: Fixed) -> bool {
        bounded::is_negative(self.raw)
    }
    #[inline(always)]
    fn is_positive(self: Fixed) -> bool {
        self.raw > 0
    }
    #[inline(always)]
    fn is_sign_negative(self: Fixed) -> bool {
        bounded::is_negative(self.raw)
    }
    #[inline(always)]
    fn is_sign_positive(self: Fixed) -> bool {
        !bounded::is_negative(self.raw)
    }
    #[inline(always)]
    fn min(self: Fixed, other: Fixed) -> Fixed {
        if self.raw < other.raw {
            self
        } else {
            other
        }
    }
    #[inline(always)]
    fn max(self: Fixed, other: Fixed) -> Fixed {
        if self.raw < other.raw {
            other
        } else {
            self
        }
    }
    #[inline(always)]
    fn clamp(self: Fixed, min: Fixed, max: Fixed) -> Fixed {
        if self.raw < min.raw {
            min
        } else if max.raw < self.raw {
            max
        } else {
            self
        }
    }
    #[inline(always)]
    fn floor(self: Fixed) -> Fixed {
        Fixed { raw: bounded::floor(self.raw) }
    }
    #[inline(always)]
    fn ceil(self: Fixed) -> Fixed {
        Fixed { raw: bounded::ceil(self.raw) }
    }
    #[inline(always)]
    fn round(self: Fixed) -> Fixed {
        Fixed { raw: bounded::round(self.raw) }
    }
    #[inline(always)]
    fn trunc(self: Fixed) -> Fixed {
        Fixed { raw: bounded::trunc(self.raw) }
    }
    #[inline(always)]
    fn fract(self: Fixed) -> Fixed {
        Fixed { raw: bounded::fract_trunc(self.raw) }
    }
    #[inline(always)]
    fn fract_gl(self: Fixed) -> Fixed {
        Fixed { raw: bounded::fract_floor(self.raw) }
    }
    #[inline(always)]
    fn recip(self: Fixed) -> Fixed {
        Fixed { raw: bounded::recip_nearest(self.raw) }
    }
    #[inline(always)]
    fn div_nearest(self: Fixed, rhs: Fixed) -> Fixed {
        Fixed { raw: bounded::div_nearest(self.raw, rhs.raw) }
    }
    #[inline(always)]
    fn recip_nearest(self: Fixed) -> Fixed {
        Fixed { raw: bounded::recip_nearest(self.raw) }
    }
    #[inline(always)]
    fn sqrt(self: Fixed) -> Fixed {
        Fixed { raw: bounded::sqrt(self.raw) }
    }
    #[inline(always)]
    fn div_euclid(self: Fixed, rhs: Fixed) -> Fixed {
        Fixed { raw: bounded::div_euclid(self.raw, rhs.raw) }
    }
    #[inline(always)]
    fn rem_euclid(self: Fixed, rhs: Fixed) -> Fixed {
        Fixed { raw: bounded::rem_euclid(self.raw, rhs.raw) }
    }
    #[inline(always)]
    fn mul_add(self: Fixed, a: Fixed, b: Fixed) -> Fixed {
        Fixed { raw: bounded::mul_add(self.raw, a.raw, b.raw) }
    }
    fn powi(self: Fixed, n: i32) -> Fixed {
        let wide: i64 = n.into();
        let negative = wide < 0;
        // |i32| always fits a u32.
        let e: u32 = (if negative {
            -wide
        } else {
            wide
        }).try_into().unwrap();
        let p = match e {
            0 => ONE,
            1 => self,
            2 => self * self,
            3 => Fixed { raw: bounded::mul3(self.raw, self.raw, self.raw) },
            4 => {
                let x2 = self * self;
                x2 * x2
            },
            _ => powi_loop(self, e),
        };
        if negative {
            Self::recip(p)
        } else {
            p
        }
    }
    #[inline(always)]
    fn lerp(self: Fixed, rhs: Fixed, t: Fixed) -> Fixed {
        Fixed { raw: bounded::lerp(self.raw, rhs.raw, t.raw) }
    }
    #[inline(always)]
    fn inverse_lerp(a: Fixed, b: Fixed, v: Fixed) -> Fixed {
        (v - a) / (b - a)
    }
    #[inline(always)]
    fn remap(
        self: Fixed, in_start: Fixed, in_end: Fixed, out_start: Fixed, out_end: Fixed,
    ) -> Fixed {
        Self::lerp(out_start, out_end, Self::inverse_lerp(in_start, in_end, self))
    }
    #[inline(always)]
    fn step(self: Fixed, value: Fixed) -> Fixed {
        if value.raw < self.raw {
            ZERO
        } else {
            ONE
        }
    }
    #[inline(always)]
    fn saturate(self: Fixed) -> Fixed {
        Self::clamp(self, ZERO, ONE)
    }
    #[inline(always)]
    fn smoothstep(self: Fixed, edge0: Fixed, edge1: Fixed) -> Fixed {
        let t = Self::saturate((self - edge0) / (edge1 - edge0));
        Fixed { raw: bounded::smooth(t.raw) }
    }
    #[inline(always)]
    fn move_towards(self: Fixed, rhs: Fixed, d: Fixed) -> Fixed {
        let a = rhs - self;
        if bounded::is_negative(a.raw) {
            if a.raw >= -d.raw {
                rhs
            } else {
                self - d
            }
        } else if a.raw <= d.raw {
            rhs
        } else {
            self + d
        }
    }
    #[inline(always)]
    fn abs_diff_eq(self: Fixed, other: Fixed, max_abs_diff: Fixed) -> bool {
        let diff: i128 = bounded::abs_diff(self.raw, other.raw).into();
        diff <= max_abs_diff.raw.into()
    }
}

/// Binary exponentiation, least significant bit first; every product rounds toward negative
/// infinity.
fn powi_loop(x: Fixed, n: u32) -> Fixed {
    let mut e = n;
    let mut base = x;
    let mut acc = ONE;
    while e != 0 {
        let (q, r) = DivRem::div_rem(e, 2);
        if r == 1 {
            acc = acc * base;
        }
        e = q;
        if e != 0 {
            base = base * base;
        }
    }
    acc
}

pub impl FixedAdd of Add<Fixed> {
    /// `lhs + rhs` (exact). Panics with `'i64_add Overflow'` / `'i64_add Underflow'` when out of
    /// range.
    #[inline(always)]
    fn add(lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed { raw: lhs.raw + rhs.raw }
    }
}

pub impl FixedSub of Sub<Fixed> {
    /// `lhs - rhs` (exact). Panics with `'i64_sub Overflow'` / `'i64_sub Underflow'` when out of
    /// range.
    #[inline(always)]
    fn sub(lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed { raw: lhs.raw - rhs.raw }
    }
}

pub impl FixedMul of Mul<Fixed> {
    /// `floor(lhs * rhs)`: rounds toward negative infinity. Panics with `'Fixed: overflow'` when
    /// out of range.
    #[inline(always)]
    fn mul(lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed { raw: bounded::mul(lhs.raw, rhs.raw) }
    }
}

pub impl FixedDiv of Div<Fixed> {
    /// `lhs / rhs` rounded to nearest, ties to even, like `f64 /` (up to 0.2 it truncated toward
    /// zero). Panics with `'Fixed: division by zero'` or `'Fixed: overflow'`.
    #[inline(always)]
    fn div(lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed { raw: bounded::div_nearest(lhs.raw, rhs.raw) }
    }
}

pub impl FixedRem of Rem<Fixed> {
    /// Remainder of the truncated division (sign of `lhs`, exact), like Rust's `%` on floats.
    /// Panics with `'Fixed: division by zero'`.
    #[inline(always)]
    fn rem(lhs: Fixed, rhs: Fixed) -> Fixed {
        Fixed { raw: bounded::rem_trunc(lhs.raw, rhs.raw) }
    }
}

pub impl FixedNeg of Neg<Fixed> {
    /// `-a` (exact). Panics with `'i64_neg Underflow'` for `MIN`.
    #[inline(always)]
    fn neg(a: Fixed) -> Fixed {
        Fixed { raw: -a.raw }
    }
}

pub impl FixedPartialOrd of PartialOrd<Fixed> {
    #[inline(always)]
    fn lt(lhs: Fixed, rhs: Fixed) -> bool {
        lhs.raw < rhs.raw
    }
    #[inline(always)]
    fn le(lhs: Fixed, rhs: Fixed) -> bool {
        lhs.raw <= rhs.raw
    }
    #[inline(always)]
    fn gt(lhs: Fixed, rhs: Fixed) -> bool {
        lhs.raw > rhs.raw
    }
    #[inline(always)]
    fn ge(lhs: Fixed, rhs: Fixed) -> bool {
        lhs.raw >= rhs.raw
    }
}

pub impl FixedAddAssign of AddAssign<Fixed, Fixed> {
    #[inline(always)]
    fn add_assign(ref self: Fixed, rhs: Fixed) {
        self = self + rhs;
    }
}

pub impl FixedSubAssign of SubAssign<Fixed, Fixed> {
    #[inline(always)]
    fn sub_assign(ref self: Fixed, rhs: Fixed) {
        self = self - rhs;
    }
}

pub impl FixedMulAssign of MulAssign<Fixed, Fixed> {
    #[inline(always)]
    fn mul_assign(ref self: Fixed, rhs: Fixed) {
        self = self * rhs;
    }
}

pub impl FixedDivAssign of DivAssign<Fixed, Fixed> {
    #[inline(always)]
    fn div_assign(ref self: Fixed, rhs: Fixed) {
        self = self / rhs;
    }
}

pub impl FixedRemAssign of RemAssign<Fixed, Fixed> {
    #[inline(always)]
    fn rem_assign(ref self: Fixed, rhs: Fixed) {
        self = self % rhs;
    }
}

pub impl FixedZero of Zero<Fixed> {
    #[inline(always)]
    fn zero() -> Fixed {
        ZERO
    }
    #[inline(always)]
    fn is_zero(self: @Fixed) -> bool {
        *self.raw == 0
    }
    #[inline(always)]
    fn is_non_zero(self: @Fixed) -> bool {
        *self.raw != 0
    }
}

pub impl FixedOne of One<Fixed> {
    #[inline(always)]
    fn one() -> Fixed {
        ONE
    }
    #[inline(always)]
    fn is_one(self: @Fixed) -> bool {
        *self.raw == ONE_RAW
    }
    #[inline(always)]
    fn is_non_one(self: @Fixed) -> bool {
        *self.raw != ONE_RAW
    }
}

pub impl FixedBounded of Bounded<Fixed> {
    const MIN: Fixed = MIN;
    const MAX: Fixed = MAX;
}

pub impl I8IntoFixed of Into<i8, Fixed> {
    #[inline(always)]
    fn into(self: i8) -> Fixed {
        FixedTrait::from_int(self.into())
    }
}

pub impl I16IntoFixed of Into<i16, Fixed> {
    #[inline(always)]
    fn into(self: i16) -> Fixed {
        FixedTrait::from_int(self.into())
    }
}

pub impl I32IntoFixed of Into<i32, Fixed> {
    #[inline(always)]
    fn into(self: i32) -> Fixed {
        FixedTrait::from_int(self)
    }
}

pub impl U8IntoFixed of Into<u8, Fixed> {
    #[inline(always)]
    fn into(self: u8) -> Fixed {
        Fixed { raw: bounded::from_u16(self.into()) }
    }
}

pub impl U16IntoFixed of Into<u16, Fixed> {
    #[inline(always)]
    fn into(self: u16) -> Fixed {
        Fixed { raw: bounded::from_u16(self) }
    }
}

/// `None` above `2^31 - 1`.
pub impl U32TryIntoFixed of TryInto<u32, Fixed> {
    #[inline(always)]
    fn try_into(self: u32) -> Option<Fixed> {
        let v: i32 = self.try_into()?;
        Some(FixedTrait::from_int(v))
    }
}

/// `None` outside `[-2^31, 2^31 - 1]`.
pub impl I64TryIntoFixed of TryInto<i64, Fixed> {
    #[inline(always)]
    fn try_into(self: i64) -> Option<Fixed> {
        let v: i32 = self.try_into()?;
        Some(FixedTrait::from_int(v))
    }
}

/// `None` above `2^31 - 1`.
pub impl U64TryIntoFixed of TryInto<u64, Fixed> {
    #[inline(always)]
    fn try_into(self: u64) -> Option<Fixed> {
        let v: i32 = self.try_into()?;
        Some(FixedTrait::from_int(v))
    }
}
