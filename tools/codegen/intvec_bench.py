"""Bench (`packages/benches/tests/bench_<m>.cairo`) and alt (`packages/benches/src/alt/<m>.cairo`)
templates of tools/codegen/intvec.py."""
import re

import intvec as g

MIN, MAX, UMAX = g.I32_MIN, g.I32_MAX, g.U32_MAX


def lit(t, vals):
    """`IVec3Trait::new(1, -2, 3)` from a list of 4 values."""
    return f"{t.name}Trait::new(" + ", ".join(str(v) for v in vals[:t.n]) + ")"


def blit(t, vals):
    return f"{t.B}Trait::new(" + ", ".join("true" if v else "false" for v in vals[:t.n]) + ")"


class Bench:
    def __init__(self, name, inputs, res, op, pre=""):
        self.name, self.inputs, self.res, self.op, self.pre = name, inputs, res, op, pre

    def emit(self):
        muts = set(re.findall(r"\b(\w+) (?:[-+*/%]=)", self.pre))
        base = "".join(f"    let _{n} = bb({e});\n" for n, e in self.inputs)
        op = "".join(f"    let {'mut ' if n in muts else ''}{n} = bb({e});\n"
                     for n, e in self.inputs)
        pre = f"    {self.pre}\n" if self.pre else ""
        return (f"#[test]\nfn {self.name}__base() {{\n{base}    let r = bb({self.res});\n"
                f"    sink(r);\n}}\n\n"
                f"#[test]\nfn {self.name}__op() {{\n{op}    let _r = bb({self.res});\n{pre}"
                f"    sink({self.op});\n}}\n")


def results(t):
    o = t.other
    return {
        "T": lit(t, [1, 2, 3, 4]), "S": f"1_{t.S}", "u32": "1_u32", "usize": "1_usize",
        "B": blit(t, [1, 0, 1, 0]), "OT": f"Some({lit(t, [1, 2, 3, 4])})",
        "Ou32": "Some(1_u32)", "O": lit(o, [1, 2, 3, 4]), "OO": f"Some({lit(o, [1, 2, 3, 4])})",
    }


