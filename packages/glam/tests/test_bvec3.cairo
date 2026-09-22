//! Tests of `glam::bvec3`: the glam-rs `impl_bvec3_tests!` cases, plus exhaustive checks over
//! the 8 masks (and the 64 pairs of masks for the binary operators).

use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use glam::bvec3::{BVec3, BVec3Trait, bvec3};

const COUNT: u32 = 8;
const FULL: u32 = 7;

/// Bit `index` of `m`, computed independently of the library.
fn bit(m: u32, index: u32) -> bool {
    let pow: u32 = match index {
        0 => 1,
        1 => 2,
        2 => 4,
        _ => 8,
    };
    (m / pow) % 2 == 1
}

/// The mask whose bitmask is `m`, built field by field.
fn from_bits(m: u32) -> BVec3 {
    BVec3 { x: bit(m, 0), y: bit(m, 1), z: bit(m, 2) }
}

fn hash(v: BVec3) -> felt252 {
    PoseidonTrait::new().update_with(v).finalize()
}

#[test]
fn test_mask_new() {
    assert_eq!(BVec3Trait::new(false, false, false), bvec3(false, false, false));
    assert_eq!(BVec3Trait::new(true, false, false), bvec3(true, false, false));
    assert_eq!(BVec3Trait::new(false, true, true), bvec3(false, true, true));
    assert_eq!(BVec3Trait::new(false, true, false), bvec3(false, true, false));
    assert_eq!(BVec3Trait::new(true, false, true), bvec3(true, false, true));
    assert_eq!(BVec3Trait::new(true, true, true), bvec3(true, true, true));
    let v = BVec3Trait::new(true, false, true);
    assert_eq!(v.x, true);
    assert_eq!(v.y, false);
    assert_eq!(v.z, true);
    assert_eq!(Default::<BVec3>::default(), BVec3Trait::FALSE);
}

#[test]
fn test_mask_consts() {
    assert_eq!(BVec3Trait::FALSE, BVec3Trait::new(false, false, false));
    assert_eq!(BVec3Trait::TRUE, BVec3Trait::new(true, true, true));
}

#[test]
fn test_mask_from_array_bool() {
    assert_eq!(BVec3Trait::new(false, false, false), BVec3Trait::from_array([false, false, false]));
    assert_eq!(BVec3Trait::new(false, false, false), [false, false, false].into());
    assert_eq!(BVec3Trait::new(true, false, false), BVec3Trait::from_array([true, false, false]));
    assert_eq!(BVec3Trait::new(true, false, false), [true, false, false].into());
    assert_eq!(BVec3Trait::new(false, true, true), BVec3Trait::from_array([false, true, true]));
    assert_eq!(BVec3Trait::new(false, true, true), [false, true, true].into());
    assert_eq!(BVec3Trait::new(false, true, false), BVec3Trait::from_array([false, true, false]));
    assert_eq!(BVec3Trait::new(false, true, false), [false, true, false].into());
    assert_eq!(BVec3Trait::new(true, false, true), BVec3Trait::from_array([true, false, true]));
    assert_eq!(BVec3Trait::new(true, false, true), [true, false, true].into());
    assert_eq!(BVec3Trait::new(true, true, true), BVec3Trait::from_array([true, true, true]));
    assert_eq!(BVec3Trait::new(true, true, true), [true, true, true].into());
}

#[test]
fn test_mask_into_array_u32() {
    let a: [u32; 3] = BVec3Trait::new(false, false, false).into();
    assert_eq!(a, [0, 0, 0]);
    let a: [u32; 3] = BVec3Trait::new(true, false, false).into();
    assert_eq!(a, [0xffffffff, 0, 0]);
    let a: [u32; 3] = BVec3Trait::new(false, true, true).into();
    assert_eq!(a, [0, 0xffffffff, 0xffffffff]);
    let a: [u32; 3] = BVec3Trait::new(false, true, false).into();
    assert_eq!(a, [0, 0xffffffff, 0]);
    let a: [u32; 3] = BVec3Trait::new(true, false, true).into();
    assert_eq!(a, [0xffffffff, 0, 0xffffffff]);
    let a: [u32; 3] = BVec3Trait::new(true, true, true).into();
    assert_eq!(a, [0xffffffff, 0xffffffff, 0xffffffff]);
}

