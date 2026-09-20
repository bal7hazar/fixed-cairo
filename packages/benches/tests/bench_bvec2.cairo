//! Gas benchmarks of `glam::bvec2` and of the alternatives kept in `benches::alt::bvec2`
//! (the `alt_*` benches).
//!
//! Sierra gas is charged at the most expensive sibling branch, but steps depend on the path
//! taken: branching candidates are measured on a favourable and on an unfavourable input
//! (`_first` / `_last`: the deciding element or the index is the first / the last one).

use benches::alt::bvec2 as alt;
use benches::harness::{bb, sink};
use glam::bvec2::BVec2Trait;

#[test]
fn bitmask__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(5_u32);
    sink(d);
}

#[test]
fn bitmask__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(5_u32);
    sink(v.bitmask());
}

#[test]
fn alt_bitmask_if_tree__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(5_u32);
    sink(d);
}

#[test]
fn alt_bitmask_if_tree__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(5_u32);
    sink(alt::bitmask_if_tree(v));
}

#[test]
fn alt_bitmask_if_tree_lsb__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(5_u32);
    sink(d);
}

#[test]
fn alt_bitmask_if_tree_lsb__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(5_u32);
    sink(alt::bitmask_if_tree_lsb(v));
}

#[test]
fn alt_bitmask_felt__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(5_u32);
    sink(d);
}

#[test]
fn alt_bitmask_felt__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(5_u32);
    sink(alt::bitmask_felt(v));
}

#[test]
fn alt_bitmask_if_add__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(5_u32);
    sink(d);
}

#[test]
fn alt_bitmask_if_add__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(5_u32);
    sink(alt::bitmask_if_add(v));
}

#[test]
fn alt_bitmask_if_add_felt__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(5_u32);
    sink(d);
}

#[test]
fn alt_bitmask_if_add_felt__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(5_u32);
    sink(alt::bitmask_if_add_felt(v));
}

#[test]
fn alt_bitmask_match__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(5_u32);
    sink(d);
}

#[test]
fn alt_bitmask_match__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(5_u32);
    sink(alt::bitmask_match(v));
}

#[test]
fn any_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn any_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(v.any());
}

#[test]
fn any_last__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn any_last__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(v.any());
}

#[test]
fn alt_any_short_circuit_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_any_short_circuit_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::any_short_circuit(v));
}

#[test]
fn alt_any_short_circuit_last__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_any_short_circuit_last__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::any_short_circuit(v));
}

#[test]
fn alt_any_eager_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_any_eager_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::any_eager(v));
}

#[test]
fn alt_any_eager_last__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_any_eager_last__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::any_eager(v));
}

#[test]
fn alt_any_felt_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_any_felt_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::any_felt(v));
}

#[test]
fn alt_any_felt_last__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_any_felt_last__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::any_felt(v));
}

#[test]
fn alt_any_felt_match_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_any_felt_match_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::any_felt_match(v));
}

#[test]
fn alt_any_felt_match_last__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_any_felt_match_last__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::any_felt_match(v));
}

#[test]
fn alt_any_ne_false_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_any_ne_false_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::any_ne_false(v));
}

#[test]
fn alt_any_ne_false_last__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_any_ne_false_last__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::any_ne_false(v));
}

#[test]
fn alt_any_if_chain_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_any_if_chain_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::any_if_chain(v));
}

#[test]
fn alt_any_if_chain_last__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_any_if_chain_last__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::any_if_chain(v));
}

#[test]
fn all_first__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn all_first__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(v.all());
}

#[test]
fn all_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn all_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(v.all());
}

#[test]
fn alt_all_short_circuit_first__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_short_circuit_first__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::all_short_circuit(v));
}

#[test]
fn alt_all_short_circuit_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_short_circuit_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::all_short_circuit(v));
}

#[test]
fn alt_all_eager_first__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_eager_first__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::all_eager(v));
}

#[test]
fn alt_all_eager_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_eager_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::all_eager(v));
}

#[test]
fn alt_all_felt_sum_first__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_felt_sum_first__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::all_felt_sum(v));
}

#[test]
fn alt_all_felt_sum_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_felt_sum_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::all_felt_sum(v));
}

#[test]
fn alt_all_felt_product_first__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_felt_product_first__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::all_felt_product(v));
}

