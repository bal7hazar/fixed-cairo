//! Tests of `glam::affine2`: table-driven constructors and transforms, exact fixed-point
//! identities, seeded fuzz properties, and every explicit panic path. glam-rs `DAffine2`
//! comparisons are generated separately in `golden_affine2.cairo`.

use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use fixed::fixed::{FRAC_PI_2, Fixed, FixedTrait, PI, TAU_RAW};
use glam::affine2::{Affine2, Affine2Trait};
use glam::mat2::Mat2Trait;
use glam::mat3::{Mat3, Mat3Trait};
use glam::vec2::{Vec2, Vec2Trait};
use glam::vec3::Vec3;

const IDENTITY_EPS: Fixed = Fixed { raw: 24 };

fn f(raw: i64) -> Fixed {
    FixedTrait::from_raw(raw)
}

fn vc(r: Span<i64>, o: u32) -> Vec2 {
    Vec2 { x: f(*r[o]), y: f(*r[o + 1]) }
}

fn af(r: Span<i64>, o: u32) -> Affine2 {
    Affine2Trait::from_cols_array(
        [f(*r[o]), f(*r[o + 1]), f(*r[o + 2]), f(*r[o + 3]), f(*r[o + 4]), f(*r[o + 5])],
    )
}

fn hash(a: Affine2) -> felt252 {
    PoseidonTrait::new().update_with(a).finalize()
}

#[test]
fn test_consts_layout_default_hash_serde() {
    let a = Affine2Trait::from_cols_array([f(1), f(-2), f(3), f(-4), f(5), f(-6)]);
    assert_eq!(
        Affine2Trait::ZERO, Affine2Trait::from_cols_array([f(0), f(0), f(0), f(0), f(0), f(0)]),
    );
    assert_eq!(
        Affine2Trait::IDENTITY,
        Affine2Trait::from_cols_array([f(0x100000000), f(0), f(0), f(0x100000000), f(0), f(0)]),
    );
    assert_eq!(Default::<Affine2>::default(), Affine2Trait::IDENTITY);
    assert_eq!(Affine2Trait::from_cols_array(a.to_cols_array()), a);
    assert_eq!(Affine2Trait::from_cols_array_2d(a.to_cols_array_2d()), a);
    assert_eq!(Affine2Trait::from_cols(a.matrix2.x_axis, a.matrix2.y_axis, a.translation), a);
    assert_eq!(hash(a), hash(a));
    assert!(hash(a) != hash(Affine2Trait::IDENTITY));
    let mut out = array![];
    a.serialize(ref out);
    assert_eq!(out.len(), 6);
    let mut span = out.span();
    assert_eq!(Serde::<Affine2>::deserialize(ref span), Some(a));
}
#[cairofmt::skip]
const CONSTRUCTORS: [[i64; 4]; 5] = [
    [4294967296, 8589934592, 4294967296, 0],
    [-8589934592, 12884901888, -8589934592, 12884901888],
    [1, -1, 1, -1],
    [0, 0, 0, 0],
    [34359738368, -21474836480, 34359738368, -21474836480],
];

#[test]
fn test_basic_constructors() {
    for row in CONSTRUCTORS.span() {
        let r = row.span();
        let scale = vc(r, 0);
        let translation = vc(r, 2);
        let scaled = Affine2Trait::from_scale(scale);
        let translated = Affine2Trait::from_translation(translation);
        assert_eq!(scaled.matrix2.x_axis, Vec2 { x: scale.x, y: f(0) });
        assert_eq!(scaled.matrix2.y_axis, Vec2 { x: f(0), y: scale.y });
        assert_eq!(scaled.translation, Vec2Trait::ZERO);
        assert_eq!(translated.matrix2, Mat2Trait::IDENTITY);
        assert_eq!(translated.translation, translation);
        assert_eq!(
            Affine2Trait::from_mat2_translation(scaled.matrix2, translation),
            Affine2 { matrix2: scaled.matrix2, translation },
        );
        assert_eq!(Affine2Trait::from_mat2(scaled.matrix2).translation, Vec2Trait::ZERO);
    }
}

#[test]
fn test_to_scale_angle_translation() {
    let translation = Vec2 { x: f(0x300000000), y: f(-0x200000000) };
    let cases = [
        (Vec2 { x: f(0x200000000), y: f(0x300000000) }, f(0)),
        (Vec2 { x: f(-0x200000000), y: f(0x300000000) }, FRAC_PI_2),
    ];
    for case in cases.span() {
        let (scale, angle) = *case;
        let a = Affine2Trait::from_scale_angle_translation(scale, angle, translation);
        let (actual_scale, actual_angle, actual_translation) = a.to_scale_angle_translation();
        assert_eq!(actual_scale, scale);
        assert_eq!(actual_angle, angle);
        assert_eq!(actual_translation, translation);
    }
}

