//! Port of glam-rs `euler.rs` @ 0.33.8 on the Q32.32 scalar: the 24 Euler rotation sequences of
//! [`EulerRot`] and the conversions between them and [`Quat`], [`Mat3`] and [`Mat4`].
//!
//! The algorithm is the axis-sequence one of Ken Shoemake (*Euler angle conversion*, Graphics
//! Gems IV, 1994) that glam-rs uses: an order decodes into an axis permutation `(i, j, k)`, a
//! parity, a "repeated first axis" flag (the 12 proper Euler sequences `XYX`, `ZXZ`, ... against
//! the 12 Tait-Bryan ones `XYZ`, `ZYX`, ...) and a frame flag (intrinsic against the extrinsic
//! `*Ex` variants). [`decode`] is the single `match` over the 24 orders; everything after it is
//! order-independent arithmetic plus one six-way `match` that permutes the components.
//!
//! #### Fusion
//!
//! glam-rs builds the four products `cc = ci * ch`, `cs`, `sc`, `ss` and then combines them with
//! `cj` / `sj`, i.e. two roundings per matrix entry. Every entry here is instead a sum of two
//! exact triple products narrowed once (`fixed::wide`, docs/DESIGN.md section 2.1):
//! `m[j][j] = sj * si * sh + ci * ch` is one `T2` accumulator and one rescale. The intermediate
//! form is kept in `benches::alt::euler` and costs more for a strictly larger error.
//!
//! #### Extension traits
//!
//! `from_euler` / `to_euler` are methods of `Quat`, `Mat3` and `Mat4` in glam-rs. Cairo has no
//! inherent impls, and putting them in `QuatTrait` / `Mat3Trait` / `Mat4Trait` would make
//! `glam::quat` depend on `glam::euler` and back. They live here as the extension traits
//! [`QuatEulerTrait`], [`Mat3EulerTrait`] and [`Mat4EulerTrait`]: importing one of them brings
//! the methods into scope on the type it extends.
//!
//! #### Gimbal lock
//!
//! `to_euler` reads the angles back from the rotation matrix. When the middle angle reaches
//! `+-pi/2` (Tait-Bryan) or `0` / `pi` (proper Euler) the first and third axes coincide and only
//! their sum or their difference is defined: glam-rs detects it with `sqrt(..) > 16 * EPSILON`
//! and returns the whole rotation in the first angle, with a third angle of zero.
//! [`GIMBAL_EPS`] is the Q32.32 transposition of that threshold; see its documentation for the
//! ULP derivation and for the conditioning of the branch just above it.

use fixed::fixed::Fixed;
use fixed::trig::TrigTrait;
use fixed::wide::{
    WideAdd, WideLift, WideMul, WideNarrow, WideSub, dot2, dot2_add, mul_sub, norm2, wide_mul,
};
use crate::mat3::{Mat3, Mat3Trait};
use crate::mat4::{Mat4, Mat4Trait};
use crate::quat::Quat;
use crate::vec3::Vec3;

const HALF: Fixed = Fixed { raw: 0x80000000 };
const ONE: Fixed = Fixed { raw: 0x100000000 };
const ZERO: Fixed = Fixed { raw: 0 };

/// The gimbal-lock threshold of [`Mat3EulerTrait::to_euler`]: 16 raw ULP, i.e. `2^-28`
/// (`3.7e-9`).
///
/// Mirrors the `16.0 * EPSILON` of `glam::euler`, re-derived for Q32.32 (docs/DESIGN.md
/// section 3). `f32::EPSILON` and `f64::EPSILON` are the gap between `1.0` and its successor,
/// i.e. one ULP at `1.0`; the same quantity for a Q32.32 scalar is `2^-32`, so the literal
/// transposition of glam-rs' rule is `16 * 2^-32`. It is also the right order of magnitude on
/// its own: the entries of a matrix that [`Mat3EulerTrait::from_euler`] produced carry up to
/// 8 ULP of rounding, so below 16 ULP the two entries that separate the first and the third
/// angle are already dominated by noise.
///
/// The threshold only picks the branch; it does not make the general branch well conditioned
/// near the singularity. `to_euler` of an **exact** rotation matrix is accurate to 5 ULP for
/// every order, singular or not: the first and the third angle are `atan2` of two entries whose
/// ratio is exact whatever their magnitude. What the residual amplifies is the error the matrix
/// already carries: a matrix that is off by `d` ULP (8 ULP for the output of `from_euler`)
/// yields a first and a third angle off by about `d / r` ULP, where the residual `r` is
/// `|cos(middle angle)|` for a Tait-Bryan sequence and `|sin(middle angle)|` for a proper Euler
/// one. `from_euler(order, to_euler(m))` is therefore within 80 ULP of `m` for `r >= 1/4`, and
/// degrades as `1 / r` below it until the branch fires. That conditioning is inherent to Euler
/// angles and is the same in glam-rs, where `f32::EPSILON` plays the part of `d`.
pub const GIMBAL_EPS: Fixed = Fixed { raw: 16 };

