//! Alternative implementations benchmarked against `glamx::rot2`. The library ships the fused
//! formulations; these literal glamx expressions preserve the gas comparison across compilers.

use glam::vec2::Vec2;
use glamx::rot2::Rot2;

/// Literal complex multiplication with four separately rescaled products: 9,320 gas versus
/// 4,680 for the fused library implementation.
#[inline(always)]
pub fn mul_unfused(lhs: Rot2, rhs: Rot2) -> Rot2 {
    Rot2 { re: lhs.re * rhs.re - lhs.im * rhs.im, im: lhs.re * rhs.im + lhs.im * rhs.re }
}

/// Literal vector transform with four separately rescaled products: 9,320 gas versus 4,680 for
/// the fused library implementation.
#[inline(always)]
pub fn mul_vec2_unfused(lhs: Rot2, rhs: Vec2) -> Vec2 {
    Vec2 { x: lhs.re * rhs.x - lhs.im * rhs.y, y: lhs.im * rhs.x + lhs.re * rhs.y }
}
