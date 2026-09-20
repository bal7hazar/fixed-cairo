//! Alternative implementations benchmarked against `bvec3`.
//!
//! Every function here is a candidate formulation of a `glam::bvec3::BVec3` method, including a
//! copy of the winner so that the comparison stays reproducible. The cheapest one (l2_gas first,
//! then steps) lives in the library; `gas/bvec3.snap` holds the numbers (`alt_*` rows).

use glam::bvec3::BVec3;

const PANIC: felt252 = 'BVec3: index out of bounds';

// ---------------------------------------------------------------------------------------------
// bitmask
// ---------------------------------------------------------------------------------------------

/// `bitmask` as a decision tree of nested `if`s returning constants (the library version).
#[inline(always)]
pub fn bitmask_if_tree(v: BVec3) -> u32 {
    if v.z {
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
pub fn bitmask_if_tree_lsb(v: BVec3) -> u32 {
    if v.x {
        if v.y {
            if v.z {
                7
            } else {
                3
            }
        } else if v.z {
            5
        } else {
            1
        }
    } else if v.y {
        if v.z {
            6
        } else {
            2
        }
    } else if v.z {
        4
    } else {
        0
    }
}

/// `bitmask` as a `felt252` weighted sum (`bool -> felt252` is free), converted back to `u32`.
#[inline(always)]
pub fn bitmask_felt(v: BVec3) -> u32 {
    let f: felt252 = v.x.into() + v.y.into() * 2 + v.z.into() * 4;
    f.try_into().unwrap()
}

/// `bitmask` as a sum of `u32` terms selected by one `if` per element.
#[inline(always)]
pub fn bitmask_if_add(v: BVec3) -> u32 {
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
    x + y + z
}

/// `bitmask` as a sum of `felt252` terms selected by one `if` per element, converted to `u32`.
#[inline(always)]
pub fn bitmask_if_add_felt(v: BVec3) -> u32 {
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
    (x + y + z).try_into().unwrap()
}

/// `bitmask` as a `match` on the tuple of elements.
#[inline(always)]
pub fn bitmask_match(v: BVec3) -> u32 {
    match (v.x, v.y, v.z) {
        (false, false, false) => 0,
        (true, false, false) => 1,
        (false, true, false) => 2,
        (true, true, false) => 3,
        (false, false, true) => 4,
        (true, false, true) => 5,
        (false, true, true) => 6,
        (true, true, true) => 7,
    }
}

// ---------------------------------------------------------------------------------------------
// any / all
// ---------------------------------------------------------------------------------------------

/// `any` with the short-circuit `||` (the library version).
#[inline(always)]
pub fn any_short_circuit(v: BVec3) -> bool {
    v.x || v.y || v.z
}

/// `any` with the eager `bool | bool` (the `bool_or_impl` libfunc, not the bitwise builtin).
#[inline(always)]
pub fn any_eager(v: BVec3) -> bool {
    v.x | v.y | v.z
}

/// `any` mixing one short-circuit `||` with eager `|`.
#[inline(always)]
pub fn any_hybrid(v: BVec3) -> bool {
    v.x || (v.y | v.z)
}

/// `any` as a `felt252` sum compared to zero.
#[inline(always)]
pub fn any_felt(v: BVec3) -> bool {
    v.x.into() + v.y.into() + v.z.into() != 0_felt252
}

/// `any` as a `match` of the `felt252` sum against zero (a bare `felt252_is_zero`).
#[inline(always)]
pub fn any_felt_match(v: BVec3) -> bool {
    match v.x.into() + v.y.into() + v.z.into() {
        0 => false,
        _ => true,
    }
}

/// `any` as a structural comparison with `FALSE`.
#[inline(always)]
pub fn any_ne_false(v: BVec3) -> bool {
    v != BVec3 { x: false, y: false, z: false }
}

/// `any` as an if-chain.
#[inline(always)]
pub fn any_if_chain(v: BVec3) -> bool {
    if v.x {
        true
    } else if v.y {
        true
    } else {
        v.z
    }
}

/// `all` with the short-circuit `&&`.
#[inline(always)]
pub fn all_short_circuit(v: BVec3) -> bool {
    v.x && v.y && v.z
}

/// `all` with the eager `bool & bool` (the `bool_and_impl` libfunc, not the bitwise builtin; the
/// library version).
#[inline(always)]
pub fn all_eager(v: BVec3) -> bool {
    v.x & v.y & v.z
}

/// `all` as a `felt252` sum compared to the dimension.
#[inline(always)]
pub fn all_felt_sum(v: BVec3) -> bool {
    v.x.into() + v.y.into() + v.z.into() == 3_felt252
}

/// `all` as a `felt252` product compared to one.
#[inline(always)]
pub fn all_felt_product(v: BVec3) -> bool {
    v.x.into() * v.y.into() * v.z.into() == 1_felt252
}

/// `all` as a `match` of the `felt252` sum minus the dimension against zero.
#[inline(always)]
pub fn all_felt_match(v: BVec3) -> bool {
    match v.x.into() + v.y.into() + v.z.into() - 3 {
        0 => true,
        _ => false,
    }
}

/// `all` as a structural comparison with `TRUE`.
#[inline(always)]
pub fn all_eq_true(v: BVec3) -> bool {
    v == BVec3 { x: true, y: true, z: true }
}

/// `all` as an if-chain.
#[inline(always)]
pub fn all_if_chain(v: BVec3) -> bool {
    if v.x {
        if v.y {
            v.z
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
pub fn test_match(v: BVec3, index: usize) -> bool {
    match index {
        0 => v.x,
        1 => v.y,
        2 => v.z,
        _ => core::panic_with_felt252(PANIC),
    }
}

/// `test` as an if-chain of index comparisons.
#[inline(always)]
pub fn test_if_chain(v: BVec3, index: usize) -> bool {
    if index == 0 {
        v.x
    } else if index == 1 {
        v.y
    } else if index == 2 {
        v.z
    } else {
        core::panic_with_felt252(PANIC)
    }
}

/// `test` through a runtime fixed-size array and a span lookup.
#[inline(always)]
pub fn test_span(v: BVec3, index: usize) -> bool {
    match [v.x, v.y, v.z].span().get(index) {
        Option::Some(b) => *b.unbox(),
        Option::None => core::panic_with_felt252(PANIC),
    }
}

/// `test` by extracting the bit `index` of the bitmask: `(bitmask / 2^index) % 2`.
#[inline(always)]
pub fn test_bitmask(v: BVec3, index: usize) -> bool {
    let pow: NonZero<u32> = match index {
        0 => 1,
        1 => 2,
        2 => 4,
        _ => core::panic_with_felt252(PANIC),
    };
    let (q, _) = DivRem::div_rem(bitmask_if_tree(v), pow);
    let (_, bit) = DivRem::div_rem(q, 2);
    bit == 1
}

/// `test` as a `match` on the index, not inlined (one call boundary instead of code growth).
#[inline(never)]
pub fn test_match_noinline(v: BVec3, index: usize) -> bool {
    match index {
        0 => v.x,
        1 => v.y,
        2 => v.z,
        _ => core::panic_with_felt252(PANIC),
    }
}

// ---------------------------------------------------------------------------------------------
// set
// ---------------------------------------------------------------------------------------------

/// `set` as a `match` on the index assigning one field (the library version).
#[inline(always)]
pub fn set_match(ref v: BVec3, index: usize, value: bool) {
    match index {
        0 => v.x = value,
        1 => v.y = value,
        2 => v.z = value,
        _ => core::panic_with_felt252(PANIC),
    }
}

/// `set` as a `match` on the index rebuilding the whole struct.
#[inline(always)]
pub fn set_match_rebuild(ref v: BVec3, index: usize, value: bool) {
    v = match index {
        0 => BVec3 { x: value, y: v.y, z: v.z },
        1 => BVec3 { x: v.x, y: value, z: v.z },
        2 => BVec3 { x: v.x, y: v.y, z: value },
        _ => core::panic_with_felt252(PANIC),
    };
}

/// `set` as an if-chain of index comparisons.
#[inline(always)]
pub fn set_if_chain(ref v: BVec3, index: usize, value: bool) {
    if index == 0 {
        v.x = value;
    } else if index == 1 {
        v.y = value;
    } else if index == 2 {
        v.z = value;
    } else {
        core::panic_with_felt252(PANIC);
    }
}

/// `set` as a `match` on the index, not inlined.
#[inline(never)]
pub fn set_match_noinline(ref v: BVec3, index: usize, value: bool) {
    match index {
        0 => v.x = value,
        1 => v.y = value,
        2 => v.z = value,
        _ => core::panic_with_felt252(PANIC),
    }
}

// ---------------------------------------------------------------------------------------------
// operators
// ---------------------------------------------------------------------------------------------

/// `BitAnd` with the short-circuit `&&` instead of the eager `&`.
#[inline(always)]
pub fn bitand_short_circuit(a: BVec3, b: BVec3) -> BVec3 {
    BVec3 { x: a.x && b.x, y: a.y && b.y, z: a.z && b.z }
}

/// `BitOr` with the short-circuit `||` instead of the eager `|`.
#[inline(always)]
pub fn bitor_short_circuit(a: BVec3, b: BVec3) -> BVec3 {
    BVec3 { x: a.x || b.x, y: a.y || b.y, z: a.z || b.z }
}

/// `BitOr` as `a ^ b ^ (a & b)`.
#[inline(always)]
pub fn bitor_xor_and(a: BVec3, b: BVec3) -> BVec3 {
    BVec3 { x: a.x ^ b.x ^ (a.x & b.x), y: a.y ^ b.y ^ (a.y & b.y), z: a.z ^ b.z ^ (a.z & b.z) }
}

/// `BitXor` with `!=` instead of `^`.
#[inline(always)]
pub fn bitxor_ne(a: BVec3, b: BVec3) -> BVec3 {
    BVec3 { x: a.x != b.x, y: a.y != b.y, z: a.z != b.z }
}

/// `Not` as `a ^ true`.
#[inline(always)]
pub fn not_xor_true(a: BVec3) -> BVec3 {
    BVec3 { x: a.x ^ true, y: a.y ^ true, z: a.z ^ true }
}

/// `Not` as one `if` per element (`a == false` was measured slower still, 1 720 gas on `BVec3`,
/// and is rejected by the linter, hence not kept).
#[inline(always)]
pub fn not_if(a: BVec3) -> BVec3 {
    BVec3 { x: flip(a.x), y: flip(a.y), z: flip(a.z) }
}

#[inline(always)]
fn flip(v: bool) -> bool {
    if v {
        false
    } else {
        true
    }
}
