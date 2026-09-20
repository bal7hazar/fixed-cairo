//! Measurement helpers.
//!
//! `bb` (black box) makes a value opaque to the compiler: it is `#[inline(never)]`, so the
//! constant-folding pass cannot see through it. `sink` consumes a result so that the computation
//! is not dead-code-eliminated, and costs the same in the baseline and in the measured test.

#[inline(never)]
pub fn bb<T>(x: T) -> T {
    x
}

#[inline(never)]
pub fn sink<T, +Drop<T>>(x: T) {}