#[test]
fn test_rotation_translation_and_transforms_exact() {
    let quarter = Affine2Trait::from_angle(FRAC_PI_2);
    assert_eq!(quarter.matrix2.x_axis, Vec2Trait::Y);
    assert_eq!(quarter.matrix2.y_axis, Vec2Trait::NEG_X);
    assert_eq!(quarter.transform_vector2(Vec2Trait::X), Vec2Trait::Y);
    assert_eq!(quarter.transform_vector2(Vec2Trait::Y), Vec2Trait::NEG_X);

    let t = Vec2 { x: f(0x300000000), y: f(-0x200000000) };
    let translated = Affine2Trait::from_translation(t);
    assert_eq!(translated.transform_point2(Vec2Trait::X), Vec2Trait::X + t);
    assert_eq!(translated.transform_vector2(Vec2Trait::X), Vec2Trait::X);
    assert_eq!(Affine2Trait::ZERO.transform_point2(t), Vec2Trait::ZERO);
    assert_eq!(
        Affine2Trait::from_angle_translation(FRAC_PI_2, t),
        Affine2 { matrix2: quarter.matrix2, translation: t },
    );
    assert_eq!(
        Affine2Trait::from_scale_angle_translation(Vec2Trait::ONE, FRAC_PI_2, t),
        Affine2 { matrix2: quarter.matrix2, translation: t },
    );
}
#[cairofmt::skip]
const COMPOSE: [[i64; 20]; 4] = [
    [4294967296,0,0,4294967296,0,0, 4294967296,0,0,4294967296,8589934592,-4294967296, 4294967296,0,0,4294967296,8589934592,-4294967296, 12884901888,17179869184],
    [0,4294967296,-4294967296,0,4294967296,8589934592, 8589934592,0,0,12884901888,-4294967296,4294967296, 0,8589934592,-12884901888,0,0,4294967296, 4294967296,8589934592],
    [8589934592,0,0,12884901888,4294967296,-4294967296, 4294967296,0,0,4294967296,8589934592,12884901888, 8589934592,0,0,12884901888,21474836480,34359738368, 4294967296,4294967296],
    [4294967296,0,0,4294967296,-4294967296,8589934592, 0,4294967296,-4294967296,0,0,0, 0,4294967296,-4294967296,0,-4294967296,8589934592, 8589934592,-12884901888],
];

#[test]
fn test_composition_and_operator() {
    for row in COMPOSE.span() {
        let r = row.span();
        let lhs = af(r, 0);
        let rhs = af(r, 6);
        let expected = af(r, 12);
        let point = vc(r, 18);
        assert_eq!(lhs * rhs, expected);
        assert_eq!(Affine2Trait::IDENTITY * lhs, lhs);
        assert_eq!(lhs * Affine2Trait::IDENTITY, lhs);
        assert_eq!(
            (lhs * rhs).transform_point2(point), lhs.transform_point2(rhs.transform_point2(point)),
        );
        let mut assigned = lhs;
        assigned *= rhs;
        assert_eq!(assigned, expected);
    }
}

#[test]
fn test_mat3_conversions_and_products() {
    let a = Affine2Trait::from_cols_array(
        [
            f(0x180000000), f(-0x80000000), f(0x40000000), f(0x200000000), f(0x300000000),
            f(-0x100000000),
        ],
    );
    let m: Mat3 = a.into();
    assert_eq!(m.x_axis, Vec3 { x: a.matrix2.x_axis.x, y: a.matrix2.x_axis.y, z: f(0) });
    assert_eq!(m.y_axis, Vec3 { x: a.matrix2.y_axis.x, y: a.matrix2.y_axis.y, z: f(0) });
    assert_eq!(m.z_axis, Vec3 { x: a.translation.x, y: a.translation.y, z: f(0x100000000) });
    let back: Affine2 = m.into();
    assert_eq!(back, a);
    assert_eq!(Affine2Trait::from_mat3(m), a);
    let rhs = Mat3Trait::from_cols(
        Vec3 { x: f(0x100000000), y: f(0x200000000), z: f(-0x100000000) },
        Vec3 { x: f(0), y: f(0x100000000), z: f(0x200000000) },
        Vec3 { x: f(0x300000000), y: f(-0x100000000), z: f(0x100000000) },
    );
    assert_eq!(a.mul_mat3(rhs), Mat3Trait::mul_mat3(m, rhs));
}

#[test]
fn test_inverse_identities_and_abs_diff() {
    let values = [
        Affine2Trait::IDENTITY,
        Affine2Trait::from_translation(Vec2 { x: f(0x100000000), y: f(0x200000000) }),
        Affine2Trait::from_scale(Vec2 { x: f(0x200000000), y: f(0x400000000) }),
        Affine2Trait::from_scale_angle_translation(
            Vec2 { x: f(0x180000000), y: f(0x140000000) },
            f(0x59999999),
            Vec2 { x: f(-0x200000000), y: f(0x300000000) },
        ),
    ];
    for a in values.span() {
        let a = *a;
        let inv = a.inverse();
        assert!((a * inv).abs_diff_eq(Affine2Trait::IDENTITY, IDENTITY_EPS));
        assert!((inv * a).abs_diff_eq(Affine2Trait::IDENTITY, IDENTITY_EPS));
        assert!(a.abs_diff_eq(a, f(0)));
    }
}