#[test]
fn alt_all_felt_product_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_felt_product_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::all_felt_product(v));
}

#[test]
fn alt_all_felt_match_first__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_felt_match_first__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::all_felt_match(v));
}

#[test]
fn alt_all_felt_match_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_felt_match_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::all_felt_match(v));
}

#[test]
fn alt_all_eq_true_first__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_eq_true_first__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::all_eq_true(v));
}

#[test]
fn alt_all_eq_true_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_eq_true_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::all_eq_true(v));
}

#[test]
fn alt_all_if_chain_first__base() {
    let _v = bb(BVec2Trait::new(false, true));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_if_chain_first__op() {
    let v = bb(BVec2Trait::new(false, true));
    let _d = bb(true);
    sink(alt::all_if_chain(v));
}

#[test]
fn alt_all_if_chain_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_all_if_chain_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb(true);
    sink(alt::all_if_chain(v));
}

#[test]
fn test_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let _i = bb(0_usize);
    let d = bb(true);
    sink(d);
}

#[test]
fn test_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let i = bb(0_usize);
    let _d = bb(true);
    sink(v.test(i));
}

#[test]
fn test_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let _i = bb(1_usize);
    let d = bb(true);
    sink(d);
}

#[test]
fn test_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let i = bb(1_usize);
    let _d = bb(true);
    sink(v.test(i));
}

#[test]
fn alt_test_match_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let _i = bb(0_usize);
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_test_match_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let i = bb(0_usize);
    let _d = bb(true);
    sink(alt::test_match(v, i));
}

#[test]
fn alt_test_match_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let _i = bb(1_usize);
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_test_match_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let i = bb(1_usize);
    let _d = bb(true);
    sink(alt::test_match(v, i));
}

#[test]
fn alt_test_if_chain_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let _i = bb(0_usize);
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_test_if_chain_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let i = bb(0_usize);
    let _d = bb(true);
    sink(alt::test_if_chain(v, i));
}

#[test]
fn alt_test_if_chain_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let _i = bb(1_usize);
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_test_if_chain_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let i = bb(1_usize);
    let _d = bb(true);
    sink(alt::test_if_chain(v, i));
}

#[test]
fn alt_test_span_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let _i = bb(0_usize);
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_test_span_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let i = bb(0_usize);
    let _d = bb(true);
    sink(alt::test_span(v, i));
}

#[test]
fn alt_test_span_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let _i = bb(1_usize);
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_test_span_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let i = bb(1_usize);
    let _d = bb(true);
    sink(alt::test_span(v, i));
}

#[test]
fn alt_test_bitmask_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let _i = bb(0_usize);
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_test_bitmask_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let i = bb(0_usize);
    let _d = bb(true);
    sink(alt::test_bitmask(v, i));
}

#[test]
fn alt_test_bitmask_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let _i = bb(1_usize);
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_test_bitmask_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let i = bb(1_usize);
    let _d = bb(true);
    sink(alt::test_bitmask(v, i));
}

#[test]
fn alt_test_match_noinline_first__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let _i = bb(0_usize);
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_test_match_noinline_first__op() {
    let v = bb(BVec2Trait::new(true, false));
    let i = bb(0_usize);
    let _d = bb(true);
    sink(alt::test_match_noinline(v, i));
}

#[test]
fn alt_test_match_noinline_last__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let _i = bb(1_usize);
    let d = bb(true);
    sink(d);
}

#[test]
fn alt_test_match_noinline_last__op() {
    let v = bb(BVec2Trait::new(true, false));
    let i = bb(1_usize);
    let _d = bb(true);
    sink(alt::test_match_noinline(v, i));
}

#[test]
fn set_first__base() {
    let v = bb(BVec2Trait::new(true, false));
    let _i = bb(0_usize);
    let _value = bb(false);
    sink(v);
}

#[test]
fn set_first__op() {
    let mut v = bb(BVec2Trait::new(true, false));
    let i = bb(0_usize);
    let value = bb(false);
    v.set(i, value);
    sink(v);
}

#[test]
fn set_last__base() {
    let v = bb(BVec2Trait::new(true, false));
    let _i = bb(1_usize);
    let _value = bb(true);
    sink(v);
}

