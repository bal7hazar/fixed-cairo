//! Tests of `glam::affine3`: table-driven constructors and transforms, exact fixed-point
//! identities (exact quarter turns, identity products, `Mat4` round trips), the rigid-body
//! helpers against the general inverse, seeded fuzz properties, and every explicit panic path.
//! glam-rs `DAffine3` comparisons are generated separately in `golden_affine3.cairo`.

use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use fixed::fixed::{FRAC_PI_2, Fixed, FixedTrait, TAU_RAW};
use glam::affine3::{Affine3, Affine3RigidTrait, Affine3Trait, quat_from_affine3};
use glam::mat3::Mat3Trait;
use glam::mat4::{Mat4, Mat4Trait};
use glam::quat::{Quat, QuatTrait};
use glam::vec3::{Vec3, Vec3Trait};

const ONE: i64 = 0x100000000;

fn f(raw: i64) -> Fixed {
    FixedTrait::from_raw(raw)
}

fn v(x: i64, y: i64, z: i64) -> Vec3 {
    Vec3 { x: f(x), y: f(y), z: f(z) }
}

/// Twelve raw values in column-major order, starting at `o`.
fn af(r: Span<i64>, o: u32) -> Affine3 {
    Affine3Trait::from_cols(
        v(*r[o], *r[o + 1], *r[o + 2]),
        v(*r[o + 3], *r[o + 4], *r[o + 5]),
        v(*r[o + 6], *r[o + 7], *r[o + 8]),
        v(*r[o + 9], *r[o + 10], *r[o + 11]),
    )
}

fn hash(a: Affine3) -> felt252 {
    PoseidonTrait::new().update_with(a).finalize()
}

#[test]
fn test_consts_layout_default_hash_serde() {
    let a = Affine3Trait::from_cols_array(
        [f(1), f(-2), f(3), f(-4), f(5), f(-6), f(7), f(-8), f(9), f(-10), f(11), f(-12)],
    );
    assert_eq!(a.matrix3.x_axis, v(1, -2, 3));
    assert_eq!(a.matrix3.z_axis, v(7, -8, 9));
    assert_eq!(a.translation, v(-10, 11, -12));
    assert_eq!(Affine3Trait::ZERO, Affine3Trait::from_cols_array([f(0); 12]));
    assert_eq!(
        Affine3Trait::IDENTITY,
        Affine3Trait::from_mat3_translation(Mat3Trait::IDENTITY, Vec3Trait::ZERO),
    );
    assert_eq!(Default::<Affine3>::default(), Affine3Trait::IDENTITY);
    assert_eq!(Affine3Trait::from_cols_array(a.to_cols_array()), a);
    assert_eq!(Affine3Trait::from_cols_array_2d(a.to_cols_array_2d()), a);
    let [c0, _, _, c3] = a.to_cols_array_2d();
    assert_eq!(c0, [f(1), f(-2), f(3)]);
    assert_eq!(c3, [f(-10), f(11), f(-12)]);
    assert_eq!(hash(a), hash(a));
    assert!(hash(a) != hash(Affine3Trait::IDENTITY));
    let mut out = array![];
    a.serialize(ref out);
    assert_eq!(out.len(), 12);
    let mut span = out.span();
    assert_eq!(Serde::<Affine3>::deserialize(ref span), Some(a));
}
#[cairofmt::skip]
const VECS: [[i64; 6]; 4] = [
    [4294967296, 8589934592, -4294967296, 0, 12884901888, -2147483648],
    [-8589934592, 12884901888, 1, -1, 1, 2],
    [0, 0, 0, 0, 0, 0],
    [34359738368, -21474836480, 3221225472, -34359738368, 21474836480, 7],
];

