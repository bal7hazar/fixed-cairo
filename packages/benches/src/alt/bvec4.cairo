//! Alternative implementations benchmarked against `bvec4`.
//!
//! Every function here is a candidate formulation of a `glam::bvec4::BVec4` method, including a
//! copy of the winner so that the comparison stays reproducible. The cheapest one (l2_gas first,
//! then steps) lives in the library; `gas/bvec4.snap` holds the numbers (`alt_*` rows).

use glam::bvec4::BVec4;

const PANIC: felt252 = 'BVec4: index out of bounds';

// ---------------------------------------------------------------------------------------------
// bitmask
// ---------------------------------------------------------------------------------------------

/// `bitmask` as a decision tree of nested `if`s returning constants.
#[inline(always)]
pub fn bitmask_if_tree(v: BVec4) -> u32 {
    if v.w {
        if v.z {
            if v.y {
                if v.x {
                    15
                } else {
                    14
                }
            } else if v.x {
                13
            } else {
                12
            }
        } else if v.y {
            if v.x {
                11
            } else {
                10
            }
        } else if v.x {
            9
        } else {
            8
        }
    } else if v.z {
        if v.y {
            if v.x {
                7
            } else {
                6
            }
        } else if v.x {
            5
        } else {
            4
        }
    } else if v.y {
        if v.x {
            3
        } else {
            2
        }
    } else if v.x {
        1
    } else {
        0
    }
}

/// `bitmask` as the same decision tree with `x` at the root instead of the last element.
#[inline(always)]
pub fn bitmask_if_tree_lsb(v: BVec4) -> u32 {
    if v.x {
        if v.y {
            if v.z {
                if v.w {
                    15
                } else {
                    7
                }
            } else if v.w {
                11
            } else {
                3
            }
        } else if v.z {
            if v.w {
                13
            } else {
                5
            }
        } else if v.w {
            9
        } else {
            1
        }
    } else if v.y {
        if v.z {
            if v.w {
                14
            } else {
                6
            }
        } else if v.w {
            10
        } else {
            2
        }
    } else if v.z {
        if v.w {
            12
        } else {
            4
        }
    } else if v.w {
        8
    } else {
        0
    }
}

/// `bitmask` as a `felt252` weighted sum (`bool -> felt252` is free), converted back to `u32`
/// (the library version).
#[inline(always)]
pub fn bitmask_felt(v: BVec4) -> u32 {
    let f: felt252 = v.x.into() + v.y.into() * 2 + v.z.into() * 4 + v.w.into() * 8;
    f.try_into().unwrap()
}

/// `bitmask` as a sum of `u32` terms selected by one `if` per element.
#[inline(always)]
pub fn bitmask_if_add(v: BVec4) -> u32 {
    let x: u32 = if v.x {
        1
    } else {
        0
    };
    let y: u32 = if v.y {
        2
    } else {
        0
    };
    let z: u32 = if v.z {
        4
    } else {
        0
    };
    let w: u32 = if v.w {
        8
    } else {
        0
    };
    x + y + z + w
}

/// `bitmask` as a sum of `felt252` terms selected by one `if` per element, converted to `u32`.
#[inline(always)]
pub fn bitmask_if_add_felt(v: BVec4) -> u32 {
    let x: felt252 = if v.x {
        1
    } else {
        0
    };
    let y: felt252 = if v.y {
        2
    } else {
        0
    };
    let z: felt252 = if v.z {
        4
    } else {
        0
    };
    let w: felt252 = if v.w {
        8
    } else {
        0
    };
    (x + y + z + w).try_into().unwrap()
}

/// `bitmask` as a `match` on the tuple of elements.
#[inline(always)]
pub fn bitmask_match(v: BVec4) -> u32 {
    match (v.x, v.y, v.z, v.w) {
        (false, false, false, false) => 0,
        (true, false, false, false) => 1,
        (false, true, false, false) => 2,
        (true, true, false, false) => 3,
        (false, false, true, false) => 4,
        (true, false, true, false) => 5,
        (false, true, true, false) => 6,
        (true, true, true, false) => 7,
        (false, false, false, true) => 8,
        (true, false, false, true) => 9,
        (false, true, false, true) => 10,
        (true, true, false, true) => 11,
        (false, false, true, true) => 12,
        (true, false, true, true) => 13,
        (false, true, true, true) => 14,
        (true, true, true, true) => 15,
    }
}

// ---------------------------------------------------------------------------------------------
// any / all
// ---------------------------------------------------------------------------------------------

/// `any` with the short-circuit `||` (the library version).
#[inline(always)]
pub fn any_short_circuit(v: BVec4) -> bool {
    v.x || v.y || v.z || v.w
}

