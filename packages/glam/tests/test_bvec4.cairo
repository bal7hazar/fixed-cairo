//! Tests of `glam::bvec4`: the glam-rs `impl_bvec4_tests!` cases, plus exhaustive checks over
//! the 16 masks (and the 256 pairs of masks for the binary operators).

use core::hash::{HashStateExTrait, HashStateTrait};
use core::poseidon::PoseidonTrait;
use glam::bvec4::{BVec4, BVec4Trait, bvec4};

const COUNT: u32 = 16;
const FULL: u32 = 15;

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
fn from_bits(m: u32) -> BVec4 {
    BVec4 { x: bit(m, 0), y: bit(m, 1), z: bit(m, 2), w: bit(m, 3) }
}

fn hash(v: BVec4) -> felt252 {
    PoseidonTrait::new().update_with(v).finalize()
}

#[test]
fn test_mask_new() {
    assert_eq!(BVec4Trait::new(false, false, false, false), bvec4(false, false, false, false));
    assert_eq!(BVec4Trait::new(false, false, true, true), bvec4(false, false, true, true));
    assert_eq!(BVec4Trait::new(true, true, false, false), bvec4(true, true, false, false));
    assert_eq!(BVec4Trait::new(false, true, false, true), bvec4(false, true, false, true));
    assert_eq!(BVec4Trait::new(true, false, true, false), bvec4(true, false, true, false));
    assert_eq!(BVec4Trait::new(true, true, true, true), bvec4(true, true, true, true));
    let v = BVec4Trait::new(true, false, true, false);
    assert_eq!(v.x, true);
    assert_eq!(v.y, false);
    assert_eq!(v.z, true);
    assert_eq!(v.w, false);
    assert_eq!(Default::<BVec4>::default(), BVec4Trait::FALSE);
}

#[test]
fn test_mask_consts() {
    assert_eq!(BVec4Trait::FALSE, BVec4Trait::new(false, false, false, false));
    assert_eq!(BVec4Trait::TRUE, BVec4Trait::new(true, true, true, true));
}

#[test]
fn test_mask_from_array_bool() {
    assert_eq!(
        BVec4Trait::new(false, false, false, false),
        BVec4Trait::from_array([false, false, false, false]),
    );
    assert_eq!(BVec4Trait::new(false, false, false, false), [false, false, false, false].into());
    assert_eq!(
        BVec4Trait::new(false, false, true, true),
        BVec4Trait::from_array([false, false, true, true]),
    );
    assert_eq!(BVec4Trait::new(false, false, true, true), [false, false, true, true].into());
    assert_eq!(
        BVec4Trait::new(true, true, false, false),
        BVec4Trait::from_array([true, true, false, false]),
    );
    assert_eq!(BVec4Trait::new(true, true, false, false), [true, true, false, false].into());
    assert_eq!(
        BVec4Trait::new(false, true, false, true),
        BVec4Trait::from_array([false, true, false, true]),
    );
    assert_eq!(BVec4Trait::new(false, true, false, true), [false, true, false, true].into());
    assert_eq!(
        BVec4Trait::new(true, false, true, false),
        BVec4Trait::from_array([true, false, true, false]),
    );
    assert_eq!(BVec4Trait::new(true, false, true, false), [true, false, true, false].into());
    assert_eq!(
        BVec4Trait::new(true, true, true, true), BVec4Trait::from_array([true, true, true, true]),
    );
    assert_eq!(BVec4Trait::new(true, true, true, true), [true, true, true, true].into());
}

#[test]
fn test_mask_into_array_u32() {
    let a: [u32; 4] = BVec4Trait::new(false, false, false, false).into();
    assert_eq!(a, [0, 0, 0, 0]);
    let a: [u32; 4] = BVec4Trait::new(false, false, true, true).into();
    assert_eq!(a, [0, 0, 0xffffffff, 0xffffffff]);
    let a: [u32; 4] = BVec4Trait::new(true, true, false, false).into();
    assert_eq!(a, [0xffffffff, 0xffffffff, 0, 0]);
    let a: [u32; 4] = BVec4Trait::new(false, true, false, true).into();
    assert_eq!(a, [0, 0xffffffff, 0, 0xffffffff]);
    let a: [u32; 4] = BVec4Trait::new(true, false, true, false).into();
    assert_eq!(a, [0xffffffff, 0, 0xffffffff, 0]);
    let a: [u32; 4] = BVec4Trait::new(true, true, true, true).into();
    assert_eq!(a, [0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff]);
}