def lib_benches(t):
    """One bench (or one per branch) for every public function of `t` that computes something."""
    T, S, o, s = t.name, t.S, t.other, t.signed
    R = results(t)
    out = []

    def b(name, inputs, res, op, pre=""):
        out.append(Bench(name, [(n, e if isinstance(e, str) else lit(t, e)) for n, e in inputs],
                         R[res], op, pre))

    # typical operands (no zero in B: it is also a divisor)
    A = [3, -7, 11, -13] if s else [30, 7, 110, 13]
    Bv = [-5, 2, 9, 4] if s else [5, 2, 9, 4]
    LO, HI = [1, 2, 3, 4], [5, 6, 7, 8]
    POS, NEG = [30, 7, 110, 13], [-30, -7, -110, -13]
    D = [5, 2, 9, 4]
    ND = [-5, -2, -9, -4]

    b("select_true", [("m", blit(t, [1, 1, 1, 1])), ("a", A), ("b", Bv)], "T",
      f"{T}Trait::select(m, a, b)")
    b("select_false", [("m", blit(t, [0, 0, 0, 0])), ("a", A), ("b", Bv)], "T",
      f"{T}Trait::select(m, a, b)")
    b("dot", [("a", A), ("b", Bv)], "S", "a.dot(b)")
    b("dot_into_vec", [("a", A), ("b", Bv)], "T", "a.dot_into_vec(b)")
    if t.n == 3:
        # unsigned: a x b is orthogonal to a, so a non-negative result needs zero components
        b("cross", [("a", A if s else [3, 0, 0, 0]), ("b", Bv if s else [2, 5, 0, 0])], "T",
          "a.cross(b)")
    for f in ["min", "max"]:
        b(f"{f}_lhs", [("a", LO if f == "min" else HI), ("b", HI if f == "min" else LO)], "T",
          f"a.{f}(b)")
        b(f"{f}_rhs", [("a", HI if f == "min" else LO), ("b", LO if f == "min" else HI)], "T",
          f"a.{f}(b)")
    for name, v in [("below", [0, 0, 0, 0]), ("inside", [3, 4, 5, 6]), ("above", [9, 9, 9, 9])]:
        b(f"clamp_{name}", [("a", v), ("lo", [1, 2, 3, 4]), ("hi", [5, 6, 7, 8])], "T",
          "a.clamp(lo, hi)")
    asc, desc = [1, 2, 3, 4], [9, 8, 7, 6]
    for f, first, last in [("min_element", asc, desc), ("max_element", desc, asc),
                           ("min_position", asc, desc), ("max_position", desc, asc)]:
        res = "S" if f.endswith("element") else "usize"
        b(f"{f}_first", [("a", first)], res, f"a.{f}()")
        b(f"{f}_last", [("a", last)], res, f"a.{f}()")
    b("element_sum", [("a", A)], "S", "a.element_sum()")
    b("element_product", [("a", A)], "S", "a.element_product()")
    for f in ["cmpeq", "cmpne", "cmpge", "cmpgt", "cmple", "cmplt"]:
        b(f, [("a", A), ("b", Bv)], "B", f"a.{f}(b)")
    if s:
        for name, v in [("pos", POS), ("neg", NEG)]:
            b(f"abs_{name}", [("a", v)], "T", "a.abs()")
        for name, v in [("pos", POS), ("neg", NEG), ("zero", [0, 0, 0, 0])]:
            b(f"signum_{name}", [("a", v)], "T", "a.signum()")
        for name, v in [("pos", POS), ("neg", NEG)]:
            b(f"is_negative_bitmask_{name}", [("a", v)], "u32", "a.is_negative_bitmask()")
        b("is_negative_mask", [("a", A)], "B", "a.is_negative_mask()")
    b("length_squared", [("a", A)], "S", "a.length_squared()")
    if s:
        b("distance_squared", [("a", A), ("b", Bv)], "S", "a.distance_squared(b)")
        for f in ["div_euclid", "rem_euclid"]:
            b(f"{f}_pos", [("a", POS), ("b", D)], "T", f"a.{f}(b)")
            b(f"{f}_neg", [("a", NEG), ("b", ND)], "T", f"a.{f}(b)")
            b(f"{f}_fixup", [("a", NEG), ("b", D)], "T", f"a.{f}(b)")
    for f, res in [("manhattan_distance", "u32"), ("checked_manhattan_distance", "Ou32"),
                   ("chebyshev_distance", "u32")]:
        b(f"{f}_ge", [("a", HI), ("b", LO)], res, f"a.{f}(b)")
        b(f"{f}_lt", [("a", LO), ("b", HI)], res, f"a.{f}(b)")
    if s and t.n == 2:
        b("perp", [("a", A)], "T", "a.perp()")
        b("perp_dot", [("a", A), ("b", Bv)], "S", "a.perp_dot(b)")
        b("rotate", [("a", A), ("b", Bv)], "T", "a.rotate(b)")
    if s:
        b(f"as_{o.mod}_pos", [("a", POS)], "O", f"a.as_{o.mod}()")
        b(f"as_{o.mod}_neg", [("a", NEG)], "O", f"a.as_{o.mod}()")
    else:
        b(f"as_{o.mod}_low", [("a", POS)], "O", f"a.as_{o.mod}()")
        b(f"as_{o.mod}_high", [("a", [UMAX, UMAX - 1, UMAX - 2, UMAX - 3])], "O",
          f"a.as_{o.mod}()")
    b("try_into_some", [("a", POS)], "OO", f"TryInto::<{T}, {o.name}>::try_into(a)")
    b("try_into_none", [("a", (NEG if s else [UMAX] * 4))], "OO",
      f"TryInto::<{T}, {o.name}>::try_into(a)")

    # checked / wrapping / saturating: in range, and out of range on every component
    big = [MAX, MAX - 1, MAX - 2, MAX - 3] if s else [UMAX, UMAX - 1, UMAX - 2, UMAX - 3]
    small = [MIN, MIN + 1, MIN + 2, MIN + 3] if s else [0, 1, 2, 3]
    for kind, hit in [("checked", "none"), ("wrapping", "wraps"), ("saturating", "saturates")]:
        res = "OT" if kind == "checked" else "T"
        for op in ["add", "sub", "mul", "div"]:
            f = f"{kind}_{op}"
            b(f"{f}_inrange", [("a", A), ("b", Bv)], res, f"a.{f}(b)")
            if op == "div":
                if s:
                    b(f"{f}_{hit}", [("a", [MIN] * 4), ("b", [-1] * 4)], res, f"a.{f}(b)")
                elif kind == "checked":
                    b(f"{f}_{hit}", [("a", A), ("b", [0] * 4)], res, f"a.{f}(b)")
            else:
                x, y = {"add": (big, [9, 9, 9, 9]), "sub": (small, [9, 9, 9, 9]),
                        "mul": (big, [9, 9, 9, 9])}[op]
                b(f"{f}_{hit}", [("a", x), ("b", y)], res, f"a.{f}(b)")
        mixed = [("add", "unsigned"), ("sub", "unsigned")] if s else [("add", "signed")]
        for op, sfx in mixed:
            f = f"{kind}_{op}_{sfx}"
            rb = lit(o, [5, 2, 9, 4])
            b(f"{f}_inrange", [("a", POS), ("b", rb)], res, f"a.{f}(b)")
            x = big if op == "add" else small
            b(f"{f}_{hit}", [("a", x), ("b", lit(o, [9, 9, 9, 9]))], res, f"a.{f}(b)")

    # operators
    ops = [("add", "+"), ("sub", "-"), ("mul", "*"), ("div", "/"), ("rem", "%")]
    for f, sym in ops:
        if s and f in ("div", "rem"):
            b(f"{f}_pos", [("a", POS), ("b", D)], "T", f"a {sym} b")
            b(f"{f}_neg", [("a", NEG), ("b", ND)], "T", f"a {sym} b")
        else:
            b(f, [("a", A), ("b", Bv)], "T", f"a {sym} b")
    if s:
        b("neg", [("a", A)], "T", "-a")
    for f, sym in ops:
        sc = f"3_{S}"
        if s and f in ("div", "rem"):
            b(f"{f}_scalar_pos", [("a", POS), ("k", sc)], "T", f"a.{f}_scalar(k)")
            b(f"{f}_scalar_neg", [("a", NEG), ("k", f"-3_{S}")], "T", f"a.{f}_scalar(k)")
        else:
            b(f"{f}_scalar", [("a", A), ("k", sc)], "T", f"a.{f}_scalar(k)")
    for f, sym in ops:
        x = POS if s else A
        y = D if s else Bv
        b(f"{f}_assign", [("a", x), ("b", y)], "T", "a", pre=f"a {sym}= b;")
        b(f"{f}_assign_scalar", [("a", x), ("k", f"3_{S}")], "T", "a", pre=f"a {sym}= k;")

    # bits and shifts
    for f, sym in [("bitand", "&"), ("bitor", "|"), ("bitxor", "^")]:
        if s:
            b(f"{f}_pos", [("a", POS), ("b", D)], "T", f"a {sym} b")
            b(f"{f}_neg", [("a", NEG), ("b", ND)], "T", f"a {sym} b")
        else:
            b(f, [("a", A), ("b", Bv)], "T", f"a {sym} b")
    b("bitnot", [("a", A)], "T", "~a")
    for f in ["shl", "shr"]:
        if s:
            b(f"{f}_pos", [("a", POS), ("k", "5_u32")], "T", f"a.{f}(k)")
            b(f"{f}_neg", [("a", NEG), ("k", "5_u32")], "T", f"a.{f}(k)")
        else:
            b(f, [("a", A), ("k", "5_u32")], "T", f"a.{f}(k)")
    b("index_first", [("a", A), ("i", "0_usize")], "S", "a[i]")
    b("index_last", [("a", A), ("i", f"{t.n - 1}_usize")], "S", "a[i]")
    return out