#[test]
fn test_mask_into_array_bool() {
    let a: [bool; 3] = BVec3Trait::new(false, false, false).into();
    assert_eq!(a, [false, false, false]);
    let a: [bool; 3] = BVec3Trait::new(true, false, false).into();
    assert_eq!(a, [true, false, false]);
    let a: [bool; 3] = BVec3Trait::new(false, true, true).into();
    assert_eq!(a, [false, true, true]);
    let a: [bool; 3] = BVec3Trait::new(false, true, false).into();
    assert_eq!(a, [false, true, false]);
    let a: [bool; 3] = BVec3Trait::new(true, false, true).into();
    assert_eq!(a, [true, false, true]);
    let a: [bool; 3] = BVec3Trait::new(true, true, true).into();
    assert_eq!(a, [true, true, true]);
}

#[test]
fn test_mask_arrays_exhaustive() {
    for m in 0..COUNT {
        let v = from_bits(m);
        let bools: [bool; 3] = v.into();
        assert_eq!(bools, [v.x, v.y, v.z]);
        assert_eq!(BVec3Trait::from_array(bools), v);
        let back: BVec3 = bools.into();
        assert_eq!(back, v);
        let [x, y, z]: [u32; 3] = v.into();
        assert_eq!(x, if v.x {
            0xffffffff
        } else {
            0
        });
        assert_eq!(y, if v.y {
            0xffffffff
        } else {
            0
        });
        assert_eq!(z, if v.z {
            0xffffffff
        } else {
            0
        });
    }
}

#[test]
fn test_mask_splat() {
    assert_eq!(BVec3Trait::splat(false), BVec3Trait::new(false, false, false));
    assert_eq!(BVec3Trait::splat(true), BVec3Trait::new(true, true, true));
}

#[test]
fn test_mask_bitmask() {
    assert_eq!(BVec3Trait::new(false, false, false).bitmask(), 0b000);
    assert_eq!(BVec3Trait::new(true, false, false).bitmask(), 0b001);
    assert_eq!(BVec3Trait::new(false, true, true).bitmask(), 0b110);
    assert_eq!(BVec3Trait::new(false, true, false).bitmask(), 0b010);
    assert_eq!(BVec3Trait::new(true, false, true).bitmask(), 0b101);
    assert_eq!(BVec3Trait::new(true, true, true).bitmask(), 0b111);
}

#[test]
fn test_mask_bitmask_exhaustive() {
    for m in 0..COUNT {
        assert_eq!(from_bits(m).bitmask(), m);
    }
}

#[test]
fn test_mask_any() {
    assert_eq!(BVec3Trait::new(false, false, false).any(), false);
    assert_eq!(BVec3Trait::new(true, false, false).any(), true);
    assert_eq!(BVec3Trait::new(false, true, false).any(), true);
    assert_eq!(BVec3Trait::new(false, false, true).any(), true);
}

#[test]
fn test_mask_all() {
    assert_eq!(BVec3Trait::new(true, true, true).all(), true);
    assert_eq!(BVec3Trait::new(false, true, true).all(), false);
    assert_eq!(BVec3Trait::new(true, false, true).all(), false);
    assert_eq!(BVec3Trait::new(true, true, false).all(), false);
}

#[test]
fn test_mask_any_all_exhaustive() {
    for m in 0..COUNT {
        assert_eq!(from_bits(m).any(), m != 0);
        assert_eq!(from_bits(m).all(), m == FULL);
    }
}

#[test]
fn test_mask_and() {
    assert_eq!(
        (BVec3Trait::new(false, false, false) & BVec3Trait::new(false, false, false)).bitmask(),
        0b000,
    );
    assert_eq!(
        (BVec3Trait::new(true, true, true) & BVec3Trait::new(true, true, true)).bitmask(), 0b111,
    );
    assert_eq!(
        (BVec3Trait::new(true, false, true) & BVec3Trait::new(false, true, false)).bitmask(), 0b000,
    );
    assert_eq!(
        (BVec3Trait::new(true, false, true) & BVec3Trait::new(true, true, true)).bitmask(), 0b101,
    );
    let mut mask = BVec3Trait::new(true, true, false);
    mask = mask & BVec3Trait::new(true, false, false);
    assert_eq!(mask.bitmask(), 0b001);
}