#[test]
fn test_mask_into_array_bool() {
    let a: [bool; 4] = BVec4Trait::new(false, false, false, false).into();
    assert_eq!(a, [false, false, false, false]);
    let a: [bool; 4] = BVec4Trait::new(false, false, true, true).into();
    assert_eq!(a, [false, false, true, true]);
    let a: [bool; 4] = BVec4Trait::new(true, true, false, false).into();
    assert_eq!(a, [true, true, false, false]);
    let a: [bool; 4] = BVec4Trait::new(false, true, false, true).into();
    assert_eq!(a, [false, true, false, true]);
    let a: [bool; 4] = BVec4Trait::new(true, false, true, false).into();
    assert_eq!(a, [true, false, true, false]);
    let a: [bool; 4] = BVec4Trait::new(true, true, true, true).into();
    assert_eq!(a, [true, true, true, true]);
}

#[test]
fn test_mask_arrays_exhaustive() {
    for m in 0..COUNT {
        let v = from_bits(m);
        let bools: [bool; 4] = v.into();
        assert_eq!(bools, [v.x, v.y, v.z, v.w]);
        assert_eq!(BVec4Trait::from_array(bools), v);
        let back: BVec4 = bools.into();
        assert_eq!(back, v);
        let [x, y, z, w]: [u32; 4] = v.into();
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
        assert_eq!(w, if v.w {
            0xffffffff
        } else {
            0
        });
    }
}

#[test]
fn test_mask_splat() {
    assert_eq!(BVec4Trait::splat(false), BVec4Trait::new(false, false, false, false));
    assert_eq!(BVec4Trait::splat(true), BVec4Trait::new(true, true, true, true));
}

#[test]
fn test_mask_bitmask() {
    assert_eq!(BVec4Trait::new(false, false, false, false).bitmask(), 0b0000);
    assert_eq!(BVec4Trait::new(false, false, true, true).bitmask(), 0b1100);
    assert_eq!(BVec4Trait::new(true, true, false, false).bitmask(), 0b0011);
    assert_eq!(BVec4Trait::new(false, true, false, true).bitmask(), 0b1010);
    assert_eq!(BVec4Trait::new(true, false, true, false).bitmask(), 0b0101);
    assert_eq!(BVec4Trait::new(true, true, true, true).bitmask(), 0b1111);
}

#[test]
fn test_mask_bitmask_exhaustive() {
    for m in 0..COUNT {
        assert_eq!(from_bits(m).bitmask(), m);
    }
}

#[test]
fn test_mask_any() {
    assert_eq!(BVec4Trait::new(false, false, false, false).any(), false);
    assert_eq!(BVec4Trait::new(true, false, false, false).any(), true);
    assert_eq!(BVec4Trait::new(false, true, false, false).any(), true);
    assert_eq!(BVec4Trait::new(false, false, true, false).any(), true);
    assert_eq!(BVec4Trait::new(false, false, false, true).any(), true);
}

#[test]
fn test_mask_all() {
    assert_eq!(BVec4Trait::new(true, true, true, true).all(), true);
    assert_eq!(BVec4Trait::new(false, true, true, true).all(), false);
    assert_eq!(BVec4Trait::new(true, false, true, true).all(), false);
    assert_eq!(BVec4Trait::new(true, true, false, true).all(), false);
    assert_eq!(BVec4Trait::new(true, true, true, false).all(), false);
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
        (BVec4Trait::new(false, false, false, false) & BVec4Trait::new(false, false, false, false))
            .bitmask(),
        0b0000,
    );
    assert_eq!(
        (BVec4Trait::new(true, true, true, true) & BVec4Trait::new(true, true, true, true))
            .bitmask(),
        0b1111,
    );
    assert_eq!(
        (BVec4Trait::new(true, false, true, false) & BVec4Trait::new(false, true, false, true))
            .bitmask(),
        0b0000,
    );
    assert_eq!(
        (BVec4Trait::new(true, false, true, false) & BVec4Trait::new(true, true, true, true))
            .bitmask(),
        0b0101,
    );
    let mut mask = BVec4Trait::new(true, true, false, false);
    mask = mask & BVec4Trait::new(true, false, true, false);
    assert_eq!(mask.bitmask(), 0b0001);
}

