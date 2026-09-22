//! Tests of `glam::bvec2`: the glam-rs `impl_bvec2_tests!` cases, plus exhaustive checks over
//! the 4 masks (and the 16 pairs of masks for the binary operators).

use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use glam::bvec2::{BVec2, BVec2Trait, bvec2};

const COUNT: u32 = 4;
const FULL: u32 = 3;

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
fn from_bits(m: u32) -> BVec2 {
    BVec2 { x: bit(m, 0), y: bit(m, 1) }
}

fn hash(v: BVec2) -> felt252 {
    PoseidonTrait::new().update_with(v).finalize()
}

#[test]
fn test_mask_new() {
    assert_eq!(BVec2Trait::new(false, false), bvec2(false, false));
    assert_eq!(BVec2Trait::new(true, false), bvec2(true, false));
    assert_eq!(BVec2Trait::new(false, true), bvec2(false, true));
    assert_eq!(BVec2Trait::new(true, true), bvec2(true, true));
    let v = BVec2Trait::new(true, false);
    assert_eq!(v.x, true);
    assert_eq!(v.y, false);
    assert_eq!(Default::<BVec2>::default(), BVec2Trait::FALSE);
}

#[test]
fn test_mask_consts() {
    assert_eq!(BVec2Trait::FALSE, BVec2Trait::new(false, false));
    assert_eq!(BVec2Trait::TRUE, BVec2Trait::new(true, true));
}

#[test]
fn test_mask_from_array_bool() {
    assert_eq!(BVec2Trait::new(false, false), BVec2Trait::from_array([false, false]));
    assert_eq!(BVec2Trait::new(false, false), [false, false].into());
    assert_eq!(BVec2Trait::new(true, false), BVec2Trait::from_array([true, false]));
    assert_eq!(BVec2Trait::new(true, false), [true, false].into());
    assert_eq!(BVec2Trait::new(false, true), BVec2Trait::from_array([false, true]));
    assert_eq!(BVec2Trait::new(false, true), [false, true].into());
    assert_eq!(BVec2Trait::new(true, true), BVec2Trait::from_array([true, true]));
    assert_eq!(BVec2Trait::new(true, true), [true, true].into());
}

#[test]
fn test_mask_into_array_u32() {
    let a: [u32; 2] = BVec2Trait::new(false, false).into();
    assert_eq!(a, [0, 0]);
    let a: [u32; 2] = BVec2Trait::new(true, false).into();
    assert_eq!(a, [0xffffffff, 0]);
    let a: [u32; 2] = BVec2Trait::new(false, true).into();
    assert_eq!(a, [0, 0xffffffff]);
    let a: [u32; 2] = BVec2Trait::new(true, true).into();
    assert_eq!(a, [0xffffffff, 0xffffffff]);
}

#[test]
fn test_mask_into_array_bool() {
    let a: [bool; 2] = BVec2Trait::new(false, false).into();
    assert_eq!(a, [false, false]);
    let a: [bool; 2] = BVec2Trait::new(true, false).into();
    assert_eq!(a, [true, false]);
    let a: [bool; 2] = BVec2Trait::new(false, true).into();
    assert_eq!(a, [false, true]);
    let a: [bool; 2] = BVec2Trait::new(true, true).into();
    assert_eq!(a, [true, true]);
}

#[test]
fn test_mask_arrays_exhaustive() {
    for m in 0..COUNT {
        let v = from_bits(m);
        let bools: [bool; 2] = v.into();
        assert_eq!(bools, [v.x, v.y]);
        assert_eq!(BVec2Trait::from_array(bools), v);
        let back: BVec2 = bools.into();
        assert_eq!(back, v);
        let [x, y]: [u32; 2] = v.into();
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
    }
}

#[test]
fn test_mask_splat() {
    assert_eq!(BVec2Trait::splat(false), BVec2Trait::new(false, false));
    assert_eq!(BVec2Trait::splat(true), BVec2Trait::new(true, true));
}

#[test]
fn test_mask_bitmask() {
    assert_eq!(BVec2Trait::new(false, false).bitmask(), 0b00);
    assert_eq!(BVec2Trait::new(true, false).bitmask(), 0b01);
    assert_eq!(BVec2Trait::new(false, true).bitmask(), 0b10);
    assert_eq!(BVec2Trait::new(true, true).bitmask(), 0b11);
}