#[test]
fn test_basic_constructors() {
    for row in VECS.span() {
        let r = row.span();
        let s = v(*r[0], *r[1], *r[2]);
        let t = v(*r[3], *r[4], *r[5]);
        let scaled = Affine3Trait::from_scale(s);
        assert_eq!(scaled.matrix3, Mat3Trait::from_diagonal(s));
        assert_eq!(scaled.translation, Vec3Trait::ZERO);
        let translated = Affine3Trait::from_translation(t);
        assert_eq!(translated.matrix3, Mat3Trait::IDENTITY);
        assert_eq!(translated.translation, t);
        assert_eq!(translated.transform_point3(s), s + t);
        assert_eq!(translated.transform_vector3(s), s);
        assert_eq!(scaled.transform_vector3(Vec3Trait::ONE), s);
        assert_eq!(Affine3Trait::from_mat3(scaled.matrix3), scaled);
        assert_eq!(
            Affine3Trait::from_mat3_translation(scaled.matrix3, t),
            Affine3 { matrix3: scaled.matrix3, translation: t },
        );
        assert_eq!(Affine3Trait::ZERO.transform_point3(t), Vec3Trait::ZERO);
    }
    let q = Quat { x: f(0), y: f(0), z: f(0), w: f(ONE) };
    assert_eq!(Affine3Trait::from_quat(q), Affine3Trait::IDENTITY);
    let t = v(ONE, 2 * ONE, 3 * ONE);
    assert_eq!(Affine3Trait::from_rotation_translation(q, t), Affine3Trait::from_translation(t));
    assert_eq!(
        Affine3Trait::from_scale_rotation_translation(v(2 * ONE, 3 * ONE, ONE / 2), q, t),
        Affine3Trait::from_mat3_translation(
            Mat3Trait::from_diagonal(v(2 * ONE, 3 * ONE, ONE / 2)), t,
        ),
    );
}

#[test]
fn test_quarter_turns_exact() {
    // `sin_cos(pi / 2)` is exactly `(1, 0)`: every quarter-turn constructor is exact.
    let rz = Affine3Trait::from_rotation_z(FRAC_PI_2);
    assert_eq!(rz.matrix3.x_axis, Vec3Trait::Y);
    assert_eq!(rz.matrix3.y_axis, Vec3Trait::NEG_X);
    assert_eq!(rz.matrix3.z_axis, Vec3Trait::Z);
    let rx = Affine3Trait::from_rotation_x(FRAC_PI_2);
    assert_eq!(rx.transform_vector3(Vec3Trait::Y), Vec3Trait::Z);
    assert_eq!(rx.transform_vector3(Vec3Trait::Z), Vec3Trait::NEG_Y);
    let ry = Affine3Trait::from_rotation_y(FRAC_PI_2);
    assert_eq!(ry.transform_vector3(Vec3Trait::Z), Vec3Trait::X);
    assert_eq!(ry.transform_vector3(Vec3Trait::X), Vec3Trait::NEG_Z);
    assert_eq!(Affine3Trait::from_axis_angle(Vec3Trait::Z, FRAC_PI_2), rz);
    assert_eq!(Affine3Trait::from_axis_angle(Vec3Trait::X, FRAC_PI_2), rx);
    // A quarter turn plus a translation, and its exact inverses.
    let t = v(ONE, -2 * ONE, 3 * ONE);
    let a = Affine3Trait::from_mat3_translation(rz.matrix3, t);
    assert_eq!(a.transform_point3(Vec3Trait::X), Vec3Trait::Y + t);
    let expected = Affine3Trait::from_cols(
        v(0, -ONE, 0), v(ONE, 0, 0), v(0, 0, ONE), v(2 * ONE, ONE, -3 * ONE),
    );
    assert_eq!(a.inverse(), expected);
    assert_eq!(a.inverse_rigid(), expected);
    assert_eq!(a * a.inverse(), Affine3Trait::IDENTITY);
    assert_eq!(a.inv_mul(a), Affine3Trait::IDENTITY);
    assert_eq!(quat_from_affine3(Affine3Trait::IDENTITY), QuatTrait::IDENTITY);
    assert_eq!(QuatTrait::from_affine3(Affine3Trait::IDENTITY), QuatTrait::IDENTITY);
}
#[cairofmt::skip]
const COMPOSE: [[i64; 39]; 3] = [
    // lhs (12), rhs (12), lhs * rhs (12), point (3)
    [
        4294967296,0,0, 0,4294967296,0, 0,0,4294967296, 0,0,0,
        4294967296,8589934592,0, -4294967296,0,4294967296, 0,4294967296,4294967296, 8589934592,-4294967296,0,
        4294967296,8589934592,0, -4294967296,0,4294967296, 0,4294967296,4294967296, 8589934592,-4294967296,0,
        12884901888,17179869184,-4294967296,
    ],
    [
        0,4294967296,0, -4294967296,0,0, 0,0,4294967296, 4294967296,8589934592,12884901888,
        8589934592,0,0, 0,12884901888,0, 0,0,17179869184, -4294967296,4294967296,8589934592,
        0,8589934592,0, -12884901888,0,0, 0,0,17179869184, 0,4294967296,21474836480,
        4294967296,-8589934592,2147483648,
    ],
    [
        8589934592,0,0, 0,4294967296,0, 0,0,2147483648, -4294967296,8589934592,0,
        4294967296,0,0, 0,0,4294967296, 0,-4294967296,0, 12884901888,-4294967296,8589934592,
        8589934592,0,0, 0,0,2147483648, 0,-4294967296,0, 21474836480,4294967296,4294967296,
        -4294967296,4294967296,4294967296,
    ],
];