#[test]
fn test_mask_and_exhaustive() {
    for a in 0..COUNT {
        for b in 0..COUNT {
            let r = from_bits(a) & from_bits(b);
            assert_eq!(r.x, bit(a, 0) && bit(b, 0));
            assert_eq!(r.y, bit(a, 1) && bit(b, 1));
            assert_eq!(r.z, bit(a, 2) && bit(b, 2));
            assert_eq!(r.w, bit(a, 3) && bit(b, 3));
            assert_eq!(r.bitmask(), a & b);
        }
    }
}

#[test]
fn test_mask_or() {
    assert_eq!(
        (BVec4Trait::new(false, false, false, false) | BVec4Trait::new(false, false, false, false))
            .bitmask(),
        0b0000,
    );
    assert_eq!(
        (BVec4Trait::new(true, true, true, true) | BVec4Trait::new(true, true, true, true))
            .bitmask(),
        0b1111,
    );
    assert_eq!(
        (BVec4Trait::new(true, false, true, false) | BVec4Trait::new(false, true, false, true))
            .bitmask(),
        0b1111,
    );
    assert_eq!(
        (BVec4Trait::new(true, false, true, false) | BVec4Trait::new(true, false, true, false))
            .bitmask(),
        0b0101,
    );
    let mut mask = BVec4Trait::new(true, true, false, false);
    mask = mask | BVec4Trait::new(true, false, true, false);
    assert_eq!(mask.bitmask(), 0b0111);
}

#[test]
fn test_mask_or_exhaustive() {
    for a in 0..COUNT {
        for b in 0..COUNT {
            let r = from_bits(a) | from_bits(b);
            assert_eq!(r.x, bit(a, 0) || bit(b, 0));
            assert_eq!(r.y, bit(a, 1) || bit(b, 1));
            assert_eq!(r.z, bit(a, 2) || bit(b, 2));
            assert_eq!(r.w, bit(a, 3) || bit(b, 3));
            assert_eq!(r.bitmask(), a | b);
        }
    }
}

#[test]
fn test_mask_xor() {
    assert_eq!(
        (BVec4Trait::new(false, false, false, false) ^ BVec4Trait::new(false, false, false, false))
            .bitmask(),
        0b0000,
    );
    assert_eq!(
        (BVec4Trait::new(true, true, true, true) ^ BVec4Trait::new(true, true, true, true))
            .bitmask(),
        0b0000,
    );
    assert_eq!(
        (BVec4Trait::new(true, false, true, false) ^ BVec4Trait::new(false, true, false, true))
            .bitmask(),
        0b1111,
    );
    assert_eq!(
        (BVec4Trait::new(true, false, true, false) ^ BVec4Trait::new(true, false, true, false))
            .bitmask(),
        0b0000,
    );
    let mut mask = BVec4Trait::new(true, true, false, false);
    mask = mask ^ BVec4Trait::new(true, false, true, false);
    assert_eq!(mask.bitmask(), 0b0110);
}

#[test]
fn test_mask_xor_exhaustive() {
    for a in 0..COUNT {
        for b in 0..COUNT {
            let r = from_bits(a) ^ from_bits(b);
            assert_eq!(r.x, bit(a, 0) != bit(b, 0));
            assert_eq!(r.y, bit(a, 1) != bit(b, 1));
            assert_eq!(r.z, bit(a, 2) != bit(b, 2));
            assert_eq!(r.w, bit(a, 3) != bit(b, 3));
            assert_eq!(r.bitmask(), a ^ b);
        }
    }
}

#[test]
fn test_mask_not() {
    assert_eq!((!BVec4Trait::new(false, false, false, false)).bitmask(), 0b1111);
    assert_eq!((!BVec4Trait::new(true, true, true, true)).bitmask(), 0b0000);
    assert_eq!((!BVec4Trait::new(true, false, true, false)).bitmask(), 0b1010);
    assert_eq!((!BVec4Trait::new(false, true, false, true)).bitmask(), 0b0101);
}

#[test]
fn test_mask_not_exhaustive() {
    for m in 0..COUNT {
        let r = !from_bits(m);
        assert_eq!(r.x, !bit(m, 0));
        assert_eq!(r.y, !bit(m, 1));
        assert_eq!(r.z, !bit(m, 2));
        assert_eq!(r.w, !bit(m, 3));
        assert_eq!(r.bitmask(), FULL - m);
        assert_eq!(!r, from_bits(m));
    }
}