/// Euler rotation sequences.
///
/// The three elemental rotations may be extrinsic (rotations about the axes `xyz` of the
/// original coordinate system, which is assumed to remain motionless), or intrinsic (rotations
/// about the axes of the rotating coordinate system `XYZ`, solidary with the moving body, which
/// changes its orientation after each elemental rotation). The `*Ex` variants are the extrinsic
/// ones:
///
/// ```cairo
/// // 40 raw ULP: `from_euler` rounds once per entry, the product twice more.
/// let tol = FixedTrait::from_raw(40);
/// let m_intrinsic = Mat3Trait::from_rotation_x(i)
///     * Mat3Trait::from_rotation_y(j)
///     * Mat3Trait::from_rotation_z(k);
/// assert!(m_intrinsic.abs_diff_eq(Mat3EulerTrait::from_euler(EulerRot::XYZ, i, j, k), tol));
///
/// let m_extrinsic = Mat3Trait::from_rotation_z(k)
///     * Mat3Trait::from_rotation_y(j)
///     * Mat3Trait::from_rotation_x(i);
/// assert!(m_extrinsic.abs_diff_eq(Mat3EulerTrait::from_euler(EulerRot::XYZEx, i, j, k), tol));
/// ```
///
/// Mirrors `glam::EulerRot`, with the 0.33 semantics and the 0.33 default (`YXZ`: yaw around
/// `y`, pitch around `x`, roll around `z`).
/// #### Deviations
/// * `Eq` and `Hash` are not derived (`PartialEq` is exact here anyway); `Serde` is, so an order
///   can cross a storage or calldata boundary.
#[derive(Copy, Drop, Serde, PartialEq, Debug, Default)]
pub enum EulerRot {
    /// Intrinsic three-axis rotation ZYX.
    ZYX,
    /// Intrinsic three-axis rotation ZXY.
    ZXY,
    /// Intrinsic three-axis rotation YXZ: yaw (`y`), pitch (`x`), roll (`z`). The default.
    #[default]
    YXZ,
    /// Intrinsic three-axis rotation YZX.
    YZX,
    /// Intrinsic three-axis rotation XYZ.
    XYZ,
    /// Intrinsic three-axis rotation XZY.
    XZY,
    /// Intrinsic two-axis rotation ZYZ.
    ZYZ,
    /// Intrinsic two-axis rotation ZXZ.
    ZXZ,
    /// Intrinsic two-axis rotation YXY.
    YXY,
    /// Intrinsic two-axis rotation YZY.
    YZY,
    /// Intrinsic two-axis rotation XYX.
    XYX,
    /// Intrinsic two-axis rotation XZX.
    XZX,
    /// Extrinsic three-axis rotation ZYX.
    ZYXEx,
    /// Extrinsic three-axis rotation ZXY.
    ZXYEx,
    /// Extrinsic three-axis rotation YXZ.
    YXZEx,
    /// Extrinsic three-axis rotation YZX.
    YZXEx,
    /// Extrinsic three-axis rotation XYZ.
    XYZEx,
    /// Extrinsic three-axis rotation XZY.
    XZYEx,
    /// Extrinsic two-axis rotation ZYZ.
    ZYZEx,
    /// Extrinsic two-axis rotation ZXZ.
    ZXZEx,
    /// Extrinsic two-axis rotation YXY.
    YXYEx,
    /// Extrinsic two-axis rotation YZY.
    YZYEx,
    /// Extrinsic two-axis rotation XYX.
    XYXEx,
    /// Extrinsic two-axis rotation XZX.
    XZXEx,
}

