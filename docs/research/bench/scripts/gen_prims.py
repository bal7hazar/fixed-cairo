#!/usr/bin/env python3
"""Generates tests/prims.cairo: micro-benchmarks of Cairo primitive operations.

Every benchmark `X` yields two tests:
  X__base : creates the opaque inputs + an opaque value of the result type, sinks it
  X__op   : same prelude, but sinks `expr(inputs)` instead
cost(X) = X__op - X__base   (computed by scripts/bench.py)
"""
import os
import re

VALS = {
    "u8": ("25", "7"),
    "u16": ("300", "50"),
    "u32": ("70000", "300"),
    "u64": ("0x123456789", "0x54321"),
    "u128": ("0x123456789abcdef0123", "0x7654321fedcba"),
    "u256": ("0x400000000000000000000000000003039", "0x10000000000000000000000309"),
    "felt252": ("0x123456789abcdef0123456789abcdef0123456789abcdef", "0x7654321fedcba9876543210fedcba"),
    "i8": ("-11", "7"),
    "i16": ("-300", "50"),
    "i32": ("-70000", "300"),
    "i64": ("-0x123456789", "0x54321"),
    "i128": ("-0x123456789abcdef0123", "0x7654321fedcba"),
}
UNSIGNED = ["u8", "u16", "u32", "u64", "u128", "u256"]
SIGNED = ["i8", "i16", "i32", "i64", "i128"]
INTS = UNSIGNED + SIGNED

benches = []  # (name, inputs[(var,type,val)], (rtype, rval), expr)


def B(name, ins, out, expr):
    benches.append((name, ins, out, expr))


def ab(t):
    a, b = VALS[t]
    return [("a", t, a), ("b", t, b)]


# ---- arithmetic -----------------------------------------------------------
for t in INTS + ["felt252"]:
    B(f"{t}_add", ab(t), (t, "1"), "a + b")
    B(f"{t}_sub", ab(t), (t, "1"), "a - b")
    B(f"{t}_mul", ab(t), (t, "1"), "a * b")
    B(f"{t}_eq", ab(t), ("bool", "true"), "a == b")
for t in INTS:
    B(f"{t}_div", ab(t), (t, "1"), "a / b")
    B(f"{t}_rem", ab(t), (t, "1"), "a % b")
    B(f"{t}_divrem", ab(t), (f"({t}, {t})", "(1, 1)"), "DivRem::div_rem(a, b.try_into().unwrap())")
    B(f"{t}_lt", ab(t), ("bool", "true"), "a < b")
    B(f"{t}_le", ab(t), ("bool", "true"), "a <= b")
for t in SIGNED:
    B(f"{t}_neg", ab(t), (t, "1"), "-a")
# division by a compile-time constant (NonZero const, no zero check)
for t in ["u32", "u64", "u128", "u256"]:
    B(f"{t}_div_const_pow2", ab(t), (t, "1"), "a / 0x10000")
    B(f"{t}_divrem_const_pow2", ab(t), (f"({t}, {t})", "(1, 1)"), "DivRem::div_rem(a, 0x10000)")
    B(f"{t}_mul_const_pow2", ab(t), (t, "1"), "a * 0x100")
B("i64_div_const_pow2", ab("i64"), ("i64", "1"), "a / 0x10000")
B("i128_div_const_pow2", ab("i128"), ("i128", "1"), "a / 0x100000000")
B("felt252_div", ab("felt252"), ("felt252", "1"), "felt252_div(a, b.try_into().unwrap())")
B("felt252_is_zero", ab("felt252"), ("bool", "true"), "a == 0")
B("felt252_mul_add_x3", ab("felt252"), ("felt252", "1"), "a * b + b * a + a * a")

# wrapping / overflowing / checked / saturating
for t in ["u32", "u64", "u128"]:
    B(f"{t}_wrapping_add", ab(t), (t, "1"), "WrappingAdd::wrapping_add(a, b)")
    B(f"{t}_wrapping_sub", ab(t), (t, "1"), "WrappingSub::wrapping_sub(a, b)")
    B(f"{t}_overflowing_add", ab(t), (f"({t}, bool)", "(1, true)"), "OverflowingAdd::overflowing_add(a, b)")
    B(f"{t}_checked_add", ab(t), (f"Option<{t}>", "Some(1)"), "CheckedAdd::checked_add(a, b)")
    B(f"{t}_saturating_add", ab(t), (t, "1"), "SaturatingAdd::saturating_add(a, b)")
