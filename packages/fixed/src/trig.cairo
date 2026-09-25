//! Loop-free transcendental functions (sin, cos, sin_cos, tan, atan2, acos, asin).
//!
//! Every function is straight-line code: a range reduction by a **constant** divisor
//! (`DivRem`, never a loop), a `match` on the reduced index (never an if-chain) and a minimax
//! polynomial in Horner form. No table lookup, no CORDIC, no Taylor recursion.
//!
//! The polynomial accumulators carry 24 extra fractional bits (coefficients scaled by `2^24`,
//! each Horner step being a single rescale), so the rounding of the evaluation itself is
//! invisible: the error of every function below is dominated by its **final** rescale and by the
//! minimax residual. That final rescale **rounds to nearest** (ties toward +infinity), the
//! second exception to the floor rule of `docs/DESIGN.md` section 2 after
//! `wide::RecipTrait::mul`, which halves the error and centres it on zero: `sin` and `cos` are
//! within 1.02 ULP of the exact value over a whole turn, 0.55 ULP inside one octant.
//!
//! It costs nothing. Where the result leaves a Q96.96 accumulator (`sin`, `acos`) the rounding
//! is the bias of [`bounded::narrow64_round`] instead of the bias of `narrow64`; where it leaves
//! a plain `Fixed *` (`cos`, `atan`) half a unit of that rescale is baked into the constant term
//! of the polynomial by the generator, so the floor of the biased polynomial *is* the
//! round-to-nearest of the exact one. `tan` (a division, rounded half to even like every `/` of the
//! crate)
//! and `to_radians` / `to_degrees` (a plain multiplication, floored like every `*`) keep the
//! house rounding: making them round as well would cost a second division and 570 gas
//! respectively, for no measurable gain.
//!
//! The coefficients, the reduction constants and the measured errors come from
//! [`scripts/gen_trig.py`](../../../../scripts/gen_trig.py), which also mirrors every function
//! of this module in Python integer arithmetic, bit for bit, and sweeps the mirror against
//! 60-digit references (`scripts/gen_trig.py sweep`). The table of measured errors is at the end
//! of the generated block below.
//!
//! Symmetries are exact **by construction**, not by approximation: the reduction runs on `|x|`
//! and the sign is applied to the result, so `sin(-x) = -sin(x)`, `cos(-x) = cos(x)`,
//! `atan(-x) = -atan(x)` and `asin(-x) = -asin(x)` hold for every input.
#[feature("bounded-int-utils")]
use core::internal::bounded_int::upcast;
use crate::fixed::{FRAC_PI_2, Fixed, FixedTrait, ONE, ONE_RAW, PI, ZERO};
use crate::internal::bounded;
use crate::wide::{
    W1, WideAdd, WideLift, WideMul, WideNarrow, WideSqrt, mul_add, wide_from, wide_mul,
};

// GENERATED-BEGIN trig
/// `floor(pi / 4 * 2^32)`: the octant divisor of the range reduction.
pub const FRAC_PI_4_RAW: u64 = 3373259426;
const FRAC_PI_4_NZ: NonZero<u64> = 3373259426;
/// `(pi / 4 * 2^32 - FRAC_PI_4_RAW) * 2^32`: the Cody-Waite tail of `pi / 4`, subtracted
/// once per octant beyond the first turn so that the reduction of a large angle stays
/// accurate to ~1 ULP instead of drifting by `k * 1.6e-11` radians.
const FRAC_PI_4_TAIL: u64 = 560513589;
/// Half a unit of the tail rescale: makes the Cody-Waite correction round to nearest.
const FRAC_PI_4_TAIL_HALF: u64 = 2147483648;
/// The octant divisor as an `i64` (the reduced angle is signed: see `reduce8`).
const FRAC_PI_4_RAW_I: i64 = 3373259426;
const EIGHT_NZ: NonZero<u64> = 8;
const TWO_POW_32_NZ: NonZero<u64> = 0x100000000;
/// The atan segment width, `1 / 8` in raw units.
const ATAN_SEG_NZ: NonZero<u64> = 0x20000000;
/// `pi / 4` scaled by `2^24`, the value of the last atan segment (`z == 1`); rescaled by
/// `INV_SCALE` like every other segment, it yields exactly `FRAC_PI_4`.
const FRAC_PI_4_SCALED: Fixed = Fixed { raw: 0xc90fdaa2a168c2 };
/// `2^-24`, exact: undoes the scaling of the polynomial accumulators in the single
/// rescale that produces the result.
const INV_SCALE: Fixed = Fixed { raw: 256 };