/// Decodes an order into `(perm, parity_even, repeated, frame_static)`.
///
/// `perm` indexes the six `(i, j, k)` axis permutations that `Order::angle_order` of glam-rs
/// produces: `0 = (0, 1, 2)`, `1 = (1, 2, 0)`, `2 = (2, 0, 1)` for an even parity and
/// `3 = (0, 2, 1)`, `4 = (1, 0, 2)`, `5 = (2, 1, 0)` for an odd one. The table is the
/// `Order::from_euler` table of glam-rs, folded once: an initial axis plus a parity is exactly
/// one of those six permutations.
#[inline(always)]
fn decode(order: EulerRot) -> (u8, bool, bool, bool) {
    match order {
        EulerRot::XYZ => (0, true, false, true),
        EulerRot::XYX => (0, true, true, true),
        EulerRot::XZY => (3, false, false, true),
        EulerRot::XZX => (3, false, true, true),
        EulerRot::YZX => (1, true, false, true),
        EulerRot::YZY => (1, true, true, true),
        EulerRot::YXZ => (4, false, false, true),
        EulerRot::YXY => (4, false, true, true),
        EulerRot::ZXY => (2, true, false, true),
        EulerRot::ZXZ => (2, true, true, true),
        EulerRot::ZYX => (5, false, false, true),
        EulerRot::ZYZ => (5, false, true, true),
        EulerRot::ZYXEx => (0, true, false, false),
        EulerRot::XYXEx => (0, true, true, false),
        EulerRot::YZXEx => (3, false, false, false),
        EulerRot::XZXEx => (3, false, true, false),
        EulerRot::XZYEx => (1, true, false, false),
        EulerRot::YZYEx => (1, true, true, false),
        EulerRot::ZXYEx => (4, false, false, false),
        EulerRot::YXYEx => (4, false, true, false),
        EulerRot::YXZEx => (2, true, false, false),
        EulerRot::ZXZEx => (2, true, true, false),
        EulerRot::XYZEx => (5, false, false, false),
        EulerRot::ZYZEx => (5, false, true, false),
    }
}

/// Computes `a * b * c + d * e` from the two exact Q96.96 products, with a single rescale.
#[inline(always)]
fn mul3_add2(a: Fixed, b: Fixed, c: Fixed, d: Fixed, e: Fixed) -> Fixed {
    wide_mul(a, b).mul(c).add(wide_mul(d, e).lift()).narrow()
}

/// Computes `a * b * c - d * e` from the two exact Q96.96 products, with a single rescale.
#[inline(always)]
fn mul3_sub2(a: Fixed, b: Fixed, c: Fixed, d: Fixed, e: Fixed) -> Fixed {
    wide_mul(a, b).mul(c).sub(wide_mul(d, e).lift()).narrow()
}

/// Computes `a * b * c + d * e * f` from the two exact Q96.96 products, with a single rescale.
#[inline(always)]
fn mul3_add3(a: Fixed, b: Fixed, c: Fixed, d: Fixed, e: Fixed, f: Fixed) -> Fixed {
    wide_mul(a, b).mul(c).add(wide_mul(d, e).mul(f)).narrow()
}

/// Computes `a * b * c - d * e * f` from the two exact Q96.96 products, with a single rescale.
#[inline(always)]
fn mul3_sub3(a: Fixed, b: Fixed, c: Fixed, d: Fixed, e: Fixed, f: Fixed) -> Fixed {
    wide_mul(a, b).mul(c).sub(wide_mul(d, e).mul(f)).narrow()
}

/// Orders the three angles as the elemental rotations `(i, j, k)`: an extrinsic sequence is the
/// intrinsic one read backwards.
#[inline(always)]
fn angles(frame_static: bool, a: Fixed, b: Fixed, c: Fixed) -> (Fixed, Fixed, Fixed) {
    if frame_static {
        (a, b, c)
    } else {
        (c, b, a)
    }
}

