//! Port of glam-rs `f32/affine2.rs` @ 0.33.8 on the Q32.32 scalar: a 2D affine transform
//! stored as a `Mat2` linear part and a `Vec2` translation.
//!
//! Products use the fused kernels of `fixed::wide`. In particular, point transforms and the
//! translation of a composition use `dot2_add`, so each output scalar is rescaled once.
//!
//! There is no NaN and no infinity: overflow and inversion of a singular transform panic
//! (docs/DESIGN.md section 3).

use core::ops::MulAssign;
use fixed::fixed::{Fixed, FixedTrait};
use fixed::trig::TrigTrait;
use fixed::wide::{RecipTrait, dot2, dot2_add, mul_sub};
use crate::mat2::{Mat2, Mat2Trait};
use crate::mat3::{Mat3, Mat3Trait};
use crate::vec2::{Vec2, Vec2Trait};
use crate::vec3::Vec3;

/// A 2D affine transform, which can represent translation, rotation, scaling and shear.
///
/// Mirrors `glam::Affine2`.
/// #### Deviations
/// * `Debug` is the derived Cairo formatting; `Display` and `Deref` are not implemented.
/// * No `NAN` const and no `is_nan` / `is_finite`: those values do not exist
///   (docs/DESIGN.md section 3).
/// * Not ported: `from_cols_slice` / `write_cols_to_slice` (no `Span` in fixed-size math),
///   `Product` (no iterator trait to implement), by-reference operator overloads, casts to the
///   collapsed f32/f64 variants, and `from_mat3a` (there is no distinct `Mat3A`).
/// * Heterogeneous `Mul` is not a core Cairo operator. `Affine2 * Mat3` is `mul_mat3`; spell
///   `Mat3 * Affine2` as `mat3 * Into::<Affine2, Mat3>::into(affine)`.
#[derive(Copy, Drop, Serde, PartialEq, Debug, Hash)]
pub struct Affine2 {
    pub matrix2: Mat2,
    pub translation: Vec2,
}