# --------------------------------------------------------------------------------------------
# Alternatives
# --------------------------------------------------------------------------------------------
class Alt:
    """A losing (or reference) formulation: a free function of `benches::alt::<m>` and the
    benches that compare it with the library function `base` (same inputs, same names)."""

    def __init__(self, name, of, sig, body, note, inline="always", only=None):
        self.name, self.of, self.sig, self.body, self.note, self.inline, self.only = (
            name, of, sig, body, note, inline, only)


def to_free(body):
    return re.sub(r"\bSelf::", "", re.sub(r"\bself\b", "lhs", body))


def alts(t):
    T, S, n, o, s = t.name, t.S, t.n, t.other, t.signed
    out = []
    add = lambda *a, **k: out.append(Alt(*a, **k))

    # the other formulation of each fused-or-plain pair
    for op in g.fused_ops(t):
        fused = g.is_fused(t, op)
        unary = op in ("length_squared", "element_sum", "element_product")
        ret = {"cross": T, "rotate": T, "manhattan_distance": "u32"}.get(op, S)
        sig = f"(lhs: {T}) -> {ret}" if unary else f"(lhs: {T}, rhs: {T}) -> {ret}"
        add(f"{op}_{'plain' if fused else 'fused'}", op, sig,
            to_free(g.FUSED_BODIES[op](t, not fused)),
            ("The literal glam-rs expression with the panicking corelib operators." if fused else
             "Terms widened to `felt252`, accumulated, converted back once."))
    if n != 3:
        return out

    cw = t.cw
    bin_sig = f"(lhs: {T}, rhs: {T}) -> {T}"
    if s:
        add("dot_i64", "dot", f"(lhs: {T}, rhs: {T}) -> {S}",
            "let d: i64 = " + t.join(" + ", lambda c: f"lhs.{c}.wide_mul(rhs.{c})")
            + f";\nd.try_into().expect({g.ovf(t)})",
            "Products accumulated in `i64` (two range checks per addition) instead of `felt252`.")
        add("abs_lt", "abs", f"(lhs: {T}) -> {T}",
            cw(lambda c: f"if lhs.{c} < 0 {{ -lhs.{c} }} else {{ lhs.{c} }}"),
            "Sign test with `< 0` (an `i32_diff`) instead of the `i32 -> u32` downcast.")
        add("signum_gt_first", "signum", f"(lhs: {T}) -> {T}",
            cw(lambda c: f"if lhs.{c} > 0 {{ 1 }} else if lhs.{c} < 0 {{ -1 }} else {{ 0 }}"),
            "Two ordering comparisons, zero last.")
        add("signum_zero_first", "signum", f"(lhs: {T}) -> {T}",
            cw(lambda c: f"if lhs.{c} == 0 {{ 0 }} else if lhs.{c} < 0 {{ -1 }} else {{ 1 }}"),
            "Zero first, then `< 0` (an `i32_diff`) instead of the `i32 -> u32` downcast.")
        add("is_negative_bitmask_felt", "is_negative_bitmask", f"(lhs: {T}) -> u32",
            "let m: felt252 = " + " + ".join(
                f"(if lhs.{c} < 0 {{ {1 << i} }} else {{ 0 }})" for i, c in enumerate(t.c))
            + ";\nm.try_into().unwrap()",
            "Weighted `felt252` sum of the sign tests instead of the `BVec3::bitmask` tree.")
        add("is_negative_mask_try_into", "is_negative_mask", f"(lhs: {T}) -> {t.B}",
            cw(lambda c: f"TryInto::<i32, u32>::try_into(lhs.{c}).is_none()", t.B),
            "The `i32 -> u32` downcast as the sign test instead of `< 0`.")
        add("cmplt_felt", "cmplt", f"(lhs: {T}, rhs: {T}) -> {t.B}",
            cw(lambda c: f"lt_felt(lhs.{c}, rhs.{c})", t.B),
            "`lhs - rhs` in `felt252`, then a `u32` downcast as the sign test.")
        add("manhattan_distance_abs_diff_felt", "manhattan_distance",
            f"(lhs: {T}, rhs: {T}) -> u32",
            t.join(" + ", lambda c: f"abs_diff_felt(lhs.{c}, rhs.{c})"),
            "`abs_diff` negating the wrapped `i32_diff` error through `felt252` instead of a "
            "second `i32_diff`.")
        add(f"as_{o.mod}_felt", f"as_{o.mod}", f"(lhs: {T}) -> {o.name}",
            cw(lambda c: f"as_u32_felt(lhs.{c})", o.name),
            "Wrapping cast with a sign test and a `felt252` offset instead of `i32_diff(a, 0)`.")
        add(f"as_{o.mod}_try_first", f"as_{o.mod}", f"(lhs: {T}) -> {o.name}",
            cw(lambda c: f"as_u32_try_first(lhs.{c})", o.name),
            "Wrapping cast trying the checked downcast first, `i32_diff(a, 0)` on failure.")
        add(f"as_{o.mod}_checked", f"as_{o.mod}", f"(lhs: {T}) -> {o.name}",
            cw(lambda c: f"lhs.{c}.try_into().expect('IVec3: cast')", o.name),
            "Reference: the panicking checked cast (different semantics, not glam's).",
            only=["pos"])
        add("div_euclid_divrem", "div_euclid", bin_sig,
            cw(lambda c: f"div_euclid_divrem_i32(lhs.{c}, rhs.{c})"),
            "The corelib signed `DivRem`, then the fix-up of Rust's `i32::div_euclid`.")
        add("div_euclid_call", "div_euclid", bin_sig,
            cw(lambda c: f"div_euclid_call_i32(lhs.{c}, rhs.{c})"),
            "The library formulation with a non-inlined scalar helper (3 panicking calls).")
        add("rem_euclid_divrem", "rem_euclid", bin_sig,
            cw(lambda c: f"rem_euclid_divrem_i32(lhs.{c}, rhs.{c})"),
            "The corelib signed `DivRem`, then the fix-up of Rust's `i32::rem_euclid`.")
        add("wrapping_mul_nofast", "wrapping_mul", bin_sig,
            cw(lambda c: f"wrapping_mul_nofast_i32(lhs.{c}, rhs.{c})"),
            "Always reduces the 64-bit product (no in-range fast path).")
        add("wrapping_mul_i64", "wrapping_mul", bin_sig,
            cw(lambda c: f"wrapping_mul_i64_i32(lhs.{c}, rhs.{c})"),
            "No fast path, and the product is biased with `i64_diff` instead of `felt252`.")
        add("shr_div_floor", "shr", f"(lhs: {T}, rhs: u32) -> {T}",
            "let p: i64 = pow2(rhs).into();\n"
            "let p: NonZero<i64> = p.try_into().unwrap();\n"
            + cw(lambda c: f"shr_div_floor_i32(lhs.{c}, p)"),
            "Signed `DivRem` and a floor fix-up instead of the biased unsigned division.")
    else:
        add("dot_u64", "dot", f"(lhs: {T}, rhs: {T}) -> {S}",
            "let d: u64 = " + t.join(" + ", lambda c: f"lhs.{c}.wide_mul(rhs.{c})")
            + f";\nd.try_into().expect({g.ovf(t)})",
            "Products accumulated in `u64` (one range check per addition) instead of `felt252`.")
        add("manhattan_distance_cmp", "manhattan_distance", f"(lhs: {T}, rhs: {T}) -> u32",
            "let d: felt252 = "
            + t.join(" + ", lambda c: f"abs_diff_cmp(lhs.{c}, rhs.{c}).into()")
            + f";\nd.try_into().expect({g.ovf(t)})",
            "`abs_diff` through a comparison and a subtraction instead of `checked_sub`.")
        add("checked_mul_core", "checked_mul", f"(lhs: {T}, rhs: {T}) -> Option<{T}>",
            g.option_cw(t, lambda c: f"lhs.{c}.checked_mul(rhs.{c})"),
            "The corelib `CheckedMul` (overflowing-based).")
        add("saturating_mul_core", "saturating_mul", bin_sig,
            cw(lambda c: f"lhs.{c}.saturating_mul(rhs.{c})"),
            "The corelib `SaturatingMul` (overflowing-based).")
        add("wrapping_mul_divrem", "wrapping_mul", bin_sig,
            cw(lambda c: f"wrapping_mul_divrem_u32(lhs.{c}, rhs.{c})"),
            "`wide_mul`, then the low half through `DivRem` by `2^32`.")
        add("wrapping_mul_fast", "wrapping_mul", bin_sig,
            cw(lambda c: f"wrapping_mul_fast_u32(lhs.{c}, rhs.{c})"),
            "In-range fast path (`wide_mul` and a downcast), corelib `WrappingMul` otherwise.")
        add(f"as_{o.mod}_not", f"as_{o.mod}", f"(lhs: {T}) -> {o.name}",
            cw(lambda c: f"as_i32_not(lhs.{c})", o.name),
            "Wrapping cast computing `-1 - !a` in integers instead of a `felt252` offset.")
        add(f"as_{o.mod}_checked", f"as_{o.mod}", f"(lhs: {T}) -> {o.name}",
            cw(lambda c: f"lhs.{c}.try_into().expect('UVec3: cast')", o.name),
            "Reference: the panicking checked cast (different semantics, not glam's).",
            only=["low"])
        add("shl_pow", "shl", f"(lhs: {T}, rhs: u32) -> {T}",
            "assert(rhs < 32, 'UVec3: shift overflow');\n"
            "let p: u64 = core::num::traits::Pow::pow(2_u64, rhs);\n"
            "let p: u32 = p.try_into().unwrap();\n" + cw(lambda c: f"shl_u32(lhs.{c}, p)"),
            "Reference: the runtime `pow(2, n)` that the jump table replaces.")
    shl = f"shl_{S}"
    add("shl_table", "shl", f"(lhs: {T}, rhs: u32) -> {T}",
        "let p: u32 = *POW2.span()[rhs];\n" + cw(lambda c: f"{shl}(lhs.{c}, p)"),
        "Power of two from a `const` array instead of a `match` jump table.")
    add("shl_call", "shl", f"(lhs: {T}, rhs: u32) -> {T}",
        "let p = pow2(rhs);\n" + cw(lambda c: f"{shl}(lhs.{c}, p)"),
        "The library formulation, not inlined (one panicking call).", inline="never")
    add("min_core", "min", bin_sig,
        cw(lambda c: f"core::cmp::min(lhs.{c}, rhs.{c})"), "The generic `core::cmp::min`.")
    add("clamp_min_max", "clamp", f"(lhs: {T}, min: {T}, max: {T}) -> {T}",
        "let v = " + cw(lambda c: f"if lhs.{c} > min.{c} {{ lhs.{c} }} else {{ min.{c} }}")
        + ";\n" + cw(lambda c: f"if v.{c} < max.{c} {{ v.{c} }} else {{ max.{c} }}"),
        "The glam-rs `self.max(min).min(max)`: always two comparisons per component.")
    add("select_match", "select", f"(mask: {t.B}, lhs: {T}, rhs: {T}) -> {T}",
        cw(lambda c: f"match mask.{c} {{ true => lhs.{c}, false => rhs.{c} }}"),
        "`match` on the mask element instead of `if`.")
    return out