/// Places the nine entries of the `(i, j, k)` frame into the world frame.
///
/// The argument order is the `m[i][i], m[i][j], m[i][k], m[j][i], ...` of glam-rs, i.e. column
/// then row: the returned matrix has `m[i]` as its `i`-th column.
#[inline(always)]
fn from_ijk(
    perm: u8,
    ii: Fixed,
    ij: Fixed,
    ik: Fixed,
    ji: Fixed,
    jj: Fixed,
    jk: Fixed,
    ki: Fixed,
    kj: Fixed,
    kk: Fixed,
) -> Mat3 {
    match perm {
        0 => Mat3 {
            x_axis: Vec3 { x: ii, y: ij, z: ik },
            y_axis: Vec3 { x: ji, y: jj, z: jk },
            z_axis: Vec3 { x: ki, y: kj, z: kk },
        },
        1 => Mat3 {
            x_axis: Vec3 { x: kk, y: ki, z: kj },
            y_axis: Vec3 { x: ik, y: ii, z: ij },
            z_axis: Vec3 { x: jk, y: ji, z: jj },
        },
        2 => Mat3 {
            x_axis: Vec3 { x: jj, y: jk, z: ji },
            y_axis: Vec3 { x: kj, y: kk, z: ki },
            z_axis: Vec3 { x: ij, y: ik, z: ii },
        },
        3 => Mat3 {
            x_axis: Vec3 { x: ii, y: ik, z: ij },
            y_axis: Vec3 { x: ki, y: kk, z: kj },
            z_axis: Vec3 { x: ji, y: jk, z: jj },
        },
        4 => Mat3 {
            x_axis: Vec3 { x: jj, y: ji, z: jk },
            y_axis: Vec3 { x: ij, y: ii, z: ik },
            z_axis: Vec3 { x: kj, y: ki, z: kk },
        },
        _ => Mat3 {
            x_axis: Vec3 { x: kk, y: kj, z: ki },
            y_axis: Vec3 { x: jk, y: jj, z: ji },
            z_axis: Vec3 { x: ik, y: ij, z: ii },
        },
    }
}

/// Reads the nine entries of `m` in the `(i, j, k)` frame: the inverse of [`from_ijk`], returned
/// as the matrix whose first column is `(m[i][i], m[i][j], m[i][k])`.
#[inline(always)]
fn to_ijk(m: Mat3, perm: u8) -> Mat3 {
    let (x, y, z) = (m.x_axis, m.y_axis, m.z_axis);
    match perm {
        0 => Mat3 { x_axis: x, y_axis: y, z_axis: z },
        1 => Mat3 {
            x_axis: Vec3 { x: y.y, y: y.z, z: y.x },
            y_axis: Vec3 { x: z.y, y: z.z, z: z.x },
            z_axis: Vec3 { x: x.y, y: x.z, z: x.x },
        },
        2 => Mat3 {
            x_axis: Vec3 { x: z.z, y: z.x, z: z.y },
            y_axis: Vec3 { x: x.z, y: x.x, z: x.y },
            z_axis: Vec3 { x: y.z, y: y.x, z: y.y },
        },
        3 => Mat3 {
            x_axis: Vec3 { x: x.x, y: x.z, z: x.y },
            y_axis: Vec3 { x: z.x, y: z.z, z: z.y },
            z_axis: Vec3 { x: y.x, y: y.z, z: y.y },
        },
        4 => Mat3 {
            x_axis: Vec3 { x: y.y, y: y.x, z: y.z },
            y_axis: Vec3 { x: x.y, y: x.x, z: x.z },
            z_axis: Vec3 { x: z.y, y: z.x, z: z.z },
        },
        _ => Mat3 {
            x_axis: Vec3 { x: z.z, y: z.y, z: z.x },
            y_axis: Vec3 { x: y.z, y: y.y, z: y.x },
            z_axis: Vec3 { x: x.z, y: x.y, z: x.x },
        },
    }
}