B("u64_wrapping_mul", ab("u64"), ("u64", "1"), "WrappingMul::wrapping_mul(a, b)")

# widening multiplications
for t, w in [("u8", "u16"), ("u16", "u32"), ("u32", "u64"), ("u64", "u128"), ("u128", "u256"),
             ("i8", "i16"), ("i16", "i32"), ("i32", "i64"), ("i64", "i128")]:
    B(f"{t}_wide_mul", ab(t), (w, "1"), "WideMul::wide_mul(a, b)")
B("u256_wide_mul", ab("u256"), ("u512", "u512 { limb0: 1, limb1: 1, limb2: 1, limb3: 1 }"), "WideMul::wide_mul(a, b)")
B("u64_wide_square", ab("u64"), ("u128", "1"), "WideSquare::wide_square(a)")

# ---- conversions ----------------------------------------------------------
def conv(name, ft, fv, tt, expr, rval="1"):
    B(name, [("a", ft, fv)], (tt, rval), expr)


conv("conv_u8_into_u64", "u8", "200", "u64", "a.into()")
conv("conv_u32_into_u64", "u32", "70000", "u64", "a.into()")
conv("conv_u64_into_u128", "u64", "0x123456789", "u128", "a.into()")
conv("conv_u64_into_u256", "u64", "0x123456789", "u256", "a.into()")
conv("conv_u128_into_u256", "u128", "0x123456789", "u256", "a.into()")
conv("conv_u64_into_felt", "u64", "0x123456789", "felt252", "a.into()")
conv("conv_u128_into_felt", "u128", "0x123456789", "felt252", "a.into()")
conv("conv_i64_into_felt", "i64", "-0x123456789", "felt252", "a.into()")
conv("conv_i64_into_i128", "i64", "-0x123456789", "i128", "a.into()")
conv("conv_u64_into_i128", "u64", "0x123456789", "i128", "a.into()")
conv("conv_bool_into_felt", "bool", "true", "felt252", "a.into()")
conv("conv_u64_tryinto_u32", "u64", "0x12345", "u32", "a.try_into().unwrap()")
conv("conv_u64_tryinto_u8", "u64", "0x12", "u8", "a.try_into().unwrap()")
conv("conv_u128_tryinto_u64", "u128", "0x123456789", "u64", "a.try_into().unwrap()")
conv("conv_u256_tryinto_u128", "u256", "0x123456789", "u128", "a.try_into().unwrap()")
conv("conv_u256_tryinto_u64", "u256", "0x123456789", "u64", "a.try_into().unwrap()")
conv("conv_u256_tryinto_felt", "u256", "0x123456789", "felt252", "a.try_into().unwrap()")
conv("conv_felt_tryinto_u8", "felt252", "0x12", "u8", "a.try_into().unwrap()")
conv("conv_felt_tryinto_u32", "felt252", "0x12345", "u32", "a.try_into().unwrap()")
conv("conv_felt_tryinto_u64", "felt252", "0x123456789", "u64", "a.try_into().unwrap()")
conv("conv_felt_tryinto_u128", "felt252", "0x123456789", "u128", "a.try_into().unwrap()")
conv("conv_felt_tryinto_i64_pos", "felt252", "0x123456789", "i64", "a.try_into().unwrap()")
conv("conv_felt_tryinto_i64_neg", "felt252", "-0x123456789", "i64", "a.try_into().unwrap()")
conv("conv_felt_tryinto_i128_neg", "felt252", "-0x123456789", "i128", "a.try_into().unwrap()")
conv("conv_felt_into_u256", "felt252", "0x123456789abcdef0123456789abcdef0123456789abcdef", "u256", "a.into()")
conv("conv_u64_tryinto_i64", "u64", "0x123456789", "i64", "a.try_into().unwrap()")
conv("conv_i64_tryinto_u64", "i64", "0x123456789", "u64", "a.try_into().unwrap()")
conv("conv_i128_tryinto_i64", "i128", "-0x123456789", "i64", "a.try_into().unwrap()")
conv("conv_i128_tryinto_u128", "i128", "0x123456789", "u128", "a.try_into().unwrap()")
conv("conv_i64_abs_via_felt", "i64", "-0x123456789", "u64",
     "{ let f: felt252 = a.into(); if a < 0 { (-f).try_into().unwrap() } else { f.try_into().unwrap() } }")