ALT_HELPERS = {
    "POW2": """
const POW2: [u32; 32] = [
    0x1, 0x2, 0x4, 0x8, 0x10, 0x20, 0x40, 0x80, 0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000,
    0x4000, 0x8000, 0x10000, 0x20000, 0x40000, 0x80000, 0x100000, 0x200000, 0x400000, 0x800000,
    0x1000000, 0x2000000, 0x4000000, 0x8000000, 0x10000000, 0x20000000, 0x40000000, 0x80000000,
];
""",
    "lt_felt": """
#[inline(always)]
fn lt_felt(a: i32, b: i32) -> bool {
    let d: felt252 = a.into() - b.into();
    TryInto::<felt252, u32>::try_into(d).is_none()
}
""",
    "abs_diff_felt": """
#[inline(always)]
fn abs_diff_felt(a: i32, b: i32) -> u32 {
    match i32_diff(a, b) {
        Ok(d) => d,
        Err(e) => {
            let e: felt252 = e.into();
            (0x100000000 - e).try_into().unwrap()
        },
    }
}
""",
    "as_u32_felt": """
#[inline(always)]
fn as_u32_felt(a: i32) -> u32 {
    if a < 0 {
        let f: felt252 = a.into();
        (f + 0x100000000).try_into().unwrap()
    } else {
        a.try_into().unwrap()
    }
}
""",
    "as_u32_try_first": """
#[inline(always)]
fn as_u32_try_first(a: i32) -> u32 {
    match a.try_into() {
        Some(v) => v,
        None => match i32_diff(a, 0) {
            Ok(v) | Err(v) => v,
        },
    }
}
""",
    "as_i32_not": """
#[inline(always)]
fn as_i32_not(a: u32) -> i32 {
    match a.try_into() {
        Some(v) => v,
        None => {
            let n: i32 = (~a).try_into().unwrap();
            -1 - n
        },
    }
}
""",
    "div_euclid_divrem_i32": """
#[inline(always)]
fn div_euclid_divrem_i32(a: i32, b: i32) -> i32 {
    let (q, r) = DivRem::div_rem(a, b.try_into().expect('Division by 0'));
    if r < 0 {
        if b > 0 {
            q - 1
        } else {
            q + 1
        }
    } else {
        q
    }
}
""",
    "rem_euclid_divrem_i32": """
#[inline(always)]
fn rem_euclid_divrem_i32(a: i32, b: i32) -> i32 {
    let (_, r) = DivRem::div_rem(a, b.try_into().expect('Division by 0'));
    if r < 0 {
        if b < 0 {
            r - b
        } else {
            r + b
        }
    } else {
        r
    }
}
""",
    "div_euclid_call_i32": """
#[inline(never)]
fn div_euclid_call_i32(a: i32, b: i32) -> i32 {
    div_euclid_i32(a, b)
}
""",
    "wrapping_mul_nofast_i32": """
#[inline(always)]
fn wrapping_mul_nofast_i32(a: i32, b: i32) -> i32 {
    let p: felt252 = a.wide_mul(b).into();
    let p: u64 = (p + 0x8000000000000000).try_into().unwrap();
    let (_, lo) = DivRem::div_rem(p, 0x100000000);
    u32_as_i32(lo.try_into().unwrap())
}
""",
    "wrapping_mul_i64_i32": """
#[inline(always)]
fn wrapping_mul_i64_i32(a: i32, b: i32) -> i32 {
    match i64_diff(a.wide_mul(b), -0x8000000000000000) {
        Ok(p) |
        Err(p) => {
            let (_, lo) = DivRem::div_rem(p, 0x100000000);
            u32_as_i32(lo.try_into().unwrap())
        },
    }
}
""",
    "shr_div_floor_i32": """
#[inline(always)]
fn shr_div_floor_i32(a: i32, p: NonZero<i64>) -> i32 {
    let (q, r) = DivRem::div_rem(a.into(), p);
    let q = if r < 0 {
        q - 1
    } else {
        q
    };
    q.try_into().unwrap()
}
""",
    "abs_diff_cmp": """
#[inline(always)]
fn abs_diff_cmp(a: u32, b: u32) -> u32 {
    if a < b {
        b - a
    } else {
        a - b
    }
}
""",
    "wrapping_mul_divrem_u32": """
#[inline(always)]
fn wrapping_mul_divrem_u32(a: u32, b: u32) -> u32 {
    let (_, lo) = DivRem::div_rem(a.wide_mul(b), 0x100000000);
    lo.try_into().unwrap()
}
""",
    "wrapping_mul_fast_u32": """
#[inline(always)]
fn wrapping_mul_fast_u32(a: u32, b: u32) -> u32 {
    match a.wide_mul(b).try_into() {
        Some(v) => v,
        None => a.wrapping_mul(b),
    }
}
""",
}