/// `sin(z) / z` as a polynomial in `u = z * z`, degree 4, coefficients scaled by
/// `2^24`. Minimax on `[0, (pi/4)^2]` with the constant term pinned to 1 so that
/// `sin(z) = z` for a tiny `z`.
#[inline(always)]
fn sin_poly(u: W1) -> Fixed {
    let acc = Fixed { raw: 0x2db7c95a39 };
    let acc = step(u, acc, Fixed { raw: -0xd009d4451ec });
    let acc = step(u, acc, Fixed { raw: 0x222221be02480 });
    let acc = step(u, acc, Fixed { raw: -0x2aaaaaaa8bd0fc });
    step(u, acc, Fixed { raw: 0x100000000000000 })
}

/// `cos(z)` as a polynomial in `u = z * z`, degree 5, coefficients scaled by
/// `2^24`. Minimax on `[0, (pi/4)^2]` with the constant term pinned to 1 so that
/// `cos(0) = 1` exactly.
#[inline(always)]
fn cos_poly(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x491d41f32 };
    let acc = step(u, acc, Fixed { raw: 0x1a0129994d5 });
    let acc = step(u, acc, Fixed { raw: -0x5b05aeb9c4ac });
    let acc = step(u, acc, Fixed { raw: 0xaaaaaaa8a84bd });
    let acc = step(u, acc, Fixed { raw: -0x7fffffffff9a88 });
    step(u, acc, Fixed { raw: 0x100000000800000 })
}

/// `acos(x) / sqrt(1 - x)` on `[0, 1]`, degree 10, coefficients scaled by `2^24`.
/// The constant term is pinned to `pi / 2` so that `acos(0)` is exactly `FRAC_PI_2` and
/// `asin(0)` exactly zero.
#[inline(always)]
fn acos_poly(x: Fixed) -> Fixed {
    let acc = Fixed { raw: 0x160e567f7243 };
    let acc = mul_add(acc, x, Fixed { raw: -0x87b78bd5ddb8 });
    let acc = mul_add(acc, x, Fixed { raw: 0x18aad9bbbd2be });
    let acc = mul_add(acc, x, Fixed { raw: -0x2f2dc2a75bc9a });
    let acc = mul_add(acc, x, Fixed { raw: 0x4766f11828cee });
    let acc = mul_add(acc, x, Fixed { raw: -0x62a3d52fe6644 });
    let acc = mul_add(acc, x, Fixed { raw: 0x89caac5b0629b });
    let acc = mul_add(acc, x, Fixed { raw: -0xd0090d59071b4 });
    let acc = mul_add(acc, x, Fixed { raw: 0x16cbe296fbc043 });
    let acc = mul_add(acc, x, Fixed { raw: -0x36f0255c37915a });
    mul_add(acc, x, Fixed { raw: 0x1921fb54442d180 })
}

/// `atan(0 / 8 + t)` for `t` in `[0, 1/8)`, degree 5, scaled by `2^24`.
#[inline(always)]
fn atan_seg0(t: Fixed) -> Fixed {
    let acc = Fixed { raw: 0x30dbee1ce528c2 };
    let acc = mul_add(acc, t, Fixed { raw: 0x57eb20a58752 });
    let acc = mul_add(acc, t, Fixed { raw: -0x5559cc3e84d078 });
    let acc = mul_add(acc, t, Fixed { raw: 0x13646adc00 });
    let acc = mul_add(acc, t, Fixed { raw: 0xfffffff2ae0910 });
    mul_add(acc, t, Fixed { raw: 0x800000 })
}

