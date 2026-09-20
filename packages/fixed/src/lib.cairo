//! Signed Q32.32 fixed-point scalar for provable game math.
//!
//! See `docs/DESIGN.md` at the repository root for the number format, the rounding mode and the
//! overflow policy.

pub mod fixed;
mod internal;
pub mod trig;
pub mod wide;

pub use fixed::{
    DEG_TO_RAD, E, EPSILON, FRAC_1_PI, FRAC_1_SQRT_2, FRAC_2_PI, FRAC_BITS, FRAC_PI_2,
    FRAC_PI_2_RAW, FRAC_PI_3, FRAC_PI_4, FRAC_PI_6, FRAC_PI_8, Fixed, FixedTrait, HALF, HALF_RAW,
    LN_10, LN_2, MAX, MIN, NEG_ONE, ONE, ONE_RAW, PI, PI_RAW, RAD_TO_DEG, SQRT_2, TAU, TAU_RAW, TWO,
    ZERO,
};
pub use trig::{TrigImpl, TrigTrait};