#[test]
fn test_mask_fmt() {
    // Deviation: the derived `Debug`, not glam's `BVec4(0xffffffff, 0x0, ..)`; no `Display`.
    let a = BVec4Trait::new(true, false, false, false);
    assert_eq!(format!("{:?}", a), "BVec4 { x: true, y: false, z: false, w: false }");
}

#[test]
fn test_mask_eq() {
    let a = BVec4Trait::new(true, false, true, false);
    let b = BVec4Trait::new(true, false, true, false);
    let c = BVec4Trait::new(false, true, true, false);
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
    let a = BVec4Trait::new(true, false, true, false);
    assert_eq!(a.test(0), true);
    assert_eq!(a.test(1), false);
    assert_eq!(a.test(2), true);
    assert_eq!(a.test(3), false);
    let b = BVec4Trait::new(false, true, false, true);
    assert_eq!(b.test(0), false);
    assert_eq!(b.test(1), true);
    assert_eq!(b.test(2), false);
    assert_eq!(b.test(3), true);
}

#[test]
fn test_mask_test_exhaustive() {
    for m in 0..COUNT {
        for i in 0..4_u32 {
            assert_eq!(from_bits(m).test(i), bit(m, i));
        }
    }
}

// panics: BVec4::test
#[test]
#[should_panic(expected: 'BVec4: index out of bounds')]
fn test_mask_test_out_of_bounds() {
    BVec4Trait::new(true, false, true, false).test(4);
}

// panics: BVec4::test
#[test]
#[should_panic(expected: 'BVec4: index out of bounds')]
fn test_mask_test_out_of_bounds_max() {
    BVec4Trait::new(true, false, true, false).test(0xffffffff);
}

#[test]
fn test_mask_set() {
    let mut a = BVec4Trait::new(false, true, false, true);
    a.set(0, true);
    assert_eq!(a.test(0), true);
    a.set(1, false);
    assert_eq!(a.test(1), false);
    a.set(2, true);
    assert_eq!(a.test(2), true);
    a.set(3, false);
    assert_eq!(a.test(3), false);
    assert_eq!(a, BVec4Trait::new(true, false, true, false));
    let mut b = BVec4Trait::new(true, false, true, false);
    b.set(0, false);
    assert_eq!(b.test(0), false);
    b.set(1, true);
    assert_eq!(b.test(1), true);
    b.set(2, false);
    assert_eq!(b.test(2), false);
    b.set(3, true);
    assert_eq!(b.test(3), true);
    assert_eq!(b, BVec4Trait::new(false, true, false, true));
}

#[test]
fn test_mask_set_exhaustive() {
    for m in 0..COUNT {
        for i in 0..4_u32 {
            let mut on = from_bits(m);
            on.set(i, true);
            let mut off = from_bits(m);
            off.set(i, false);
            for k in 0..4_u32 {
                assert_eq!(on.test(k), k == i || bit(m, k));
                assert_eq!(off.test(k), k != i && bit(m, k));
            }
        }
    }
}

// panics: BVec4::set
#[test]
#[should_panic(expected: 'BVec4: index out of bounds')]
fn test_mask_set_out_of_bounds() {
    let mut a = BVec4Trait::FALSE;
    a.set(4, true);
}

// panics: BVec4::set
#[test]
#[should_panic(expected: 'BVec4: index out of bounds')]
fn test_mask_set_out_of_bounds_max() {
    let mut a = BVec4Trait::FALSE;
    a.set(0xffffffff, true);
}

#[test]
fn test_mask_hash() {
    let a = BVec4Trait::new(true, false, true, false);
    let b = BVec4Trait::new(true, false, true, false);
    let c = BVec4Trait::new(false, true, true, false);
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
        let expected: Array<felt252> = array![v.x.into(), v.y.into(), v.z.into(), v.w.into()];
        assert_eq!(out, expected);
        let mut span = out.span();
        assert_eq!(Serde::<BVec4>::deserialize(ref span), Option::Some(v));
        assert!(span.is_empty());
    }
}

#[test]
fn test_mask_serde_too_short() {
    let mut short = array![1, 1, 1].span();
    assert!(Serde::<BVec4>::deserialize(ref short).is_none());
}