conv("conv_nonzero_u64", "u64", "0x123456789", "NonZero<u64>", "a.try_into().unwrap()", rval="1_u64.try_into().unwrap()")

# ---- bitwise --------------------------------------------------------------
for t in UNSIGNED:
    B(f"{t}_and", ab(t), (t, "1"), "a & b")
    B(f"{t}_or", ab(t), (t, "1"), "a | b")
    B(f"{t}_xor", ab(t), (t, "1"), "a ^ b")
for t in ["u8", "u64", "u128", "u256"]:
    B(f"{t}_not", ab(t), (t, "1"), "~a")
# low 32 bits: `& mask` vs `% 2^32`
B("u64_low32_via_and", ab("u64"), ("u64", "1"), "a & 0xffffffff")
B("u64_low32_via_rem", ab("u64"), ("u64", "1"), "a % 0x100000000")
B("u64_is_odd_via_and", ab("u64"), ("bool", "true"), "a & 1 == 1")
B("u64_is_odd_via_rem", ab("u64"), ("bool", "true"), "a % 2 == 1")

# ---- shifts ---------------------------------------------------------------
sh = [("a", "u64", "0x123456789abcdef"), ("n", "u32", "13")]
B("shr_u64_const_div", sh, ("u64", "1"), "a / 0x2000")
B("shl_u64_const_mul", [("a", "u64", "0x123456789"), ("n", "u32", "13")], ("u64", "1"), "a * 0x2000")
B("shr_u64_pow_trait", sh, ("u64", "1"), "a / Pow::pow(2_u64, n)")
B("shr_u64_match_lut", sh, ("u64", "1"), "a / pow2_match(n)")
B("shr_u64_span_lut", sh, ("u64", "1"), "a / *POW2_TABLE.span()[n]")
B("shr_u64_loop_halving", sh, ("u64", "1"), "shr_loop(a, n)")
B("pow2_u64_pow_trait", sh, ("u64", "1"), "Pow::pow(2_u64, n)")
B("pow2_u64_match_lut", sh, ("u64", "1"), "pow2_match(n)")
B("pow2_u64_span_lut", sh, ("u64", "1"), "*POW2_TABLE.span()[n]")
B("pow2_u64_boxed_lut", sh, ("u64", "1"), "pow2_boxed(n)")

# ---- sqrt -----------------------------------------------------------------
B("u8_sqrt", [("a", "u8", "200")], ("u8", "1"), "Sqrt::sqrt(a)")
B("u16_sqrt", [("a", "u16", "30000")], ("u8", "1"), "Sqrt::sqrt(a)")
B("u32_sqrt", [("a", "u32", "0x12345678")], ("u16", "1"), "Sqrt::sqrt(a)")
B("u64_sqrt", [("a", "u64", "0x123456789abcdef")], ("u32", "1"), "Sqrt::sqrt(a)")
B("u128_sqrt", [("a", "u128", "0x123456789abcdef0123456789abcd")], ("u64", "1"), "Sqrt::sqrt(a)")
B("u256_sqrt", [("a", "u256", "0x123456789abcdef0123456789abcdef0123456789abcdef")], ("u128", "1"), "Sqrt::sqrt(a)")

# ---- loops ----------------------------------------------------------------
lp = [("n", "u32", "100")]
B("loop_while_100_empty", lp, ("u32", "1"), "loop_while(n)")
B("loop_for_range_100_empty", lp, ("u32", "1"), "loop_for(n)")
B("loop_while_100_felt_counter", [("n", "felt252", "100")], ("felt252", "1"), "loop_felt(n)")
B("loop_recursive_100", lp, ("u32", "1"), "loop_rec(n, 0)")
B("loop_while_100_acc_add", lp, ("u32", "1"), "loop_acc(n)")
B("loop_span_iter_16", [("n", "u32", "16")], ("u64", "1"), "loop_span(POW2_TABLE.span().slice(0, n))")
B("unrolled_acc_add_8", [("a", "u32", "3")], ("u32", "1"), "a + a + a + a + a + a + a + a + a")
B("loop_acc_add_8", [("a", "u32", "3")], ("u32", "1"), "loop_add8(a)")