#[test]
fn test_composition_and_operator() {
    for row in COMPOSE.span() {
        let r = row.span();
        let lhs = af(r, 0);
        let rhs = af(r, 12);
        let expected = af(r, 24);
        let point = v(*r[36], *r[37], *r[38]);
        assert_eq!(lhs * rhs, expected);
        assert_eq!(Affine3Trait::IDENTITY * lhs, lhs);
        assert_eq!(lhs * Affine3Trait::IDENTITY, lhs);
        assert_eq!(
            (lhs * rhs).transform_point3(point), lhs.transform_point3(rhs.transform_point3(point)),
        );
        let mut assigned = lhs;
        assigned *= rhs;
        assert_eq!(assigned, expected);
    }
}

#[test]
fn test_mat4_conversions_and_products() {
    let a = af(COMPOSE.span()[1].span(), 0);
    let b = af(COMPOSE.span()[1].span(), 12);
    let m: Mat4 = a.into();
    assert_eq!(m, Mat4Trait::from_mat3_translation(a.matrix3, a.translation));
    assert_eq!(Affine3Trait::from_mat4(m), a);
    let n: Mat4 = b.into();
    assert_eq!(a.mul_mat4(n), m * n);
    assert_eq!(Affine3Trait::from_mat4(a.mul_mat4(n)), a * b);
    let p = Mat4Trait::from_cols_array(
        [
            f(ONE), f(2 * ONE), f(-ONE), f(ONE / 4), f(0), f(ONE), f(3 * ONE), f(-ONE / 2),
            f(ONE / 2), f(0), f(ONE), f(0), f(-ONE), f(ONE), f(2 * ONE), f(ONE),
        ],
    );
    assert_eq!(a.mul_mat4(p), m * p);
}

#[test]
fn test_trs_and_views() {
    // The TRS decomposition of axis-aligned transforms is exact, including a negative
    // determinant (carried by `scale.x`).
    let t = v(ONE, 2 * ONE, 3 * ONE);
    let (s, q, tt) = Affine3Trait::from_cols(
        v(2 * ONE, 0, 0), v(0, 3 * ONE, 0), v(0, 0, ONE / 2), t,
    )
        .to_scale_rotation_translation();
    assert_eq!(s, v(2 * ONE, 3 * ONE, ONE / 2));
    assert_eq!(q, QuatTrait::IDENTITY);
    assert_eq!(tt, t);
    let (s, q, _) = Affine3Trait::from_cols(v(-2 * ONE, 0, 0), v(0, 3 * ONE, 0), v(0, 0, ONE), t)
        .to_scale_rotation_translation();
    assert_eq!(s, v(-2 * ONE, 3 * ONE, ONE));
    assert_eq!(q, QuatTrait::IDENTITY);
    // An axis-aligned camera looking down -Z (right-handed) or +Z (left-handed) is a
    // translation by `-eye`.
    let eye = v(ONE, 2 * ONE, 3 * ONE);
    let expected = Affine3Trait::from_translation(-eye);
    assert_eq!(Affine3Trait::look_to_rh(eye, v(0, 0, -5 * ONE), Vec3Trait::Y), expected);
    assert_eq!(Affine3Trait::look_to_lh(eye, Vec3Trait::Z, Vec3Trait::Y), expected);
    assert_eq!(Affine3Trait::look_at_rh(eye, eye + v(0, 0, -7 * ONE), Vec3Trait::Y), expected);
    assert_eq!(Affine3Trait::look_at_lh(eye, eye + v(0, 0, ONE), Vec3Trait::Y), expected);
}

#[test]
fn test_abs_diff_eq() {
    let a = af(COMPOSE.span()[2].span(), 0);
    assert!(a.abs_diff_eq(a, f(0)));
    let b = Affine3 { matrix3: a.matrix3, translation: a.translation + v(0, 0, 5) };
    assert!(!a.abs_diff_eq(b, f(4)));
    assert!(a.abs_diff_eq(b, f(5)));
    let c = Affine3 {
        matrix3: a.matrix3 + Mat3Trait::from_diagonal(v(-3, 0, 0)), translation: a.translation,
    };
    assert!(!a.abs_diff_eq(c, f(2)));
    assert!(a.abs_diff_eq(c, f(3)));
}

#[should_panic(expected: 'Affine3: singular')]
#[test]
fn test_inverse_singular_panics() {
    Affine3Trait::ZERO.inverse();
}