/// `atan(1 / 8 + t)` for `t` in `[0, 1/8)`, degree 5, scaled by `2^24`.
#[inline(always)]
fn atan_seg1(t: Fixed) -> Fixed {
    let acc = Fixed { raw: 0x1c2154179c62df };
    let acc = mul_add(acc, t, Fixed { raw: 0x1f57a14a7863f6 });
    let acc = mul_add(acc, t, Fixed { raw: -0x4dc05a11283c3c });
    let acc = mul_add(acc, t, Fixed { raw: -0x1f0502ba669a70 });
    let acc = mul_add(acc, t, Fixed { raw: 0xfc0fbe971150a0 });
    mul_add(acc, t, Fixed { raw: 0x1fd5ba9c3e6344 })
}

/// `atan(2 / 8 + t)` for `t` in `[0, 1/8)`, degree 5, scaled by `2^24`.
#[inline(always)]
fn atan_seg2(t: Fixed) -> Fixed {
    let acc = Fixed { raw: 0x2646717faf9de };
    let acc = mul_add(acc, t, Fixed { raw: 0x30cc0983ab4e50 });
    let acc = mul_add(acc, t, Fixed { raw: -0x39e9cb6cabc736 });
    let acc = mul_add(acc, t, Fixed { raw: -0x38b059758a93bc });
    let acc = mul_add(acc, t, Fixed { raw: 0xf0f0eebb047c88 });
    mul_add(acc, t, Fixed { raw: 0x3eb6ebf3d27090 })
}

/// `atan(3 / 8 + t)` for `t` in `[0, 1/8)`, degree 5, scaled by `2^24`.
#[inline(always)]
fn atan_seg3(t: Fixed) -> Fixed {
    let acc = Fixed { raw: -0xf708d788aa482 };
    let acc = mul_add(acc, t, Fixed { raw: 0x31ae650588b77e });
    let acc = mul_add(acc, t, Fixed { raw: -0x214d53c9afc8ea });
    let acc = mul_add(acc, t, Fixed { raw: -0x49c94b31fdec3c });
    let acc = mul_add(acc, t, Fixed { raw: 0xe07036fb56cce8 });
    mul_add(acc, t, Fixed { raw: 0x5bd8650890b368 })
}

/// `atan(4 / 8 + t)` for `t` in `[0, 1/8)`, degree 5, scaled by `2^24`.
#[inline(always)]
fn atan_seg4(t: Fixed) -> Fixed {
    let acc = Fixed { raw: -0x157275eac71912 };
    let acc = mul_add(acc, t, Fixed { raw: 0x27795eebcc7186 });
    let acc = mul_add(acc, t, Fixed { raw: -0xaee37259506b0 });
    let acc = mul_add(acc, t, Fixed { raw: -0x51eb7877a48fe4 });
    let acc = mul_add(acc, t, Fixed { raw: 0xccccccaefbef50 });
    mul_add(acc, t, Fixed { raw: 0x76b19c16126570 })
}

/// `atan(5 / 8 + t)` for `t` in `[0, 1/8)`, degree 5, scaled by `2^24`.
#[inline(always)]
fn atan_seg5(t: Fixed) -> Fixed {
    let acc = Fixed { raw: -0x13412a740161f8 };
    let acc = mul_add(acc, t, Fixed { raw: 0x19c92b00cdd988 });
    let acc = mul_add(acc, t, Fixed { raw: 0x57920e279e5e0 });
    let acc = mul_add(acc, t, Fixed { raw: -0x52bcd3fb54c7d8 });
    let acc = mul_add(acc, t, Fixed { raw: 0xb817034aef95d0 });
    mul_add(acc, t, Fixed { raw: 0x8f005d5f47c018 })
}

/// `atan(6 / 8 + t)` for `t` in `[0, 1/8)`, degree 5, scaled by `2^24`.
#[inline(always)]
fn atan_seg6(t: Fixed) -> Fixed {
    let acc = Fixed { raw: -0xde5fe8b6817f8 };
    let acc = mul_add(acc, t, Fixed { raw: 0xdb17e811b2a7e });
    let acc = mul_add(acc, t, Fixed { raw: 0xf67afcad9b173 });
    let acc = mul_add(acc, t, Fixed { raw: -0x4ea4da7f5e5aa4 });
    let acc = mul_add(acc, t, Fixed { raw: 0xa3d70ac5d26238 });
    mul_add(acc, t, Fixed { raw: 0xa4bc7d19786100 })
}

