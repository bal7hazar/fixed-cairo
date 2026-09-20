//! Candidate scalar representations. All are signed fixed-point numbers.
pub mod felt;
pub mod i64b; // C/E: Q32.32 in a native i64, bounded-int arithmetic + fused kernels
pub mod i64b_types; // generated bounded-int type plumbing for i64b
pub mod i64n; // B: Q32.32 in a native i64, plain corelib operators only
pub mod mag; // A: cubit-style Q32.32 { mag: u64, sign: bool }
pub mod magi; // A': same as A with #[inline(always)] on the hot operators
pub mod q64;

/// Operations every representation provides on top of the std operator traits.
pub trait Real<T> {
    /// Builds a value from its raw Q32.32 representation (test/bench helper).
    fn from_raw(raw: i64) -> T;
    /// Raw Q32.32 representation (test/bench helper, may panic if out of range).
    fn to_raw(self: T) -> i64;
    fn from_int(v: i32) -> T;
    /// Integer part, rounded towards -inf.
    fn to_int(self: T) -> i32;
    fn floor(self: T) -> T;
    fn round(self: T) -> T;
    fn abs(self: T) -> T;
    fn sqrt(self: T) -> T;
}

/// Fused multiply-accumulate kernels. Naive representations implement them with plain operators;
/// `i64b` and `felt` implement them with a single rescale ("lazy reduction").
pub trait Fused<T> {
    /// a0*b0 + a1*b1
    fn dot2(a0: T, b0: T, a1: T, b1: T) -> T;
    /// a0*b0 - a1*b1
    fn mul_sub(a0: T, b0: T, a1: T, b1: T) -> T;
    /// a0*b0 + a1*b1 + a2*b2
    fn dot3(a0: T, b0: T, a1: T, b1: T, a2: T, b2: T) -> T;
    /// a0*b0 + a1*b1 + a2*b2 + a3*b3
    fn dot4(a0: T, b0: T, a1: T, b1: T, a2: T, b2: T, a3: T, b3: T) -> T;
    /// sqrt(x*x + y*y + z*z)
    fn norm3(x: T, y: T, z: T) -> T;
}

/// Default (naive) implementation of the fused kernels from the operator traits.
pub mod naive {
    use super::Real;
    pub impl NaiveFused<T, +Add<T>, +Sub<T>, +Mul<T>, +Copy<T>, +Drop<T>, +Real<T>> of super::Fused<T> {
        #[inline(always)]
        fn dot2(a0: T, b0: T, a1: T, b1: T) -> T {
            a0 * b0 + a1 * b1
        }
        #[inline(always)]
        fn mul_sub(a0: T, b0: T, a1: T, b1: T) -> T {
            a0 * b0 - a1 * b1
        }
        #[inline(always)]
        fn dot3(a0: T, b0: T, a1: T, b1: T, a2: T, b2: T) -> T {
            a0 * b0 + a1 * b1 + a2 * b2
        }
        #[inline(always)]
        fn dot4(a0: T, b0: T, a1: T, b1: T, a2: T, b2: T, a3: T, b3: T) -> T {
            a0 * b0 + a1 * b1 + a2 * b2 + a3 * b3
        }
        #[inline(always)]
        fn norm3(x: T, y: T, z: T) -> T {
            (x * x + y * y + z * z).sqrt()
        }
    }
}