/// Places `(a[i], a[j], a[k], a[3])` into a quaternion.
#[inline(always)]
fn quat_from_ijk(perm: u8, ai: Fixed, aj: Fixed, ak: Fixed, w: Fixed) -> Quat {
    match perm {
        0 => Quat { x: ai, y: aj, z: ak, w },
        1 => Quat { x: ak, y: ai, z: aj, w },
        2 => Quat { x: aj, y: ak, z: ai, w },
        3 => Quat { x: ai, y: ak, z: aj, w },
        4 => Quat { x: aj, y: ai, z: ak, w },
        _ => Quat { x: ak, y: aj, z: ai, w },
    }
}

/// The rotation matrix of a unit quaternion, as `glam::Mat3::from_quat` computes it.
///
/// `glam::Mat3::from_quat` itself is task X1 and does not exist yet; this private copy keeps
/// `euler` self-contained and is the only duplication in the module.
fn mat3_from_quat(q: Quat) -> Mat3 {
    let (x2, y2, z2) = (q.x + q.x, q.y + q.y, q.z + q.z);
    Mat3 {
        x_axis: Vec3 {
            x: dot2_add(-q.y, y2, -q.z, z2, ONE),
            y: dot2(q.x, y2, q.w, z2),
            z: mul_sub(q.x, z2, q.w, y2),
        },
        y_axis: Vec3 {
            x: mul_sub(q.x, y2, q.w, z2),
            y: dot2_add(-q.x, x2, -q.z, z2, ONE),
            z: dot2(q.y, z2, q.w, x2),
        },
        z_axis: Vec3 {
            x: dot2(q.x, z2, q.w, y2),
            y: mul_sub(q.y, z2, q.w, x2),
            z: dot2_add(-q.x, x2, -q.y, y2, ONE),
        },
    }
}

pub trait Mat3EulerTrait {
    /// Creates a 3D rotation matrix from the given Euler rotation sequence and the angles (in
    /// radians).
    ///
    /// Mirrors `glam::Mat3::from_euler`.
    /// #### Panics
    /// * Never (every entry is a product of sines and cosines, so `|entry| <= 2`).
    /// #### Deviations
    /// * A method of an extension trait, not of `Mat3Trait`: `use glam::euler::Mat3EulerTrait;`
    ///   brings it into scope.
    /// * Each entry is a single rescale of the exact sum of two triple products instead of the
    ///   two chained roundings of glam-rs: the result is the floor of the exact entry, within
    ///   3 ULP of the real one (1 ULP per `sin_cos`, amplified by factors of modulus <= 1).
    fn from_euler(order: EulerRot, a: Fixed, b: Fixed, c: Fixed) -> Mat3;
    /// Extracts the Euler angles of `self` with the given Euler rotation order.
    ///
    /// #### Preconditions
    /// * `self` is a rotation matrix. The result is ill-defined for a matrix that carries a
    ///   scale, a shear or a reflection (glam-rs asserts it under `glam_assert`; this port does
    ///   not check it, docs/DESIGN.md section 3).
    ///
    /// Mirrors `glam::Mat3::to_euler`.
    /// #### Panics
    /// * `'Fixed: overflow'` if `sqrt(a^2 + b^2)` of two entries of `self` leaves the scalar
    ///   range, which no rotation matrix does (`|entry| <= 1`).
    /// #### Deviations
    /// * A method of an extension trait, not of `Mat3Trait`.
    /// * The gimbal-lock threshold is [`GIMBAL_EPS`] (16 raw ULP), the Q32.32 transposition of
    ///   the `16 * EPSILON` of glam-rs.
    /// * The error is that of [`fixed::trig::TrigTrait::atan2`] (3.22 ULP) plus the 1 ULP of the
    ///   floored `sqrt`, as long as the rotation is not close to gimbal lock; see
    ///   [`GIMBAL_EPS`] for the conditioning near it.
    fn to_euler(self: Mat3, order: EulerRot) -> (Fixed, Fixed, Fixed);
}

