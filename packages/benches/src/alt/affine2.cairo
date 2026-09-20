//! Alternative implementations benchmarked against `affine2`.

use fixed::fixed::Fixed;
use glam::affine2::Affine2;
use glam::mat2::Mat2Trait;

/// The direct glam-rs formulation of `Affine2::inverse`: invert the linear matrix first, then
/// transform and negate the translation. This performs two `dot2` kernels after the reciprocal,
/// while the shipped formulation shares the determinant reciprocal with the translation.
#[inline(never)]
pub fn inverse_two_stage(m: Affine2) -> Affine2 {
    if m.matrix2.determinant() == F_ZERO {
        core::panic_with_felt252('Affine2: singular');
    }
    let matrix2 = m.matrix2.inverse();
    let translation = -matrix2.mul_vec2(m.translation);
    Affine2 { matrix2, translation }
}

/// Composition with a separately rounded matrix-vector product followed by exact translation.
/// The shipped implementation uses `dot2_add`, rescaling the products and addend once.
#[inline(always)]
pub fn mul_unfused(lhs: Affine2, rhs: Affine2) -> Affine2 {
    Affine2 {
        matrix2: lhs.matrix2 * rhs.matrix2,
        translation: lhs.matrix2.mul_vec2(rhs.translation) + lhs.translation,
    }
}

const F_ZERO: Fixed = Fixed { raw: 0 };