# ---- arrays / LUTs --------------------------------------------------------
ix = [("i", "u32", "37")]
B("lut64_span_index", ix, ("u64", "1"), "*LUT64.span()[i]")
B("lut64_span_at", ix, ("u64", "1"), "*LUT64.span().at(i)")
B("lut64_span_get", ix, ("u64", "1"), "*LUT64.span().get(i).unwrap().unbox()")
B("lut64_match", ix, ("u64", "1"), "lut64_match(i)")
B("lut64_match_felt", [("i", "felt252", "37")], ("u64", "1"), "lut64_match_felt(i)")
B("lut64_if_chain_worst", [("i", "u32", "7")], ("u64", "1"), "lut8_if(i)")
B("lut8_match", [("i", "u32", "7")], ("u64", "1"), "lut8_match(i)")
B("lut64_runtime_array_build_and_index", ix, ("u64", "1"), "{ let arr = build_array64(); *arr[i] }")
B("lut256_span_index", [("i", "u32", "200")], ("u64", "1"), "*LUT256.span()[i]")
B("lut256_match", [("i", "u32", "200")], ("u64", "1"), "lut256_match(i)")
B("lut64_struct_span_index", ix, ("(u64, u64)", "(1, 1)"), "*LUT64_PAIRS.span()[i]")

# ---- sign handling: struct{mag,sign} vs native ------------------------------
B("sign_struct_add", [("am", "u64", "0x123456789"), ("asg", "bool", "true"), ("bm", "u64", "0x54321"), ("bsg", "bool", "false")],
  ("(u64, bool)", "(1, true)"), "magsign_add(am, asg, bm, bsg)")
B("sign_native_add", ab("i64"), ("i64", "1"), "a + b")
B("sign_struct_mul", [("am", "u64", "0x123456789"), ("asg", "bool", "true"), ("bm", "u64", "0x54321"), ("bsg", "bool", "false")],
  ("(u64, bool)", "(1, true)"), "(am * bm, asg ^ bsg)")
B("sign_native_mul", ab("i64"), ("i64", "1"), "a * b")
B("bool_xor", [("a", "bool", "true"), ("b", "bool", "false")], ("bool", "true"), "a ^ b")
B("bool_and", [("a", "bool", "true"), ("b", "bool", "false")], ("bool", "true"), "a && b")
B("bool_not", [("a", "bool", "true"), ("b", "bool", "false")], ("bool", "true"), "!a")
B("bool_ne", [("a", "bool", "true"), ("b", "bool", "false")], ("bool", "true"), "a != b")
B("if_branch_select", [("c", "bool", "true"), ("a", "u64", "5"), ("b", "u64", "6")], ("u64", "1"), "if c { a } else { b }")

# ---- inlining ---------------------------------------------------------------
B("inline_default_small_fn", ab("u64"), ("u64", "1"), "small_default(a, b)")
B("inline_always_small_fn", ab("u64"), ("u64", "1"), "small_always(a, b)")
B("inline_never_small_fn", ab("u64"), ("u64", "1"), "small_never(a, b)")
B("inline_default_medium_fn", ab("u64"), ("u64", "1"), "medium_default(a, b)")
B("inline_always_medium_fn", ab("u64"), ("u64", "1"), "medium_always(a, b)")
B("inline_never_medium_fn", ab("u64"), ("u64", "1"), "medium_never(a, b)")
B("inline_never_nopanic_felt_fn", ab("felt252"), ("felt252", "1"), "felt_never(a, b)")
B("inline_always_nopanic_felt_fn", ab("felt252"), ("felt252", "1"), "felt_always(a, b)")
B("struct_by_value_vec3", [("x", "felt252", "1"), ("y", "felt252", "2"), ("z", "felt252", "3")], ("felt252", "1"),
  "v3_sum_val(V3 { x, y, z })")