pub impl Mat3EulerImpl of Mat3EulerTrait {
    fn from_euler(order: EulerRot, a: Fixed, b: Fixed, c: Fixed) -> Mat3 {
        let (perm, parity_even, repeated, frame_static) = decode(order);
        let (ai, aj, ah) = angles(frame_static, a, b, c);
        let (si, ci) = ai.sin_cos();
        let (sj, cj) = aj.sin_cos();
        let (sh, ch) = ah.sin_cos();
        // The rotation direction is reversed from the original paper: glam-rs negates the three
        // angles on an even parity. `sin(-x) = -sin(x)` and `cos(-x) = cos(x)` are exact
        // (`fixed::trig`), so the sines are negated instead, which also keeps `i64::MIN` out of
        // the negation.
        let (si, sj, sh) = if parity_even {
            (-si, -sj, -sh)
        } else {
            (si, sj, sh)
        };
        if repeated {
            from_ijk(
                perm,
                cj,
                sj * si,
                sj * ci,
                sj * sh,
                mul3_add2(-si, sh, cj, ci, ch),
                mul3_sub2(-ci, sh, cj, si, ch),
                (-sj) * ch,
                mul3_add2(si, ch, cj, ci, sh),
                mul3_sub2(ci, ch, cj, si, sh),
            )
        } else {
            from_ijk(
                perm,
                cj * ch,
                mul3_sub2(si, ch, sj, ci, sh),
                mul3_add2(ci, ch, sj, si, sh),
                cj * sh,
                mul3_add2(si, sh, sj, ci, ch),
                mul3_sub2(ci, sh, sj, si, ch),
                -sj,
                cj * si,
                cj * ci,
            )
        }
    }

    fn to_euler(self: Mat3, order: EulerRot) -> (Fixed, Fixed, Fixed) {
        let (perm, parity_even, repeated, frame_static) = decode(order);
        let m = to_ijk(self, perm);
        let (ex, ey, ez) = if repeated {
            let sy = norm2(m.x_axis.y, m.x_axis.z);
            if sy > GIMBAL_EPS {
                (m.x_axis.y.atan2(m.x_axis.z), sy.atan2(m.x_axis.x), m.y_axis.x.atan2(-m.z_axis.x))
            } else {
                ((-m.y_axis.z).atan2(m.y_axis.y), sy.atan2(m.x_axis.x), ZERO)
            }
        } else {
            let cy = norm2(m.x_axis.x, m.y_axis.x);
            if cy > GIMBAL_EPS {
                (
                    m.z_axis.y.atan2(m.z_axis.z),
                    (-m.z_axis.x).atan2(cy),
                    m.y_axis.x.atan2(m.x_axis.x),
                )
            } else {
                ((-m.y_axis.z).atan2(m.y_axis.y), (-m.z_axis.x).atan2(cy), ZERO)
            }
        };
        // The reverse rotation angle of the original code, then the extrinsic reading.
        let (ex, ey, ez) = if parity_even {
            (-ex, -ey, -ez)
        } else {
            (ex, ey, ez)
        };
        angles(frame_static, ex, ey, ez)
    }
}

pub trait Mat4EulerTrait {
    /// Creates a 4x4 affine transformation matrix from the given 3D Euler rotation sequence and
    /// the angles (in radians).
    ///
    /// Mirrors `glam::Mat4::from_euler`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * A method of an extension trait, not of `Mat4Trait`.
    /// * Same rounding as [`Mat3EulerTrait::from_euler`], whose result it embeds.
    fn from_euler(order: EulerRot, a: Fixed, b: Fixed, c: Fixed) -> Mat4;
    /// Extracts the Euler angles of the upper 3x3 block of `self` with the given Euler rotation
    /// order.
    ///
    /// #### Preconditions
    /// * The upper 3x3 block of `self` is a rotation matrix.
    ///
    /// Mirrors `glam::Mat4::to_euler`.
    /// #### Panics
    /// * `'Fixed: overflow'`, as [`Mat3EulerTrait::to_euler`].
    /// #### Deviations
    /// * A method of an extension trait, not of `Mat4Trait`.
    /// * Same values as [`Mat3EulerTrait::to_euler`] of `Mat3::from_mat4(self)`.
    fn to_euler(self: Mat4, order: EulerRot) -> (Fixed, Fixed, Fixed);
}

pub impl Mat4EulerImpl of Mat4EulerTrait {
    #[inline(always)]
    fn from_euler(order: EulerRot, a: Fixed, b: Fixed, c: Fixed) -> Mat4 {
        Mat4Trait::from_mat3(Mat3EulerTrait::from_euler(order, a, b, c))
    }