#[test]
fn set_last__op() {
    let mut v = bb(BVec2Trait::new(true, false));
    let i = bb(1_usize);
    let value = bb(true);
    v.set(i, value);
    sink(v);
}

#[test]
fn alt_set_match_first__base() {
    let v = bb(BVec2Trait::new(true, false));
    let _i = bb(0_usize);
    let _value = bb(false);
    sink(v);
}

#[test]
fn alt_set_match_first__op() {
    let mut v = bb(BVec2Trait::new(true, false));
    let i = bb(0_usize);
    let value = bb(false);
    alt::set_match(ref v, i, value);
    sink(v);
}

#[test]
fn alt_set_match_last__base() {
    let v = bb(BVec2Trait::new(true, false));
    let _i = bb(1_usize);
    let _value = bb(true);
    sink(v);
}

#[test]
fn alt_set_match_last__op() {
    let mut v = bb(BVec2Trait::new(true, false));
    let i = bb(1_usize);
    let value = bb(true);
    alt::set_match(ref v, i, value);
    sink(v);
}

#[test]
fn alt_set_match_rebuild_first__base() {
    let v = bb(BVec2Trait::new(true, false));
    let _i = bb(0_usize);
    let _value = bb(false);
    sink(v);
}

#[test]
fn alt_set_match_rebuild_first__op() {
    let mut v = bb(BVec2Trait::new(true, false));
    let i = bb(0_usize);
    let value = bb(false);
    alt::set_match_rebuild(ref v, i, value);
    sink(v);
}

#[test]
fn alt_set_match_rebuild_last__base() {
    let v = bb(BVec2Trait::new(true, false));
    let _i = bb(1_usize);
    let _value = bb(true);
    sink(v);
}

#[test]
fn alt_set_match_rebuild_last__op() {
    let mut v = bb(BVec2Trait::new(true, false));
    let i = bb(1_usize);
    let value = bb(true);
    alt::set_match_rebuild(ref v, i, value);
    sink(v);
}

#[test]
fn alt_set_if_chain_first__base() {
    let v = bb(BVec2Trait::new(true, false));
    let _i = bb(0_usize);
    let _value = bb(false);
    sink(v);
}

#[test]
fn alt_set_if_chain_first__op() {
    let mut v = bb(BVec2Trait::new(true, false));
    let i = bb(0_usize);
    let value = bb(false);
    alt::set_if_chain(ref v, i, value);
    sink(v);
}

#[test]
fn alt_set_if_chain_last__base() {
    let v = bb(BVec2Trait::new(true, false));
    let _i = bb(1_usize);
    let _value = bb(true);
    sink(v);
}

#[test]
fn alt_set_if_chain_last__op() {
    let mut v = bb(BVec2Trait::new(true, false));
    let i = bb(1_usize);
    let value = bb(true);
    alt::set_if_chain(ref v, i, value);
    sink(v);
}

#[test]
fn alt_set_match_noinline_first__base() {
    let v = bb(BVec2Trait::new(true, false));
    let _i = bb(0_usize);
    let _value = bb(false);
    sink(v);
}

#[test]
fn alt_set_match_noinline_first__op() {
    let mut v = bb(BVec2Trait::new(true, false));
    let i = bb(0_usize);
    let value = bb(false);
    alt::set_match_noinline(ref v, i, value);
    sink(v);
}

#[test]
fn alt_set_match_noinline_last__base() {
    let v = bb(BVec2Trait::new(true, false));
    let _i = bb(1_usize);
    let _value = bb(true);
    sink(v);
}

#[test]
fn alt_set_match_noinline_last__op() {
    let mut v = bb(BVec2Trait::new(true, false));
    let i = bb(1_usize);
    let value = bb(true);
    alt::set_match_noinline(ref v, i, value);
    sink(v);
}

#[test]
fn bitand__base() {
    let a = bb(BVec2Trait::new(true, false));
    let _b = bb(BVec2Trait::new(true, true));
    sink(a);
}

#[test]
fn bitand__op() {
    let a = bb(BVec2Trait::new(true, false));
    let b = bb(BVec2Trait::new(true, true));
    sink(a & b);
}

#[test]
fn alt_bitand_short_circuit__base() {
    let a = bb(BVec2Trait::new(true, false));
    let _b = bb(BVec2Trait::new(true, true));
    sink(a);
}