B("struct_by_snapshot_vec3", [("x", "felt252", "1"), ("y", "felt252", "2"), ("z", "felt252", "3")], ("felt252", "1"),
  "v3_sum_snap(@V3 { x, y, z })")

# ---- bounded int --------------------------------------------------------------
B("bounded_u64_mul_divrem_2p32", ab("u64"), ("u64", "1"), "bi_mul_shift_u64(a, b)")
B("plain_u64_mul_divrem_2p32", ab("u64"), ("u64", "1"),
  "{ let p: u128 = WideMul::wide_mul(a, b); let (q, _) = DivRem::div_rem(p, 0x100000000); q.try_into().unwrap() }")
B("bounded_i64_mul_floor_shift32", ab("i64"), ("i64", "1"), "bi_mul_shift_i64(a, b)")
B("plain_i64_mul_div_2p32", ab("i64"), ("i64", "1"),
  "{ let p: i128 = WideMul::wide_mul(a, b); (p / 0x100000000).try_into().unwrap() }")
B("rescale_i64_v1_naive_i128_div", ab("i64"), ("i64", "1"),
  "{ let p: i128 = WideMul::wide_mul(a, b); (p / 0x100000000).try_into().unwrap() }")
B("rescale_i64_v2_sign_split_u128", ab("i64"), ("i64", "1"), "rescale_sign_split(a, b)")
B("rescale_i64_v3_bounded_bias", ab("i64"), ("i64", "1"), "bi_mul_shift_i64(a, b)")
B("rescale_i64_v4_felt_u128_bias", ab("i64"), ("i64", "1"), "rescale_felt_bias(a, b)")
B("u128_div_runtime_divisor", [("a", "u128", "0x123456789abcdef0123"), ("d", "u128", "0x100000000")], ("u128", "1"), "a / d")
B("u128_div_const_divisor", [("a", "u128", "0x123456789abcdef0123"), ("d", "u128", "0x100000000")], ("u128", "1"), "a / 0x100000000")
B("bounded_i64_add_nocheck", ab("i64"), ("felt252", "1"), "bi_add_i64(a, b)")
B("bounded_u64_divrem_pow2", ab("u64"), ("u64", "1"), "bi_shr13_u64(a)")
B("plain_u64_divrem_pow2", ab("u64"), ("u64", "1"), "a / 0x2000")
B("bounded_i64_is_neg_constrain", ab("i64"), ("bool", "true"), "bi_is_neg(a)")
B("plain_i64_is_neg_lt", ab("i64"), ("bool", "true"), "a < 0")
B("bounded_i64_abs", ab("i64"), ("u64", "1"), "bi_abs(a)")

PRELUDE = '''// GENERATED by scripts/gen_prims.py -- do not edit by hand.
use bench::harness::{bb, sink};
use bench::prims_support::*;
use core::num::traits::{
    CheckedAdd, OverflowingAdd, Pow, SaturatingAdd, Sqrt, WideMul, WideSquare, WrappingAdd, WrappingMul,
    WrappingSub,
};
use core::integer::u512;
use core::felt252_div;
'''


def main():
    out = [PRELUDE]
    for name, ins, (rt, rv), expr in benches:
        decl_base = "".join(f"    let _{v} = bb::<{t}>({val});\n" for v, t, val in ins)
        used = lambda v: re.search(r"\b" + v + r"\b", expr) is not None
        decl_op = "".join(f"    let {v if used(v) else '_' + v} = bb::<{t}>({val});\n" for v, t, val in ins)
        out.append(
            f"#[test]\nfn {name}__base() {{\n{decl_base}    let r = bb::<{rt}>({rv});\n    sink::<{rt}>(r);\n}}\n"
            f"#[test]\nfn {name}__op() {{\n{decl_op}    let _r = bb::<{rt}>({rv});\n    sink::<{rt}>({expr});\n}}\n"
        )
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "..", "tests", "prims.cairo")
    with open(path, "w") as f:
        f.write("\n".join(out))
    print(f"wrote {len(benches)} benchmarks to tests/prims.cairo")


if __name__ == "__main__":
    main()