    #[inline(always)]
    fn to_euler(self: Mat4, order: EulerRot) -> (Fixed, Fixed, Fixed) {
        Mat3Trait::from_mat4(self).to_euler(order)
    }
}

pub trait QuatEulerTrait {
    /// Creates a quaternion from the given Euler rotation sequence and the angles (in radians).
    ///
    /// Mirrors `glam::Quat::from_euler`.
    /// #### Panics
    /// * Never (every component is a product of sines and cosines of half angles).
    /// #### Deviations
    /// * A method of an extension trait, not of `QuatTrait`: `use glam::euler::QuatEulerTrait;`
    ///   brings it into scope.
    /// * Each component is a single rescale of the exact sum of two triple products instead of
    ///   the two chained roundings of glam-rs: the result is the floor of the exact component,
    ///   within 3 ULP of the real one.
    /// * The result is a unit quaternion up to that rounding; it is not renormalized, exactly as
    ///   in glam-rs.
    fn from_euler(order: EulerRot, a: Fixed, b: Fixed, c: Fixed) -> Quat;
    /// Returns the Euler angles of `self` for the given Euler rotation order.
    ///
    /// #### Preconditions
    /// * `self` is normalized (glam-rs asserts it under `glam_assert`; this port does not check
    ///   it, docs/DESIGN.md section 3).
    ///
    /// Mirrors `glam::Quat::to_euler`.
    /// #### Panics
    /// * `'i64_add Overflow'` / `'i64_add Underflow'` if a component of `self` is outside
    ///   `[-2^30, 2^30)`: the rotation matrix doubles every component first. A normalized
    ///   quaternion never reaches it.
    /// #### Deviations
    /// * A method of an extension trait, not of `QuatTrait`.
    /// * Goes through the rotation matrix of `self`, as glam-rs does. The nine entries are
    ///   fused (one rescale each) instead of glam-rs' twelve rounded products.
    /// * The error is that of [`Mat3EulerTrait::to_euler`] (5 ULP) plus the 2 ULP of the matrix
    ///   entries divided by the residual of the order (see [`GIMBAL_EPS`]).
    fn to_euler(self: Quat, order: EulerRot) -> (Fixed, Fixed, Fixed);
}

pub impl QuatEulerImpl of QuatEulerTrait {
    fn from_euler(order: EulerRot, a: Fixed, b: Fixed, c: Fixed) -> Quat {
        let (perm, parity_even, repeated, frame_static) = decode(order);
        let (ai, aj, ah) = angles(frame_static, a, b, c);
        // Half angles: `angle * 0.5`, floored once, exactly as `Quat::from_rotation_x` does it,
        // so that `from_euler(XYZ, a, 0, 0)` is `from_rotation_x(a)` to the bit.
        let (si, ci) = (ai * HALF).sin_cos();
        let (sj, cj) = (aj * HALF).sin_cos();
        let (sh, ch) = (ah * HALF).sin_cos();
        // glam-rs negates the middle angle on an even parity, and multiplies `a[j]` by the
        // parity sign. `sin(-x) = -sin(x)` is exact, so the negation lands on `sj`.
        let sj = if parity_even {
            -sj
        } else {
            sj
        };
        let (pcj, psj) = if parity_even {
            (-cj, -sj)
        } else {
            (cj, sj)
        };
        if repeated {
            quat_from_ijk(
                perm,
                mul3_add3(ci, sh, cj, si, ch, cj),
                mul3_add3(ci, ch, psj, si, sh, psj),
                mul3_sub3(ci, sh, sj, si, ch, sj),
                mul3_sub3(ci, ch, cj, si, sh, cj),
            )
        } else {
            quat_from_ijk(
                perm,
                mul3_sub3(si, ch, cj, ci, sh, sj),
                mul3_add3(si, sh, pcj, ci, ch, psj),
                mul3_sub3(ci, sh, cj, si, ch, sj),
                mul3_add3(ci, ch, cj, si, sh, sj),
            )
        }
    }

    fn to_euler(self: Quat, order: EulerRot) -> (Fixed, Fixed, Fixed) {
        mat3_from_quat(self).to_euler(order)
    }
}