/// `atan(7 / 8 + t)` for `t` in `[0, 1/8)`, degree 5, scaled by `2^24`.
#[inline(always)]
fn atan_seg7(t: Fixed) -> Fixed {
    let acc = Fixed { raw: -0x89a2a56d242da };
    let acc = mul_add(acc, t, Fixed { raw: 0x50e9c426f0ffa });
    let acc = mul_add(acc, t, Fixed { raw: 0x1420bc18430e28 });
    let acc = mul_add(acc, t, Fixed { raw: -0x47dacb221bcb14 });
    let acc = mul_add(acc, t, Fixed { raw: 0x90fdbc7b605bc8 });
    mul_add(acc, t, Fixed { raw: 0xb8053e2c0fbb00 })
}

/// Dispatches `atan(idx / 8 + t)` on the segment index (a jump table, never an if-chain).
/// `idx == 8` is reached only by `z == 1`, whose result is the exact `FRAC_PI_4`.
#[inline(always)]
fn atan_poly(idx: u64, t: Fixed) -> Fixed {
    match idx {
        0 => atan_seg0(t),
        1 => atan_seg1(t),
        2 => atan_seg2(t),
        3 => atan_seg3(t),
        4 => atan_seg4(t),
        5 => atan_seg5(t),
        6 => atan_seg6(t),
        7 => atan_seg7(t),
        _ => FRAC_PI_4_SCALED,
    }
}

/// `pi / 180` scaled by `2^24` (57 significant bits instead of the 32 of `DEG_TO_RAD`).
const DEG_TO_RAD_SCALED: Fixed = Fixed { raw: 0x477d1a894a74e };
/// `180 / pi` scaled by `2^24`.
const RAD_TO_DEG_SCALED: Fixed = Fixed { raw: 0x394bb834c783f000 };

/// Measured maximum absolute error of the mirrored implementation, in ULP (`2^-32`),
/// over 40 001 points per row (`scripts/gen_trig.py sweep`):
///
/// | function | range | max error (ULP) |
/// |---|---|---:|
/// | `sin` | turn | 1.02 |
/// | `cos` | turn | 0.86 |
/// | `sin` | octant | 0.55 |
/// | `cos` | octant | 0.50 |
/// | `sin` | 1000 turns | 1.08 |
/// | `cos` | 1000 turns | 1.07 |
/// | `sin` | near MIN / MAX | 2.03 |
/// | `cos` | near MIN / MAX | 1.71 |
/// | `tan` | [-pi/4, pi/4] | 1.73 |
/// | `tan` | whole branch, error / (1 + tan^2) | 1.18 |
/// | `atan` | -16 to 16 | 2.75 |
/// | `atan2` | unit circle | 2.78 |
/// | `acos` | full | 2.96 |
/// | `asin` | full | 2.25 |
/// | `to_radians` | [-360, 360] deg | 1.00 |
/// | `to_degrees` | [-360, 360] rad | 1.00 |
// GENERATED-END trig

/// `i64::MAX` as a `u64`: the clamp of a magnitude that came back from [`bounded::abs_diff`].
/// Only `MIN` reaches `2^63`, and the clamp is invisible there: `atan` moves by `2^-94` radians
/// between `2^31` and `2^31 - 2^-32`.
const MAX_MAG: u64 = 0x7fffffffffffffff;
/// `ONE_RAW` as a `u64`.
const ONE_MAG: u64 = 0x100000000;