/// `any` with the eager `bool | bool` (the `bool_or_impl` libfunc, not the bitwise builtin).
#[inline(always)]
pub fn any_eager(v: BVec4) -> bool {
    v.x | v.y | v.z | v.w
}

/// `any` mixing one short-circuit `||` with eager `|`.
#[inline(always)]
pub fn any_hybrid(v: BVec4) -> bool {
    (v.x | v.y) || (v.z | v.w)
}

/// `any` as a `felt252` sum compared to zero.
#[inline(always)]
pub fn any_felt(v: BVec4) -> bool {
    v.x.into() + v.y.into() + v.z.into() + v.w.into() != 0_felt252
}

/// `any` as a `match` of the `felt252` sum against zero (a bare `felt252_is_zero`).
#[inline(always)]
pub fn any_felt_match(v: BVec4) -> bool {
    match v.x.into() + v.y.into() + v.z.into() + v.w.into() {
        0 => false,
        _ => true,
    }
}

/// `any` as a structural comparison with `FALSE`.
#[inline(always)]
pub fn any_ne_false(v: BVec4) -> bool {
    v != BVec4 { x: false, y: false, z: false, w: false }
}

/// `any` as an if-chain.
#[inline(always)]
pub fn any_if_chain(v: BVec4) -> bool {
    if v.x {
        true
    } else if v.y {
        true
    } else if v.z {
        true
    } else {
        v.w
    }
}

/// `all` with the short-circuit `&&`.
#[inline(always)]
pub fn all_short_circuit(v: BVec4) -> bool {
    v.x && v.y && v.z && v.w
}

/// `all` with the eager `bool & bool` (the `bool_and_impl` libfunc, not the bitwise builtin; the
/// library version).
#[inline(always)]
pub fn all_eager(v: BVec4) -> bool {
    v.x & v.y & v.z & v.w
}

/// `all` as a `felt252` sum compared to the dimension.
#[inline(always)]
pub fn all_felt_sum(v: BVec4) -> bool {
    v.x.into() + v.y.into() + v.z.into() + v.w.into() == 4_felt252
}

/// `all` as a `felt252` product compared to one.
#[inline(always)]
pub fn all_felt_product(v: BVec4) -> bool {
    v.x.into() * v.y.into() * v.z.into() * v.w.into() == 1_felt252
}

/// `all` as a `match` of the `felt252` sum minus the dimension against zero.
#[inline(always)]
pub fn all_felt_match(v: BVec4) -> bool {
    match v.x.into() + v.y.into() + v.z.into() + v.w.into() - 4 {
        0 => true,
        _ => false,
    }
}

/// `all` as a structural comparison with `TRUE`.
#[inline(always)]
pub fn all_eq_true(v: BVec4) -> bool {
    v == BVec4 { x: true, y: true, z: true, w: true }
}

/// `all` as an if-chain.
#[inline(always)]
pub fn all_if_chain(v: BVec4) -> bool {
    if v.x {
        if v.y {
            if v.z {
                v.w
            } else {
                false
            }
        } else {
            false
        }
    } else {
        false
    }
}

// ---------------------------------------------------------------------------------------------
// test
// ---------------------------------------------------------------------------------------------

/// `test` as a `match` on the index (the library version).
#[inline(always)]
pub fn test_match(v: BVec4, index: usize) -> bool {
    match index {
        0 => v.x,
        1 => v.y,
        2 => v.z,
        3 => v.w,
        _ => core::panic_with_felt252(PANIC),
    }
}

/// `test` as an if-chain of index comparisons.
#[inline(always)]
pub fn test_if_chain(v: BVec4, index: usize) -> bool {
    if index == 0 {
        v.x
    } else if index == 1 {
        v.y
    } else if index == 2 {
        v.z
    } else if index == 3 {
        v.w
    } else {
        core::panic_with_felt252(PANIC)
    }
}

/// `test` through a runtime fixed-size array and a span lookup.
#[inline(always)]
pub fn test_span(v: BVec4, index: usize) -> bool {
    match [v.x, v.y, v.z, v.w].span().get(index) {
        Option::Some(b) => *b.unbox(),
        Option::None => core::panic_with_felt252(PANIC),
    }
}

/// `test` by extracting the bit `index` of the bitmask: `(bitmask / 2^index) % 2`.
#[inline(always)]
pub fn test_bitmask(v: BVec4, index: usize) -> bool {
    let pow: NonZero<u32> = match index {
        0 => 1,
        1 => 2,
        2 => 4,
        3 => 8,
        _ => core::panic_with_felt252(PANIC),
    };
    let (q, _) = DivRem::div_rem(bitmask_if_tree(v), pow);
    let (_, bit) = DivRem::div_rem(q, 2);
    bit == 1
}