pub trait Affine2Trait {
    /// The degenerate zero transform. It transforms every representable vector and point to zero.
    ///
    /// Mirrors `glam::Affine2::ZERO`.
    const ZERO: Affine2;
    /// The identity transform.
    ///
    /// Mirrors `glam::Affine2::IDENTITY`.
    const IDENTITY: Affine2;
    /// Creates an affine transform from three column vectors.
    ///
    /// Mirrors `glam::Affine2::from_cols`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_cols(x_axis: Vec2, y_axis: Vec2, z_axis: Vec2) -> Affine2;
    /// Creates an affine transform from a `[Fixed; 6]` array in column-major order.
    ///
    /// Implementation notes:
    /// * The array is passed by value, as fixed-size Cairo values are.
    ///
    /// Mirrors `glam::Affine2::from_cols_array`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_cols_array(m: [Fixed; 6]) -> Affine2;
    /// Creates a `[Fixed; 6]` array storing the transform in column-major order.
    ///
    /// Implementation notes:
    /// * The transform is passed by value, as fixed-size Cairo values are.
    ///
    /// Mirrors `glam::Affine2::to_cols_array`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn to_cols_array(self: Affine2) -> [Fixed; 6];
    /// Creates an affine transform from a `[[Fixed; 2]; 3]` array in column-major order.
    ///
    /// Implementation notes:
    /// * The array is passed by value, as fixed-size Cairo values are.
    ///
    /// Mirrors `glam::Affine2::from_cols_array_2d`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_cols_array_2d(m: [[Fixed; 2]; 3]) -> Affine2;
    /// Creates a `[[Fixed; 2]; 3]` array storing the transform in column-major order.
    ///
    /// Implementation notes:
    /// * The transform is passed by value, as fixed-size Cairo values are.
    ///
    /// Mirrors `glam::Affine2::to_cols_array_2d`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn to_cols_array_2d(self: Affine2) -> [[Fixed; 2]; 3];
    /// Creates an affine transform that changes scale.
    ///
    /// Implementation notes:
    /// * Exact.
    ///
    /// Mirrors `glam::Affine2::from_scale`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_scale(scale: Vec2) -> Affine2;
    /// Creates an affine transform from the rotation `angle` in radians.
    ///
    /// Mirrors `glam::Affine2::from_angle`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * `fixed::trig::sin_cos` is accurate to about 1 ULP over a turn.
    fn from_angle(angle: Fixed) -> Affine2;
    /// Creates an affine transform from a 2D translation.
    ///
    /// Implementation notes:
    /// * Exact.
    ///
    /// Mirrors `glam::Affine2::from_translation`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_translation(translation: Vec2) -> Affine2;
    /// Creates an affine transform from a 2x2 linear transform.
    ///
    /// Implementation notes:
    /// * Exact.
    ///
    /// Mirrors `glam::Affine2::from_mat2`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_mat2(matrix2: Mat2) -> Affine2;
    /// Creates an affine transform from a 2x2 linear transform and a translation.
    ///
    /// Implementation notes:
    /// * Exact.
    ///
    /// Mirrors `glam::Affine2::from_mat2_translation`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_mat2_translation(matrix2: Mat2, translation: Vec2) -> Affine2;
    /// Creates an affine transform from scale, rotation angle in radians and translation.
    ///
    /// Mirrors `glam::Affine2::from_scale_angle_translation`.
    /// #### Panics
    /// * `'Fixed: overflow'` if a scaled rotation element leaves the scalar range.
    /// #### Deviations
    /// * `fixed::trig::sin_cos` is accurate to about 1 ULP over a turn; each following product
    ///   has one floor rescale.
    fn from_scale_angle_translation(scale: Vec2, angle: Fixed, translation: Vec2) -> Affine2;
    /// Creates an affine transform from a rotation angle in radians and a translation.
    ///
    /// Mirrors `glam::Affine2::from_angle_translation`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * `fixed::trig::sin_cos` is accurate to about 1 ULP over a turn.
    fn from_angle_translation(angle: Fixed, translation: Vec2) -> Affine2;
    /// Creates an affine transform from the first two rows of a 3x3 affine matrix.
    ///
    /// Mirrors `glam::Affine2::from_mat3`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * The glam-rs precondition that `m` is affine is not checked.
    fn from_mat3(m: Mat3) -> Affine2;
    /// Extracts `scale`, rotation `angle` in radians, and `translation` from `self`.
    ///
    /// #### Preconditions
    /// * The linear transform must be non-degenerate and contain no shear; it is not checked.
    ///
    /// Mirrors `glam::Affine2::to_scale_angle_translation`.
    /// #### Panics
    /// * `'Fixed: overflow'` if the determinant or a column length leaves the scalar range.
    /// #### Deviations
    /// * The determinant sign is applied by exact negation instead of multiplication by
    ///   `signum(det)`. The column lengths are integer-square-root floors (at most 1 ULP low),
    ///   and `atan2` is accurate to 3.22 ULP.
    /// * The `glam_assert!` checks for a nonzero determinant and scale are not performed
    ///   (docs/DESIGN.md section 3).
    fn to_scale_angle_translation(self: Affine2) -> (Vec2, Fixed, Vec2);
    /// Transforms a 2D point, applying the linear transform and translation.
    ///
    /// Mirrors `glam::Affine2::transform_point2`.
    /// #### Panics
    /// * `'Fixed: overflow'` if an output component leaves the scalar range.
    /// #### Deviations
    /// * One `dot2_add` fused kernel per component: both products and the translation are
    ///   rescaled once, so an output is at most 1 ULP below the exact value.
    fn transform_point2(self: Affine2, rhs: Vec2) -> Vec2;
    /// Transforms a 2D vector without applying translation.
    ///
    /// Mirrors `glam::Affine2::transform_vector2`.
    /// #### Panics
    /// * `'Fixed: overflow'` if an output component leaves the scalar range.
    /// #### Deviations
    /// * One `dot2` fused kernel per component: both products are rescaled once.
    fn transform_vector2(self: Affine2, rhs: Vec2) -> Vec2;
    /// Returns the inverse transform.
    ///
    /// Mirrors `glam::Affine2::inverse`.
    /// #### Panics
    /// * `'Affine2: singular'` if the determinant is zero.
    /// * `'Fixed: overflow'` if an inverse component leaves the scalar range.
    /// * `'i64_neg Underflow'` if an off-diagonal element is `Fixed::MIN`.
    /// #### Deviations
    /// * glam-rs returns an invalid transform when assertions are disabled; there is no NaN here,
    ///   so singular transforms panic.
    /// * The six quotient outputs share one wide reciprocal. The adjugate products used by the
    ///   inverse translation are fused before that reciprocal is applied.
    fn inverse(self: Affine2) -> Affine2;
    /// Returns true when every element differs from `rhs` by at most `max_abs_diff`.
    ///
    /// Mirrors `glam::Affine2::abs_diff_eq`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * Differences are compared on 65 bits by the component methods and cannot overflow.
    fn abs_diff_eq(self: Affine2, rhs: Affine2, max_abs_diff: Fixed) -> bool;
    /// Multiplies this affine transform by a 3x3 matrix.
    ///
    /// Mirrors `impl Mul<Mat3> for glam::Affine2`.
    /// #### Panics
    /// * `'Fixed: overflow'` if a result element leaves the scalar range.
    /// #### Deviations
    /// * Cairo's core `Mul` is homogeneous, so the heterogeneous operator is named `mul_mat3`.
    /// * The affine transform is first embedded in a `Mat3`, then the fused `Mat3` product is used.
    fn mul_mat3(self: Affine2, rhs: Mat3) -> Mat3;
}

