#!/usr/bin/env python3
"""Coefficient generator and bit-exact mirror of `fixed::exp`.

The minimax polynomials, the table of `2^(i / 16)`, the normalisation tree of `log2` and the
domain thresholds of `packages/fixed/src/exp.cairo` (and of the losing variants of
`packages/benches/src/alt/exp.cairo`) are computed here and written between the
`// GENERATED-BEGIN <tag>` / `// GENERATED-END <tag>` markers of those files.

The second half of the file mirrors **every** Cairo function of `fixed::exp` in Python integer
arithmetic, operation by operation (`step` = one floor rescale of a Q96.96 accumulator,
`narrow64_round` = one rounded rescale, ...). The mirror is what the error sweeps measure: it is
bit-exact with the Cairo code, so the figures quoted in the doc comments are the ones the library
returns, and the test tables of `packages/fixed/tests/test_exp.cairo` are generated from it. The
references are computed by `mpmath` with 50 significant digits.

The hyperbolic functions (`sinh`, `cosh`, `tanh`, `sinhc`, `coshc`) have their own generated
block (`// GENERATED-BEGIN hyperbolic`): one polynomial of `sinh(x) / x`, fitted by `mpmath` alone
(`chebyfit`, no numpy), so that it is reproducible on every platform, plus the thresholds derived
from the mirror.

Environment (pinned in `scripts/requirements.txt`):

  python3 -m venv /tmp/fixed-venv && /tmp/fixed-venv/bin/pip install -r scripts/requirements.txt
  /tmp/fixed-venv/bin/python scripts/gen_exp.py check

The `exp` / `log2` fits go through `numpy.linalg.solve`, whose last bits depend on the BLAS of
the platform, not only on the numpy version: on Linux x86-64 no numpy release reproduces the
committed coefficients bit for bit (they differ by at most ~1e-6 ULP of the polynomial value).
`reconcile` therefore keeps a committed polynomial whenever the fresh fit agrees with it to
within `2^-48` of the polynomial value (platform noise), and replaces it otherwise (a deliberate
change of the fit). The mirror always runs on the coefficients of the Cairo code, so every figure
and every test table stays bit-exact.

usage:
  scripts/gen_exp.py emit     rewrite the generated blocks of the two Cairo files
  scripts/gen_exp.py check    exit 1 if those blocks are not up to date
  scripts/gen_exp.py sweep    print the measured max error of every function
  scripts/gen_exp.py tables   print the Cairo test tables (input / expected raw values)
"""

import argparse
import math
import random
import re
import sys
from fractions import Fraction
from pathlib import Path

import mpmath as mp

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_trig import fit_shifted, hexi, remez, splice, wrap_table  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "packages/fixed/src/exp.cairo"
ALT = ROOT / "packages/benches/src/alt/exp.cairo"

mp.mp.dps = 50

# ----------------------------------------------------------------- the number format

FRAC = 32
ONE = 1 << FRAC  # raw 1.0
I64_MIN, I64_MAX = -(1 << 63), (1 << 63) - 1

# exp2: x = k / 16 + g with g in [0, 1/16): 2^x = TABLE[k] * P(g).
SEGS = 16  # table entries per octave
KLO, KHI = -33, 31  # exponent range of the table: [2^-33, 2^31)
TAB_LO = KLO * SEGS  # the table index 0 is `2^(-33)`
TAB_LEN = (KHI - KLO) * SEGS  # 1024 entries
SEG_RAW = ONE // SEGS  # 1 / 16 in raw units (2^28)
EXP_ACC = 60  # fractional bits of the 2^g accumulator: 2^g in [1, 1.044) fits an i64
DEG_EXP2 = 6
QB = 56  # fractional bits of the wide exponent `q` of exp and powf
Q_SEG = 1 << (QB - 4)  # 1 / 16 at the scale of `q`

# log2: x = 2^e * m, m = 1 + j / 32 + t with t in [0, 1/32).
LOG_SEGS = 32
DEG_LOG = 4
LOG_ACC = 56  # fractional bits of the log accumulator `A` (|A| <= 32 * 2^56 fits an i64)
M_BITS = 62  # the normalised mantissa lives in [2^62, 2^63)
LOG_SEG_RAW = 1 << (M_BITS - 5)  # 1 / 32 at the scale of the mantissa

# Alternative variants (benches::alt::exp).
DEG_EXP2_SINGLE = 12  # alt: one polynomial of 2^f on [0, 1)
DEG_EXP_CW = 6  # alt: e^r on [0, ln 2 / 16)
DEG_ATANH = 7  # alt: atanh(s) / s in u = s^2 on [0, 1/9]


def const(v):
    """An mpmath constant as an exact integer multiple of 2^-bits, rounded to nearest."""
    return int(mp.nint(v))


LN2 = mp.log(2)
LOG2_E_Q = const(mp.power(2, QB) / LN2)  # log2(e) at the scale of q
K_LOG2 = 1 << (96 - LOG_ACC)  # A * K / 2^64 = result at Q32.32
K_LN = const(LN2 * K_LOG2)
K_LOG10 = const(mp.log10(2) * K_LOG2)

# ----------------------------------------------------------------- tables and fits

# Rounded down, like the final rescale of `exp2`: with a polynomial that does not overshoot
# `2^(1/16)` at the right end of a segment (`seal_exp2`), the seams cannot decrease.
TABLE = [int(mp.floor(mp.power(2, mp.mpf(i + TAB_LO) / SEGS) * ONE)) for i in range(TAB_LEN)]


def f_exp2(g):
    """`(2^g - 1) / g` without cancellation."""
    if g == 0:
        return float(LN2)
    g = mp.mpf(g)
    return float(mp.expm1(g * LN2) / g)


def f_exp(r):
    """`(e^r - 1) / r` without cancellation."""
    if r == 0:
        return 1.0
    r = mp.mpf(r)
    return float(mp.expm1(r) / r)


def f_log0(t):
    """`log2(1 + t) / t` without cancellation."""
    if t == 0:
        return float(1 / LN2)
    t = mp.mpf(t)
    return float(mp.log1p(t) / t / LN2)


def f_atanh(u):
    """`2 / ln 2 * atanh(s) / s` with `u = s^2`: `log2(m) = s * f(s^2)`, `s = (m-1)/(m+1)`."""
    if u == 0:
        return float(2 / LN2)
    s = mp.sqrt(mp.mpf(u))
    return float(2 / LN2 * mp.atanh(s) / s)


