//! Benchmarks of `fixed::exp`: one `X__base` / `X__op` pair per public function, with several
//! inputs where the cost depends on the branch taken (overflow / underflow checks, the zero and
//! negative bases of `powf`) or on the leaf of the exponent search of the logarithms. The losing
//! variants of `benches::alt::exp` are the `alt_*` rows; `alt_normalize_*` isolate the exponent
//! search of `log2` (the library uses the `tree` one).
use benches::alt::exp as alt;
use benches::harness::{bb, sink};
use fixed::Fixed;
use fixed::exp::ExpTrait;

#[test]
fn exp__small__base() {
    let _a = bb(Fixed { raw: 0x80000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn exp__small__op() {
    let a = bb(Fixed { raw: 0x80000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.exp());
}

#[test]
fn exp__negative__base() {
    let _a = bb(Fixed { raw: -0x500003039 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn exp__negative__op() {
    let a = bb(Fixed { raw: -0x500003039 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.exp());
}

#[test]
fn exp__large__base() {
    let _a = bb(Fixed { raw: 0x14000003e7 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn exp__large__op() {
    let a = bb(Fixed { raw: 0x14000003e7 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.exp());
}

#[test]
fn exp__underflow__base() {
    let _a = bb(Fixed { raw: -0x1e00000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn exp__underflow__op() {
    let a = bb(Fixed { raw: -0x1e00000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.exp());
}

#[test]
fn exp2__small__base() {
    let _a = bb(Fixed { raw: 0x55555555 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn exp2__small__op() {
    let a = bb(Fixed { raw: 0x55555555 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.exp2());
}

#[test]
fn exp2__negative__base() {
    let _a = bb(Fixed { raw: -0x733333333 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn exp2__negative__op() {
    let a = bb(Fixed { raw: -0x733333333 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.exp2());
}

#[test]
fn exp2__large__base() {
    let _a = bb(Fixed { raw: 0x1d24924924 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn exp2__large__op() {
    let a = bb(Fixed { raw: 0x1d24924924 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.exp2());
}

#[test]
fn exp2__underflow__base() {
    let _a = bb(Fixed { raw: -0x2800000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn exp2__underflow__op() {
    let a = bb(Fixed { raw: -0x2800000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.exp2());
}

#[test]
fn exp_m1__base() {
    let _a = bb(Fixed { raw: 0x19999999 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn exp_m1__op() {
    let a = bb(Fixed { raw: 0x19999999 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.exp_m1());
}

#[test]
fn ln__below_one__base() {
    let _a = bb(Fixed { raw: 0x55555555 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn ln__below_one__op() {
    let a = bb(Fixed { raw: 0x55555555 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.ln());
}

#[test]
fn ln__large__base() {
    let _a = bb(Fixed { raw: 0x1e24000000315 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn ln__large__op() {
    let a = bb(Fixed { raw: 0x1e24000000315 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.ln());
}

#[test]
fn log2__below_one__base() {
    let _a = bb(Fixed { raw: 0x55555555 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn log2__below_one__op() {
    let a = bb(Fixed { raw: 0x55555555 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.log2());
}

#[test]
fn log2__large__base() {
    let _a = bb(Fixed { raw: 0x1e24000000315 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn log2__large__op() {
    let a = bb(Fixed { raw: 0x1e24000000315 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.log2());
}

#[test]
fn log2__epsilon__base() {
    let _a = bb(Fixed { raw: 0x1 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn log2__epsilon__op() {
    let a = bb(Fixed { raw: 0x1 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.log2());
}

#[test]
fn log10__base() {
    let _a = bb(Fixed { raw: 0x3e800000005 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn log10__op() {
    let a = bb(Fixed { raw: 0x3e800000005 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.log10());
}

#[test]
fn ln_1p__base() {
    let _a = bb(Fixed { raw: 0x28f5c28 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn ln_1p__op() {
    let a = bb(Fixed { raw: 0x28f5c28 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.ln_1p());
}

#[test]
fn log__base() {
    let _a = bb(Fixed { raw: 0x3e800000005 });
    let _b = bb(Fixed { raw: 0x300000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn log__op() {
    let a = bb(Fixed { raw: 0x3e800000005 });
    let b = bb(Fixed { raw: 0x300000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.log(b));
}

#[test]
fn powf__positive__base() {
    let _a = bb(Fixed { raw: 0x340000000 });
    let _b = bb(Fixed { raw: 0x280000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn powf__positive__op() {
    let a = bb(Fixed { raw: 0x340000000 });
    let b = bb(Fixed { raw: 0x280000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.powf(b));
}

#[test]
fn powf__fraction__base() {
    let _a = bb(Fixed { raw: 0x55555555 });
    let _b = bb(Fixed { raw: -0x80000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn powf__fraction__op() {
    let a = bb(Fixed { raw: 0x55555555 });
    let b = bb(Fixed { raw: -0x80000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.powf(b));
}

#[test]
fn powf__negative_base__base() {
    let _a = bb(Fixed { raw: -0x300000000 });
    let _b = bb(Fixed { raw: 0x300000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn powf__negative_base__op() {
    let a = bb(Fixed { raw: -0x300000000 });
    let b = bb(Fixed { raw: 0x300000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.powf(b));
}

#[test]
fn powf__zero_base__base() {
    let _a = bb(Fixed { raw: 0x0 });
    let _b = bb(Fixed { raw: 0x200000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn powf__zero_base__op() {
    let a = bb(Fixed { raw: 0x0 });
    let b = bb(Fixed { raw: 0x200000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.powf(b));
}

#[test]
fn powf__underflow__base() {
    let _a = bb(Fixed { raw: 0x418937 });
    let _b = bb(Fixed { raw: 0x6400000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn powf__underflow__op() {
    let a = bb(Fixed { raw: 0x418937 });
    let b = bb(Fixed { raw: 0x6400000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.powf(b));
}

#[test]
fn alt_exp2_single_poly__base() {
    let _a = bb(Fixed { raw: 0x55555555 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_exp2_single_poly__op() {
    let a = bb(Fixed { raw: 0x55555555 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::exp2_single_poly(a));
}

#[test]
fn alt_exp2_single_poly_large__base() {
    let _a = bb(Fixed { raw: 0x1d24924924 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_exp2_single_poly_large__op() {
    let a = bb(Fixed { raw: 0x1d24924924 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::exp2_single_poly(a));
}

#[test]
fn alt_exp_cody_waite__base() {
    let _a = bb(Fixed { raw: 0x80000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_exp_cody_waite__op() {
    let a = bb(Fixed { raw: 0x80000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::exp_cody_waite(a));
}

#[test]
fn alt_exp_cody_waite_negative__base() {
    let _a = bb(Fixed { raw: -0x500003039 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_exp_cody_waite_negative__op() {
    let a = bb(Fixed { raw: -0x500003039 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::exp_cody_waite(a));
}

#[test]
fn alt_exp_naive__base() {
    let _a = bb(Fixed { raw: 0x80000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_exp_naive__op() {
    let a = bb(Fixed { raw: 0x80000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::exp_naive(a));
}

#[test]
fn alt_log2_atanh__base() {
    let _a = bb(Fixed { raw: 0x55555555 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_log2_atanh__op() {
    let a = bb(Fixed { raw: 0x55555555 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::log2_atanh(a));
}

#[test]
fn alt_log2_atanh_large__base() {
    let _a = bb(Fixed { raw: 0x1e24000000315 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_log2_atanh_large__op() {
    let a = bb(Fixed { raw: 0x1e24000000315 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::log2_atanh(a));
}

#[test]
fn alt_normalize_tree__small__base() {
    let _a = bb(0x3_u64);
    sink(bb((1_u64, 1_i64)));
}

#[test]
fn alt_normalize_tree__small__op() {
    let a = bb(0x3_u64);
    let _r = bb((1_u64, 1_i64));
    sink(alt::normalize_tree(a));
}

#[test]
fn alt_normalize_clz__small__base() {
    let _a = bb(0x3_u64);
    sink(bb((1_u64, 1_i64)));
}

#[test]
fn alt_normalize_clz__small__op() {
    let a = bb(0x3_u64);
    let _r = bb((1_u64, 1_i64));
    sink(alt::normalize_clz(a));
}

#[test]
fn alt_normalize_msb_table__small__base() {
    let _a = bb(0x3_u64);
    sink(bb((1_u64, 1_i64)));
}

#[test]
fn alt_normalize_msb_table__small__op() {
    let a = bb(0x3_u64);
    let _r = bb((1_u64, 1_i64));
    sink(alt::normalize_msb_table(a));
}

#[test]
fn alt_normalize_tree__mid__base() {
    let _a = bb(0x55555555_u64);
    sink(bb((1_u64, 1_i64)));
}

#[test]
fn alt_normalize_tree__mid__op() {
    let a = bb(0x55555555_u64);
    let _r = bb((1_u64, 1_i64));
    sink(alt::normalize_tree(a));
}

#[test]
fn alt_normalize_clz__mid__base() {
    let _a = bb(0x55555555_u64);
    sink(bb((1_u64, 1_i64)));
}

#[test]
fn alt_normalize_clz__mid__op() {
    let a = bb(0x55555555_u64);
    let _r = bb((1_u64, 1_i64));
    sink(alt::normalize_clz(a));
}

#[test]
fn alt_normalize_msb_table__mid__base() {
    let _a = bb(0x55555555_u64);
    sink(bb((1_u64, 1_i64)));
}

#[test]
fn alt_normalize_msb_table__mid__op() {
    let a = bb(0x55555555_u64);
    let _r = bb((1_u64, 1_i64));
    sink(alt::normalize_msb_table(a));
}

#[test]
fn alt_normalize_tree__large__base() {
    let _a = bb(0x1e24000000315_u64);
    sink(bb((1_u64, 1_i64)));
}

#[test]
fn alt_normalize_tree__large__op() {
    let a = bb(0x1e24000000315_u64);
    let _r = bb((1_u64, 1_i64));
    sink(alt::normalize_tree(a));
}

#[test]
fn alt_normalize_clz__large__base() {
    let _a = bb(0x1e24000000315_u64);
    sink(bb((1_u64, 1_i64)));
}

#[test]
fn alt_normalize_clz__large__op() {
    let a = bb(0x1e24000000315_u64);
    let _r = bb((1_u64, 1_i64));
    sink(alt::normalize_clz(a));
}

#[test]
fn alt_normalize_msb_table__large__base() {
    let _a = bb(0x1e24000000315_u64);
    sink(bb((1_u64, 1_i64)));
}

#[test]
fn alt_normalize_msb_table__large__op() {
    let a = bb(0x1e24000000315_u64);
    let _r = bb((1_u64, 1_i64));
    sink(alt::normalize_msb_table(a));
}