/// `test` as a `match` on the index, not inlined (one call boundary instead of code growth).
#[inline(never)]
pub fn test_match_noinline(v: BVec4, index: usize) -> bool {
    match index {
        0 => v.x,
        1 => v.y,
        2 => v.z,
        3 => v.w,
        _ => core::panic_with_felt252(PANIC),
    }
}

// ---------------------------------------------------------------------------------------------
// set
// ---------------------------------------------------------------------------------------------

/// `set` as a `match` on the index assigning one field (the library version).
#[inline(always)]
pub fn set_match(ref v: BVec4, index: usize, value: bool) {
    match index {
        0 => v.x = value,
        1 => v.y = value,
        2 => v.z = value,
        3 => v.w = value,
        _ => core::panic_with_felt252(PANIC),
    }
}

/// `set` as a `match` on the index rebuilding the whole struct.
#[inline(always)]
pub fn set_match_rebuild(ref v: BVec4, index: usize, value: bool) {
    v = match index {
        0 => BVec4 { x: value, y: v.y, z: v.z, w: v.w },
        1 => BVec4 { x: v.x, y: value, z: v.z, w: v.w },
        2 => BVec4 { x: v.x, y: v.y, z: value, w: v.w },
        3 => BVec4 { x: v.x, y: v.y, z: v.z, w: value },
        _ => core::panic_with_felt252(PANIC),
    };
}

/// `set` as an if-chain of index comparisons.
#[inline(always)]
pub fn set_if_chain(ref v: BVec4, index: usize, value: bool) {
    if index == 0 {
        v.x = value;
    } else if index == 1 {
        v.y = value;
    } else if index == 2 {
        v.z = value;
    } else if index == 3 {
        v.w = value;
    } else {
        core::panic_with_felt252(PANIC);
    }
}

/// `set` as a `match` on the index, not inlined.
#[inline(never)]
pub fn set_match_noinline(ref v: BVec4, index: usize, value: bool) {
    match index {
        0 => v.x = value,
        1 => v.y = value,
        2 => v.z = value,
        3 => v.w = value,
        _ => core::panic_with_felt252(PANIC),
    }
}

// ---------------------------------------------------------------------------------------------
// operators
// ---------------------------------------------------------------------------------------------

/// `BitAnd` with the short-circuit `&&` instead of the eager `&`.
#[inline(always)]
pub fn bitand_short_circuit(a: BVec4, b: BVec4) -> BVec4 {
    BVec4 { x: a.x && b.x, y: a.y && b.y, z: a.z && b.z, w: a.w && b.w }
}

/// `BitOr` with the short-circuit `||` instead of the eager `|`.
#[inline(always)]
pub fn bitor_short_circuit(a: BVec4, b: BVec4) -> BVec4 {
    BVec4 { x: a.x || b.x, y: a.y || b.y, z: a.z || b.z, w: a.w || b.w }
}

/// `BitOr` as `a ^ b ^ (a & b)`.
#[inline(always)]
pub fn bitor_xor_and(a: BVec4, b: BVec4) -> BVec4 {
    BVec4 {
        x: a.x ^ b.x ^ (a.x & b.x),
        y: a.y ^ b.y ^ (a.y & b.y),
        z: a.z ^ b.z ^ (a.z & b.z),
        w: a.w ^ b.w ^ (a.w & b.w),
    }
}

/// `BitXor` with `!=` instead of `^`.
#[inline(always)]
pub fn bitxor_ne(a: BVec4, b: BVec4) -> BVec4 {
    BVec4 { x: a.x != b.x, y: a.y != b.y, z: a.z != b.z, w: a.w != b.w }
}

/// `Not` as `a ^ true`.
#[inline(always)]
pub fn not_xor_true(a: BVec4) -> BVec4 {
    BVec4 { x: a.x ^ true, y: a.y ^ true, z: a.z ^ true, w: a.w ^ true }
}

/// `Not` as one `if` per element (`a == false` was measured slower still, 1 720 gas on `BVec3`,
/// and is rejected by the linter, hence not kept).
#[inline(always)]
pub fn not_if(a: BVec4) -> BVec4 {
    BVec4 { x: flip(a.x), y: flip(a.y), z: flip(a.z), w: flip(a.w) }
}

#[inline(always)]
fn flip(v: bool) -> bool {
    if v {
        false
    } else {
        true
    }
}