#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_inverse_overflow_panics() {
    // det = 2^-32: the inverse element 2^32 does not fit.
    Affine3Trait::from_scale(v(1, ONE, ONE)).inverse();
}

// panics: Affine3::transform_point3
#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_transform_point_overflow_panics() {
    Affine3Trait::from_scale(v(0x7fffffffffffffff, ONE, ONE)).transform_point3(v(2 * ONE, 0, 0));
}

// panics: Affine3::transform_vector3
#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_transform_vector_overflow_panics() {
    Affine3Trait::from_scale(v(0x7fffffffffffffff, ONE, ONE)).transform_vector3(v(2 * ONE, 0, 0));
}

// panics: Affine3::Affine3Mul
#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_composition_overflow_panics() {
    let a = Affine3Trait::from_scale(v(0x7fffffffffffffff, ONE, ONE));
    let _ = a * Affine3Trait::from_translation(v(2 * ONE, 0, 0));
}

#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_mul_mat4_overflow_panics() {
    Affine3Trait::from_translation(v(0x7fffffffffffffff, 0, 0))
        .mul_mat4(
            Mat4Trait::from_diagonal(
                glam::vec4::Vec4 { x: f(ONE), y: f(ONE), z: f(ONE), w: f(2 * ONE) },
            ),
        );
}

#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_inverse_rigid_overflow_panics() {
    // -(-2^31) does not fit: floor(-x) of the raw MIN translation.
    Affine3Trait::from_translation(v(-0x8000000000000000, 0, 0)).inverse_rigid();
}

#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_inv_mul_overflow_panics() {
    let a = Affine3Trait::from_translation(v(-0x7fffffffffffffff, 0, 0));
    a.inv_mul(Affine3Trait::from_translation(v(0x7fffffffffffffff, 0, 0)));
}

// panics: Affine3::look_to_rh
#[should_panic(expected: 'Vec3: normalize zero')]
#[test]
fn test_look_to_zero_dir_panics() {
    Affine3Trait::look_to_rh(Vec3Trait::ZERO, Vec3Trait::ZERO, Vec3Trait::Y);
}

// panics: Affine3::look_at_rh
#[should_panic(expected: 'Vec3: normalize zero')]
#[test]
fn test_look_at_parallel_up_panics() {
    Affine3Trait::look_at_rh(Vec3Trait::ZERO, Vec3Trait::Y, Vec3Trait::Y);
}

#[should_panic(expected: 'Fixed: division by zero')]
#[test]
fn test_to_scale_rotation_translation_zero_column_panics() {
    Affine3Trait::from_scale(v(0, ONE, ONE)).to_scale_rotation_translation();
}

#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_to_scale_rotation_translation_overflow_panics() {
    // |x_axis| = sqrt(2) * MAX
    let x_axis = v(0x7fffffffffffffff, 0x7fffffffffffffff, 0);
    Affine3Trait::from_cols(x_axis, Vec3Trait::Y, Vec3Trait::Z, Vec3Trait::ZERO)
        .to_scale_rotation_translation();
}

#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_look_to_rh_overflow_panics() {
    // `s = (0, -1, 1) / sqrt(2)`: `-dot(eye, s)` is `sqrt(2) * MAX`
    Affine3Trait::look_to_rh(
        v(0, -0x8000000000000000, 0x7fffffffffffffff), Vec3Trait::X, v(0, ONE, ONE),
    );
}

#[should_panic(expected: 'Vec3: normalize zero')]
#[test]
fn test_look_at_lh_eye_is_center_panics() {
    Affine3Trait::look_at_lh(Vec3Trait::ONE, Vec3Trait::ONE, Vec3Trait::Y);
}

#[should_panic(expected: 'i64_sub Underflow')]
#[test]
fn test_look_at_lh_sub_underflow_panics() {
    Affine3Trait::look_at_lh(
        v(0x7fffffffffffffff, 0, 0), v(-0x8000000000000000, 0, 0), Vec3Trait::Y,
    );
}

/// `|x| mod 1` in raw units.
fn frac(x: i64) -> i64 {
    let r = x % ONE;
    if r < 0 {
        -r
    } else {
        r
    }
}

/// A rotation (two exact-to-a-few-ULP rotations composed) and a translation `|t| < 8`.
fn fuzz_rigid(a: i64, b: i64, c: i64) -> Affine3 {
    let r = Affine3Trait::from_rotation_x(f(a % TAU_RAW))
        * Affine3Trait::from_rotation_z(f(b % TAU_RAW));
    Affine3 { matrix3: r.matrix3, translation: v(c % (8 * ONE), a % (8 * ONE), b % (8 * ONE)) }
}