#[test]
fn test_mask_bitmask_exhaustive() {
    for m in 0..COUNT {
        assert_eq!(from_bits(m).bitmask(), m);
    }
}

#[test]
fn test_mask_any() {
    assert_eq!(BVec2Trait::new(false, false).any(), false);
    assert_eq!(BVec2Trait::new(true, false).any(), true);
    assert_eq!(BVec2Trait::new(false, true).any(), true);
}

#[test]
fn test_mask_all() {
    assert_eq!(BVec2Trait::new(true, true).all(), true);
    assert_eq!(BVec2Trait::new(false, true).all(), false);
    assert_eq!(BVec2Trait::new(true, false).all(), false);
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
    assert_eq!((BVec2Trait::new(false, false) & BVec2Trait::new(false, false)).bitmask(), 0b00);
    assert_eq!((BVec2Trait::new(true, true) & BVec2Trait::new(true, true)).bitmask(), 0b11);
    assert_eq!((BVec2Trait::new(true, false) & BVec2Trait::new(false, true)).bitmask(), 0b00);
    assert_eq!((BVec2Trait::new(true, false) & BVec2Trait::new(true, true)).bitmask(), 0b01);
    let mut mask = BVec2Trait::new(true, true);
    mask = mask & BVec2Trait::new(true, false);
    assert_eq!(mask.bitmask(), 0b01);
}

#[test]
fn test_mask_and_exhaustive() {
    for a in 0..COUNT {
        for b in 0..COUNT {
            let r = from_bits(a) & from_bits(b);
            assert_eq!(r.x, bit(a, 0) && bit(b, 0));
            assert_eq!(r.y, bit(a, 1) && bit(b, 1));
            assert_eq!(r.bitmask(), a & b);
        }
    }
}

#[test]
fn test_mask_or() {
    assert_eq!((BVec2Trait::new(false, false) | BVec2Trait::new(false, false)).bitmask(), 0b00);
    assert_eq!((BVec2Trait::new(true, true) | BVec2Trait::new(true, true)).bitmask(), 0b11);
    assert_eq!((BVec2Trait::new(true, false) | BVec2Trait::new(false, true)).bitmask(), 0b11);
    assert_eq!((BVec2Trait::new(true, false) | BVec2Trait::new(true, false)).bitmask(), 0b01);
    let mut mask = BVec2Trait::new(true, true);
    mask = mask | BVec2Trait::new(true, false);
    assert_eq!(mask.bitmask(), 0b11);
}

#[test]
fn test_mask_or_exhaustive() {
    for a in 0..COUNT {
        for b in 0..COUNT {
            let r = from_bits(a) | from_bits(b);
            assert_eq!(r.x, bit(a, 0) || bit(b, 0));
            assert_eq!(r.y, bit(a, 1) || bit(b, 1));
            assert_eq!(r.bitmask(), a | b);
        }
    }
}

#[test]
fn test_mask_xor() {
    assert_eq!((BVec2Trait::new(false, false) ^ BVec2Trait::new(false, false)).bitmask(), 0b00);
    assert_eq!((BVec2Trait::new(true, true) ^ BVec2Trait::new(true, true)).bitmask(), 0b00);
    assert_eq!((BVec2Trait::new(true, false) ^ BVec2Trait::new(false, true)).bitmask(), 0b11);
    assert_eq!((BVec2Trait::new(true, false) ^ BVec2Trait::new(true, false)).bitmask(), 0b00);
    let mut mask = BVec2Trait::new(true, true);
    mask = mask ^ BVec2Trait::new(true, false);
    assert_eq!(mask.bitmask(), 0b10);
}

#[test]
fn test_mask_xor_exhaustive() {
    for a in 0..COUNT {
        for b in 0..COUNT {
            let r = from_bits(a) ^ from_bits(b);
            assert_eq!(r.x, bit(a, 0) != bit(b, 0));
            assert_eq!(r.y, bit(a, 1) != bit(b, 1));
            assert_eq!(r.bitmask(), a ^ b);
        }
    }
}