pub impl Affine2Impl of Affine2Trait {
    const ZERO: Affine2 = Affine2 {
        matrix2: Mat2 {
            x_axis: Vec2 { x: Fixed { raw: 0 }, y: Fixed { raw: 0 } },
            y_axis: Vec2 { x: Fixed { raw: 0 }, y: Fixed { raw: 0 } },
        },
        translation: Vec2 { x: Fixed { raw: 0 }, y: Fixed { raw: 0 } },
    };
    const IDENTITY: Affine2 = Affine2 {
        matrix2: Mat2 {
            x_axis: Vec2 { x: Fixed { raw: 0x100000000 }, y: Fixed { raw: 0 } },
            y_axis: Vec2 { x: Fixed { raw: 0 }, y: Fixed { raw: 0x100000000 } },
        },
        translation: Vec2 { x: Fixed { raw: 0 }, y: Fixed { raw: 0 } },
    };

    #[inline(always)]
    fn from_cols(x_axis: Vec2, y_axis: Vec2, z_axis: Vec2) -> Affine2 {
        Affine2 { matrix2: Mat2 { x_axis, y_axis }, translation: z_axis }
    }

    #[inline(always)]
    fn from_cols_array(m: [Fixed; 6]) -> Affine2 {
        let [m00, m01, m10, m11, tx, ty] = m;
        Affine2 {
            matrix2: Mat2 { x_axis: Vec2 { x: m00, y: m01 }, y_axis: Vec2 { x: m10, y: m11 } },
            translation: Vec2 { x: tx, y: ty },
        }
    }

    #[inline(always)]
    fn to_cols_array(self: Affine2) -> [Fixed; 6] {
        [
            self.matrix2.x_axis.x, self.matrix2.x_axis.y, self.matrix2.y_axis.x,
            self.matrix2.y_axis.y, self.translation.x, self.translation.y,
        ]
    }

    #[inline(always)]
    fn from_cols_array_2d(m: [[Fixed; 2]; 3]) -> Affine2 {
        let [x, y, z] = m;
        let [m00, m01] = x;
        let [m10, m11] = y;
        let [tx, ty] = z;
        Affine2 {
            matrix2: Mat2 { x_axis: Vec2 { x: m00, y: m01 }, y_axis: Vec2 { x: m10, y: m11 } },
            translation: Vec2 { x: tx, y: ty },
        }
    }