pub trait TrigTrait {
    /// Computes the sine of `self` (in radians).
    ///
    /// Mirrors `f32::sin`.
    /// #### Panics
    /// * Never (the result always fits `[-1, 1]`).
    /// #### Deviations
    /// * Maximum absolute error 1.02 ULP over a turn, 1.08 at `1000 * TAU`, 2.03 at the
    ///   extremes of the range (see the table above): the Cody-Waite tail of `pi / 4` keeps the
    ///   octant reduction accurate instead of drifting with the magnitude of the angle.
    /// * `sin(-x) = -sin(x)` exactly; `sin(0) = 0`, `sin(2^-32) = 2^-32` and
    ///   `sin(FRAC_PI_2) = 1` exactly.
    fn sin(self: Fixed) -> Fixed;
    /// Computes the cosine of `self` (in radians).
    ///
    /// Mirrors `f32::cos`.
    /// #### Panics
    /// * Never (the result always fits `[-1, 1]`).
    /// #### Deviations
    /// * Maximum absolute error 0.86 ULP over a turn, 1.08 at `1000 * TAU`, 1.71 at the
    ///   extremes of the range; `cos(-x) = cos(x)`, `cos(0) = 1`, `cos(2^-32) = 1` and
    ///   `cos(PI) = -1` exactly.
    fn cos(self: Fixed) -> Fixed;
    /// Computes `(sin(self), cos(self))`, sharing the range reduction and `u = z * z`: 1.4x the
    /// cost of `sin` alone instead of the 2x of two calls.
    ///
    /// Mirrors `f32::sin_cos`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * Bit-identical to `(self.sin(), self.cos())`.
    fn sin_cos(self: Fixed) -> (Fixed, Fixed);
    /// Computes the tangent of `self` (in radians) as `sin / cos`.
    ///
    /// Mirrors `f32::tan`.
    /// #### Panics
    /// * `'Fixed: tan overflow'` when `|tan(self)|` does not fit the scalar range, i.e. when
    ///   `self` is within `4.7e-10` (2 ULP of `cos`) of an odd multiple of `pi / 2`, where
    ///   `f32::tan` returns a huge value or infinity.
    /// #### Deviations
    /// * Maximum absolute error 1.73 ULP on `[-pi/4, pi/4]`, and `tan(FRAC_PI_4) = 1` exactly
    ///   (`sin` and `cos` agree there once rounded). `tan` is ill-conditioned near `pi / 2`: a
    ///   1 ULP perturbation of `self` moves the result by `1 + tan^2(self)` ULP, and the
    ///   measured error stays within 1.18 ULP of that bound over the whole branch.
    /// * The division itself rounds to nearest (ties to even), like every `/` of the crate.
    fn tan(self: Fixed) -> Fixed;
    /// Computes the arcsine of `self`, in radians, in `[-pi/2, pi/2]`.
    ///
    /// Mirrors `f32::asin`.
    /// #### Panics
    /// * `'Fixed: asin domain'` if `|self| > 1` (`f32::asin` returns NaN).
    /// #### Deviations
    /// * Maximum absolute error 2.25 ULP. `asin(0) = 0`, `asin(1) = FRAC_PI_2` and
    ///   `asin(-x) = -asin(x)` are exact.
    fn asin(self: Fixed) -> Fixed;
    /// Computes the arccosine of `self`, in radians, in `[0, pi]`.
    ///
    /// Mirrors `f32::acos`.
    /// #### Panics
    /// * `'Fixed: acos domain'` if `|self| > 1` (`f32::acos` returns NaN).
    /// #### Deviations
    /// * Maximum absolute error 2.96 ULP. `acos(1) = 0`, `acos(0) = FRAC_PI_2` and
    ///   `acos(-1) = PI` are exact.
    /// * Replaces `glam::f32::math::acos_approx` (a degree-7 approximation): this one is exact
    ///   to 3 ULP, which is why `glam-cairo` has no `*_approx` variant.
    fn acos(self: Fixed) -> Fixed;
    /// Computes the arcsine of `self` clamped to `[-1, 1]` first.
    ///
    /// Mirrors the clamping of `glam::f32::math::asin_approx`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * Same values as [`TrigTrait::asin`] inside the domain.
    fn asin_clamped(self: Fixed) -> Fixed;
    /// Computes the arccosine of `self` clamped to `[-1, 1]` first: the safe form for a dot
    /// product of two unit vectors, whose rounding can leave it just outside the domain.
    ///
    /// Mirrors `glam::f32::math::acos_approx` (which clamps), `glam::Vec3::angle_between`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * Same values as [`TrigTrait::acos`] inside the domain.
    fn acos_clamped(self: Fixed) -> Fixed;
    /// Computes the arctangent of `self`, in radians, in `(-pi/2, pi/2)`.
    ///
    /// Mirrors `f32::atan`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * Maximum absolute error 2.75 ULP. `atan(0) = 0`, `atan(+-1) = +-FRAC_PI_4` and
    ///   `atan(-x) = -atan(x)` are exact.
    /// * `|self| <= 1` costs no division; a larger magnitude is reflected through
    ///   `atan(x) = pi/2 - atan(1/x)` (one division).
    fn atan(self: Fixed) -> Fixed;
    /// Computes the four-quadrant arctangent of `self` (`y`) and `x`, in radians, in
    /// `[-pi, pi]`. The argument order is Rust's: `y.atan2(x)`.
    ///
    /// Mirrors `f32::atan2` (`glam::Vec2::to_angle`).
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * Maximum absolute error 2.78 ULP. The axes are exact: `atan2(0, 0) = 0`,
    ///   `atan2(y, 0) = +-FRAC_PI_2`, `atan2(0, x) = 0` or `PI`, `atan2(x, x) = FRAC_PI_4`.
    /// * `atan2(0, 0) = 0` as in Rust (no negative zero, so the `+-0.0` cases collapse).
    fn atan2(self: Fixed, x: Fixed) -> Fixed;
    /// Converts degrees to radians.
    ///
    /// Mirrors `f32::to_radians`.
    /// #### Panics
    /// * Never: `|self * PI / 180| < |self|` (R1 panic-coverage audit, escalation 1).
    /// #### Deviations
    /// * Multiplies by a 57-bit `pi / 180` and rescales once, instead of the 32-bit
    ///   [`DEG_TO_RAD`](crate::fixed::DEG_TO_RAD): the result is the floor of the exact product
    ///   (within 1 ULP) over the whole range, where `self * DEG_TO_RAD` drifts by `5.6e-9`
    ///   relative.
    fn to_radians(self: Fixed) -> Fixed;
    /// Converts radians to degrees.
    ///
    /// Mirrors `f32::to_degrees`.
    /// #### Panics
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    /// #### Deviations
    /// * Multiplies by a 57-bit `180 / pi` and rescales once (within 1 ULP of the exact
    ///   product), instead of the 32-bit [`RAD_TO_DEG`](crate::fixed::RAD_TO_DEG).
    fn to_degrees(self: Fixed) -> Fixed;
}