def grid(lo, hi, points):
    return [lo + ((hi - lo) * i) // (points - 1) for i in range(points)]


def scale(coeffs, bits):
    out = [int(round(c * (1 << bits))) for c in coeffs]
    for c in out:
        assert abs(c) < 1 << 62, f"coefficient {c} leaves no headroom in the Fixed range"
    return out


def build_exp2_poly():
    return scale(fit_shifted(f_exp2, 0.0, 1 / SEGS, DEG_EXP2, 1.0), EXP_ACC)


def build_log_polys():
    seg = 1 / LOG_SEGS
    out = [scale(fit_shifted(f_log0, 0.0, seg, DEG_LOG, 0.0), LOG_ACC)]
    for j in range(1, LOG_SEGS):
        base = mp.mpf(1) + mp.mpf(j) / LOG_SEGS
        c = remez(lambda t, b=base: float(mp.log(b + t) / LN2), 0.0, seg, DEG_LOG)
        out.append(scale(c, LOG_ACC))
    return out


def horner_w(coeffs, u):
    """Horner in a Q64.64 variable `u`: `acc = floor(u * acc / 2^64 + c)` per step (`step`)."""
    acc = coeffs[0]
    for c in coeffs[1:]:
        acc = (u * acc + (c << 64)) >> 64
    return acc


def seal(coeffs, u_max, target):
    """Lowers the linear coefficient until the polynomial at its largest argument `u_max` does
    not exceed `target` (the value that starts the next segment). The minimax residual is ~1e-17
    at the scale of the accumulator, so the change is a few units of the last place: it trades
    nothing measurable for **monotonicity by construction** across every seam. Returns the number
    of units removed."""
    removed = 0
    while True:
        excess = horner_w(coeffs, u_max) - target
        if excess <= 0:
            return removed
        d = max(1, (excess << 64) // u_max)
        coeffs[-2] -= d
        removed += d


EXP2_C = build_exp2_poly()
# The largest fraction reachable (at the scale of the wide exponent of exp) must stay below the
# exact `2^(1/16)`, rounded down: then `floor(TABLE[i-1] * P) <= floor(2^((i+1)/16)) = TABLE[i]`.
EXP2_SEALED = seal(EXP2_C, (Q_SEG - 1) << (64 - QB),
                   int(mp.floor(mp.power(2, mp.mpf(1) / SEGS) * (1 << EXP_ACC))))
LOG_C = build_log_polys()
# Segment `j` must end at or below the constant term of segment `j + 1` (and the last one at or
# below `1`, where the next octave starts): `log2` is then non-decreasing across every seam.
LOG_SEALED = [
    seal(LOG_C[j], (LOG_SEG_RAW - 1) << (64 - M_BITS),
         LOG_C[j + 1][-1] if j + 1 < LOG_SEGS else 1 << LOG_ACC)
    for j in range(LOG_SEGS)
]


def committed(path, name):
    """The coefficients of the Horner function `name` as committed in `path`, or None."""
    found = re.search(rf"fn {name}\(u: W\d\) -> Fixed \{{(.*?)\n\}}", path.read_text(), re.S)
    if not found:
        return None
    return [int(v, 16) for v in re.findall(r"raw: (-?0x[0-9a-f]+)", found.group(1))]


def reconcile(fitted, path, name, u_max, bits):
    """The committed coefficients of `name` if the fresh fit only differs from them by platform
    noise (at most `2^-48` of the value of the polynomial, at the scale `2^bits`, on `[0, u_max]`),
    the fresh fit otherwise. See the module docstring (debt D1)."""
    old = committed(path, name)
    if old is None or len(old) != len(fitted) or old == fitted:
        return fitted
    noise = max(abs(horner_w(fitted, u) - horner_w(old, u)) for u in grid(0, u_max, 257))
    return old if noise <= 1 << (bits - 48) else fitted


EXP2_C = reconcile(EXP2_C, LIB, "exp2_poly", (Q_SEG - 1) << (64 - QB), EXP_ACC)
LOG_C = [reconcile(LOG_C[j], LIB, f"log2_seg{j}", (LOG_SEG_RAW - 1) << (64 - M_BITS), LOG_ACC)
         for j in range(LOG_SEGS)]
# A committed polynomial must be sealed as well as a fresh one.
assert seal(list(EXP2_C), (Q_SEG - 1) << (64 - QB),
            int(mp.floor(mp.power(2, mp.mpf(1) / SEGS) * (1 << EXP_ACC)))) == 0
assert all(seal(list(LOG_C[j]), (LOG_SEG_RAW - 1) << (64 - M_BITS),
                LOG_C[j + 1][-1] if j + 1 < LOG_SEGS else 1 << LOG_ACC) == 0
           for j in range(LOG_SEGS))

# ----------------------------------------------------------------- the mirror


def i64(v, msg="Fixed: overflow"):
    if not I64_MIN <= v <= I64_MAX:
        raise OverflowError(msg)
    return v


def narrow32(v):
    """`W1::narrow`: floor of a Q64.64 accumulator."""
    return i64(v >> 32)


def narrow64(v):
    """`bounded::narrow64`: floor of a Q96.96 accumulator."""
    return i64(v >> 64)


def narrow64_round(v):
    """`bounded::narrow64_round`: round to nearest, ties toward +infinity."""
    return i64((v + (1 << 63)) >> 64)


def _half_even(n, d):
    """`round_half_even(n / d)` of two integers, `d != 0`."""
    if d < 0:
        n, d = -n, -d
    q, r = divmod(n, d)
    return q + 1 if 2 * r > d or (2 * r == d and q % 2) else q


def div(a, b):
    """`Fixed / Fixed`: round_half_even(a * 2^32 / b)."""
    if b == 0:
        raise ZeroDivisionError("Fixed: division by zero")
    return i64(_half_even(a << FRAC, b))


def exp2_core(idx, u):
    """`TABLE[idx] * P(u)`, one floor rescale (`u` is the Q64.64 fraction of the segment)."""
    return narrow64(TABLE[idx] * horner_w(EXP2_C, u) * 16)




def exp2_raw(raw):
    """exp2 without the overflow check (for the threshold search)."""
    if raw < KLO * ONE:
        return 0
    idx, g = divmod(raw - KLO * ONE, SEG_RAW)
    if idx >= TAB_LEN:
        raise OverflowError("Fixed: overflow")
    return exp2_core(idx, g << 32)


def exp_q(raw):
    """`floor(x * log2(e) * 2^56)`: the wide exponent of exp."""
    return narrow32(raw * LOG2_E_Q)


def exp_from_q(q):
    idx, g = divmod(q + (-KLO << QB), Q_SEG)
    if idx >= TAB_LEN:
        raise OverflowError("Fixed: overflow")
    return exp2_core(idx, g << (64 - QB))


def exp_raw(raw):
    if raw < EXP_MIN_RAW:
        return 0
    return exp_from_q(exp_q(raw))


def first_overflow(fn, lo, hi):
    """Smallest raw in (lo, hi] for which `fn` overflows (fn(lo) fits, fn(hi) overflows)."""
    def ovf(r):
        try:
            fn(r)
            return False
        except OverflowError:
            return True
    assert not ovf(lo) and ovf(hi)
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if ovf(mid):
            hi = mid
        else:
            lo = mid
    # The results are monotone around the threshold: check a window on both sides.
    for r in range(hi - 4000, hi):
        assert not ovf(r), r
    for r in range(hi, hi + 4000):
        assert ovf(r), r
    return hi


# The smallest raw input of exp whose wide exponent reaches the table: q >= -33 * 2^56.
EXP_MIN_RAW = -((-KLO << (QB + FRAC)) // LOG2_E_Q)
assert exp_q(EXP_MIN_RAW) >= KLO << QB > exp_q(EXP_MIN_RAW - 1)
EXP2_MAX_RAW = first_overflow(exp2_raw, 30 * ONE, 31 * ONE)
EXP_MAX_RAW = first_overflow(exp_raw, 21 * ONE, 22 * ONE)


def exp2(raw):
    if raw >= EXP2_MAX_RAW:
        raise OverflowError("Fixed: exp overflow")
    return exp2_raw(raw)


def exp(raw):
    if raw >= EXP_MAX_RAW:
        raise OverflowError("Fixed: exp overflow")
    return exp_raw(raw)


def exp_m1(raw):
    return i64(exp(raw) - ONE)


def normalize(x):
    """`(2^(62 - e), (e - 32) * 2^56)` with `e = floor(log2(x))` (the generated tree)."""
    e = x.bit_length() - 1
    return 1 << (M_BITS - e), (e - 32) << LOG_ACC


def log2_core(raw):
    """`A = log2(x) * 2^56`, floor-rounded steps."""
    if raw <= 0:
        raise ValueError("Fixed: ln domain")
    c, ek = normalize(raw)
    j, t = divmod(raw * c - (1 << M_BITS), LOG_SEG_RAW)
    return ek + horner_w(LOG_C[j], t << (64 - M_BITS))


def log2(raw):
    return narrow64_round(log2_core(raw) * K_LOG2)


def ln(raw):
    return narrow64_round(log2_core(raw) * K_LN)


def log10(raw):
    return narrow64_round(log2_core(raw) * K_LOG10)


def ln_1p(raw):
    return ln(i64(raw + ONE, "i64_add Overflow"))


def log(raw, base):
    return div(log2_core(raw), log2_core(base))


def pow_pos(x, n):
    """`x^n` for `x > 0`: `exp2(n * log2(x))` on the wide exponent."""
    w = log2_core(x) * n  # t * 2^88
    t24 = narrow64(w)
    if t24 >= KHI << 24:
        raise OverflowError("Fixed: overflow")
    if t24 < KLO << 24:
        return 0
    return exp_from_q(narrow32(w))


def powf(x, n):
    if x > 0:
        return pow_pos(x, n)
    if x == 0:
        if n > 0:
            return 0
        if n == 0:
            return ONE
        raise ZeroDivisionError("Fixed: division by zero")
    if n % ONE != 0:
        raise ValueError("Fixed: powf domain")
    r = pow_pos(i64(-x), n)
    return -r if (n >> FRAC) % 2 else r

# ----------------------------------------------------------------- hyperbolic functions
#
# sinh / cosh from one exponential: `E = e^|x|` from the wide exponent, then (exact integer
# identities, see `hyp_core`) `sinh = round(E / 2 - 1 / (2E))`, `cosh = round(E / 2 + 1 / (2E))`
# with a single u64 division `floor((2^64 - 1) / E)`. From `|x| = 21` on, `E` would leave the
# range: the core computes `E / 2 = 2^(t - 1)` instead (`sinh = round(E' - 1 / (4E'))`), which
# reaches `asinh(2^31)`. Below `|x| = 2`, `sinh(x) = x * S(x^2)` with `S(u) = sinh(sqrt(u)) /
# sqrt(u)`: no exponential, an error of half an ULP, `sinh(x) = x` for tiny `x`; `sinhc` is `S`
# itself there. `tanh = (T - c) / (T + c)` with `T = e^(2|x|) * c`, `c = 1` or `2^-16` (from
# `|x| = 5.5` on, so that `T` keeps fitting), one division.

DEG_SINHC = 6  # S(u) = 1 + u * g(u), g of degree 5 on [0, 4]
HYP_POLY = 2 * ONE  # |x| below it: the polynomial
HYP_SPLIT = 21 * ONE  # |x| from it on: E / 2 instead of E
TANH_SPLIT = 11 * ONE // 2  # |x| from it on: T = e^(2|x|) * 2^-16
TANH_SHIFT = 16
U64_MAX = (1 << 64) - 1


def build_sinhc_poly():
    """`S(u) = sinh(sqrt(u)) / sqrt(u)` on `[0, 4]` at the scale `2^60`, constant term pinned to 1
    (`S = 1 + u * g(u)`, `g` by `mpmath.chebyfit`: deterministic, no numpy)."""
    def g(u):
        if u == 0:
            return mp.mpf(1) / 6
        r = mp.sqrt(u)
        return (mp.sinh(r) / r - 1) / u
    c, err = mp.chebyfit(g, [0, mp.mpf(HYP_POLY * HYP_POLY) / ONE / ONE], DEG_SINHC, error=True)
    out = [int(mp.nint(v * (1 << EXP_ACC))) for v in c] + [1 << EXP_ACC]
    # Non-negative coefficients make every Horner step non-decreasing in `u`: `S` is monotone by
    # construction, and so are `sinh = x * S` and `sinhc = S` on the polynomial range.
    assert all(v >= 0 for v in out), out
    return out, float(err)


SINHC_C, SINHC_FIT_ERR = build_sinhc_poly()


def sinhc_s(a):
    """`S(a^2)` at the scale `2^60`, `0 <= a < 2`."""
    return horner_w(SINHC_C, a * a)


def hyp_core(a):
    """`(sinh(a), cosh(a))` raw from one exponential, `a >= 0` (not overflow-checked)."""
    big = a >= HYP_SPLIT
    e = exp_from_q(exp_q(a) - (1 << QB if big else 0))  # e^a, or e^a / 2 from 21 on
    r = U64_MAX // e  # ceil(2^64 / e) - 1, e >= 2^32
    if big:
        g = (r + 2) // 4  # round(2^62 / e) = round(1 / (4 E')), exactly
        return e - g, e + g
    # round(e / 2 -+ 2^63 / e) = (e - r) // 2 and (e + r + 1) // 2, exactly.
    return (e - r) // 2, (e + r + 1) // 2


def hyp_core_exact(a):
    """`hyp_core` from the rational values, for the check of its integer identities."""
    q = exp_q(a)
    if a < HYP_SPLIT:
        e = exp_from_q(q)
        s, c = Fraction(e, 2) - Fraction(1 << 63, e), Fraction(e, 2) + Fraction(1 << 63, e)
    else:
        e = exp_from_q(q - (1 << QB))
        s, c = e - Fraction(1 << 62, e), e + Fraction(1 << 62, e)
    return math.floor(s + Fraction(1, 2)), math.floor(c + Fraction(1, 2))


def sinh_raw(x):
    a = abs(x)
    if a < HYP_POLY:
        r = narrow64_round(a * sinhc_s(a) * 16)
    else:
        r = hyp_core(a)[0]
    i64(r)
    return -r if x < 0 else r


def cosh_raw(x):
    return i64(hyp_core(abs(x))[1])


SINH_MAX_RAW = first_overflow(sinh_raw, 22 * ONE, 23 * ONE)
COSH_MAX_RAW = first_overflow(cosh_raw, 22 * ONE, 23 * ONE)


def sinh(x):
    if not -SINH_MAX_RAW < x < SINH_MAX_RAW:
        raise OverflowError("Fixed: overflow")
    return sinh_raw(x)


def cosh(x):
    if not -COSH_MAX_RAW < x < COSH_MAX_RAW:
        raise OverflowError("Fixed: overflow")
    return cosh_raw(x)


def last_identity():
    """The largest raw `x` with `sinh(x) = x` (the cubic term stays below half an ULP)."""
    lo, hi = 1, 1 << 23
    assert sinh(lo) == lo and sinh(hi) != hi
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if sinh(mid) == mid:
            lo = mid
        else:
            hi = mid
    return lo


SINH_ID_RAW = last_identity()


def tanh_raw(x):
    a = abs(x)
    q = exp_q(2 * a)
    if a < TANH_SPLIT:
        t, c = exp_from_q(q), ONE
    else:
        t, c = exp_from_q(q - (TANH_SHIFT << QB)), ONE >> TANH_SHIFT
    r = div(t - c, t + c)
    return -r if x < 0 else r


def tanh_recip(x):
    """alt: `1 - 2^65 / D` with `D = e^(2|x|) + 1` raw from one reciprocal `floor((2^64 - 1) /
    D)`, for `|x| < 5.5` (`benches::alt::exp::tanh_recip`): bit-identical to `tanh`."""
    a = abs(x)
    d = exp(2 * a) + ONE
    r, rem = divmod(U64_MAX, d)
    w = 4 * (rem + 1)
    m = 2 * r + (w >= d) + (w >= 3 * d)
    return m - ONE if x < 0 else ONE - m


def first_one(fn, lo, hi):
    """Smallest raw in (lo, hi] with `fn = ONE` (fn(lo) < ONE, fn non-decreasing)."""
    assert fn(lo) < ONE and fn(hi) == ONE
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if fn(mid) == ONE:
            hi = mid
        else:
            lo = mid
    return hi


# From TANH_SAT_RAW on the formula returns exactly ONE: tanh returns it without computing.
TANH_SAT_RAW = first_one(tanh_raw, 11 * ONE, 12 * ONE)
# The first input whose exact tanh rounds to ONE: 1 - tanh(x) = 2 / (e^(2x) + 1) <= 2^-33.
TANH_SAT_EXACT = int(mp.ceil(mp.log(mp.power(2, 34) - 1) / 2 * ONE))


def tanh(x):
    if x >= TANH_SAT_RAW:
        return ONE
    if x <= -TANH_SAT_RAW:
        return -ONE
    return tanh_raw(x)


def sinhc(x):
    a = abs(x)
    if a < HYP_POLY:
        return (sinhc_s(a) + (1 << 27)) >> 28
    return div(sinh(a), a)


def coshc(x):
    if x == 0:
        return ONE
    return div(cosh(x), x)

# ----------------------------------------------------------------- alternative variants

P2_TABLE = [1 << (k + 32) for k in range(-32, 31)]  # alt: 2^k at Q32.32, k in [-32, 30]


def build_alt():
    single = scale(fit_shifted(f_exp2, 0.0, 1.0, DEG_EXP2_SINGLE, 1.0), EXP_ACC)
    cw = scale(fit_shifted(f_exp, 0.0, float(LN2) / SEGS, DEG_EXP_CW, 1.0), EXP_ACC)
    atanh = scale(remez(f_atanh, 0.0, 1 / 9, DEG_ATANH), LOG_ACC)
    single = reconcile(single, ALT, "exp2_poly_single", 1 << 64, EXP_ACC)
    cw = reconcile(cw, ALT, "exp_poly_cw", int(LN2 / SEGS * (1 << 64)), EXP_ACC)
    atanh = reconcile(atanh, ALT, "atanh_poly", (1 << 64) // 9, LOG_ACC)
    return single, cw, atanh


CW_D = int(LN2 / SEGS * ONE)  # floor(ln 2 / 16 * 2^32): the Cody-Waite divisor
CW_TAIL = const((LN2 / SEGS * ONE - CW_D) * ONE)  # its tail at the Q64.64 scale
CW_BIAS = 531  # multiples of the divisor added to make the dividend non-negative


def alt_exp2_single(raw, single):
    """alt: `2^f` on [0, 1) by one polynomial, times a power of two (floor final rescale)."""
    k, f = divmod(raw, ONE)
    if k < -32:
        return 0
    acc = horner_w(single, f << 32)
    return narrow64(acc * P2_TABLE[k + 32] * 16)


def alt_exp_cw(raw, cw):
    """alt: Cody-Waite reduction by `ln 2 / 16`, `e^r` polynomial, the library table."""
    if raw < EXP_MIN_RAW:
        return 0
    q, r1 = divmod(raw + CW_BIAS * CW_D, CW_D)
    assert q >= CW_BIAS + TAB_LO
    k = q - CW_BIAS
    u = (r1 << 32) - k * CW_TAIL
    acc = horner_w(cw, u)
    return narrow64(TABLE[k - TAB_LO] * acc * 16)


def alt_log2_atanh(raw, atanh):
    """alt: `log2(m) = s * P(s^2)`, `s = (m - 1) / (m + 1)` (one division)."""
    c, ek = normalize(raw)
    m = (raw * c) >> 30  # the mantissa at Q32.32, in [1, 2)
    s = div(m - ONE, m + ONE)
    acc = horner_w(atanh, s * s)
    a = ek + ((s * acc) >> 32)
    return narrow64(a * 256 * ONE)


def check_alt(single, cw, atanh):
    """The variants of `benches::alt::exp` are only benchmarked, never asserted in Cairo: a broken
    fit there would make the gas comparison meaningless, so their mirrors are swept here."""
    ws = wc = wa = 0.0
    for i in range(2001):
        raw = -20 * ONE + (36 * ONE * i) // 2000
        ref = mp.power(2, mp.mpf(raw) / ONE) * ONE
        ws = max(ws, float(abs(alt_exp2_single(raw, single) - ref) / max(ref, 1 << 48) * (1 << 48)))
        raw_e = -15 * ONE + (30 * ONE * i) // 2000
        ref = mp.exp(mp.mpf(raw_e) / ONE) * ONE
        wc = max(wc, float(abs(alt_exp_cw(raw_e, cw) - ref) / max(ref, 1 << 48) * (1 << 48)))
        raw_l = 1 + ((1 << 62) * i) // 2000
        ref = mp.log(mp.mpf(raw_l) / ONE, 2) * ONE
        wa = max(wa, float(abs(alt_log2_atanh(raw_l, atanh) - ref)))
    assert ws < 8 and wc < 8 and wa < 8, f"alt variants: {ws:.2f} / {wc:.2f} / {wa:.2f} ULP"
    return ws, wc, wa

# ----------------------------------------------------------------- error sweeps


def err_exp(got, ref):
    """Absolute error in ULP below 2^16, relative error in units of 2^-30 above."""
    return abs(got - ref) if ref < 1 << 48 else abs(got - ref) / ref * (1 << 30)


def sweep(points=40001):
    """Measures the max error of every mirrored function; returns {row: (value, unit)}."""
    rnd = random.Random(20260921)
    out = {}

    def run(name, xs, fn, ref, errf, unit):
        worst = 0.0
        for x in xs:
            worst = max(worst, float(errf(fn(x), ref(x))))
        out[name] = (worst, unit)

    def split_exp(name, xs, fn, ref):
        small = [x for x in xs if ref(x) < 1 << 48]
        large = [x for x in xs if ref(x) >= 1 << 48]
        run(f"{name} (result < 2^16)", small, fn, ref, err_exp, "ULP")
        run(f"{name} (result >= 2^16)", large, fn, ref, err_exp, "2^-30 rel")

    ref2 = lambda r: mp.power(2, mp.mpf(r) / ONE) * ONE  # noqa: E731
    refe = lambda r: mp.exp(mp.mpf(r) / ONE) * ONE  # noqa: E731
    xs = grid(KLO * ONE, EXP2_MAX_RAW - 1, points) + [rnd.randrange(KLO * ONE, EXP2_MAX_RAW)
                                                       for _ in range(4000)]
    split_exp("exp2", xs, exp2, ref2)
    xs = grid(EXP_MIN_RAW, EXP_MAX_RAW - 1, points) + [rnd.randrange(EXP_MIN_RAW, EXP_MAX_RAW)
                                                        for _ in range(4000)]
    split_exp("exp", xs, exp, refe)
    run("exp_m1 ([-1, 1])", grid(-ONE, ONE, points), exp_m1,
        lambda r: mp.expm1(mp.mpf(r) / ONE) * ONE, lambda a, b: abs(a - b), "ULP")

    # Logarithms: log-uniform over the whole positive range, plus a dense grid around 1.
    lxs = sorted({max(1, int(mp.power(2, mp.mpf(63) * i / (points - 1)))) for i in range(points)}
                 | {rnd.randrange(1, 1 << 63) for _ in range(4000)})
    lxs = [x for x in lxs if x <= I64_MAX] + grid(ONE // 2, 2 * ONE, points)
    for name, fn, base in (("log2", log2, 2), ("ln", ln, math.e), ("log10", log10, 10)):
        b = mp.e if base == math.e else mp.mpf(base)
        run(f"{name} ([2^-32, 2^31))", lxs, fn, lambda r, b=b: mp.log(mp.mpf(r) / ONE, b) * ONE,
            lambda a, r: abs(a - r), "ULP")
    run("ln_1p ([-1/2, 1])", grid(-ONE // 2, ONE, points), ln_1p,
        lambda r: mp.log1p(mp.mpf(r) / ONE) * ONE, lambda a, b: abs(a - b), "ULP")
    bxs = [x for x in lxs[:: max(1, len(lxs) // 6000)]]
    worst = 0.0
    for base in (2 * ONE, 10 * ONE, 3 * ONE // 2, ONE // 3, 1000 * ONE):
        for x in bxs:
            ref = mp.log(mp.mpf(x) / ONE, mp.mpf(base) / ONE) * ONE
            worst = max(worst, float(abs(log(x, base) - ref)))
    out["log (bases 2, 10, 1.5, 1/3, 1000)"] = (worst, "ULP")

    # powf: the two stages compound; the rows below document the result.
    pxs = [const(mp.power(2, mp.mpf(-8) + mp.mpf(16) * i / 399) * ONE) for i in range(400)]
    ns = [(-4 * ONE) + (8 * ONE * i) // 99 for i in range(100)]
    small = large = 0.0
    for x in pxs:
        for n in ns:
            ref = mp.power(mp.mpf(x) / ONE, mp.mpf(n) / ONE) * ONE
            if ref >= (1 << 63) - (1 << 40):
                continue
            e = abs(powf(x, n) - ref)
            if ref < ONE:
                small = max(small, float(e))
            else:
                large = max(large, float(e / ref * (1 << 30)))
    out["powf (x in [2^-8, 2^8], n in [-4, 4], result < 1)"] = (small, "ULP")
    out["powf (x in [2^-8, 2^8], n in [-4, 4], result >= 1)"] = (large, "2^-30 rel")
    return out


def check_identities():
    """The exact identities the tests also assert, and the monotonicity across every seam."""
    assert exp2(0) == ONE and exp(0) == ONE
    for k in range(KLO + 1, KHI):
        assert exp2(k * ONE) == 1 << (k + 32), k
    for k in range(-32, 31):
        assert log2(1 << (k + 32)) == k * ONE, k
    assert ln(ONE) == 0 and log10(ONE) == 0 and log2(ONE) == 0
    assert exp2(KLO * ONE - 1) == 0 and exp(EXP_MIN_RAW - 1) == 0
    assert powf(ONE, 12345) == ONE and powf(0, 0) == ONE and powf(0, ONE) == 0
    # Monotone across every segment seam of exp2 (and so of exp) and of log2.
    for i in range(1, TAB_LEN):
        raw = (i + TAB_LO) * SEG_RAW
        vals = [exp2(r) for r in range(raw - 3, raw + 4) if r < EXP2_MAX_RAW]
        assert vals == sorted(vals), raw
    for e in (0, 5, 20, 32, 40, 62):
        for j in range(LOG_SEGS):
            raw = (1 << e) + ((j << e) >> 5)
            vals = [log2(r) for r in range(max(1, raw - 3), raw + 4) if r <= I64_MAX]
            assert vals == sorted(vals), raw


def sweep_hyp(points=20001):
    """Max error of the hyperbolic mirror: {row: (value, unit)}, like `sweep`."""
    rnd = random.Random(20260925)
    out = {}

    def run(name, xs, fn, ref, unit):
        worst = 0.0
        for x in xs:
            r = ref(mp.mpf(x) / ONE) * ONE
            e = abs(fn(x) - r)
            worst = max(worst, float(e if unit == "ULP" else e / r * (1 << 30)))
        out[name] = (worst, unit)

    def xs_in(lo, hi):
        return grid(lo, hi - 1, points) + [rnd.randrange(lo, hi) for _ in range(4000)]

    big = SINH_MAX_RAW  # also COSH_MAX_RAW
    split16 = int(mp.asinh(1 << 16) * ONE)  # sinh / cosh reach 2^16 there (to 1e-9)
    run("sinh (-2 < x < 2)", xs_in(-HYP_POLY + 1, HYP_POLY), sinh, mp.sinh, "ULP")
    run("sinh (x >= 2, result < 2^16)", xs_in(HYP_POLY, split16), sinh, mp.sinh, "ULP")
    run("sinh (result >= 2^16)", xs_in(split16 + 1, big), sinh, mp.sinh, "2^-30 rel")
    run("cosh (result < 2^16)", xs_in(0, split16), cosh, mp.cosh, "ULP")
    run("cosh (result >= 2^16)", xs_in(split16 + 1, big), cosh, mp.cosh, "2^-30 rel")
    run("tanh (whole range)", xs_in(-TANH_SAT_RAW - ONE, TANH_SAT_RAW + ONE), tanh, mp.tanh,
        "ULP")
    sref = lambda v: mp.sinh(v) / v if v else mp.mpf(1)  # noqa: E731
    run("sinhc (-2 < x < 2)", xs_in(-HYP_POLY + 1, HYP_POLY), sinhc, sref, "ULP")
    run("sinhc (2 <= x < 12)", xs_in(HYP_POLY, 12 * ONE), sinhc, sref, "ULP")
    run("coshc (1 <= x < 12)", xs_in(ONE, 12 * ONE), coshc, lambda v: mp.cosh(v) / v, "ULP")
    return out


def check_hyp():
    """The exact identities and symmetries the tests assert, the integer identities of
    `hyp_core`, and the monotonicity: on dense windows around every junction (polynomial /
    exponential at 2, `E` / `E / 2` at 21, the two scales of `tanh` at 5.5, saturation, overflow)
    and at random points. Between the junctions it holds by construction: `hyp_core` rounds an
    increasing function of a non-decreasing `E`, the polynomial has non-negative coefficients,
    and `tanh` rounds `(T - c) / (T + c)`, increasing in a non-decreasing `T`."""
    assert sinh(0) == 0 and cosh(0) == ONE and tanh(0) == 0 and sinhc(0) == ONE
    assert coshc(0) == ONE
    for x in list(range(1, 1 << 12)) + grid(1 << 12, SINH_ID_RAW, 4001):
        assert sinh(x) == x, x  # the x^3 / 6 term is below half an ULP
    assert sinh(SINH_ID_RAW + 1) == SINH_ID_RAW + 2
    rnd = random.Random(20260926)
    for x in [rnd.randrange(0, SINH_MAX_RAW) for _ in range(3000)] + list(range(0, 5000, 7)):
        assert hyp_core(x) == hyp_core_exact(x), x
        assert sinh(-x) == -sinh(x) and cosh(-x) == cosh(x) and sinhc(-x) == sinhc(x), x
        assert tanh(-x) == -tanh(x), x
    assert tanh(TANH_SAT_RAW - 1) == ONE - 1 and tanh(TANH_SAT_RAW) == ONE
    assert TANH_SAT_RAW == TANH_SAT_EXACT
    for lo, hi in ((TANH_SAT_RAW, 24 * ONE), (-(1 << 63), -TANH_SAT_RAW)):
        for x in grid(lo, hi, 2001):
            assert tanh(x) == (ONE if x > 0 else -ONE), x
    # Nothing between the saturation and 16.29 (where T would leave the range) is reached.
    assert exp_q(2 * TANH_SAT_RAW) - (TANH_SHIFT << QB) < (KHI << QB)
    for x in [rnd.randrange(-TANH_SPLIT + 1, TANH_SPLIT) for _ in range(3000)] + list(range(3000)):
        assert tanh_recip(x) == tanh(x), x
    windows = [HYP_POLY, HYP_SPLIT, 0, ONE, SINH_MAX_RAW - 3000] + [
        rnd.randrange(0, SINH_MAX_RAW - 3000) for _ in range(40)]
    twin = [TANH_SPLIT, TANH_SAT_RAW, 0, ONE] + [rnd.randrange(0, TANH_SAT_RAW) for _ in range(40)]
    for fn, centers in ((sinh, windows), (cosh, windows), (tanh, twin)):
        for c in centers:
            xs = range(max(c - 2000, -3000 if fn is not cosh else 0), min(c + 2000, SINH_MAX_RAW))
            vals = [fn(x) for x in xs]
            assert vals == sorted(vals), (fn.__name__, c)

# ----------------------------------------------------------------- Cairo emission


def horner_body_wide(coeffs, var):
    lines = [f"    let acc = Fixed {{ raw: {hexi(coeffs[0])} }};"]
    for c in coeffs[1:-1]:
        lines.append(f"    let acc = step({var}, acc, Fixed {{ raw: {hexi(c)} }});")
    lines.append(f"    step({var}, acc, Fixed {{ raw: {hexi(coeffs[-1])} }})")
    return lines


def tree(lo, hi, indent, ty):
    """The unrolled binary search of `e = floor(log2(x))` for `e` in `[lo, hi]`."""
    pad = "    " * indent
    if lo == hi:
        return [f"{pad}({hexi(1 << (M_BITS - lo))}, {hexi((lo - 32) << LOG_ACC)})"]
    mid = (lo + hi + 1) // 2
    return (
        [f"{pad}if x < {hexi(1 << mid)} {{"]
        + tree(lo, mid - 1, indent + 1, ty)
        + [f"{pad}}} else {{"]
        + tree(mid, hi, indent + 1, ty)
        + [f"{pad}}}"]
    )


def emit_tree(name, doc):
    # A balanced binary search, not an if-chain: the `else { if .. }` nesting is its shape.
    out = [doc, "#[inline(always)]", "#[allow(collapsible_if_else)]",
           f"fn {name}(x: u64) -> (u64, i64) {{"]
    out += tree(0, 62, 1, "u64")
    out.append("}")
    return out


def emit_table(name, values, doc, ty="i64"):
    return [doc, f"const {name}: [{ty}; {len(values)}] = ["] + wrap_table(values) + ["];"]


def fmt_err(v, unit):
    return f"{v:.2f}" if unit == "ULP" else f"{v:.2e} x 2^-30"


def emit_lib(errors):
    out = []
    a = out.append
    a("/// The smallest raw input of `exp2` whose result does not fit the scalar range (it rounds")
    a("/// to `2^31` or above).")
    a(f"const EXP2_MAX_RAW: i64 = {hexi(EXP2_MAX_RAW)};")
    a("/// `-33` in raw units: below it `2^x < 2^-33` rounds to zero.")
    a(f"const EXP2_MIN_RAW: i64 = {hexi(KLO * ONE)};")
    a("/// The smallest raw input of `exp` whose result does not fit the scalar range.")
    a(f"const EXP_MAX_RAW: i64 = {hexi(EXP_MAX_RAW)};")
    a("/// The smallest raw input of `exp` whose wide exponent `x * log2(e)` reaches `-33`: below")
    a("/// it `e^x < 2^-33` rounds to zero.")
    a(f"const EXP_MIN_RAW: i64 = {hexi(EXP_MIN_RAW)};")
    a(f"/// `log2(e) * 2^{QB}`, rounded to nearest: `x * LOG2_E_Q`, narrowed once, is the wide")
    a(f"/// exponent `x * log2(e)` with {QB} fractional bits.")
    a(f"const LOG2_E_Q: Fixed = Fixed {{ raw: {hexi(LOG2_E_Q)} }};")
    a("/// `33 * 2^32`: biases a raw exponent in `[-33, 31)` to a non-negative table offset.")
    a(f"const EXP2_BIAS: i64 = {hexi(-KLO * ONE)};")
    a(f"/// `33 * 2^{QB}`: the same bias at the scale of the wide exponent.")
    a(f"const EXP_BIAS_Q: i64 = {hexi(-KLO << QB)};")
    a("/// `1 / 16` in raw units: the segment width of the `exp2` reduction.")
    a(f"const EXP2_SEG_NZ: NonZero<u64> = {hexi(SEG_RAW)};")
    a(f"/// `1 / 16` at the scale of the wide exponent (`2^{QB - 4}`).")
    a(f"const EXP_SEG_Q_NZ: NonZero<u64> = {hexi(Q_SEG)};")
    a(f"/// `2^{64 - QB}`: lifts the fraction of the wide exponent to the Q64.64 scale.")
    a(f"const EXP_FRAC_LIFT: Fixed = Fixed {{ raw: {1 << (64 - QB)} }};")
    a(f"/// `16`: `TABLE * P * 16 / 2^64 = TABLE * P / 2^{EXP_ACC}`, the rescale of `exp2_core`.")
    a("const SIXTEEN: Fixed = Fixed { raw: 16 };")
    a(f"/// `2^{M_BITS}`: the leading bit of a normalised mantissa.")
    a(f"const MANT_ONE: u64 = {hexi(1 << M_BITS)};")
    a("/// `1 / 32` at the scale of the mantissa: the segment width of the `log2` polynomials.")
    a(f"const LOG_SEG_NZ: NonZero<u64> = {hexi(LOG_SEG_RAW)};")
    a(f"/// `2^{64 - M_BITS}`: lifts the mantissa fraction to the Q64.64 scale.")
    a(f"const LOG_FRAC_LIFT: Fixed = Fixed {{ raw: {1 << (64 - M_BITS)} }};")
    a(f"/// `2^{96 - LOG_ACC}`: `A * K / 2^64` turns the log accumulator (`2^{LOG_ACC}`) into Q32.32.")
    a(f"const K_LOG2: Fixed = Fixed {{ raw: {hexi(K_LOG2)} }};")
    a(f"/// `ln(2) * 2^{96 - LOG_ACC}`, rounded to nearest.")
    a(f"const K_LN: Fixed = Fixed {{ raw: {hexi(K_LN)} }};")
    a(f"/// `log10(2) * 2^{96 - LOG_ACC}`, rounded to nearest.")
    a(f"const K_LOG10: Fixed = Fixed {{ raw: {hexi(K_LOG10)} }};")
    a("")
    a(f"/// `2^g` for `g` in `[0, 1/16)`, degree {DEG_EXP2}, in the Q64.64 fraction `u`, at the")
    a(f"/// scale `2^{EXP_ACC}`. Minimax with the constant term pinned to 1 so that `exp2(k) = 2^k`")
    a("/// exactly.")
    a("#[inline(always)]")
    a("fn exp2_poly(u: W1) -> Fixed {")
    out += horner_body_wide(EXP2_C, "u")
    a("}")
    a("")
    out += emit_table(
        "EXP2_TABLE", TABLE,
        f"/// `round(2^((i - {-TAB_LO}) / 16) * 2^32)` for `i` in `0..{TAB_LEN}`: `2^(k/16)` for every\n"
        f"/// exponent of the range, so that the power of two and the segment share one lookup.",
    )
    for j in range(LOG_SEGS):
        a("")
        a(f"/// `log2(1 + {j} / 32 + t)` for `t` in `[0, 1/32)`, degree {DEG_LOG}, at the scale")
        a(f"/// `2^{LOG_ACC}`." + (" The constant term is pinned to 0: `log2(2^k) = k`." if j == 0 else ""))
        a("#[inline(always)]")
        a(f"fn log2_seg{j}(u: W1) -> Fixed {{")
        out += horner_body_wide(LOG_C[j], "u")
        a("}")
    a("")
    a("/// Dispatches `log2(1 + j / 32 + t)` on the segment index (a jump table, never an if-chain).")
    a("#[inline(always)]")
    a("fn log2_poly(j: u64, u: W1) -> Fixed {")
    a("    match j {")
    for j in range(LOG_SEGS - 1):
        a(f"        {j} => log2_seg{j}(u),")
    a(f"        _ => log2_seg{LOG_SEGS - 1}(u),")
    a("    }")
    a("}")
    a("")
    out += emit_tree(
        "normalize",
        "/// `(2^(62 - e), (e - 32) * 2^56)` for `e = floor(log2(x))`, `x` in `[1, 2^63)`: an unrolled\n"
        "/// binary search on constant thresholds (6 comparisons, no loop, no bitwise operation).",
    )
    a("")
    a("/// Measured maximum error of the mirrored implementation (`scripts/gen_exp.py sweep`):")
    a("/// absolute in ULP (`2^-32`), or relative in units of `2^-30` where marked.")
    a("///")
    a("/// | function | range | max error |")
    a("/// |---|---|---:|")
    for k, (v, unit) in errors.items():
        name, _, rng = k.partition(" (")
        rng = rng[:-1] if rng.endswith(")") else rng
        a(f"/// | `{name}` | {rng} | {fmt_err(v, unit)} |")
    return "\n".join(out)


def emit_alt(single, cw, atanh):
    out = []
    a = out.append
    a("/// `16`: `TABLE * P * 16 / 2^64 = TABLE * P / 2^60`.")
    a("const SIXTEEN: Fixed = Fixed { raw: 16 };")
    a(f"const EXP2_MAX_RAW: i64 = {hexi(EXP2_MAX_RAW)};")
    a(f"const EXP_MAX_RAW: i64 = {hexi(EXP_MAX_RAW)};")
    a(f"const EXP_MIN_RAW: i64 = {hexi(EXP_MIN_RAW)};")
    a("/// `-32` in raw units: the lower end of the power-of-two table of `exp2_single_poly`.")
    a(f"const P2_MIN_RAW: i64 = {hexi(-32 * ONE)};")
    a("const ONE_NZ: NonZero<u64> = 0x100000000;")
    a("/// `floor(ln(2) / 16 * 2^32)`: the Cody-Waite divisor.")
    a(f"const CW_D_NZ: NonZero<u64> = {CW_D};")
    a("/// `(ln(2) / 16 * 2^32 - CW_D) * 2^32`: its tail, at the Q64.64 scale.")
    a(f"const CW_TAIL: Fixed = Fixed {{ raw: {CW_TAIL} }};")
    a(f"/// `{CW_BIAS} * CW_D`: makes the dividend non-negative over the whole domain.")
    a(f"const CW_BIAS: i64 = {CW_BIAS * CW_D};")
    a(f"const CW_BIAS_K: i64 = {CW_BIAS};")
    a(f"/// `CW_BIAS_K - {-TAB_LO}`: turns the biased quotient into a table index.")
    a(f"const CW_IDX_SHIFT: u64 = {CW_BIAS + TAB_LO};")
    a("")
    a(f"/// `2^f` on `[0, 1)`, degree {DEG_EXP2_SINGLE}, scale `2^{EXP_ACC}`.")
    a("#[inline(always)]")
    a("fn exp2_poly_single(u: W1) -> Fixed {")
    out += horner_body_wide(single, "u")
    a("}")
    a("")
    a(f"/// `e^r` on `[0, ln(2) / 16)`, degree {DEG_EXP_CW}, scale `2^{EXP_ACC}`.")
    a("#[inline(always)]")
    a("fn exp_poly_cw(u: W2) -> Fixed {")
    out += [ln.replace("step(", "step2(") for ln in horner_body_wide(cw, "u")]
    a("}")
    a("")
    a(f"/// `2 / ln(2) * atanh(s) / s` in `u = s^2` on `[0, 1/9]`, degree {DEG_ATANH}, scale")
    a(f"/// `2^{LOG_ACC}`.")
    a("#[inline(always)]")
    a("fn atanh_poly(u: W1) -> Fixed {")
    out += horner_body_wide(atanh, "u")
    a("}")
    a("")
    out += emit_table("P2_TABLE", P2_TABLE, "/// `2^k` at Q32.32 for `k` in `-32..=30`.")
    out += emit_table("EXP2_TABLE", TABLE, "/// A copy of the library table (private there).")
    out += emit_table(
        "MSB8", [0] + [v.bit_length() - 1 for v in range(1, 256)],
        "/// `floor(log2(v))` for `v` in `0..256` (`v = 0` is never read).", "u32",
    )
    out += emit_table(
        "POW62", [1 << (M_BITS - e) for e in range(63)], "/// `2^(62 - e)` for `e` in `0..63`.",
        "u64",
    )
    a("")
    out += emit_tree("normalize_tree_scaled", "/// A copy of the library search tree.")
    return "\n".join(out)


def emit_hyp(errors):
    out = []
    a = out.append
    a("/// The smallest raw input whose `sinh` does not fit the scalar range: `asinh(2^31)`,")
    a("/// rounded up.")
    a(f"const SINH_MAX_RAW: i64 = {hexi(SINH_MAX_RAW)};")
    a("/// The smallest raw input whose `cosh` does not fit (`acosh(2^31)`, rounded up; it agrees")
    a("/// with `asinh(2^31)` to `1e-18`).")
    a(f"const COSH_MAX_RAW: i64 = {hexi(COSH_MAX_RAW)};")
    a("/// The smallest raw input whose `tanh` rounds to 1 (`1 - tanh(x) <= 2^-33`): `tanh` returns")
    a("/// `ONE` from there on without computing.")
    a(f"const TANH_SAT_RAW: i64 = {hexi(TANH_SAT_RAW)};")
    a(f"/// `{HYP_POLY // ONE}` in raw units: below it `sinh` and `sinhc` evaluate the polynomial.")
    a(f"const HYP_POLY_RAW: i64 = {hexi(HYP_POLY)};")
    a(f"/// `{HYP_SPLIT // ONE}` in raw units: from it on the core computes `e^x / 2` (`e^x` leaves the")
    a("/// range at 21.49).")
    a(f"const HYP_SPLIT_RAW: i64 = {hexi(HYP_SPLIT)};")
    a(f"/// `{TANH_SPLIT / ONE}` in raw units: from it on `tanh` computes `e^(2x) * 2^-{TANH_SHIFT}`.")
    a(f"const TANH_SPLIT_RAW: i64 = {hexi(TANH_SPLIT)};")
    a(f"/// `1` at the scale of the wide exponent (`2^{QB}`): `2^(t - 1) = e^x / 2`.")
    a(f"const Q_ONE: i64 = {hexi(1 << QB)};")
    a(f"/// `{TANH_SHIFT}` at the scale of the wide exponent.")
    a(f"const TANH_SHIFT_Q: i64 = {hexi(TANH_SHIFT << QB)};")
    a(f"/// `2^-{TANH_SHIFT}` in raw units.")
    a(f"const TANH_C_LOW: i64 = {hexi(ONE >> TANH_SHIFT)};")
    a("")
    a(f"/// `sinh(x) / x` in `u = x^2` (Q64.64) on `[0, 4]`, degree {DEG_SINHC}, at the scale")
    a(f"/// `2^{EXP_ACC}`. Constant term pinned to 1; all the coefficients are non-negative, so it is")
    a("/// non-decreasing in `u` by construction.")
    a("#[inline(always)]")
    a("fn sinhc_poly(u: W1) -> Fixed {")
    out += horner_body_wide(SINHC_C, "u")
    a("}")
    a("")
    a("/// Measured maximum error of the mirrored hyperbolic functions (`scripts/gen_exp.py")
    a("/// sweep`): absolute in ULP (`2^-32`), or relative in units of `2^-30` where marked.")
    a("///")
    a("/// | function | range | max error |")
    a("/// |---|---|---:|")
    for k, (v, unit) in errors.items():
        name, _, rng = k.partition(" (")
        rng = rng[:-1] if rng.endswith(")") else rng
        a(f"/// | `{name}` | {rng} | {fmt_err(v, unit)} |")
    return "\n".join(out)

# ----------------------------------------------------------------- test tables

EXP2_CASES = [0, 1, -1, ONE, -ONE, ONE // 2, -ONE // 2, 3 * ONE + ONE // 3, 10 * ONE,
              -10 * ONE, 16 * ONE + 12345, 30 * ONE, EXP2_MAX_RAW - 1, -32 * ONE, -33 * ONE,
              -33 * ONE - 1, 123456789, -987654321]
EXP_CASES = [0, 1, -1, ONE, -ONE, ONE // 2, 2 * ONE, -2 * ONE, 10 * ONE, -10 * ONE, 20 * ONE,
             EXP_MAX_RAW - 1, EXP_MIN_RAW, EXP_MIN_RAW - 1, -22 * ONE, 123456789, -987654321]
LOG_CASES = [1, 2, 3, 12345, ONE // 3, ONE // 2, ONE - 1, ONE, ONE + 1, 2 * ONE, 3 * ONE,
             10 * ONE, 11674931555, 100 * ONE + 7, 1 << 50, I64_MAX]
POWF_CASES = [(2 * ONE, ONE // 2), (2 * ONE, -ONE), (3 * ONE, 2 * ONE), (ONE // 2, 10 * ONE),
              (10 * ONE, 3 * ONE + ONE // 4), (ONE + 1, 1000 * ONE), (-2 * ONE, 3 * ONE),
              (-2 * ONE, -2 * ONE), (-ONE // 2, 5 * ONE), (0, ONE // 2), (0, 0), (5 * ONE, 0),
              (ONE // 4, -ONE // 2), (7 * ONE, 11 * ONE), (ONE // 1000, 5 * ONE)]
LOG_BASE_CASES = [(8 * ONE, 2 * ONE), (1000 * ONE, 10 * ONE), (ONE // 8, 2 * ONE),
                  (5 * ONE, ONE // 2), (3 * ONE, 3 * ONE), (ONE, 7 * ONE), (100 * ONE, 11674931555)]

SINH_CASES = [0, 1, -1, 12345, ONE // 2, -ONE // 2, ONE, -ONE, 2 * ONE - 1, 2 * ONE, -2 * ONE,
              3 * ONE, 5 * ONE + ONE // 3, 10 * ONE, -10 * ONE, 20 * ONE, 21 * ONE - 1, 21 * ONE,
              22 * ONE, SINH_MAX_RAW - 1, -(SINH_MAX_RAW - 1), 123456789, -987654321]
TANH_CASES = [0, 1, -1, 2, 12345, ONE // 2, ONE, -ONE, 3 * ONE, TANH_SPLIT - 1, TANH_SPLIT,
              8 * ONE, -8 * ONE, TANH_SAT_RAW - 1, TANH_SAT_RAW, -TANH_SAT_RAW, -TANH_SAT_RAW + 1,
              20 * ONE, I64_MAX, I64_MIN, 123456789]
COSHC_CASES = [3, -3, 12345, ONE // 2, ONE, -ONE, 2 * ONE, 5 * ONE, -5 * ONE, 20 * ONE,
               COSH_MAX_RAW - 1]


def print_tables():
    print("// exp2 (x, expected)")
    for raw in EXP2_CASES:
        print(f"    ({hexi(raw)}, {hexi(exp2(raw))}),")
    print("// exp / exp_m1 (x, exp, exp_m1)")
    for raw in EXP_CASES:
        print(f"    ({hexi(raw)}, {hexi(exp(raw))}, {hexi(exp_m1(raw))}),")
    print("// log2 / ln / log10 (x, log2, ln, log10)")
    for raw in LOG_CASES:
        print(f"    ({hexi(raw)}, {hexi(log2(raw))}, {hexi(ln(raw))}, {hexi(log10(raw))}),")
    print("// ln_1p (x, expected)")
    for raw in (0, 1, -1, ONE, -ONE // 2, ONE // 1000, 1000 * ONE):
        print(f"    ({hexi(raw)}, {hexi(ln_1p(raw))}),")
    print("// powf (x, n, expected)")
    for x, n in POWF_CASES:
        print(f"    ({hexi(x)}, {hexi(n)}, {hexi(powf(x, n))}),")
    print("// log (x, base, expected)")
    for x, b in LOG_BASE_CASES:
        print(f"    ({hexi(x)}, {hexi(b)}, {hexi(log(x, b))}),")
    print(f"// thresholds: EXP2_MAX_RAW {hexi(EXP2_MAX_RAW)}, EXP_MAX_RAW {hexi(EXP_MAX_RAW)}, "
          f"EXP_MIN_RAW {hexi(EXP_MIN_RAW)}")
    print("// sinh / cosh / sinhc (x, sinh, cosh, sinhc)")
    for raw in SINH_CASES:
        print(f"    ({hexi(raw)}, {hexi(sinh(raw))}, {hexi(cosh(raw))}, {hexi(sinhc(raw))}),")
    print("// tanh (x, expected)")
    for raw in TANH_CASES:
        print(f"    ({hexi(raw)}, {hexi(tanh(raw))}),")
    print("// coshc (x, expected)")
    for raw in COSHC_CASES:
        print(f"    ({hexi(raw)}, {hexi(coshc(raw))}),")
    print(f"// thresholds: SINH_MAX_RAW {hexi(SINH_MAX_RAW)}, COSH_MAX_RAW {hexi(COSH_MAX_RAW)}, "
          f"TANH_SAT_RAW {hexi(TANH_SAT_RAW)}")


# Maximum error tolerated per row. The brief budgets 4 ULP (absolute) for exp2 / exp below 2^16
# and for the logarithms, 2^-30 relative above 2^16; the budgets below lock the measured figures
# in (~20 % above them). `powf` has no brief budget: its rows document the two stages.
BUDGET = {
    "exp2 (result < 2^16)": 2.5, "exp2 (result >= 2^16)": 1e-5,
    "exp (result < 2^16)": 2.5, "exp (result >= 2^16)": 1e-5,
    "exp_m1": 2.5, "log2": 0.9, "ln": 0.8, "log10": 0.7, "ln_1p": 0.8, "log": 2.3,
    "powf (x in [2^-8, 2^8], n in [-4, 4], result < 1)": 2.5,
    "powf (x in [2^-8, 2^8], n in [-4, 4], result >= 1)": 0.6,
    # The brief of the hyperbolic functions targets the order of exp (~2 ULP); the budgets lock
    # the measured figures in, like above.
    "sinh (-2 < x < 2)": 0.65, "sinh (x >= 2, result < 2^16)": 1.8, "sinh (result >= 2^16)": 1e-5,
    "cosh (result < 2^16)": 1.8, "cosh (result >= 2^16)": 1e-5, "tanh": 1.5,
    "sinhc (-2 < x < 2)": 0.65, "sinhc (2 <= x < 12)": 1.35, "coshc": 1.6,
}


def budget(name):
    return BUDGET.get(name, BUDGET.get(name.split(" (")[0]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["emit", "check", "sweep", "tables"])
    args = ap.parse_args()
    check_identities()
    check_hyp()
    if args.cmd == "tables":
        print_tables()
        return
    errors = sweep()
    hyp_errors = sweep_hyp()
    for name, (v, unit) in {**errors, **hyp_errors}.items():
        if v > budget(name):
            sys.exit(f"{name}: {fmt_err(v, unit)} exceeds the {budget(name)} budget")
    if args.cmd == "sweep":
        print(f"{'function':<58} max error")
        for name, (v, unit) in {**errors, **hyp_errors}.items():
            print(f"{name:<58} {fmt_err(v, unit)}")
        alt = build_alt()
        print("alt (exp2 single poly / exp Cody-Waite / log2 atanh):",
              ", ".join(f"{e:.2f}" for e in check_alt(*alt)))
        return
    alt = build_alt()
    check_alt(*alt)
    write = args.cmd == "emit"
    ok = splice(LIB, "exp", emit_lib(errors), write)
    ok &= splice(ALT, "exp", emit_alt(*alt), write)
    ok &= splice(LIB, "hyperbolic", emit_hyp(hyp_errors), write)
    if args.cmd == "check" and not ok:
        sys.exit("the generated blocks are stale: run `scripts/gen_exp.py emit`")


if __name__ == "__main__":
    main()
