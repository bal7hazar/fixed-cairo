//! Methodology cross-check: the same operations measured as (loop of 100 ops) - (loop of 100 no-ops).
//! (delta / 100) should match the single-shot `op - base` numbers of tests/prims.cairo within ~1 step.
use bench::fixed::i64b::FI64;
use bench::harness::{bb, sink};

#[test]
fn x100_u64_add__base() {
    let n: u64 = bb(100);
    let mut i: u64 = 0;
    let mut acc: u64 = bb(7);
    while i != n {
        acc = i;
        i += 1;
    }
    sink(acc);
}
#[test]
fn x100_u64_add__op() {
    let n: u64 = bb(100);
    let mut i: u64 = 0;
    let mut acc: u64 = bb(7);
    while i != n {
        acc = acc + i;
        i += 1;
    }
    sink(acc);
}
#[test]
fn x100_u64_div__base() {
    let n: u64 = bb(100);
    let mut i: u64 = 0;
    let mut acc: u64 = bb(0x123456789abcdef);
    while i != n {
        acc = acc;
        i += 1;
    }
    sink(acc);
}
#[test]
fn x100_u64_div__op() {
    let n: u64 = bb(100);
    let mut i: u64 = 0;
    let mut acc: u64 = bb(0x123456789abcdef);
    while i != n {
        acc = acc / 0x2000 + 0x123456789abcdef;
        i += 1;
    }
    sink(acc);
}
#[test]
fn x100_u64_and__base() {
    let n: u64 = bb(100);
    let mut i: u64 = 0;
    let mut acc: u64 = bb(0x123456789abcdef);
    while i != n {
        acc = i;
        i += 1;
    }
    sink(acc);
}
#[test]
fn x100_u64_and__op() {
    let n: u64 = bb(100);
    let mut i: u64 = 0;
    let mut acc: u64 = bb(0x123456789abcdef);
    while i != n {
        acc = (acc & i) + 0x123456789abcdef;
        i += 1;
    }
    sink(acc);
}
#[test]
fn x100_fixed_i64b_mul__base() {
    let n: u64 = bb(100);
    let mut i: u64 = 0;
    let k = FI64 { raw: bb(0xfffffff0) };
    let mut acc = FI64 { raw: bb(0x123456789) };
    while i != n {
        acc = k;
        i += 1;
    }
    sink(acc);
}
#[test]
fn x100_fixed_i64b_mul__op() {
    let n: u64 = bb(100);
    let mut i: u64 = 0;
    let k = FI64 { raw: bb(0xfffffff0) };
    let mut acc = FI64 { raw: bb(0x123456789) };
    while i != n {
        acc = acc * k;
        i += 1;
    }
    sink(acc);
}