/// A rigid transform times a scale in `[1/2, 3/2)` per axis.
fn fuzz_affine(a: i64, b: i64, c: i64, d: i64) -> Affine3 {
    let s = v(ONE / 2 + frac(d), ONE / 2 + frac(c), ONE / 2 + frac(a));
    fuzz_rigid(a, b, c) * Affine3Trait::from_scale(s)
}

// Tolerances of the fuzz properties, in raw ULPs (measured maxima over 400 deterministic draws
// of the same generators in parentheses).
// * `inv_mul` vs `inverse_rigid() * rhs` (1): same linear products; the translation is floored
//   once instead of twice: 2.
// * composition action (8): the composed elements are 1 ULP off, times `|p|_1 <= 12`, plus the
//   inner transform's 1 ULP times a row sum of `|x| <= 4.5` and two floors: 20.
// * `inverse_rigid` vs `inverse` and the identity products (34 / 28): a product of two
//   `sin_cos` rotations is orthonormal within about 4 ULP per element, and `R^{-1} - R^T`
//   carries that error times `|t|_1 <= 24` into the translation: 96.
// * `x * x.inverse()` (35): scales in `[1/2, 3/2)` keep `det >= 1/8`, so each floored
//   adjugate element or determinant is `8` ULP relative, times a row sum of `|x| <= 4.5`, on
//   the linear part (36) and the translation that the same errors cancel to first order:
//   160 leaves the headroom of the second-order terms.
// * TRS round trip (17 / 2): the scale within `5 |scale| + 2 < 17` ULP and the rotation within
//   13 ULP, the bounds of `Mat4::to_scale_rotation_translation` (same code path): 24 and 16.

#[test]
#[fuzzer(runs: 128, seed: 301)]
fn fuzz_inverse_identity(a: i64, b: i64, c: i64, d: i64) {
    let x = fuzz_affine(a, b, c, d);
    assert!((x * x.inverse()).abs_diff_eq(Affine3Trait::IDENTITY, f(160)));
}

#[test]
#[fuzzer(runs: 128, seed: 302)]
fn fuzz_inverse_rigid_matches_inverse(a: i64, b: i64, c: i64) {
    let x = fuzz_rigid(a, b, c);
    assert!(x.inverse_rigid().abs_diff_eq(x.inverse(), f(96)));
    assert!((x * x.inverse_rigid()).abs_diff_eq(Affine3Trait::IDENTITY, f(96)));
}

#[test]
#[fuzzer(runs: 128, seed: 303)]
fn fuzz_inv_mul_matches_composition(a: i64, b: i64, c: i64, d: i64) {
    let x = fuzz_rigid(a, b, c);
    let y = fuzz_affine(d, c, b, a);
    assert!(x.inv_mul(y).abs_diff_eq(x.inverse_rigid() * y, f(2)));
}

#[test]
#[fuzzer(runs: 128, seed: 304)]
fn fuzz_composition_action(a: i64, b: i64, c: i64, d: i64) {
    let x = fuzz_affine(a, b, c, d);
    let y = fuzz_affine(d, c, b, a);
    let p = v(a % (4 * ONE), b % (4 * ONE), c % (4 * ONE));
    assert!(
        (x * y).transform_point3(p).abs_diff_eq(x.transform_point3(y.transform_point3(p)), f(20)),
    );
}

#[test]
#[fuzzer(runs: 128, seed: 305)]
fn fuzz_mat4_roundtrip(a: i64, b: i64, c: i64, d: i64) {
    let x = fuzz_affine(a, b, c, d);
    let y = fuzz_affine(d, c, b, a);
    let m: Mat4 = x.into();
    assert_eq!(Affine3Trait::from_mat4(m), x);
    assert_eq!(x.mul_mat4(y.into()), m * y.into());
}

#[test]
#[fuzzer(runs: 128, seed: 306)]
fn fuzz_trs_roundtrip(a: i64, b: i64, c: i64, d: i64) {
    let q = QuatTrait::from_rotation_x(f(a % TAU_RAW)) * QuatTrait::from_rotation_z(f(b % TAU_RAW));
    let s = v(ONE / 2 + frac(c), ONE + frac(d), 2 * ONE + frac(a));
    let t = v(c % (8 * ONE), d % (8 * ONE), a % (8 * ONE));
    let (s2, q2, t2) = Affine3Trait::from_scale_rotation_translation(s, q, t)
        .to_scale_rotation_translation();
    assert_eq!(t2, t);
    assert!(s2.abs_diff_eq(s, f(24)));
    // `q` and `-q` are the same rotation.
    assert!(q2.abs_diff_eq(q, f(16)) || q2.abs_diff_eq(-q, f(16)));
}
