//! Hand-written helpers used by the generated primitive benchmarks (tests/prims.cairo).
#[feature("bounded-int-utils")]
use core::internal::bounded_int::{
    self, AddHelper, BoundedInt, DivRemHelper, MulHelper, SubHelper, UnitInt, downcast, upcast,
};
pub use crate::prims_tables::*;

// ---------------------------------------------------------------- shifts / pow2
pub fn shr_loop(mut a: u64, mut n: u32) -> u64 {
    while n != 0 {
        a = a / 2;
        n -= 1;
    }
    a
}

pub fn pow2_boxed(n: u32) -> u64 {
    // const span + `get` returning a Box, then unbox.
    *POW2_TABLE.span().get(n).unwrap().unbox()
}

// ---------------------------------------------------------------- loops
pub fn loop_while(n: u32) -> u32 {
    let mut i: u32 = 0;
    while i != n {
        i += 1;
    }
    i
}
pub fn loop_for(n: u32) -> u32 {
    let mut last = 0;
    for i in 0..n {
        last = i;
    }
    last
}
pub fn loop_felt(n: felt252) -> felt252 {
    let mut i: felt252 = 0;
    while i != n {
        i += 1;
    }
    i
}
pub fn loop_rec(n: u32, acc: u32) -> u32 {
    if n == 0 {
        return acc;
    }
    loop_rec(n - 1, acc + 1)
}
pub fn loop_acc(n: u32) -> u32 {
    let mut i: u32 = 0;
    let mut acc: u32 = 0;
    while i != n {
        acc += i;
        i += 1;
    }
    acc
}
pub fn loop_span(mut s: Span<u64>) -> u64 {
    let mut acc: u64 = 0;
    for x in s {
        acc = acc | *x;
    }
    acc
}
pub fn loop_add8(a: u32) -> u32 {
    let mut acc = a;
    let mut i: u32 = 0;
    while i != 8 {
        acc += a;
        i += 1;
    }
    acc
}

// ---------------------------------------------------------------- sign handling
/// cubit-style signed addition on (magnitude, sign) pairs.
pub fn magsign_add(am: u64, asg: bool, bm: u64, bsg: bool) -> (u64, bool) {
    if asg == bsg {
        return (am + bm, asg);
    }
    if am == bm {
        return (0, false);
    }
    if am > bm {
        (am - bm, asg)
    } else {
        (bm - am, bsg)
    }
}

// ---------------------------------------------------------------- inlining
pub fn small_default(a: u64, b: u64) -> u64 {
    a + b
}
#[inline(always)]
pub fn small_always(a: u64, b: u64) -> u64 {
    a + b
}
#[inline(never)]
pub fn small_never(a: u64, b: u64) -> u64 {
    a + b
}
pub fn medium_default(a: u64, b: u64) -> u64 {
    let c = a + b;
    let d = c * 3 + a;
    let e = d / 7 + b;
    if e > a {
        e - a + c
    } else {
        a - e + d
    }
}
#[inline(always)]
pub fn medium_always(a: u64, b: u64) -> u64 {
    let c = a + b;
    let d = c * 3 + a;
    let e = d / 7 + b;
    if e > a {
        e - a + c
    } else {
        a - e + d
    }
}
#[inline(never)]
pub fn medium_never(a: u64, b: u64) -> u64 {
    let c = a + b;
    let d = c * 3 + a;
    let e = d / 7 + b;
    if e > a {
        e - a + c
    } else {
        a - e + d
    }
}
#[inline(never)]
pub fn felt_never(a: felt252, b: felt252) -> felt252 {
    a * b + a
}
#[inline(always)]
pub fn felt_always(a: felt252, b: felt252) -> felt252 {
    a * b + a
}

#[derive(Copy, Drop)]
pub struct V3 {
    pub x: felt252,
    pub y: felt252,
    pub z: felt252,
}
#[inline(never)]
pub fn v3_sum_val(v: V3) -> felt252 {
    v.x + v.y + v.z
}
#[inline(never)]
pub fn v3_sum_snap(v: @V3) -> felt252 {
    *v.x + *v.y + *v.z
}

// ---------------------------------------------------------------- bounded int
const TWO_POW_32: felt252 = 0x100000000;

type U64Prod = BoundedInt<0, 0xfffffffffffffffe0000000000000001>;
impl MulU64 of MulHelper<u64, u64> {
    type Result = U64Prod;
}
impl DivRemU64Prod of DivRemHelper<U64Prod, UnitInt<0x100000000>> {
    type DivT = BoundedInt<0, 0xfffffffffffffffe00000000>;
    type RemT = BoundedInt<0, 0xffffffff>;
}
/// (a * b) >> 32 on u64 using bounded ints: no overflow check on the product, a single
/// range-checked downcast at the end.
#[inline(always)]
pub fn bi_mul_shift_u64(a: u64, b: u64) -> u64 {
    let p = bounded_int::mul(a, b);
    let (q, _r) = bounded_int::div_rem::<_, UnitInt<0x100000000>>(p, 0x100000000);
    downcast(q).unwrap()
}