#[test]
fn test_mask_and_exhaustive() {
    for a in 0..COUNT {
        for b in 0..COUNT {
            let r = from_bits(a) & from_bits(b);
            assert_eq!(r.x, bit(a, 0) && bit(b, 0));
            assert_eq!(r.y, bit(a, 1) && bit(b, 1));
            assert_eq!(r.z, bit(a, 2) && bit(b, 2));
            assert_eq!(r.bitmask(), a & b);
        }
    }
}

#[test]
fn test_mask_or() {
    assert_eq!(
        (BVec3Trait::new(false, false, false) | BVec3Trait::new(false, false, false)).bitmask(),
        0b000,
    );
    assert_eq!(
        (BVec3Trait::new(true, true, true) | BVec3Trait::new(true, true, true)).bitmask(), 0b111,
    );
    assert_eq!(
        (BVec3Trait::new(true, false, true) | BVec3Trait::new(false, true, false)).bitmask(), 0b111,
    );
    assert_eq!(
        (BVec3Trait::new(true, false, true) | BVec3Trait::new(true, false, true)).bitmask(), 0b101,
    );
    let mut mask = BVec3Trait::new(true, true, false);
    mask = mask | BVec3Trait::new(true, false, false);
    assert_eq!(mask.bitmask(), 0b011);
}

#[test]
fn test_mask_or_exhaustive() {
    for a in 0..COUNT {
        for b in 0..COUNT {
            let r = from_bits(a) | from_bits(b);
            assert_eq!(r.x, bit(a, 0) || bit(b, 0));
            assert_eq!(r.y, bit(a, 1) || bit(b, 1));
            assert_eq!(r.z, bit(a, 2) || bit(b, 2));
            assert_eq!(r.bitmask(), a | b);
        }
    }
}

#[test]
fn test_mask_xor() {
    assert_eq!(
        (BVec3Trait::new(false, false, false) ^ BVec3Trait::new(false, false, false)).bitmask(),
        0b000,
    );
    assert_eq!(
        (BVec3Trait::new(true, true, true) ^ BVec3Trait::new(true, true, true)).bitmask(), 0b000,
    );
    assert_eq!(
        (BVec3Trait::new(true, false, true) ^ BVec3Trait::new(false, true, false)).bitmask(), 0b111,
    );
    assert_eq!(
        (BVec3Trait::new(true, false, true) ^ BVec3Trait::new(true, false, true)).bitmask(), 0b000,
    );
    let mut mask = BVec3Trait::new(true, true, false);
    mask = mask ^ BVec3Trait::new(true, false, false);
    assert_eq!(mask.bitmask(), 0b010);
}

#[test]
fn test_mask_xor_exhaustive() {
    for a in 0..COUNT {
        for b in 0..COUNT {
            let r = from_bits(a) ^ from_bits(b);
            assert_eq!(r.x, bit(a, 0) != bit(b, 0));
            assert_eq!(r.y, bit(a, 1) != bit(b, 1));
            assert_eq!(r.z, bit(a, 2) != bit(b, 2));
            assert_eq!(r.bitmask(), a ^ b);
        }
    }
}

#[test]
fn test_mask_not() {
    assert_eq!((!BVec3Trait::new(false, false, false)).bitmask(), 0b111);
    assert_eq!((!BVec3Trait::new(true, true, true)).bitmask(), 0b000);
    assert_eq!((!BVec3Trait::new(true, false, true)).bitmask(), 0b010);
    assert_eq!((!BVec3Trait::new(false, true, false)).bitmask(), 0b101);
}

#[test]
fn test_mask_not_exhaustive() {
    for m in 0..COUNT {
        let r = !from_bits(m);
        assert_eq!(r.x, !bit(m, 0));
        assert_eq!(r.y, !bit(m, 1));
        assert_eq!(r.z, !bit(m, 2));
        assert_eq!(r.bitmask(), FULL - m);
        assert_eq!(!r, from_bits(m));
    }
}

#[test]
fn test_mask_fmt() {
    // Deviation: the derived `Debug`, not glam's `BVec3(0xffffffff, 0x0, ..)`; no `Display`.
    let a = BVec3Trait::new(true, false, false);
    assert_eq!(format!("{:?}", a), "BVec3 { x: true, y: false, z: false }");
}

#[test]
fn test_mask_eq() {
    let a = BVec3Trait::new(true, false, true);
    let b = BVec3Trait::new(true, false, true);
    let c = BVec3Trait::new(false, true, true);
    assert_eq!(a, b);
    assert_eq!(b, a);
    assert_ne!(a, c);
    assert_ne!(b, c);
}