def gen_alt(t):
    items = alts(t)
    fns = []
    for a in items:
        attr = f"#[inline({a.inline})]\n" if a.inline else ""
        fns.append(f"/// Alternative to `{t.name}::{a.of}`. {a.note}\n{attr}"
                   f"pub fn {a.name}{a.sig} {{\n{g.indent(a.body, 4)}\n}}\n")
    code = "\n".join(fns)
    helpers, seen, todo = [], set(), [code]
    while todo:
        text = todo.pop()
        for h, src in ALT_HELPERS.items():
            if h not in seen and (h + "(" in text or (h == "POW2" and "POW2." in text)):
                seen.add(h)
                helpers.append(g.helper_src(src))
                todo.append(src)
    code += "".join(helpers)
    code += "".join(g.helper_src(g.HELPERS[h]) for h in g.used_helpers(code)
                    if h not in ALT_HELPERS)
    code = code.replace("@T@", t.name)

    uses = []
    if "wide_mul(" in code:
        uses.append("use core::num::traits::WideMul;")
    nt = [x for x in ["CheckedSub", "CheckedMul", "WrappingMul", "SaturatingMul"]
          if "." + g.camel_to_snake(x) + "(" in code]
    if nt:
        uses.append("use core::num::traits::{" + ", ".join(nt) + "};")
    diffs = [d for d in ["i32_diff", "i64_diff"] if d + "(" in code]
    if diffs:
        uses.append("use core::integer::{" + ", ".join(diffs) + "};" if len(diffs) > 1
                    else f"use core::integer::{diffs[0]};")
    if "DivRem::" in code:
        uses.append("use core::traits::DivRem;")
    names = [t.name] + ([t.other.name] if t.other.name + " {" in code else [])
    uses.append(f"use glam::{t.mod}::{t.name};")
    if len(names) > 1:
        uses.append(f"use glam::{t.other.mod}::{t.other.name};")
    if t.B in code:
        uses.append(f"use glam::{t.bmod}::{t.B};")
    return (f"{g.HEADER}//! Alternative implementations benchmarked against `glam::{t.mod}` "
            f"(the `alt_*` rows of\n//! `gas/{t.mod}.snap`). The library ships the cheapest "
            "formulation; the others stay here so that\n//! the comparison is reproducible "
            "across compiler upgrades.\n\n" + "\n".join(uses) + "\n\n" + code)