// i64 * i64 -> [-(2^126 - 2^63), 2^126]
type I64Prod = BoundedInt<-0x3fffffffffffffff8000000000000000, 0x40000000000000000000000000000000>;
impl MulI64 of MulHelper<i64, i64> {
    type Result = I64Prod;
}
// + 2^126 -> [2^63, 2^127]
type I64ProdOff = BoundedInt<0x8000000000000000, 0x80000000000000000000000000000000>;
impl AddOffI64Prod of AddHelper<I64Prod, UnitInt<0x40000000000000000000000000000000>> {
    type Result = I64ProdOff;
}
// / 2^32 -> [2^31, 2^95]
type I64QuotOff = BoundedInt<0x80000000, 0x800000000000000000000000>;
impl DivRemI64ProdOff of DivRemHelper<I64ProdOff, UnitInt<0x100000000>> {
    type DivT = I64QuotOff;
    type RemT = BoundedInt<0, 0xffffffff>;
}
// - 2^94 -> [2^31 - 2^94, 2^94]
impl SubOffI64Quot of SubHelper<I64QuotOff, UnitInt<0x400000000000000000000000>> {
    type Result = BoundedInt<-0x3fffffffffffffff80000000, 0x400000000000000000000000>;
}
/// floor((a * b) / 2^32) on i64 (arithmetic shift) using bounded ints.
#[inline(always)]
pub fn bi_mul_shift_i64(a: i64, b: i64) -> i64 {
    let p = bounded_int::mul(a, b);
    let po = bounded_int::add::<_, UnitInt<0x40000000000000000000000000000000>>(
        p, 0x40000000000000000000000000000000,
    );
    let (q, _r) = bounded_int::div_rem::<_, UnitInt<0x100000000>>(po, 0x100000000);
    let r = bounded_int::sub::<_, UnitInt<0x400000000000000000000000>>(q, 0x400000000000000000000000);
    downcast(r).unwrap()
}

impl AddI64 of AddHelper<i64, i64> {
    type Result = BoundedInt<-0x10000000000000000, 0xfffffffffffffffe>;
}
/// i64 + i64 without any range check: the result type is wide enough.
pub fn bi_add_i64(a: i64, b: i64) -> felt252 {
    upcast(bounded_int::add(a, b))
}

impl DivRemU64Pow13 of DivRemHelper<u64, UnitInt<0x2000>> {
    type DivT = BoundedInt<0, 0x7ffffffffffff>;
    type RemT = BoundedInt<0, 0x1fff>;
}
pub fn bi_shr13_u64(a: u64) -> u64 {
    let (q, _r) = bounded_int::div_rem::<_, UnitInt<0x2000>>(a, 0x2000);
    upcast(q)
}

pub fn bi_is_neg(a: i64) -> bool {
    match bounded_int::constrain::<i64, 0>(a) {
        Ok(_) => true,
        Err(_) => false,
    }
}
pub fn bi_abs(a: i64) -> u64 {
    match bounded_int::constrain::<i64, 0>(a) {
        Ok(neg) => upcast(bounded_int::NegateHelper::negate(neg)),
        Err(pos) => upcast(pos),
    }
}

// ---------------------------------------------------------------- rescale variants (a*b >> 32, i64)
/// Variant 2: sign-split by hand, unsigned u128 divmod by a constant, re-apply sign (stable API).
#[inline(always)]
pub fn rescale_sign_split(a: i64, b: i64) -> i64 {
    let (am, an): (u64, bool) = if a < 0 {
        ((-a).try_into().unwrap(), true)
    } else {
        (a.try_into().unwrap(), false)
    };
    let (bm, bn): (u64, bool) = if b < 0 {
        ((-b).try_into().unwrap(), true)
    } else {
        (b.try_into().unwrap(), false)
    };
    let p: u128 = core::num::traits::WideMul::wide_mul(am, bm);
    let q: i64 = (p / 0x100000000).try_into().unwrap();
    if an ^ bn {
        -q
    } else {
        q
    }
}

/// Variant 4: bias trick with stable API only: felt252 product + 2^127, u128 divmod by a constant.
#[inline(always)]
pub fn rescale_felt_bias(a: i64, b: i64) -> i64 {
    let af: felt252 = a.into();
    let bf: felt252 = b.into();
    let biased: u128 = (af * bf + 0x80000000000000000000000000000000).try_into().unwrap();
    let q: felt252 = (biased / 0x100000000).into();
    (q - 0x800000000000000000000000).try_into().unwrap()
}