#[test]
fn test_mask_not() {
    assert_eq!((!BVec2Trait::new(false, false)).bitmask(), 0b11);
    assert_eq!((!BVec2Trait::new(true, true)).bitmask(), 0b00);
    assert_eq!((!BVec2Trait::new(true, false)).bitmask(), 0b10);
    assert_eq!((!BVec2Trait::new(false, true)).bitmask(), 0b01);
}

#[test]
fn test_mask_not_exhaustive() {
    for m in 0..COUNT {
        let r = !from_bits(m);
        assert_eq!(r.x, !bit(m, 0));
        assert_eq!(r.y, !bit(m, 1));
        assert_eq!(r.bitmask(), FULL - m);
        assert_eq!(!r, from_bits(m));
    }
}

#[test]
fn test_mask_fmt() {
    // Deviation: the derived `Debug`, not glam's `BVec2(0xffffffff, 0x0, ..)`; no `Display`.
    let a = BVec2Trait::new(true, false);
    assert_eq!(format!("{:?}", a), "BVec2 { x: true, y: false }");
}

#[test]
fn test_mask_eq() {
    let a = BVec2Trait::new(true, false);
    let b = BVec2Trait::new(true, false);
    let c = BVec2Trait::new(false, true);
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
    let a = BVec2Trait::new(true, false);
    assert_eq!(a.test(0), true);
    assert_eq!(a.test(1), false);
    let b = BVec2Trait::new(false, true);
    assert_eq!(b.test(0), false);
    assert_eq!(b.test(1), true);
}

#[test]
fn test_mask_test_exhaustive() {
    for m in 0..COUNT {
        for i in 0..2_u32 {
            assert_eq!(from_bits(m).test(i), bit(m, i));
        }
    }
}

// panics: BVec2::test
#[test]
#[should_panic(expected: 'BVec2: index out of bounds')]
fn test_mask_test_out_of_bounds() {
    BVec2Trait::new(true, false).test(2);
}

// panics: BVec2::test
#[test]
#[should_panic(expected: 'BVec2: index out of bounds')]
fn test_mask_test_out_of_bounds_max() {
    BVec2Trait::new(true, false).test(0xffffffff);
}

#[test]
fn test_mask_set() {
    let mut a = BVec2Trait::new(false, true);
    a.set(0, true);
    assert_eq!(a.test(0), true);
    a.set(1, false);
    assert_eq!(a.test(1), false);
    assert_eq!(a, BVec2Trait::new(true, false));
    let mut b = BVec2Trait::new(true, false);
    b.set(0, false);
    assert_eq!(b.test(0), false);
    b.set(1, true);
    assert_eq!(b.test(1), true);
    assert_eq!(b, BVec2Trait::new(false, true));
}

#[test]
fn test_mask_set_exhaustive() {
    for m in 0..COUNT {
        for i in 0..2_u32 {
            let mut on = from_bits(m);
            on.set(i, true);
            let mut off = from_bits(m);
            off.set(i, false);
            for k in 0..2_u32 {
                assert_eq!(on.test(k), k == i || bit(m, k));
                assert_eq!(off.test(k), k != i && bit(m, k));
            }
        }
    }
}

// panics: BVec2::set
#[test]
#[should_panic(expected: 'BVec2: index out of bounds')]
fn test_mask_set_out_of_bounds() {
    let mut a = BVec2Trait::FALSE;
    a.set(2, true);
}

// panics: BVec2::set
#[test]
#[should_panic(expected: 'BVec2: index out of bounds')]
fn test_mask_set_out_of_bounds_max() {
    let mut a = BVec2Trait::FALSE;
    a.set(0xffffffff, true);
}

#[test]
fn test_mask_hash() {
    let a = BVec2Trait::new(true, false);
    let b = BVec2Trait::new(true, false);
    let c = BVec2Trait::new(false, true);
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
        let expected: Array<felt252> = array![v.x.into(), v.y.into()];
        assert_eq!(out, expected);
        let mut span = out.span();
        assert_eq!(Serde::<BVec2>::deserialize(ref span), Option::Some(v));
        assert!(span.is_empty());
    }
}

#[test]
fn test_mask_serde_too_short() {
    let mut short = array![1].span();
    assert!(Serde::<BVec2>::deserialize(ref short).is_none());
}