def alt_benches(t, lib):
    """Every alternative runs on the inputs of the library bench(es) it competes with."""
    out = []
    for a in alts(t):
        for bench in lib:
            base = bench.name
            if base != a.of and not (base.startswith(a.of + "_") and base[len(a.of) + 1:] in
                                     VARIANTS):
                continue
            suffix = base[len(a.of):]
            if a.only and suffix[1:] not in a.only:
                continue
            names = [n for n, _ in bench.inputs]
            out.append(Bench(f"alt_{a.name}{suffix}", bench.inputs, bench.res,
                             f"alt::{a.name}({', '.join(names)})"))
    return out


VARIANTS = {"pos", "neg", "zero", "fixup", "ge", "lt", "low", "high", "inrange", "wraps", "none",
            "saturates", "lhs", "rhs", "below", "inside", "above", "true", "false", "first",
            "last", "some"}


def gen_bench(t):
    lib = lib_benches(t)
    benches = lib + alt_benches(t, lib)
    body = "\n".join(x.emit() for x in benches)
    uses = ["use benches::alt::" + t.mod + " as alt;"] if "alt::" in body else []
    uses.append("use benches::harness::{bb, sink};")
    uses.append(f"use glam::{t.bmod}::{t.B}Trait;")
    uses.append(f"use glam::{t.mod}::{t.name}Trait;")
    uses.append(f"use glam::{t.other.mod}::{t.other.name}Trait;")
    if f"TryInto::<{t.name}, {t.other.name}>" in body:
        uses.append(f"use glam::{t.mod}::{t.name};")
        uses.append(f"use glam::{t.other.mod}::{t.other.name};")
    return (f"{g.HEADER}//! Gas benchmarks of `glam::{t.mod}` and of the alternatives kept in "
            f"`benches::alt::{t.mod}`\n//! (the `alt_*` benches).\n//!\n"
            "//! Sierra gas is charged at the most expensive sibling branch, but steps depend "
            "on the path\n//! taken: branching functions are measured on one input per branch "
            "(`_pos` / `_neg`,\n//! `_inrange` / `_wraps`, `_first` / `_last`, ...).\n\n"
            + "\n".join(uses) + "\n\n" + body)