#[should_panic(expected: 'Affine2: singular')]
#[test]
fn test_inverse_singular_panics() {
    Affine2Trait::ZERO.inverse();
}

// panics: Affine2::transform_point2
#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_transform_point_overflow_panics() {
    Affine2Trait::from_scale(Vec2 { x: f(0x7fffffffffffffff), y: f(0x100000000) })
        .transform_point2(Vec2 { x: f(0x200000000), y: f(0) });
}

// panics: Affine2::transform_vector2
#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_transform_vector_overflow_panics() {
    Affine2Trait::from_scale(Vec2 { x: f(0x7fffffffffffffff), y: f(0x100000000) })
        .transform_vector2(Vec2 { x: f(0x200000000), y: f(0) });
}

// panics: Affine2::from_scale_angle_translation
#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_scale_angle_overflow_panics() {
    Affine2Trait::from_scale_angle_translation(
        Vec2 { x: f(-0x8000000000000000), y: f(0x100000000) }, PI, Vec2Trait::ZERO,
    );
}

// panics: Affine2::Affine2Mul
#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_composition_overflow_panics() {
    let a = Affine2Trait::from_scale(Vec2 { x: f(0x7fffffffffffffff), y: f(0x100000000) });
    let b = Affine2Trait::from_scale(Vec2 { x: f(0x200000000), y: f(0x100000000) });
    let _ = a * b;
}

#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_to_scale_angle_translation_overflow_panics() {
    // |x_axis| = sqrt(2) * MAX
    let x_axis = Vec2 { x: f(0x7fffffffffffffff), y: f(0x7fffffffffffffff) };
    Affine2Trait::from_cols(x_axis, Vec2Trait::Y, Vec2Trait::ZERO).to_scale_angle_translation();
}

#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_mul_mat3_overflow_panics() {
    let a = Affine2Trait::from_scale(Vec2 { x: f(0x7fffffffffffffff), y: f(0x100000000) });
    a
        .mul_mat3(
            Mat3Trait::from_diagonal(
                Vec3 { x: f(0x200000000), y: f(0x100000000), z: f(0x100000000) },
            ),
        );
}

#[should_panic(expected: 'Fixed: overflow')]
#[test]
fn test_inverse_overflow_panics() {
    Affine2Trait::from_cols(
        Vec2 { x: f(1), y: f(0) }, Vec2 { x: f(0), y: f(0x100000000) }, Vec2Trait::ZERO,
    )
        .inverse();
}

#[should_panic(expected: 'i64_neg Underflow')]
#[test]
fn test_inverse_off_diagonal_negation_panics() {
    Affine2Trait::from_cols(
        Vec2 { x: f(0x100000000), y: f(-0x8000000000000000) },
        Vec2 { x: f(0), y: f(0x100000000) },
        Vec2Trait::ZERO,
    )
        .inverse();
}

fn fuzz_affine(a: i64, b: i64, c: i64, d: i64) -> Affine2 {
    let ar = a % 0x100000000;
    let br = b % 0x100000000;
    let sx = f(0x80000000 + if ar < 0 {
        -ar
    } else {
        ar
    });
    let sy = f(0x80000000 + if br < 0 {
        -br
    } else {
        br
    });
    let angle = f(c % TAU_RAW);
    let translation = Vec2 { x: f(d % 0x800000000), y: f(a % 0x800000000) };
    Affine2Trait::from_scale_angle_translation(Vec2 { x: sx, y: sy }, angle, translation)
}

#[test]
#[fuzzer(runs: 128, seed: 201)]
fn fuzz_inverse_identity(a: i64, b: i64, c: i64, d: i64) {
    let x = fuzz_affine(a, b, c, d);
    assert!((x * x.inverse()).abs_diff_eq(Affine2Trait::IDENTITY, f(96)));
}

#[test]
#[fuzzer(runs: 128, seed: 202)]
fn fuzz_composition_action(a: i64, b: i64, c: i64, d: i64) {
    let x = fuzz_affine(a, b, c, d);
    let y = fuzz_affine(d, c, b, a);
    let p = Vec2 { x: f(a % 0x400000000), y: f(b % 0x400000000) };
    assert!(
        (x * y).transform_point2(p).abs_diff_eq(x.transform_point2(y.transform_point2(p)), f(12)),
    );
}

#[test]
#[fuzzer(runs: 128, seed: 203)]
fn fuzz_mat3_roundtrip(a: i64, b: i64, c: i64, d: i64) {
    let x = fuzz_affine(a, b, c, d);
    let m: Mat3 = x.into();
    let back: Affine2 = m.into();
    assert_eq!(back, x);
}