pub impl TrigImpl of TrigTrait {
    fn sin(self: Fixed) -> Fixed {
        let (oct, z, neg) = reduce8(self);
        let u = wide_mul(z, z);
        let m = match oct {
            0 | 3 => sin_core(z, u),
            1 | 2 => cos_core(u),
            4 | 7 => -sin_core(z, u),
            _ => -cos_core(u),
        };
        if neg {
            -m
        } else {
            m
        }
    }

    fn cos(self: Fixed) -> Fixed {
        let (oct, z, _neg) = reduce8(self);
        let u = wide_mul(z, z);
        match oct {
            0 | 7 => cos_core(u),
            1 | 6 => sin_core(z, u),
            2 | 5 => -sin_core(z, u),
            _ => -cos_core(u),
        }
    }

    fn sin_cos(self: Fixed) -> (Fixed, Fixed) {
        let (oct, z, neg) = reduce8(self);
        let u = wide_mul(z, z);
        let s = sin_core(z, u);
        let c = cos_core(u);
        let (rs, rc) = match oct {
            0 => (s, c),
            1 => (c, s),
            2 => (c, -s),
            3 => (s, -c),
            4 => (-s, -c),
            5 => (-c, -s),
            6 => (-c, s),
            _ => (-s, c),
        };
        if neg {
            (-rs, rc)
        } else {
            (rs, rc)
        }
    }

