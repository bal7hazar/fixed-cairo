//! Signed Q32.32 fixed-point scalar for provable game math.
//!
//! See `docs/DESIGN.md` at the repository root for the number format, the rounding mode and the
//! overflow policy.

pub mod fixed;
mod internal;
pub mod trig;
pub mod wide;

pub use fixed::{Fixed, FixedTrait, ONE, ONE_RAW, ZERO};