    #[inline(always)]
    fn to_cols_array_2d(self: Affine2) -> [[Fixed; 2]; 3] {
        [
            [self.matrix2.x_axis.x, self.matrix2.x_axis.y],
            [self.matrix2.y_axis.x, self.matrix2.y_axis.y],
            [self.translation.x, self.translation.y],
        ]
    }

    #[inline(always)]
    fn from_scale(scale: Vec2) -> Affine2 {
        Affine2 {
            matrix2: Mat2 {
                x_axis: Vec2 { x: scale.x, y: F_ZERO }, y_axis: Vec2 { x: F_ZERO, y: scale.y },
            },
            translation: Vec2Trait::ZERO,
        }
    }

    #[inline(always)]
    fn from_angle(angle: Fixed) -> Affine2 {
        Affine2 { matrix2: Mat2Trait::from_angle(angle), translation: Vec2Trait::ZERO }
    }

    #[inline(always)]
    fn from_translation(translation: Vec2) -> Affine2 {
        Affine2 { matrix2: Mat2Trait::IDENTITY, translation }
    }

    #[inline(always)]
    fn from_mat2(matrix2: Mat2) -> Affine2 {
        Affine2 { matrix2, translation: Vec2Trait::ZERO }
    }

    #[inline(always)]
    fn from_mat2_translation(matrix2: Mat2, translation: Vec2) -> Affine2 {
        Affine2 { matrix2, translation }
    }

    #[inline(always)]
    fn from_scale_angle_translation(scale: Vec2, angle: Fixed, translation: Vec2) -> Affine2 {
        Affine2 { matrix2: Mat2Trait::from_scale_angle(scale, angle), translation }
    }

    #[inline(always)]
    fn from_angle_translation(angle: Fixed, translation: Vec2) -> Affine2 {
        Affine2 { matrix2: Mat2Trait::from_angle(angle), translation }
    }

    #[inline(always)]
    fn from_mat3(m: Mat3) -> Affine2 {
        Affine2 {
            matrix2: Mat2 {
                x_axis: Vec2 { x: m.x_axis.x, y: m.x_axis.y },
                y_axis: Vec2 { x: m.y_axis.x, y: m.y_axis.y },
            },
            translation: Vec2 { x: m.z_axis.x, y: m.z_axis.y },
        }
    }

    fn to_scale_angle_translation(self: Affine2) -> (Vec2, Fixed, Vec2) {
        let det = self.matrix2.determinant();
        let len_x = self.matrix2.x_axis.length();
        let scale = Vec2 {
            x: if det.is_negative() {
                -len_x
            } else {
                len_x
            }, y: self.matrix2.y_axis.length(),
        };
        let angle = (-self.matrix2.y_axis.x).atan2(self.matrix2.y_axis.y);
        (scale, angle, self.translation)
    }

    #[inline(always)]
    fn transform_point2(self: Affine2, rhs: Vec2) -> Vec2 {
        Vec2 {
            x: dot2_add(
                self.matrix2.x_axis.x, rhs.x, self.matrix2.y_axis.x, rhs.y, self.translation.x,
            ),
            y: dot2_add(
                self.matrix2.x_axis.y, rhs.x, self.matrix2.y_axis.y, rhs.y, self.translation.y,
            ),
        }
    }

    #[inline(always)]
    fn transform_vector2(self: Affine2, rhs: Vec2) -> Vec2 {
        Vec2 {
            x: dot2(self.matrix2.x_axis.x, rhs.x, self.matrix2.y_axis.x, rhs.y),
            y: dot2(self.matrix2.x_axis.y, rhs.x, self.matrix2.y_axis.y, rhs.y),
        }
    }

    fn inverse(self: Affine2) -> Affine2 {
        inverse_shared_recip(self)
    }

    #[inline(always)]
    fn abs_diff_eq(self: Affine2, rhs: Affine2, max_abs_diff: Fixed) -> bool {
        self.matrix2.abs_diff_eq(rhs.matrix2, max_abs_diff)
            && self.translation.abs_diff_eq(rhs.translation, max_abs_diff)
    }