    fn tan(self: Fixed) -> Fixed {
        let (s, c) = Self::sin_cos(self);
        let ac = bounded::abs(c.raw);
        // |s / c| fits the scalar range iff |s| < |c| * 2^31; |c| > 2 already guarantees it.
        let ok = if ac > 2 {
            true
        } else {
            bounded::abs(s.raw) < ac * 0x80000000
        };
        assert(ok, 'Fixed: tan overflow');
        s / c
    }

    fn asin(self: Fixed) -> Fixed {
        assert(self.raw <= ONE_RAW && self.raw >= -ONE_RAW, 'Fixed: asin domain');
        let r = FRAC_PI_2 - acos_core(bounded::abs(self.raw));
        if bounded::is_negative(self.raw) {
            -r
        } else {
            r
        }
    }

    fn acos(self: Fixed) -> Fixed {
        assert(self.raw <= ONE_RAW && self.raw >= -ONE_RAW, 'Fixed: acos domain');
        let r = acos_core(bounded::abs(self.raw));
        if bounded::is_negative(self.raw) {
            PI - r
        } else {
            r
        }
    }

    fn asin_clamped(self: Fixed) -> Fixed {
        Self::asin(FixedTrait::clamp(self, -ONE, ONE))
    }

    fn acos_clamped(self: Fixed) -> Fixed {
        Self::acos(FixedTrait::clamp(self, -ONE, ONE))
    }

    fn atan(self: Fixed) -> Fixed {
        let mag = bounded::abs_diff(self.raw, 0);
        let a = Fixed {
            raw: if mag > MAX_MAG {
                MAX_MAG.try_into().unwrap()
            } else {
                mag.try_into().unwrap()
            },
        };
        let r = if mag <= ONE_MAG {
            atan_core(a)
        } else {
            FRAC_PI_2 - atan_core(FixedTrait::recip(a))
        };
        if bounded::is_negative(self.raw) {
            -r
        } else {
            r
        }
    }

    fn atan2(self: Fixed, x: Fixed) -> Fixed {
        let ay = bounded::abs_diff(self.raw, 0);
        let ax = bounded::abs_diff(x.raw, 0);
        let (mn, mx, swap) = if ay > ax {
            (ax, ay, true)
        } else {
            (ay, ax, false)
        };
        if mx == 0 {
            return ZERO;
        }
        // Only `MIN` reaches 2^63; halving both magnitudes keeps the ratio and fits an i64.
        let (mn, mx) = if mx > MAX_MAG {
            (mn / 2, mx / 2)
        } else {
            (mn, mx)
        };
        let z = Fixed { raw: mn.try_into().unwrap() } / Fixed { raw: mx.try_into().unwrap() };
        let a = atan_core(z);
        let a = if swap {
            FRAC_PI_2 - a
        } else {
            a
        };
        let a = if bounded::is_negative(x.raw) {
            PI - a
        } else {
            a
        };
        if bounded::is_negative(self.raw) {
            -a
        } else {
            a
        }
    }

    #[inline(always)]
    fn to_radians(self: Fixed) -> Fixed {
        wide_mul(self, DEG_TO_RAD_SCALED).mul(INV_SCALE).narrow()
    }

    #[inline(always)]
    fn to_degrees(self: Fixed) -> Fixed {
        wide_mul(self, RAD_TO_DEG_SCALED).mul(INV_SCALE).narrow()
    }
}