#[test]
fn test_mask_eq_exhaustive() {
    for a in 0..COUNT {
        for b in 0..COUNT {
            assert_eq!(from_bits(a) == from_bits(b), a == b);
            assert_eq!(from_bits(a) != from_bits(b), a != b);
        }
    }
}

#[test]
fn test_mask_test() {
    let a = BVec3Trait::new(true, false, true);
    assert_eq!(a.test(0), true);
    assert_eq!(a.test(1), false);
    assert_eq!(a.test(2), true);
    let b = BVec3Trait::new(false, true, false);
    assert_eq!(b.test(0), false);
    assert_eq!(b.test(1), true);
    assert_eq!(b.test(2), false);
}

#[test]
fn test_mask_test_exhaustive() {
    for m in 0..COUNT {
        for i in 0..3_u32 {
            assert_eq!(from_bits(m).test(i), bit(m, i));
        }
    }
}

// panics: BVec3::test
#[test]
#[should_panic(expected: 'BVec3: index out of bounds')]
fn test_mask_test_out_of_bounds() {
    BVec3Trait::new(true, false, true).test(3);
}

// panics: BVec3::test
#[test]
#[should_panic(expected: 'BVec3: index out of bounds')]
fn test_mask_test_out_of_bounds_max() {
    BVec3Trait::new(true, false, true).test(0xffffffff);
}

#[test]
fn test_mask_set() {
    let mut a = BVec3Trait::new(false, true, false);
    a.set(0, true);
    assert_eq!(a.test(0), true);
    a.set(1, false);
    assert_eq!(a.test(1), false);
    a.set(2, true);
    assert_eq!(a.test(2), true);
    assert_eq!(a, BVec3Trait::new(true, false, true));
    let mut b = BVec3Trait::new(true, false, true);
    b.set(0, false);
    assert_eq!(b.test(0), false);
    b.set(1, true);
    assert_eq!(b.test(1), true);
    b.set(2, false);
    assert_eq!(b.test(2), false);
    assert_eq!(b, BVec3Trait::new(false, true, false));
}

#[test]
fn test_mask_set_exhaustive() {
    for m in 0..COUNT {
        for i in 0..3_u32 {
            let mut on = from_bits(m);
            on.set(i, true);
            let mut off = from_bits(m);
            off.set(i, false);
            for k in 0..3_u32 {
                assert_eq!(on.test(k), k == i || bit(m, k));
                assert_eq!(off.test(k), k != i && bit(m, k));
            }
        }
    }
}

// panics: BVec3::set
#[test]
#[should_panic(expected: 'BVec3: index out of bounds')]
fn test_mask_set_out_of_bounds() {
    let mut a = BVec3Trait::FALSE;
    a.set(3, true);
}

// panics: BVec3::set
#[test]
#[should_panic(expected: 'BVec3: index out of bounds')]
fn test_mask_set_out_of_bounds_max() {
    let mut a = BVec3Trait::FALSE;
    a.set(0xffffffff, true);
}

#[test]
fn test_mask_hash() {
    let a = BVec3Trait::new(true, false, true);
    let b = BVec3Trait::new(true, false, true);
    let c = BVec3Trait::new(false, true, true);
    assert_eq!(a, b);
    assert_eq!(hash(a), hash(b));
    assert_ne!(a, c);
    assert_ne!(hash(a), hash(c));
}

#[test]
fn test_mask_hash_exhaustive() {
    for a in 0..COUNT {
        for b in 0..COUNT {
            assert_eq!(hash(from_bits(a)) == hash(from_bits(b)), a == b);
        }
    }
}

#[test]
fn test_mask_serde() {
    for m in 0..COUNT {
        let v = from_bits(m);
        let mut out: Array<felt252> = array![];
        v.serialize(ref out);
        let expected: Array<felt252> = array![v.x.into(), v.y.into(), v.z.into()];
        assert_eq!(out, expected);
        let mut span = out.span();
        assert_eq!(Serde::<BVec3>::deserialize(ref span), Option::Some(v));
        assert!(span.is_empty());
    }
}

#[test]
fn test_mask_serde_too_short() {
    let mut short = array![1, 1].span();
    assert!(Serde::<BVec3>::deserialize(ref short).is_none());
}
