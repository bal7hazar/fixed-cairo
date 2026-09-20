#!/usr/bin/env python3
"""Transcendentals: coefficient fitting, Cairo code generation, bit-exact Python mirrors, error sweeps.

Outputs
  src/trig_gen.cairo      constants, tables, Horner evaluators, floor-shift helpers (generated)
  tests/trig.cairo        cost benchmarks (X__base / X__op) + bit-exact checks against the mirrors
  results/trig_errors.md  max abs error of every variant vs math.* (float64 reference)

The hand-written algorithms live in src/trig.cairo (ours) and src/cubit_trig.cairo (vendored).
"""
import math
import os
import re

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
ONE = 1 << 32
HP = 6746518852  # round(pi/2 * 2^32), same constant as cubit
QP = HP // 2  # pi/4
PI_RAW = 13493037705
TWO_PI_RAW = 26986075409
LUT_K = 22  # sin/cos table step = 2^22 raw units = 2^-10 rad
ATAN_SEG_BITS = 29  # 8 segments on [0, 1]
ATAN_DEG = 5
SIN_DEG, COS_DEG = 4, 5  # degree in u = z^2
ACOS_DEG = 10
M = -(-(1 << 63) // (8 * QP))
BIAS = 8 * QP * M


# --------------------------------------------------------------------------- fitting
def cheb_fit(f, lo, hi, deg, n=4001):
    """Near-minimax polynomial fit (least squares on Chebyshev nodes), monomial coeffs, low->high."""
    k = np.arange(n)
    t = np.cos(np.pi * (k + 0.5) / n)
    x = 0.5 * (hi - lo) * t + 0.5 * (hi + lo)
    c = np.polynomial.chebyshev.chebfit(t, f(x), deg)
    p = np.polynomial.chebyshev.cheb2poly(c)
    # substitute t = (2x - hi - lo) / (hi - lo)
    a, b = 2.0 / (hi - lo), -(hi + lo) / (hi - lo)
    res = np.zeros(deg + 1)
    basis = np.array([1.0])
    for i in range(deg + 1):
        res[: len(basis)] += p[i] * basis
        basis = np.convolve(basis, [b, a])
    return res


def q60(c):
    return [int(round(v * (1 << 60))) for v in c]


def fit_all(sin_deg=SIN_DEG, cos_deg=COS_DEG, atan_deg=ATAN_DEG, acos_deg=ACOS_DEG):
    umax = (math.pi / 4) ** 2 * 1.0001
    sinc = lambda u: np.where(u < 1e-12, 1 - u / 6, np.sin(np.sqrt(np.maximum(u, 1e-300))) / np.sqrt(np.maximum(u, 1e-300)))
    cosu = lambda u: np.cos(np.sqrt(np.maximum(u, 0)))
    C = {"sin": q60(cheb_fit(sinc, 0, umax, sin_deg)), "cos": q60(cheb_fit(cosu, 0, umax, cos_deg))}
    w = 1.0 / (1 << (32 - ATAN_SEG_BITS))
    C["atan"] = [q60(cheb_fit(lambda t, z0=i * w: np.arctan(z0 + t), 0, w, atan_deg)) for i in range(1 << (32 - ATAN_SEG_BITS))]
    g = lambda x: np.where(x > 1 - 1e-9, math.sqrt(2) * (1 + (1 - x) / 12), np.arccos(np.minimum(x, 1)) / np.sqrt(np.maximum(1 - x, 1e-300)))
    C["acos"] = q60(cheb_fit(g, 0, 1, acos_deg))
    return C


COEF = fit_all()
SIN_T = [int(round(math.sin(i * (1 << LUT_K) / ONE) * ONE)) for i in range((QP >> LUT_K) + 2)]
COS_T = [int(round(math.cos(i * (1 << LUT_K) / ONE) * ONE)) for i in range((QP >> LUT_K) + 2)]


# --------------------------------------------------------------------------- mirrors (ours)
def shr(acc, k):
    assert -(1 << 127) <= acc < (1 << 127), "accumulator overflow"
    return acc >> k


def horner(cs, x, k):
    acc = cs[-1]
    for c in reversed(cs[:-1]):
        acc = shr(acc * x, k) + c
    return acc


def reduce8(x):
    kq, r = divmod(x + BIAS, QP)
    return kq % 8, r


def _sincos_poly(z, want_cos, C):
    u = z * z
    if want_cos:
        return shr(horner(C["cos"], u, 64), 28)
    return shr(z * horner(C["sin"], u, 64), 60)


def sin_poly(x, C=COEF):
    o, r = reduce8(x)
    z = r if o % 2 == 0 else QP - r
    v = _sincos_poly(z, o in (1, 2, 5, 6), C)
    return -v if o >= 4 else v


def cos_poly(x, C=COEF):
    o, r = reduce8(x)
    z = r if o % 2 == 0 else QP - r
    v = _sincos_poly(z, o not in (1, 2, 5, 6), C)
    return -v if o in (2, 3, 4, 5) else v


def _lut(table, z, k=LUT_K):
    i, f = divmod(z, 1 << k)
    return table[i] + shr((table[i + 1] - table[i]) * f, k)


def sin_lut(x):
    o, r = reduce8(x)
    z = r if o % 2 == 0 else QP - r
    v = _lut(COS_T if o in (1, 2, 5, 6) else SIN_T, z)
    return -v if o >= 4 else v


def atan2_poly(y, x, C=COEF):
    ax, ay = abs(x), abs(y)
    mn, mx, swap = (ax, ay, True) if ay > ax else (ay, ax, False)
    if mx == 0:
        return 0
    z = (mn << 32) // mx
    idx, t = divmod(z, 1 << ATAN_SEG_BITS)
    a = shr(horner(C["atan"][idx], t, 32), 28) if idx < len(C["atan"]) else QP
    if swap:
        a = HP - a
    if x < 0:
        a = PI_RAW - a
    return -a if y < 0 else a


def acos_poly(x, C=COEF):
    ax = abs(x)
    assert ax <= ONE
    s = math.isqrt((ONE - ax) << 32)
    r = shr(s * horner(C["acos"], ax, 32), 60)
    return PI_RAW - r if x < 0 else r


# --------------------------------------------------------------------------- mirrors (cubit, sign-magnitude, truncation)
def fmul(a, b):
    s = -1 if (a < 0) != (b < 0) else 1
    return s * ((abs(a) * abs(b)) >> 32)


def fdiv(a, b):
    s = -1 if (a < 0) != (b < 0) else 1
    return s * ((abs(a) << 32) // abs(b))


def parse_lut(fn):
    src = open(os.path.join(ROOT, "src", "cubit_lut.cairo")).read()
    body = src[src.index(f"pub fn {fn}(a: u64)"):]
    nxt = body.find("\npub fn ", 10)
    body = body[: nxt if nxt > 0 else len(body)]
    step = int(re.search(r"let slot = a / (\d+);", body).group(1))
    slots = {int(m.group(1)): tuple(map(int, m.group(2, 3, 4)))
             for m in re.finditer(r"if slot == (\d+) \{\s*return \((\d+), (\d+), (\d+)\);", body)}
    default = tuple(map(int, re.findall(r"return \((\d+), (\d+), (\d+)\);", body)[-1]))
    return step, slots, default


SIN_LUT, ATAN_LUT = parse_lut("sin"), parse_lut("atan")


def cubit_sin(x):
    a1 = abs(x) % TWO_PI_RAW
    whole, part = divmod(a1, PI_RAW)
    acc = ONE
    for i in range(7, -1, -1):
        div = (2 * i + 2) * (2 * i + 3)
        acc = ONE - fdiv(fmul(fmul(part, part), acc), div * ONE)
    res = abs(fmul(part, acc))
    neg = (x < 0) ^ (whole == 1)
    return -res if neg else res


def cubit_sin_fast(x):
    a1 = abs(x) % TWO_PI_RAW
    whole, part = divmod(a1, PI_RAW)
    if part >= HP:
        part = PI_RAW - part
    step, slots, default = SIN_LUT
    start, low, high = slots.get(part // step, default)
    res = abs(fmul(fdiv(part - start, 26353589), high - low) + low)
    neg = (x < 0) ^ (whole == 1)
    return -res if neg else res


def _cubit_atan(x, fast):
    at, shift, invert = abs(x), False, False
    if at > ONE:
        at, invert = fdiv(ONE, at), True
    if at > 3006477107:
        s33 = 2479700525
        at, shift = fdiv(at - s33, ONE + fmul(at, s33)), True
    if fast:
        step, slots, default = ATAN_LUT
        start, low, high = slots.get(at // step, default)
        res = fmul(fdiv(at - start, 30064771), high - low) + low
    else:
        res = 0
        for c in [-7866091, -200950905, 834081193, -1125283850, 187746747, 816293925, 5897657, -1432117161, 17657, 4294967059]:
            res = fmul(res + c, at)
    if shift:
        res += 2248839617
    if invert:
        res -= HP
    return -abs(res) if x < 0 else abs(res)


def cubit_acos(x, fast=False):
    arg = math.isqrt((ONE - fmul(x, x)) << 32)
    asin = HP if arg == ONE else _cubit_atan(fdiv(arg, math.isqrt((ONE - fmul(arg, arg)) << 32)), fast)
    return PI_RAW - asin if x < 0 else asin


# --------------------------------------------------------------------------- error sweeps
def sweep(fn, ref, xs):
    worst, at = 0.0, None
    for x in xs:
        try:
            e = abs(fn(x) / ONE - ref(x))
        except ZeroDivisionError:
            continue
        if e > worst:
            worst, at = e, x
    return worst, at


def raws(lo, hi, n):
    return [int(round((lo + (hi - lo) * i / (n - 1)) * ONE)) for i in range(n)]


def error_report():
    rows = []
    ang = raws(-7.0, 7.0, 40001) + raws(-1000.0, 1000.0, 4001)
    small = raws(-7.0, 7.0, 40001)
    f = lambda v: v / ONE
    rows.append(("sin: cubit `sin` (Taylor recursion, 8 terms)", *sweep(cubit_sin, lambda x: math.sin(f(x)), small)))
    rows.append(("sin: cubit `sin_fast` (if-tree LUT, 256 slots + lerp)", *sweep(cubit_sin_fast, lambda x: math.sin(f(x)), small)))
    for sd, cd in [(3, 4), (4, 5), (5, 6)]:
        C = fit_all(sin_deg=sd, cos_deg=cd)
        tag = " **(benchmarked)**" if (sd, cd) == (SIN_DEG, COS_DEG) else ""
        rows.append((f"sin: ours, Horner polynomial, sin deg {2 * sd + 1} / cos deg {2 * cd}{tag}, |x| <= 7",
                     *sweep(lambda x: sin_poly(x, C), lambda x: math.sin(f(x)), small)))
        rows.append((f"cos: ours, Horner polynomial, sin deg {2 * sd + 1} / cos deg {2 * cd}{tag}, |x| <= 7",
                     *sweep(lambda x: cos_poly(x, C), lambda x: math.cos(f(x)), small)))
    rows.append(("sin: ours, Horner polynomial (benchmarked), |x| <= 1000 (phase error of the Q32.32 pi/4 constant grows with |x|)",
                 *sweep(sin_poly, lambda x: math.sin(f(x)), ang)))
    global SIN_T, COS_T
    keep = (SIN_T, COS_T)
    for k in (24, 23, 22, 21, 20):
        SIN_T = [int(round(math.sin(i * (1 << k) / ONE) * ONE)) for i in range((QP >> k) + 2)]
        COS_T = [int(round(math.cos(i * (1 << k) / ONE) * ONE)) for i in range((QP >> k) + 2)]
        def fn(x, k=k):
            o, r = reduce8(x)
            z = r if o % 2 == 0 else QP - r
            v = _lut(COS_T if o in (1, 2, 5, 6) else SIN_T, z, k)
            return -v if o >= 4 else v
        tag = " **(benchmarked)**" if k == LUT_K else ""
        rows.append((f"sin: ours, const-array LUT + lerp, step 2^{k} raw = 2^-{32 - k} rad, 2 x {len(SIN_T)} entries{tag}",
                     *sweep(fn, lambda x: math.sin(f(x)), small)))
    SIN_T, COS_T = keep
    zs = raws(-20.0, 20.0, 40001)
    rows.append(("atan: cubit `atan` (2 range reductions + degree-10 Horner)", *sweep(lambda x: _cubit_atan(x, False), lambda x: math.atan(f(x)), zs)))
    rows.append(("atan: cubit `atan_fast` (99-way if-chain LUT + lerp)", *sweep(lambda x: _cubit_atan(x, True), lambda x: math.atan(f(x)), zs)))
    pts = [(int(round(r * math.sin(t) * ONE)), int(round(r * math.cos(t) * ONE)))
           for r in (0.001, 0.37, 1.0, 12.5, 30000.0) for t in np.linspace(-math.pi, math.pi, 8001)]
    for d in (4, 5, 6):
        C = fit_all(atan_deg=d)
        tag = " **(benchmarked)**" if d == ATAN_DEG else ""
        worst = max((abs(atan2_poly(y, x, C) / ONE - math.atan2(y, x)), (y, x)) for y, x in pts if (x, y) != (0, 0) and not (x < 0 and y == 0))
        rows.append((f"atan2: ours, 1 division + 8 segments x degree-{d} Horner{tag}", worst[0], worst[1]))
    xs = raws(-1.0, 1.0, 40001)
    rows.append(("acos: cubit `acos` (sqrt + asin -> div + atan)", *sweep(cubit_acos, lambda x: math.acos(max(-1.0, min(1.0, f(x)))), xs)))
    rows.append(("acos: cubit `acos_fast`", *sweep(lambda x: cubit_acos(x, True), lambda x: math.acos(max(-1.0, min(1.0, f(x)))), xs)))
    for d in (7, 10, 12):
        C = fit_all(acos_deg=d)
        tag = " **(benchmarked)**" if d == ACOS_DEG else ""
        rows.append((f"acos: ours, sqrt(1-|x|) * P(|x|), degree {d}{tag}", *sweep(lambda x: acos_poly(x, C), lambda x: math.acos(f(x)), xs)))
    with open(os.path.join(ROOT, "results", "trig_errors.md"), "w") as fh:
        fh.write("| function / variant | max abs error | in Q32.32 ulp (2^-32) | worst input (raw) |\n|---|---:|---:|---|\n")
        for name, err, at in rows:
            fh.write(f"| {name} | {err:.3e} | {err * ONE:.1f} | `{at}` |\n")
    return rows


# --------------------------------------------------------------------------- Cairo generation
def h(v):
    return ("-" if v < 0 else "") + hex(abs(v))


def bi(lo, hi):
    return f"BoundedInt<{h(lo)}, {h(hi)}>"


def horner_fn(name, cs, shift_fn, doc):
    lines = [f"/// {doc}", "#[inline(always)]", f"pub fn {name}(x: felt252) -> felt252 {{", f"    let acc: felt252 = {h(cs[-1])};"]
    for c in reversed(cs[:-1]):
        lines.append(f"    let acc = {shift_fn}(acc * x) + {h(c)};")
    lines += ["    acc", "}"]
    return "\n".join(lines)


def gen_cairo():
    out = ["// GENERATED by scripts/gen_trig.py -- do not edit by hand.",
           "#[feature(\"bounded-int-utils\")]",
           "use core::internal::bounded_int::{self, AddHelper, BoundedInt, DivRemHelper, SubHelper, UnitInt, upcast};",
           "use crate::fixed::i64b_types::{AddI128Bias, U128B};",
           "",
           f"pub const HALF_PI: felt252 = {h(HP)};\npub const QUARTER_PI: felt252 = {h(QP)};\npub const PI: felt252 = {h(PI_RAW)};",
           f"pub const LUT_STEP_BITS: u32 = {LUT_K};", ""]
    # floor shifts of a signed felt accumulator
    for k in sorted({LUT_K, 28, 60, 64}):
        qmax = (1 << (128 - k)) - 1
        off = 1 << (127 - k)
        out.append(f"pub type Shr{k}Q = {bi(0, qmax)};")
        out.append(f"impl DivRemShr{k} of DivRemHelper<U128B, UnitInt<{h(1 << k)}>> {{\n    type DivT = Shr{k}Q;\n    type RemT = {bi(0, (1 << k) - 1)};\n}}")
        out.append(f"impl SubShr{k} of SubHelper<Shr{k}Q, UnitInt<{h(off)}>> {{\n    type Result = {bi(-off, qmax - off)};\n}}")
        out.append(
            f"/// floor(acc / 2^{k}) for a signed accumulator stored in a felt252; panics if |acc| >= 2^127.\n"
            f"#[inline(always)]\npub fn shr{k}(acc: felt252) -> felt252 {{\n"
            f"    let v: i128 = acc.try_into().expect('fixed overflow');\n"
            f"    let o = bounded_int::add::<_, UnitInt<{h(1 << 127)}>>(v, {h(1 << 127)});\n"
            f"    let (q, _r) = bounded_int::div_rem::<_, UnitInt<{h(1 << k)}>>(o, {h(1 << k)});\n"
            f"    upcast(bounded_int::sub::<_, UnitInt<{h(off)}>>(q, {h(off)}))\n}}\n")
    # octant reduction
    lo, hi = BIAS - (1 << 63), BIAS + (1 << 63) - 1
    out.append(f"// ---- octant reduction: (x + BIAS) divmod (pi/4), then divmod 8. BIAS = 8 * (pi/4) * {M}")
    out.append(f"pub type Biased = {bi(lo, hi)};\npub type OctCount = {bi(lo // QP, hi // QP)};\npub type OctRem = {bi(0, QP - 1)};")
    out.append(f"pub type Oct = {bi(0, 7)};\npub type ZT = {bi(0, QP)};")
    out.append(f"impl AddBias of AddHelper<i64, UnitInt<{h(BIAS)}>> {{\n    type Result = Biased;\n}}")
    out.append(f"impl DivRemQP of DivRemHelper<Biased, UnitInt<{h(QP)}>> {{\n    type DivT = OctCount;\n    type RemT = OctRem;\n}}")
    out.append(f"impl DivRem8 of DivRemHelper<OctCount, UnitInt<8>> {{\n    type DivT = {bi((lo // QP) // 8, (hi // QP) // 8)};\n    type RemT = Oct;\n}}")
    out.append(f"impl SubQPRem of SubHelper<UnitInt<{h(QP)}>, OctRem> {{\n    type Result = {bi(1, QP)};\n}}")
    out.append(f"pub type LutIdx = {bi(0, QP >> LUT_K)};\npub type LutFrac = {bi(0, (1 << LUT_K) - 1)};")
    out.append(f"impl DivRemLut of DivRemHelper<ZT, UnitInt<{h(1 << LUT_K)}>> {{\n    type DivT = LutIdx;\n    type RemT = LutFrac;\n}}")
    out.append(f"impl AddIdxOne of AddHelper<LutIdx, UnitInt<1>> {{\n    type Result = {bi(1, (QP >> LUT_K) + 1)};\n}}")
    out.append(
        "/// Returns (octant in 0..8, z) with z = r for even octants and pi/4 - r for odd ones, r = x mod pi/4.\n"
        "#[inline(always)]\npub fn reduce8(x: i64) -> (felt252, ZT) {\n"
        f"    let o = bounded_int::add::<_, UnitInt<{h(BIAS)}>>(x, {h(BIAS)});\n"
        f"    let (k, r) = bounded_int::div_rem::<_, UnitInt<{h(QP)}>>(o, {h(QP)});\n"
        "    let (_k8, oct) = bounded_int::div_rem::<_, UnitInt<8>>(k, 8);\n"
        "    let oct: felt252 = upcast(oct);\n"
        "    // odd octants (1, 3, 5, 7) mirror the remainder\n"
        "    let z: ZT = match oct {\n        0 | 2 | 4 | 6 => upcast(r),\n"
        f"        _ => upcast(bounded_int::sub::<UnitInt<{h(QP)}>, _>({h(QP)}, r)),\n    }};\n"
        "    (oct, z)\n}\n")
    out.append(
        "/// (table index, fraction) of z for the sin/cos tables.\n#[inline(always)]\n"
        "pub fn lut_split(z: ZT) -> (u32, u32, felt252) {\n"
        f"    let (i, f) = bounded_int::div_rem::<_, UnitInt<{h(1 << LUT_K)}>>(z, {h(1 << LUT_K)});\n"
        "    let j = bounded_int::add::<_, UnitInt<1>>(i, 1);\n"
        "    (upcast(i), upcast(j), upcast(f))\n}\n")
    out.append(horner_fn("sin_poly_u", COEF["sin"], "shr64", "sin(z)/z as a polynomial in u = z^2 (u at scale 2^64, result at scale 2^60)."))
    out.append(horner_fn("cos_poly_u", COEF["cos"], "shr64", "cos(z) as a polynomial in u = z^2 (u at scale 2^64, result at scale 2^60)."))
    out.append(horner_fn("acos_poly_x", COEF["acos"], "crate::fixed::felt::narrow", "acos(x)/sqrt(1-x) on [0, 1] (x at scale 2^32, result at scale 2^60)."))
    for i, cs in enumerate(COEF["atan"]):
        out.append(horner_fn(f"atan_seg{i}", cs, "crate::fixed::felt::narrow", f"atan({i}/8 + t), t in [0, 1/8) at scale 2^32, result at scale 2^60."))
    arms = "\n".join(f"        {i} => atan_seg{i}(t)," for i in range(len(COEF["atan"])))
    out.append(f"/// atan(idx/8 + t) at scale 2^60; idx == 8 only happens for z == 1.\n#[inline(always)]\npub fn atan_segments(idx: felt252, t: felt252) -> felt252 {{\n    match idx {{\n{arms}\n        _ => {h(QP << 28)},\n    }}\n}}\n")
    out.append(f"pub const SIN_TABLE: [i64; {len(SIN_T)}] = [" + ", ".join(map(str, SIN_T)) + "];")
    out.append(f"pub const COS_TABLE: [i64; {len(COS_T)}] = [" + ", ".join(map(str, COS_T)) + "];")
    open(os.path.join(ROOT, "src", "trig_gen.cairo"), "w").write("\n".join(out) + "\n")


def pair(name, prelude, rdecl, rtype, expr):
    pre = "".join(f"    {l}\n" for l in prelude)
    return (f"#[test]\n#[allow(unused_variables)]\nfn {name}__base() {{\n{pre}    let r: {rtype} = {rdecl};\n    sink::<{rtype}>(r);\n}}\n"
            f"#[test]\n#[allow(unused_variables)]\nfn {name}__op() {{\n{pre}    let r: {rtype} = {rdecl};\n    sink::<{rtype}>({expr});\n}}\n")


def gen_tests():
    r = lambda v: int(math.floor(v * ONE))
    out = ['''// GENERATED by scripts/gen_trig.py -- do not edit by hand.
use bench::cubit_trig;
use bench::fixed::Real;
use bench::fixed::i64b::FI64;
use bench::fixed::mag::FMag;
use bench::glam::mk;
use bench::harness::sink;
use bench::trig;
''']
    A1, A2 = 2.5, -4.0
    for tag, ang in (("q2_pos", A1), ("q3_neg", A2)):
        pre_i, pre_m = [f"let a: FI64 = mk({r(ang)});"], [f"let a: FMag = mk({r(ang)});"]
        out.append(pair(f"sin_{tag}_cubit_taylor", pre_m, "mk(1)", "FMag", "cubit_trig::sin(a)"))
        out.append(pair(f"sin_{tag}_cubit_fast_lut", pre_m, "mk(1)", "FMag", "cubit_trig::sin_fast(a)"))
        out.append(pair(f"sin_{tag}_ours_poly", pre_i, "mk(1)", "FI64", "trig::sin(a)"))
        out.append(pair(f"sin_{tag}_ours_lut", pre_i, "mk(1)", "FI64", "trig::sin_lut(a)"))
        out.append(pair(f"cos_{tag}_cubit_taylor", pre_m, "mk(1)", "FMag", "cubit_trig::cos(a)"))
        out.append(pair(f"cos_{tag}_ours_poly", pre_i, "mk(1)", "FI64", "trig::cos(a)"))
        out.append(pair(f"sincos_{tag}_ours_poly", pre_i, "(mk(1), mk(1))", "(FI64, FI64)", "trig::sin_cos(a)"))
        out.append(pair(f"sincos_{tag}_cubit_taylor", pre_m, "(mk(1), mk(1))", "(FMag, FMag)", "(cubit_trig::sin(a), cubit_trig::cos(a))"))
    for tag, z in (("small_0p3", 0.3), ("shifted_0p9", 0.9), ("inverted_m1p7", -1.7)):
        out.append(pair(f"atan_{tag}_cubit_poly", [f"let a: FMag = mk({r(z)});"], "mk(1)", "FMag", "cubit_trig::atan(a)"))
        out.append(pair(f"atan_{tag}_cubit_fast_lut", [f"let a: FMag = mk({r(z)});"], "mk(1)", "FMag", "cubit_trig::atan_fast(a)"))
        out.append(pair(f"atan_{tag}_ours_atan2_one", [f"let a: FI64 = mk({r(z)});"], "mk(1)", "FI64", "trig::atan(a)"))
    out.append(pair("atan2_q2_ours", [f"let y: FI64 = mk({r(2.2)});", f"let x: FI64 = mk({r(-1.3)});"], "mk(1)", "FI64", "trig::atan2(y, x)"))
    out.append(pair("atan2_q4_ours", [f"let y: FI64 = mk({r(-0.4)});", f"let x: FI64 = mk({r(3.1)});"], "mk(1)", "FI64", "trig::atan2(y, x)"))
    for tag, v in (("pos_0p35", 0.35), ("neg_m0p8", -0.8)):
        out.append(pair(f"acos_{tag}_cubit", [f"let a: FMag = mk({r(v)});"], "mk(1)", "FMag", "cubit_trig::acos(a)"))
        out.append(pair(f"acos_{tag}_cubit_fast", [f"let a: FMag = mk({r(v)});"], "mk(1)", "FMag", "cubit_trig::acos_fast(a)"))
        out.append(pair(f"acos_{tag}_ours", [f"let a: FI64 = mk({r(v)});"], "mk(1)", "FI64", "trig::acos(a)"))
        out.append(pair(f"asin_{tag}_cubit", [f"let a: FMag = mk({r(v)});"], "mk(1)", "FMag", "cubit_trig::asin(a)"))
        out.append(pair(f"asin_{tag}_ours", [f"let a: FI64 = mk({r(v)});"], "mk(1)", "FI64", "trig::asin(a)"))
    open(os.path.join(ROOT, "tests", "trig.cairo"), "w").write("\n".join(out))

    # bit-exact checks of the Cairo code against the Python mirrors (goes to the correctness module)
    chk = ['''// GENERATED by scripts/gen_trig.py -- do not edit by hand.
// Bit-exact comparison of the Cairo implementations with the Python mirrors used for the error sweeps.
use bench::cubit_trig;
use bench::fixed::Real;
use bench::fixed::i64b::FI64;
use bench::fixed::mag::FMag;
use bench::trig;

// `#[inline(never)]`: otherwise the compiler const-folds the whole function under test and the
// check would exercise the constant folder instead of the generated code.
#[inline(never)]
fn i(raw: i64) -> FI64 {
    FI64 { raw }
}
#[inline(never)]
fn m(raw: i64) -> FMag {
    Real::from_raw(raw)
}
''']
    angles = [r(v) for v in (0.0, 1e-5, 0.3, 0.7853, 0.79, 1.2, 1.5707, 1.58, 2.5, 3.14159, 3.2, 4.0, 5.5, 6.2831, 6.3, 100.25, -0.3, -1.0, -2.5, -4.0, -6.0, -123.456)]
    body = "".join(f"    assert!(trig::sin(i({a})).raw == {sin_poly(a)}, \"sin {a}\");\n    assert!(trig::cos(i({a})).raw == {cos_poly(a)}, \"cos {a}\");\n"
                   f"    assert!(trig::sin_lut(i({a})).raw == {sin_lut(a)}, \"sin_lut {a}\");\n"
                   f"    let (s, c) = trig::sin_cos(i({a}));\n    assert!(s.raw == {sin_poly(a)} && c.raw == {cos_poly(a)}, \"sin_cos {a}\");\n" for a in angles)
    chk.append(f"#[test]\nfn check_trig_ours_sincos() {{\n{body}}}\n")
    body = "".join(f"    assert!(cubit_trig::sin(m({a})).to_raw() == {cubit_sin(a)}, \"cubit sin {a}\");\n"
                   f"    assert!(cubit_trig::sin_fast(m({a})).to_raw() == {cubit_sin_fast(a)}, \"cubit sin_fast {a}\");\n" for a in angles)
    chk.append(f"#[test]\nfn check_trig_cubit_sin() {{\n{body}}}\n")
    yx = [(r(y), r(x)) for y, x in ((0.0, 1.0), (1.0, 1.0), (2.2, -1.3), (-0.4, 3.1), (-5.0, -5.0), (1e-4, -7.0), (3.0, 0.0), (-3.0, 0.0), (0.0, -2.0), (0.31, 0.77), (123.0, 0.5))]
    body = "".join(f"    assert!(trig::atan2(i({y}), i({x})).raw == {atan2_poly(y, x)}, \"atan2 {y} {x}\");\n" for y, x in yx)
    zs = [r(v) for v in (0.0, 0.1, 0.3, 0.69, 0.71, 0.9, 1.0, 1.7, 25.0, -0.3, -0.9, -1.7)]
    body += "".join(f"    assert!(trig::atan(i({z})).raw == {atan2_poly(z, ONE)}, \"atan {z}\");\n" for z in zs)
    chk.append(f"#[test]\nfn check_trig_ours_atan() {{\n{body}}}\n")
    body = "".join(f"    assert!(cubit_trig::atan(m({z})).to_raw() == {_cubit_atan(z, False)}, \"cubit atan {z}\");\n"
                   f"    assert!(cubit_trig::atan_fast(m({z})).to_raw() == {_cubit_atan(z, True)}, \"cubit atan_fast {z}\");\n" for z in zs)
    chk.append(f"#[test]\nfn check_trig_cubit_atan() {{\n{body}}}\n")
    vs = [r(v) for v in (0.0, 0.1, 0.35, 0.5, 0.9, 0.999, -0.2, -0.8, -0.9999)] + [ONE, -ONE]
    body = "".join(f"    assert!(trig::acos(i({v})).raw == {acos_poly(v)}, \"acos {v}\");\n    assert!(trig::asin(i({v})).raw == {HP - acos_poly(v)}, \"asin {v}\");\n" for v in vs)
    chk.append(f"#[test]\nfn check_trig_ours_acos() {{\n{body}}}\n")
    body = "".join(f"    assert!(cubit_trig::acos(m({v})).to_raw() == {cubit_acos(v)}, \"cubit acos {v}\");\n" for v in vs[:9])
    chk.append(f"#[test]\nfn check_trig_cubit_acos() {{\n{body}}}\n")
    open(os.path.join(ROOT, "tests", "correctness_trig.cairo"), "w").write("\n".join(chk))


if __name__ == "__main__":
    gen_cairo()
    gen_tests()
    print("wrote src/trig_gen.cairo, tests/trig.cairo, tests/correctness_trig.cairo")
    for name, err, at in error_report():
        print(f"{err:10.3e}  {name}")