/// Octant range reduction of `|x|`: returns the octant index `k mod 8`, the reduced angle `z`
/// (mirrored for the odd octants) and the sign of `x`.
///
/// Three `DivRem` by constants and no branch. `corr` is the Cody-Waite tail of `pi / 4`
/// (`k * (pi/4 * 2^32 - FRAC_PI_4_RAW)`, rounded to nearest), which is **zero for the first
/// four octants** and keeps the
/// reduction of a large angle accurate to ~2 ULP instead of drifting by `1.6e-11` radians per
/// octant. Subtracting it can push `z` marginally outside `[0, pi/4]` (by at most `0.045` rad,
/// and only for `|x|` near `2^31`); the octant identities hold for any `z`, and `u = z * z`
/// stays inside the fitted range for the even octants, so the measured error stays below
/// 2.07 ULP over the whole range.
///
/// Reducing `|x|` and applying the sign to the result is what makes `sin(-x) = -sin(x)` and
/// `cos(-x) = cos(x)` exact for every input.
#[inline(always)]
fn reduce8(x: Fixed) -> (u64, Fixed, bool) {
    let mag = bounded::abs_diff(x.raw, 0);
    let (k, r) = DivRem::div_rem(mag, FRAC_PI_4_NZ);
    let (corr, _) = DivRem::div_rem(k * FRAC_PI_4_TAIL + FRAC_PI_4_TAIL_HALF, TWO_POW_32_NZ);
    let (_turns, oct) = DivRem::div_rem(k, EIGHT_NZ);
    // r < pi / 4 < 2^32 and corr < 2^28: both conversions are infallible.
    let reduced: i64 = r.try_into().unwrap() - corr.try_into().unwrap();
    let z = match oct {
        0 | 2 | 4 | 6 => reduced,
        _ => FRAC_PI_4_RAW_I - reduced,
    };
    (oct, Fixed { raw: z }, bounded::is_negative(x.raw))
}

/// One Horner step at the Q96.96 scale: `floor(acc * u + c)` where `u` is the **exact** raw
/// square of the reduced angle (`wide_mul(z, z)`, never rescaled). One rescale per step, and
/// one rescale less per call than narrowing `u` first (measured: -2 080 gas on `sin`).
#[inline(always)]
fn step(u: W1, acc: Fixed, c: Fixed) -> Fixed {
    u.mul(acc).add(wide_from(c).lift()).narrow()
}

/// `sin(z)` for `z` in `[0, pi/4]`, from the exact `u = z * z`: one Horner chain and a single
/// rescale that also undoes the `2^24` scaling of the accumulator. That rescale rounds to
/// nearest (ties toward +infinity), the second exception to the floor rule of
/// `docs/DESIGN.md` section 2 after `wide::RecipTrait::mul`; it costs nothing (the bias of
/// [`bounded::narrow64_round`] replaces the bias of `narrow64`) and centres the error of every
/// function of this module on zero.
#[inline(always)]
fn sin_core(z: Fixed, u: W1) -> Fixed {
    Fixed { raw: bounded::narrow64_round(upcast(wide_mul(z, sin_poly(u)).mul(INV_SCALE).v)) }
}

/// `cos(z)` for `z` in `[0, pi/4]`, from the exact `u = z * z`. Here the rescale is a plain
/// `Fixed *`, and the rounding is baked into the constant term of `cos_poly` (half a unit of
/// the rescale, added by the generator): the floor of the biased polynomial *is* the
/// round-to-nearest of the exact one, for free.
#[inline(always)]
fn cos_core(u: W1) -> Fixed {
    cos_poly(u) * INV_SCALE
}

/// `atan(z)` for `z` in `[0, 1]`: one `DivRem` by the constant segment width, one `match` on
/// the segment index, one Horner chain. The final `* INV_SCALE` rounds to nearest through the
/// biased constant term of each segment, like `cos_core`.
#[inline(always)]
fn atan_core(z: Fixed) -> Fixed {
    // 0 <= z <= 1: the conversion cannot fail.
    let (idx, t) = DivRem::div_rem(z.raw.try_into().unwrap(), ATAN_SEG_NZ);
    atan_poly(idx, Fixed { raw: t.try_into().unwrap() }) * INV_SCALE
}

/// `acos(|x|)` for `|x| <= 1`, as `sqrt(1 - |x|) * P(|x|)`: one integer square root (exact on
/// the raw Q64.64 value, no rescale), one Horner chain, one rescale rounded to nearest. No
/// division.
#[inline(always)]
fn acos_core(ax: i64) -> Fixed {
    let s = wide_mul(Fixed { raw: ONE_RAW - ax }, ONE).sqrt();
    let acc = wide_mul(s, acos_poly(Fixed { raw: ax })).mul(INV_SCALE);
    Fixed { raw: bounded::narrow64_round(upcast(acc.v)) }
}