    #[inline(always)]
    fn mul_mat3(self: Affine2, rhs: Mat3) -> Mat3 {
        Mat3Trait::mul_mat3(self.into(), rhs)
    }
}

/// `Default` is `Affine2::IDENTITY`, as in glam-rs.
///
/// Mirrors `impl Default for glam::Affine2`.
pub impl Affine2Default of Default<Affine2> {
    #[inline(always)]
    fn default() -> Affine2 {
        Affine2Trait::IDENTITY
    }
}

/// Affine composition. See `Affine2Trait::transform_point2` for its rounding semantics.
///
/// Mirrors `impl Mul for glam::Affine2`.
pub impl Affine2Mul of Mul<Affine2> {
    #[inline(always)]
    fn mul(lhs: Affine2, rhs: Affine2) -> Affine2 {
        Affine2 {
            matrix2: lhs.matrix2 * rhs.matrix2,
            translation: Vec2 {
                x: dot2_add(
                    lhs.matrix2.x_axis.x,
                    rhs.translation.x,
                    lhs.matrix2.y_axis.x,
                    rhs.translation.y,
                    lhs.translation.x,
                ),
                y: dot2_add(
                    lhs.matrix2.x_axis.y,
                    rhs.translation.x,
                    lhs.matrix2.y_axis.y,
                    rhs.translation.y,
                    lhs.translation.y,
                ),
            },
        }
    }
}

/// Mirrors `impl MulAssign for glam::Affine2`.
pub impl Affine2MulAssign of MulAssign<Affine2, Affine2> {
    #[inline(always)]
    fn mul_assign(ref self: Affine2, rhs: Affine2) {
        self = self * rhs;
    }
}

/// Embeds an affine transform in a homogeneous 3x3 matrix.
///
/// Mirrors `impl From<glam::Affine2> for glam::Mat3`.
pub impl Affine2IntoMat3 of Into<Affine2, Mat3> {
    #[inline(always)]
    fn into(self: Affine2) -> Mat3 {
        Mat3 {
            x_axis: Vec3 { x: self.matrix2.x_axis.x, y: self.matrix2.x_axis.y, z: F_ZERO },
            y_axis: Vec3 { x: self.matrix2.y_axis.x, y: self.matrix2.y_axis.y, z: F_ZERO },
            z_axis: Vec3 { x: self.translation.x, y: self.translation.y, z: F_ONE },
        }
    }
}

/// Extracts the 2D affine columns from a 3x3 matrix.
///
/// Mirrors `glam::Affine2::from_mat3`.
/// #### Deviations
/// * The glam-rs precondition that the matrix is affine is not checked.
pub impl Mat3IntoAffine2 of Into<Mat3, Affine2> {
    #[inline(always)]
    fn into(self: Mat3) -> Affine2 {
        Affine2Trait::from_mat3(self)
    }
}

/// Inverts all six affine components with one shared wide reciprocal. The two translation
/// numerators are fused adjugate products before division.
fn inverse_shared_recip(m: Affine2) -> Affine2 {
    let a = m.matrix2.x_axis.x;
    let b = m.matrix2.x_axis.y;
    let c = m.matrix2.y_axis.x;
    let d = m.matrix2.y_axis.y;
    let det = mul_sub(a, d, b, c);
    if det == F_ZERO {
        core::panic_with_felt252('Affine2: singular');
    }
    let r = RecipTrait::new(det);
    Affine2 {
        matrix2: Mat2 {
            x_axis: Vec2 { x: r.mul(d), y: r.mul(-b) }, y_axis: Vec2 { x: r.mul(-c), y: r.mul(a) },
        },
        translation: Vec2 {
            x: r.mul(mul_sub(c, m.translation.y, d, m.translation.x)),
            y: r.mul(mul_sub(b, m.translation.x, a, m.translation.y)),
        },
    }
}

const F_ZERO: Fixed = Fixed { raw: 0 };
const F_ONE: Fixed = Fixed { raw: 0x100000000 };