#[test]
fn alt_bitand_short_circuit__op() {
    let a = bb(BVec2Trait::new(true, false));
    let b = bb(BVec2Trait::new(true, true));
    sink(alt::bitand_short_circuit(a, b));
}

#[test]
fn bitor__base() {
    let a = bb(BVec2Trait::new(true, false));
    let _b = bb(BVec2Trait::new(true, true));
    sink(a);
}

#[test]
fn bitor__op() {
    let a = bb(BVec2Trait::new(true, false));
    let b = bb(BVec2Trait::new(true, true));
    sink(a | b);
}

#[test]
fn alt_bitor_short_circuit__base() {
    let a = bb(BVec2Trait::new(true, false));
    let _b = bb(BVec2Trait::new(true, true));
    sink(a);
}

#[test]
fn alt_bitor_short_circuit__op() {
    let a = bb(BVec2Trait::new(true, false));
    let b = bb(BVec2Trait::new(true, true));
    sink(alt::bitor_short_circuit(a, b));
}

#[test]
fn alt_bitor_xor_and__base() {
    let a = bb(BVec2Trait::new(true, false));
    let _b = bb(BVec2Trait::new(true, true));
    sink(a);
}

#[test]
fn alt_bitor_xor_and__op() {
    let a = bb(BVec2Trait::new(true, false));
    let b = bb(BVec2Trait::new(true, true));
    sink(alt::bitor_xor_and(a, b));
}

#[test]
fn bitxor__base() {
    let a = bb(BVec2Trait::new(true, false));
    let _b = bb(BVec2Trait::new(true, true));
    sink(a);
}

#[test]
fn bitxor__op() {
    let a = bb(BVec2Trait::new(true, false));
    let b = bb(BVec2Trait::new(true, true));
    sink(a ^ b);
}

#[test]
fn alt_bitxor_ne__base() {
    let a = bb(BVec2Trait::new(true, false));
    let _b = bb(BVec2Trait::new(true, true));
    sink(a);
}

#[test]
fn alt_bitxor_ne__op() {
    let a = bb(BVec2Trait::new(true, false));
    let b = bb(BVec2Trait::new(true, true));
    sink(alt::bitxor_ne(a, b));
}

#[test]
fn not__base() {
    let a = bb(BVec2Trait::new(true, false));
    sink(a);
}

#[test]
fn not__op() {
    let a = bb(BVec2Trait::new(true, false));
    sink(!a);
}

#[test]
fn alt_not_xor_true__base() {
    let a = bb(BVec2Trait::new(true, false));
    sink(a);
}

#[test]
fn alt_not_xor_true__op() {
    let a = bb(BVec2Trait::new(true, false));
    sink(alt::not_xor_true(a));
}

#[test]
fn alt_not_if__base() {
    let a = bb(BVec2Trait::new(true, false));
    sink(a);
}

#[test]
fn alt_not_if__op() {
    let a = bb(BVec2Trait::new(true, false));
    sink(alt::not_if(a));
}

#[test]
fn splat__base() {
    let _s = bb(true);
    let d = bb(BVec2Trait::new(true, false));
    sink(d);
}

#[test]
fn splat__op() {
    let s = bb(true);
    let _d = bb(BVec2Trait::new(true, false));
    sink(BVec2Trait::splat(s));
}

#[test]
fn from_array__base() {
    let _arr = bb([true, false]);
    let d = bb(BVec2Trait::new(true, false));
    sink(d);
}

#[test]
fn from_array__op() {
    let arr = bb([true, false]);
    let _d = bb(BVec2Trait::new(true, false));
    sink(BVec2Trait::from_array(arr));
}

#[test]
fn into_bool_array__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb([true, false]);
    sink(d);
}

#[test]
fn into_bool_array__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb([true, false]);
    let r: [bool; 2] = v.into();
    sink(r);
}

#[test]
fn into_u32_array__base() {
    let _v = bb(BVec2Trait::new(true, false));
    let d = bb([7_u32, 7_u32]);
    sink(d);
}

#[test]
fn into_u32_array__op() {
    let v = bb(BVec2Trait::new(true, false));
    let _d = bb([7_u32, 7_u32]);
    let r: [u32; 2] = v.into();
    sink(r);
}
