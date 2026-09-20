#!/usr/bin/env python3
"""Coefficient generator and bit-exact mirror of `fixed::trig`.

The minimax polynomials, the range-reduction constants and the lookup tables of
`packages/fixed/src/trig.cairo` (and of the losing variants of
`packages/benches/src/alt/trig.cairo`) are computed here and written between the
`// GENERATED-BEGIN <tag>` / `// GENERATED-END <tag>` markers of those files.

The second half of the file mirrors **every** Cairo function of `fixed::trig` in Python integer
arithmetic, operation by operation (`mul_add` = `floor(a * b + c)` at the Q32.32 scale, `narrow`
= one floor rescale, ...). The mirror is what the error sweeps measure: it is bit-exact with the
Cairo code, so the ULP figures quoted in the doc comments are the ones the library returns, and
the hand-picked test tables of `packages/fixed/tests/test_trig.cairo` are generated from it.

usage:
  scripts/gen_trig.py emit     rewrite the generated blocks of the two Cairo files
  scripts/gen_trig.py check    exit 1 if those blocks are not up to date
  scripts/gen_trig.py sweep    print the measured max error of every function (1 ULP = 2^-32)
  scripts/gen_trig.py tables   print the Cairo test tables (input / expected raw pairs)
"""

import argparse
import math
import random
import re
import sys
from decimal import ROUND_FLOOR, Decimal, getcontext
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "packages/fixed/src/trig.cairo"
ALT = ROOT / "packages/benches/src/alt/trig.cairo"

# ----------------------------------------------------------------- the number format

FRAC = 32
ONE = 1 << FRAC  # raw 1.0
SB = 24  # extra bits carried by a scaled polynomial accumulator
SC = 1 << (FRAC + SB)  # raw 1.0 of a scaled coefficient
INV_S = 1 << (FRAC - SB)  # the `Fixed` that undoes the scaling (2^-24, exact)
I64_MIN, I64_MAX = -(1 << 63), (1 << 63) - 1

getcontext().prec = 60
PI_D = Decimal("3.141592653589793238462643383279502884197169399375105820974944")
PI_RAW = 13493037705  # round(pi * 2^32), as in fixed::fixed
TAU_RAW = 26986075409
FRAC_PI_2_RAW = 6746518852
FRAC_PI_4_RAW = 3373259426  # floor(pi/4 * 2^32) = the octant divisor P4
P4 = FRAC_PI_4_RAW
# pi/4 * 2^32 - P4, itself scaled by 2^32: the Cody-Waite tail of the octant reduction.
P4_TAIL = int(((PI_D / 4 * (1 << 32) - P4) * (1 << 32)).to_integral_value())
SEG = 1 << 29  # atan segment width (1/8 in raw units)
# Half a unit of the final rescale, at the scale of the polynomial accumulators: added to the
# constant term of every polynomial whose result is rescaled by a plain `Fixed *` (cos, atan),
# which turns that floor into a round-to-nearest for free. The polynomials whose result goes
# through a Q96.96 accumulator (sin, acos) use `bounded::narrow64_round` instead.
ROUND_BIAS = 1 << (SB - 1)
# pi/4 at the scale of the polynomial accumulators: the atan segment index 8 (z == 1) lands here.
FRAC_PI_4_SCALED = int(((PI_D / 4) * (1 << (32 + 24))).to_integral_value())
LUT_STEP = 1 << 22  # sin/cos lookup table step (alt variant)
LUT_LEN = P4 // LUT_STEP + 2  # 806 entries: indices 0..=804 plus the interpolation bound

# Degrees (in the reduced variable), chosen so that every sweep below stays inside the budget.
DEG_SIN = 4  # in u = z^2, on [0, (pi/4)^2]
DEG_COS = 5  # in u = z^2
DEG_ACOS = 10  # in x, on [0, 1]
DEG_ATAN = 5  # in t, on [0, 1/8], one polynomial per segment
DEG_SIN_Q = 6  # alt: in u = z^2, on [0, (pi/2)^2]
DEG_COS_Q = 7  # alt: in u = z^2
DEG_ATAN1 = 9  # alt: in v = w^2, on [0, tan(pi/8)^2], single polynomial

# ----------------------------------------------------------------- exact references

def ref_sin_cos(raw):
    """sin and cos of the exact value `raw / 2^32`, reduced with 60-digit pi."""
    x = Decimal(raw) / (1 << FRAC)
    two_pi = 2 * PI_D
    n = (x / two_pi).to_integral_value(rounding=ROUND_FLOOR)
    r = float(x - n * two_pi)
    return math.sin(r), math.cos(r)


def ref_angle(raw):
    """The exactly reduced angle of `raw / 2^32` in [0, 2 pi) as a float."""
    x = Decimal(raw) / (1 << FRAC)
    n = (x / (2 * PI_D)).to_integral_value(rounding=ROUND_FLOOR)
    return float(x - n * 2 * PI_D)


def dsin(x):
    """sin(x) to the working precision of `decimal` (|x| <= pi / 2)."""
    term, acc, k = Decimal(x), Decimal(x), 1
    while abs(term) > Decimal(10) ** -55:
        term = -term * x * x / ((2 * k) * (2 * k + 1))
        acc += term
        k += 1
    return acc


def dcos(x):
    """cos(x) to the working precision of `decimal` (|x| <= pi / 2)."""
    term, acc, k = Decimal(1), Decimal(1), 1
    while abs(term) > Decimal(10) ** -55:
        term = -term * x * x / ((2 * k - 1) * (2 * k))
        acc += term
        k += 1
    return acc


def datan(x):
    """atan(x) to the working precision of `decimal` (|x| <= tan(pi/8))."""
    x = Decimal(x)
    term, acc, k = x, x, 1
    while abs(term / (2 * k - 1)) > Decimal(10) ** -55:
        term = -term * x * x
        acc += term / (2 * k + 1)
        k += 1
    return acc


def dacos_over_sqrt(x):
    """`acos(x) / sqrt(1 - x)` on `[0, 1]`, from the cancellation-free series
    `acos(1 - w) = sqrt(2 w) * sum_n (2n)! / (8^n (n!)^2 (2n + 1)) w^n`."""
    w = Decimal(1) - Decimal(x)
    acc, term = Decimal(0), Decimal(1)  # term = (2n)! / (8^n (n!)^2) w^n
    n = 0
    while True:
        contrib = term / (2 * n + 1)
        acc += contrib
        if n > 4 and abs(contrib) < Decimal(10) ** -55:
            break
        n += 1
        term = term * w * (2 * n - 1) / (4 * n)
    return acc * Decimal(2).sqrt()

# ----------------------------------------------------------------- minimax fitting

def remez(f, a, b, deg, iters=24, grid=20001):
    """Returns the power-basis coefficients (highest degree first) of the minimax polynomial of
    `f` on `[a, b]`, through a Remez exchange written in the Chebyshev basis (the monomial basis
    is too ill-conditioned above degree 6)."""
    n = deg + 2
    k = np.arange(n)
    nodes = (a + b) / 2 + (b - a) / 2 * np.cos(np.pi * k / (n - 1))
    nodes = np.sort(nodes)
    xs = np.linspace(a, b, grid)
    fs = np.array([f(x) for x in xs])
    best = None
    for _ in range(iters):
        fn = np.array([f(x) for x in nodes])
        # T_j(map(x)) for j <= deg, plus the alternating error column.
        m = np.empty((n, n))
        for i, x in enumerate(nodes):
            m[i, :deg + 1] = cheb_basis(x, a, b, deg)
            m[i, deg + 1] = (-1) ** i
        sol = np.linalg.solve(m, fn)
        c = sol[: deg + 1]
        err = np.array([np.dot(cheb_basis(x, a, b, deg), c) for x in xs]) - fs
        emax = np.max(np.abs(err))
        if best is None or emax < best[0]:
            best = (emax, c.copy())
        # New nodes: the local extrema of the error, alternating in sign.
        ext = [0]
        for i in range(1, grid - 1):
            if (err[i] - err[i - 1]) * (err[i + 1] - err[i]) <= 0:
                ext.append(i)
        ext.append(grid - 1)
        picked, prev = [], None
        for i in ext:
            s = np.sign(err[i]) or 1
            if prev is not None and s == prev[0]:
                if abs(err[i]) > abs(err[prev[1]]):
                    picked[-1] = i
                    prev = (s, i)
                continue
            picked.append(i)
            prev = (s, i)
        if len(picked) < n:
            break
        while len(picked) > n:  # keep the n largest alternations, from one end
            picked.pop(0 if abs(err[picked[0]]) < abs(err[picked[-1]]) else -1)
        new = np.sort(xs[picked])
        if np.allclose(new, nodes):
            nodes = new
            break
        nodes = new
    c = best[1]
    poly = np.polynomial.chebyshev.Chebyshev(c, domain=[a, b]).convert(
        kind=np.polynomial.Polynomial,
    )
    return list(poly.coef[::-1])


def cheb_basis(x, a, b, deg):
    t = (2 * x - a - b) / (b - a)
    out = np.empty(deg + 1)
    out[0] = 1.0
    if deg >= 1:
        out[1] = t
    for j in range(2, deg + 1):
        out[j] = 2 * t * out[j - 1] - out[j - 2]
    return out


def fit_shifted(g, a, b, deg, c0):
    """Minimax fit with the constant term pinned to `c0`: `f(x) ~= c0 + x * g(x)` with `g =
    (f(x) - c0) / x` of degree `deg - 1`, sampled without cancellation (`decimal`). Pinning
    keeps the identities exact (`sin(0) = 0`, `cos(0) = 1`, `acos(0) = pi / 2`, `atan(0) = 0`)."""
    return remez(g, a, b, deg - 1) + [c0]


ZERO_D = Decimal(10) ** -30  # stands in for x = 0 in the (f(x) - c0) / x quotients


def scale_coeffs(coeffs):
    """Rounds power-basis coefficients (highest degree first) to the scaled raw integers the
    Cairo Horner uses."""
    out = [int(round(c * SC)) for c in coeffs]
    for c in out:
        # A scaled coefficient is a `Fixed` raw value: it must leave room for the Horner
        # accumulator, whose magnitude stays below the sum of the coefficients.
        assert abs(c) < 1 << 61, f"coefficient {c} leaves no headroom in the Fixed range"
    return out

# ----------------------------------------------------------------- the mirror

def i64(v):
    assert I64_MIN <= v <= I64_MAX, "Fixed: overflow"
    return v


def mul_add(a, b, c):
    """`fixed::wide::mul_add`: floor(a * b + c), one rescale."""
    return i64((a * b + (c << FRAC)) >> FRAC)


def fmul(a, b):
    """`Fixed * Fixed`: floor(a * b)."""
    return i64((a * b) >> FRAC)


def narrow64(v):
    """`T1::narrow`: floor of a Q96.96 accumulator."""
    return i64(v >> 64)


def narrow64_round(v):
    """`bounded::narrow64_round`: round to nearest, ties toward +infinity."""
    return i64((v + (1 << 63)) >> 64)


def div_trunc(a, b):
    """`Fixed / Fixed`: trunc(a / b)."""
    q = (abs(a) << FRAC) // abs(b)
    return i64(-q if (a < 0) != (b < 0) else q)


def horner(coeffs, x):
    """Horner in a Q32.32 variable: `acc = floor(acc * x + c)` per step."""
    acc = coeffs[0]
    for c in coeffs[1:]:
        acc = mul_add(acc, x, c)
    return acc


def horner_wide(coeffs, u):
    """Horner in the exact Q64.64 square `u = z_raw * z_raw`: one Q96.96 rescale per step."""
    acc = coeffs[0]
    for c in coeffs[1:]:
        acc = i64((u * acc + (c << 64)) >> 64)
    return acc


class Mirror:
    """Bit-exact Python mirror of `fixed::trig`, built from the generated coefficients."""

    def __init__(self, sin_c, cos_c, acos_c, atan_c):
        self.sin_c, self.cos_c, self.acos_c, self.atan_c = sin_c, cos_c, acos_c, atan_c

    # -- range reduction ------------------------------------------------
    def reduce8(self, raw):
        """(octant, z, negative) from |raw|; z is the reduced angle, ~[0, pi/4]."""
        mag = abs(raw)
        k, r = divmod(mag, P4)
        # The Cody-Waite tail, rounded to nearest like every other rescale of the module; it is
        # zero for the first four octants, so a small angle is untouched.
        corr = (k * P4_TAIL + (1 << (FRAC - 1))) >> FRAC
        reduced = r - corr
        oct_ = k % 8
        z = reduced if oct_ % 2 == 0 else P4 - reduced
        return oct_, z, raw < 0

    # -- cores ----------------------------------------------------------
    def sin_core(self, z, u):
        return narrow64_round(z * horner_wide(self.sin_c, u) * INV_S)

    def cos_core(self, u):
        return fmul(horner_wide(self.cos_c, u), INV_S)

    def sin(self, raw):
        o, z, neg = self.reduce8(raw)
        u = z * z
        if o in (0, 3):
            m = self.sin_core(z, u)
        elif o in (1, 2):
            m = self.cos_core(u)
        elif o in (4, 7):
            m = -self.sin_core(z, u)
        else:
            m = -self.cos_core(u)
        return -m if neg else m

    def cos(self, raw):
        o, z, _neg = self.reduce8(raw)
        u = z * z
        if o in (0, 7):
            return self.cos_core(u)
        if o in (1, 6):
            return self.sin_core(z, u)
        if o in (2, 5):
            return -self.sin_core(z, u)
        return -self.cos_core(u)

    def sin_cos(self, raw):
        o, z, neg = self.reduce8(raw)
        u = z * z
        s, c = self.sin_core(z, u), self.cos_core(u)
        rs, rc = [
            (s, c), (c, s), (c, -s), (s, -c), (-s, -c), (-c, -s), (-c, s), (-s, c),
        ][o]
        return (-rs if neg else rs), rc

    def tan(self, raw):
        s, c = self.sin_cos(raw)
        ac = abs(c)
        if ac <= 2 and abs(s) >= ac * (1 << 31):
            raise OverflowError("Fixed: tan overflow")
        return div_trunc(s, c)

    # -- inverse circular functions -------------------------------------
    def atan_core(self, z):
        """atan(z) for z in [0, 1] raw."""
        idx, t = divmod(z, SEG)
        if idx == 8:
            return fmul(FRAC_PI_4_SCALED + ROUND_BIAS, INV_S)
        return fmul(horner(self.atan_c[idx], t), INV_S)

    def atan(self, raw):
        a = abs(raw)
        r = self.atan_core(a) if a <= ONE else FRAC_PI_2_RAW - self.atan_core(recip(a))
        return -r if raw < 0 else r

    def atan2(self, y, x):
        ay, ax = abs(y), abs(x)
        (mn, mx, swap) = (ax, ay, True) if ay > ax else (ay, ax, False)
        if mx == 0:
            return 0
        if mx > I64_MAX:
            mn, mx = mn >> 1, mx >> 1
        a = self.atan_core(div_trunc(mn, mx))
        if swap:
            a = FRAC_PI_2_RAW - a
        if x < 0:
            a = PI_RAW - a
        return -a if y < 0 else a

    def acos_core(self, ax):
        """acos(|x|) = sqrt(1 - |x|) * P(|x|) for |x| <= 1 raw."""
        s = math.isqrt((ONE - ax) << FRAC)
        return narrow64_round(s * horner(self.acos_c, ax) * INV_S)

    def acos(self, raw):
        if raw > ONE or raw < -ONE:
            raise ValueError("Fixed: acos domain")
        r = self.acos_core(abs(raw))
        return PI_RAW - r if raw < 0 else r

    def asin(self, raw):
        if raw > ONE or raw < -ONE:
            raise ValueError("Fixed: asin domain")
        r = FRAC_PI_2_RAW - self.acos_core(abs(raw))
        return -r if raw < 0 else r

    def acos_clamped(self, raw):
        return self.acos(max(-ONE, min(ONE, raw)))

    def asin_clamped(self, raw):
        return self.asin(max(-ONE, min(ONE, raw)))


def recip(a):
    """`FixedTrait::recip`: trunc(2^64 / a)."""
    return i64((1 << 64) // a) if a > 0 else -i64((1 << 64) // -a)


DEG_TO_RAD_S = int(round(float(PI_D / 180) * SC))
RAD_TO_DEG_S = int(round(float(180 / PI_D) * SC))


def to_radians(raw):
    return narrow64(raw * DEG_TO_RAD_S * INV_S)


def to_degrees(raw):
    return narrow64(raw * RAD_TO_DEG_S * INV_S)

# ----------------------------------------------------------------- coefficient sets

def build():
    """Fits every polynomial and returns the coefficient sets (scaled raw integers)."""
    zmax = P4 / ONE  # the reduced argument bound, as the Cairo code sees it
    umax = zmax * zmax

    sin_c = scale_coeffs(fit_shifted(g_sin, 0.0, umax, DEG_SIN, 1.0))
    cos_c = scale_coeffs(fit_shifted(g_cos, 0.0, umax, DEG_COS, 1.0))
    acos_c = scale_coeffs(fit_shifted(g_acos, 0.0, 1.0, DEG_ACOS, float(PI_D / 2)))
    seg = SEG / ONE
    atan_c = []
    for idx in range(8):
        if idx == 0:
            c = fit_shifted(g_atan, 0.0, seg, DEG_ATAN, 0.0)
        else:
            # No cancellation here: the double-precision `atan` is 1e-16 relative, i.e. 4e-7 ULP.
            c = remez(lambda t, b=idx / 8: math.atan(b + t), 0.0, seg, DEG_ATAN)
        atan_c.append(scale_coeffs(c))
    # `cos_core` and `atan_core` finish with `poly * INV_SCALE`, i.e. a floor: half a unit added
    # to the constant term makes that rescale round to nearest at no cost. `sin_core` and
    # `acos_core` round in the Q96.96 narrow instead, so their coefficients stay untouched.
    cos_c[-1] += ROUND_BIAS
    for c in atan_c:
        c[-1] += ROUND_BIAS
    return Mirror(sin_c, cos_c, acos_c, atan_c)


def g_sin(u):
    """`(sin(z) / z - 1) / u` with `u = z * z`, without cancellation."""
    d = Decimal(u) or ZERO_D
    z = d.sqrt()
    return float((dsin(z) - z) / (z * d))


def g_cos(u):
    """`(cos(z) - 1) / u` with `u = z * z`, without cancellation."""
    d = Decimal(u) or ZERO_D
    return float((dcos(d.sqrt()) - 1) / d)


def g_acos(x):
    """`(acos(x) / sqrt(1 - x) - pi / 2) / x`, without cancellation."""
    d = Decimal(x) or ZERO_D
    return float((dacos_over_sqrt(d) - PI_D / 2) / d)


def g_atan(t):
    """`atan(t) / t`, without cancellation."""
    d = Decimal(t) or ZERO_D
    return float(datan(d) / d)


def g_atan1(v):
    """`(atan(w) / w - 1) / v` with `v = w * w`, without cancellation."""
    d = Decimal(v) or ZERO_D
    w = d.sqrt()
    return float((datan(w) - w) / (w * d))


def check_alt(sin_q, cos_q, atan1, sin_lut, cos_lut):
    """The variants of `benches::alt::trig` are only benchmarked, never asserted in Cairo: a
    broken fit there would make the gas comparison meaningless, so the mirrors of their cores
    are swept here instead."""
    worst_s = worst_c = 0.0
    for i in range(0, FRAC_PI_2_RAW, FRAC_PI_2_RAW // 4000):
        u = fmul(i, i)
        worst_s = max(worst_s, abs(narrow64(i * horner(sin_q, u) * INV_S) - math.sin(i / ONE) * ONE))
        worst_c = max(worst_c, abs(fmul(horner(cos_q, u), INV_S) - math.cos(i / ONE) * ONE))
    assert worst_s < 4 and worst_c < 4, f"quadrant variant: {worst_s:.2f} / {worst_c:.2f} ULP"
    worst_a = 0.0
    for i in range(0, int(math.tan(math.pi / 8) * ONE), 1 << 18):
        v = fmul(i, i)
        worst_a = max(worst_a, abs(narrow64(i * horner(atan1, v) * INV_S) - math.atan(i / ONE) * ONE))
    assert worst_a < 8, f"single-polynomial atan variant: {worst_a:.2f} ULP"
    worst_l = 0.0
    for i in range(0, P4, P4 // 4000):  # table + linear interpolation
        idx, f = divmod(i, LUT_STEP)
        for tab, ref in ((sin_lut, math.sin), (cos_lut, math.cos)):
            lo, hi = tab[idx], tab[idx + 1]
            d = (hi - lo) * f
            got = lo + (d // LUT_STEP if d >= 0 else -((-d) // LUT_STEP))
            worst_l = max(worst_l, abs(got - ref(i / ONE) * ONE))
    assert worst_l < 600, f"table variant: {worst_l:.2f} ULP"
    return worst_s, worst_c, worst_a, worst_l


def datan_shift(base, t):
    """`atan(base + t)` to the working precision of `decimal`, for `base` in `(0, 1)`."""
    x = base + t
    # atan(x) = pi/4 + atan((x - 1) / (x + 1)), whose argument stays inside the series radius.
    return PI_D / 4 + datan((x - 1) / (x + 1))


def build_alt():
    """The polynomials and tables of the losing variants (`benches::alt::trig`)."""
    umax = (FRAC_PI_2_RAW / ONE) ** 2
    sin_q = scale_coeffs(fit_shifted(g_sin, 0.0, umax, DEG_SIN_Q, 1.0))
    cos_q = scale_coeffs(fit_shifted(g_cos, 0.0, umax, DEG_COS_Q, 1.0))
    wmax = math.tan(math.pi / 8)
    atan1 = scale_coeffs(fit_shifted(g_atan1, 0.0, wmax * wmax, DEG_ATAN1, 1.0))
    sin_lut = [int(round(math.sin(i * LUT_STEP / ONE) * ONE)) for i in range(LUT_LEN)]
    cos_lut = [int(round(math.cos(i * LUT_STEP / ONE) * ONE)) for i in range(LUT_LEN)]
    check_alt(sin_q, cos_q, atan1, sin_lut, cos_lut)
    return sin_q, cos_q, atan1, sin_lut, cos_lut

# ----------------------------------------------------------------- error sweeps

def sweep(m, points=40001):
    """Measures the max absolute error of every mirrored function, in ULP (2^-32)."""
    out = {}
    rnd = random.Random(20260920)

    # sin / cos / sin_cos over one turn, plus the reduced range and large arguments.
    for name, span in (("turn", TAU_RAW), ("octant", P4), ("1000 turns", 1000 * TAU_RAW)):
        es, ec = 0.0, 0.0
        for i in range(points):
            raw = -span + (2 * span * i) // (points - 1)
            rs, rc = ref_sin_cos(raw)
            es = max(es, abs(m.sin(raw) - rs * ONE))
            ec = max(ec, abs(m.cos(raw) - rc * ONE))
        out[f"sin ({name})"] = es
        out[f"cos ({name})"] = ec

    # The extreme magnitudes, where the Cody-Waite tail pushes the reduced angle furthest
    # outside [0, pi/4] (up to 0.045 rad).
    es, ec = 0.0, 0.0
    for i in range(points):
        raw = (1 << 63) - 1 - i * ((1 << 62) // points)
        for x in (raw, -raw):
            rs, rc = ref_sin_cos(x)
            es = max(es, abs(m.sin(x) - rs * ONE))
            ec = max(ec, abs(m.cos(x) - rc * ONE))
    out["sin (near MIN / MAX)"] = es
    out["cos (near MIN / MAX)"] = ec

    # sin_cos agrees with sin and cos, bit for bit.
    for _ in range(4000):
        raw = rnd.randrange(-(1 << 63), 1 << 63)
        s, c = m.sin_cos(raw)
        assert (s, c) == (m.sin(raw), m.cos(raw)), raw

    # tan on the safe part of the range.
    # tan is ill-conditioned near pi/2: a 1 ULP perturbation of x moves tan(x) by `1 + tan^2(x)`
    # ULP. Hence two rows: the absolute error where |tan| <= 1, and the condition-normalised
    # error over the whole branch.
    e_small, e_cond = 0.0, 0.0
    for i in range(points):
        raw = -FRAC_PI_2_RAW + (2 * FRAC_PI_2_RAW * i) // (points - 1)
        a = ref_angle(raw if raw >= 0 else raw + TAU_RAW)
        ref = math.tan(a)
        try:
            got = m.tan(raw)
        except OverflowError:  # |cos| below 1 ULP: the documented panic
            continue
        e = abs(got - ref * ONE)
        e_cond = max(e_cond, e / (1.0 + ref * ref))
        if abs(raw) <= FRAC_PI_4_RAW:
            e_small = max(e_small, e)
    out["tan ([-pi/4, pi/4])"] = e_small
    out["tan (whole branch, error / (1 + tan^2))"] = e_cond

    # atan over [-16, 16], atan2 over the four quadrants.
    ea = 0.0
    for i in range(points):
        raw = -16 * ONE + (32 * ONE * i) // (points - 1)
        ea = max(ea, abs(m.atan(raw) - math.atan(raw / ONE) * ONE))
    out["atan (-16 to 16)"] = ea
    e2 = 0.0
    for i in range(points):
        th = -math.pi + 2 * math.pi * i / (points - 1)
        y, x = int(round(math.sin(th) * ONE)), int(round(math.cos(th) * ONE))
        if x == 0 and y == 0:
            continue
        ref = math.atan2(y / ONE, x / ONE)
        e2 = max(e2, abs(m.atan2(y, x) - ref * ONE))
    out["atan2 (unit circle)"] = e2

    # acos / asin over [-1, 1].
    ec, es = 0.0, 0.0
    for i in range(points):
        raw = -ONE + (2 * ONE * i) // (points - 1)
        v = raw / ONE
        ec = max(ec, abs(m.acos(raw) - math.acos(max(-1.0, min(1.0, v))) * ONE))
        es = max(es, abs(m.asin(raw) - math.asin(max(-1.0, min(1.0, v))) * ONE))
    out["acos"] = ec
    out["asin"] = es

    # to_radians / to_degrees.
    ed, er = 0.0, 0.0
    for i in range(points):
        raw = -360 * ONE + (720 * ONE * i) // (points - 1)
        ed = max(ed, abs(to_radians(raw) - raw / ONE * float(PI_D / 180) * ONE))
        er = max(er, abs(to_degrees(raw) - raw / ONE * float(180 / PI_D) * ONE))
    out["to_radians ([-360, 360] deg)"] = ed
    out["to_degrees ([-360, 360] rad)"] = er
    return out


def check_identities(m):
    """The exact identities the tests also assert."""
    assert m.sin(0) == 0
    assert m.cos(0) == ONE
    assert m.sin(FRAC_PI_2_RAW) == ONE
    assert m.sin_cos(0) == (0, ONE)
    assert m.acos(ONE) == 0
    assert m.acos(0) == FRAC_PI_2_RAW
    assert m.acos(-ONE) == PI_RAW
    assert m.asin(0) == 0
    assert m.asin(ONE) == FRAC_PI_2_RAW
    assert m.asin(-ONE) == -FRAC_PI_2_RAW
    assert m.atan(0) == 0
    assert m.atan2(0, 0) == 0
    assert m.atan2(ONE, 0) == FRAC_PI_2_RAW
    assert m.atan2(-ONE, 0) == -FRAC_PI_2_RAW
    assert m.atan2(0, ONE) == 0
    assert m.atan2(0, -ONE) == PI_RAW
    assert m.atan2(ONE, ONE) == FRAC_PI_4_RAW
    assert m.atan2(ONE, -ONE) == PI_RAW - FRAC_PI_4_RAW
    for raw in (1, 12345, ONE, PI_RAW, TAU_RAW, -7 * ONE, 1 << 40, -(1 << 50)):
        assert m.sin(-raw) == -m.sin(raw), raw
        assert m.cos(-raw) == m.cos(raw), raw
        assert m.atan(-raw) == -m.atan(raw), raw
    for raw in (0, 1, 12345, ONE // 3, ONE):
        assert m.asin(-raw) == -m.asin(raw), raw

# ----------------------------------------------------------------- Cairo emission

def hexi(v):
    return f"-0x{-v:x}" if v < 0 else f"0x{v:x}"


def horner_body(coeffs, var):
    """The Cairo body of a scaled Horner evaluation in a `Fixed` variable."""
    lines = [f"    let acc = Fixed {{ raw: {hexi(coeffs[0])} }};"]
    for c in coeffs[1:-1]:
        lines.append(f"    let acc = mul_add(acc, {var}, Fixed {{ raw: {hexi(c)} }});")
    lines.append(f"    mul_add(acc, {var}, Fixed {{ raw: {hexi(coeffs[-1])} }})")
    return lines


def horner_body_wide(coeffs, var):
    """The Cairo body of a scaled Horner evaluation in the exact Q64.64 square `u`."""
    lines = [f"    let acc = Fixed {{ raw: {hexi(coeffs[0])} }};"]
    for c in coeffs[1:-1]:
        lines.append(f"    let acc = step({var}, acc, Fixed {{ raw: {hexi(c)} }});")
    lines.append(f"    step({var}, acc, Fixed {{ raw: {hexi(coeffs[-1])} }})")
    return lines


def emit_lib(m, errors):
    e = errors
    out = []
    a = out.append
    a("/// `floor(pi / 4 * 2^32)`: the octant divisor of the range reduction.")
    a(f"pub const FRAC_PI_4_RAW: u64 = {P4};")
    a(f"const FRAC_PI_4_NZ: NonZero<u64> = {P4};")
    a("/// `(pi / 4 * 2^32 - FRAC_PI_4_RAW) * 2^32`: the Cody-Waite tail of `pi / 4`, subtracted")
    a("/// once per octant beyond the first turn so that the reduction of a large angle stays")
    a("/// accurate to ~1 ULP instead of drifting by `k * 1.6e-11` radians.")
    a(f"const FRAC_PI_4_TAIL: u64 = {P4_TAIL};")
    a("/// Half a unit of the tail rescale: makes the Cody-Waite correction round to nearest.")
    a(f"const FRAC_PI_4_TAIL_HALF: u64 = {1 << (FRAC - 1)};")
    a("/// The octant divisor as an `i64` (the reduced angle is signed: see `reduce8`).")
    a(f"const FRAC_PI_4_RAW_I: i64 = {P4};")
    a("const EIGHT_NZ: NonZero<u64> = 8;")
    a("const TWO_POW_32_NZ: NonZero<u64> = 0x100000000;")
    a("/// The atan segment width, `1 / 8` in raw units.")
    a(f"const ATAN_SEG_NZ: NonZero<u64> = {hexi(SEG)};")
    a("/// `pi / 4` scaled by `2^24`, the value of the last atan segment (`z == 1`); rescaled by")
    a("/// `INV_SCALE` like every other segment, it yields exactly `FRAC_PI_4`.")
    a(f"const FRAC_PI_4_SCALED: Fixed = Fixed {{ raw: {hexi(FRAC_PI_4_SCALED + ROUND_BIAS)} }};")
    a("/// `2^-24`, exact: undoes the scaling of the polynomial accumulators in the single")
    a("/// rescale that produces the result.")
    a(f"const INV_SCALE: Fixed = Fixed {{ raw: {INV_S} }};")
    a("")
    a(f"/// `sin(z) / z` as a polynomial in `u = z * z`, degree {DEG_SIN}, coefficients scaled by")
    a(f"/// `2^{SB}`. Minimax on `[0, (pi/4)^2]` with the constant term pinned to 1 so that")
    a("/// `sin(z) = z` for a tiny `z`.")
    a("#[inline(always)]")
    a("fn sin_poly(u: W1) -> Fixed {")
    out += horner_body_wide(m.sin_c, "u")
    a("}")
    a("")
    a(f"/// `cos(z)` as a polynomial in `u = z * z`, degree {DEG_COS}, coefficients scaled by")
    a(f"/// `2^{SB}`. Minimax on `[0, (pi/4)^2]` with the constant term pinned to 1 so that")
    a("/// `cos(0) = 1` exactly.")
    a("#[inline(always)]")
    a("fn cos_poly(u: W1) -> Fixed {")
    out += horner_body_wide(m.cos_c, "u")
    a("}")
    a("")
    a(f"/// `acos(x) / sqrt(1 - x)` on `[0, 1]`, degree {DEG_ACOS}, coefficients scaled by `2^{SB}`.")
    a("/// The constant term is pinned to `pi / 2` so that `acos(0)` is exactly `FRAC_PI_2` and")
    a("/// `asin(0)` exactly zero.")
    a("#[inline(always)]")
    a("fn acos_poly(x: Fixed) -> Fixed {")
    out += horner_body(m.acos_c, "x")
    a("}")
    for idx in range(8):
        a("")
        a(f"/// `atan({idx} / 8 + t)` for `t` in `[0, 1/8)`, degree {DEG_ATAN}, scaled by `2^{SB}`.")
        a("#[inline(always)]")
        a(f"fn atan_seg{idx}(t: Fixed) -> Fixed {{")
        out += horner_body(m.atan_c[idx], "t")
        a("}")
    a("")
    a("/// Dispatches `atan(idx / 8 + t)` on the segment index (a jump table, never an if-chain).")
    a("/// `idx == 8` is reached only by `z == 1`, whose result is the exact `FRAC_PI_4`.")
    a("#[inline(always)]")
    a("fn atan_poly(idx: u64, t: Fixed) -> Fixed {")
    a("    match idx {")
    for idx in range(8):
        a(f"        {idx} => atan_seg{idx}(t),")
    a("        _ => FRAC_PI_4_SCALED,")
    a("    }")
    a("}")
    a("")
    a("/// `pi / 180` scaled by `2^24` (57 significant bits instead of the 32 of `DEG_TO_RAD`).")
    a(f"const DEG_TO_RAD_SCALED: Fixed = Fixed {{ raw: {hexi(DEG_TO_RAD_S)} }};")
    a("/// `180 / pi` scaled by `2^24`.")
    a(f"const RAD_TO_DEG_SCALED: Fixed = Fixed {{ raw: {hexi(RAD_TO_DEG_S)} }};")
    a("")
    a("/// Measured maximum absolute error of the mirrored implementation, in ULP (`2^-32`),")
    a("/// over 40 001 points per row (`scripts/gen_trig.py sweep`):")
    a("///")
    a("/// | function | range | max error (ULP) |")
    a("/// |---|---|---:|")
    for k, v in errors.items():
        name, _, rng = k.partition(" (")
        rng = rng[:-1] if rng.endswith(")") else rng
        a(f"/// | `{name}` | {rng or 'full'} | {v:.2f} |")
    return "\n".join(out)


def emit_alt(m, sin_q, cos_q, atan1, sin_lut, cos_lut):
    out = []
    a = out.append
    a("/// `floor(pi / 2 * 2^32)`: the quadrant divisor of the `*_q` variants.")
    a(f"const FRAC_PI_2_NZ: NonZero<u64> = {FRAC_PI_2_RAW};")
    a("const FOUR_NZ: NonZero<u64> = 4;")
    a("/// `floor(pi / 4 * 2^32)`: the octant divisor of the table variants.")
    a(f"const FRAC_PI_4_NZ_ALT: NonZero<u64> = {P4};")
    a(f"const FRAC_PI_4_RAW_ALT: u64 = {P4};")
    a("const EIGHT_NZ_ALT: NonZero<u64> = 8;")
    a("/// `2^-24`, exact: undoes the scaling of the polynomial accumulators.")
    a(f"const INV_SCALE: Fixed = Fixed {{ raw: {INV_S} }};")
    a("/// `round(tan(pi / 8) * 2^32)`: the reduction threshold of the single-polynomial atan.")
    a(f"const TAN_PI_8_RAW: i64 = {int(round(math.tan(math.pi / 8) * ONE))};")
    a("/// The lookup table step, `2^-10` radians.")
    a(f"const LUT_STEP_NZ: NonZero<u64> = {hexi(LUT_STEP)};")
    a(f"const LUT_SHIFT: i64 = {hexi(LUT_STEP)};")
    a("")
    a("/// The octant polynomials of the library, to measure the price of the Cody-Waite tail")
    a("/// (`sin_no_tail` below is the library `sin` with the tail removed).")
    a("#[inline(always)]")
    a("fn sin_poly_oct(u: W1) -> Fixed {")
    out += horner_body_wide(m.sin_c, "u")
    a("}")
    a("")
    a("/// `cos(z)` on `[0, pi/4]`, the library polynomial.")
    a("#[inline(always)]")
    a("fn cos_poly_oct(u: W1) -> Fixed {")
    out += horner_body_wide(m.cos_c, "u")
    a("}")
    a("")
    a(f"/// `sin(z) / z` as a polynomial in `u = z * z` on `[0, (pi/2)^2]`, degree {DEG_SIN_Q},")
    a(f"/// coefficients scaled by `2^{SB}`.")
    a("#[inline(always)]")
    a("fn sin_poly_q(u: Fixed) -> Fixed {")
    out += horner_body(sin_q, "u")
    a("}")
    a("")
    a(f"/// `cos(z)` as a polynomial in `u = z * z` on `[0, (pi/2)^2]`, degree {DEG_COS_Q}.")
    a("#[inline(always)]")
    a("fn cos_poly_q(u: Fixed) -> Fixed {")
    out += horner_body(cos_q, "u")
    a("}")
    a("")
    a(f"/// `atan(w) / w` as a polynomial in `v = w * w` on `[0, tan(pi/8)^2]`, degree {DEG_ATAN1}.")
    a("#[inline(always)]")
    a("fn atan_poly_single(v: Fixed) -> Fixed {")
    out += horner_body(atan1, "v")
    a("}")
    a("")
    a(f"/// `round(sin(i * 2^-10) * 2^32)` for `i` in `0..{LUT_LEN}`.")
    a(f"const SIN_TABLE: [i64; {LUT_LEN}] = [")
    out += wrap_table(sin_lut)
    a("];")
    a(f"/// `round(cos(i * 2^-10) * 2^32)` for `i` in `0..{LUT_LEN}`.")
    a(f"const COS_TABLE: [i64; {LUT_LEN}] = [")
    out += wrap_table(cos_lut)
    a("];")
    return "\n".join(out)


def wrap_table(values, width=96):
    lines, cur = [], "   "
    for v in values:
        item = f" {v},"
        if len(cur) + len(item) > width:
            lines.append(cur)
            cur = "   "
        cur += item
    if cur.strip():
        lines.append(cur)
    return lines


def splice(path, tag, body, write):
    """Rewrites the `tag` block of `path`; returns True when the block was already up to date.

    `scarb fmt` reflows the emitted code (it reflows the long tables in particular), so the
    comparison ignores whitespace: only the values and the code matter."""
    text = path.read_text()
    begin, end = f"// GENERATED-BEGIN {tag}", f"// GENERATED-END {tag}"
    pat = re.compile(re.escape(begin) + r"\n(.*?)" + re.escape(end), re.S)
    found = pat.search(text)
    if not found:
        sys.exit(f"{path}: missing the `{begin}` / `{end}` markers")
    squeeze = lambda s: re.sub(r"\s+", " ", s).strip()
    if squeeze(found.group(1)) == squeeze(body):
        return True
    if write:
        path.write_text(pat.sub(lambda _: f"{begin}\n{body}\n{end}", text))
        print(f"wrote {path.relative_to(ROOT)} (run `scarb fmt`)", file=sys.stderr)
    return False

# ----------------------------------------------------------------- test tables

SIN_CASES = [
    0, 1, -1, ONE, -ONE, ONE // 2, FRAC_PI_4_RAW, FRAC_PI_2_RAW, -FRAC_PI_2_RAW,
    PI_RAW, -PI_RAW, PI_RAW + FRAC_PI_2_RAW, TAU_RAW, -TAU_RAW, 3 * FRAC_PI_4_RAW,
    5 * FRAC_PI_4_RAW, 7 * FRAC_PI_4_RAW, 1000 * TAU_RAW, -1000 * TAU_RAW,
    123456789, -987654321, 1 << 40, -(1 << 45), (1 << 62), -(1 << 62),
]
ATAN2_CASES = [
    (0, 0), (ONE, 0), (-ONE, 0), (0, ONE), (0, -ONE), (ONE, ONE), (ONE, -ONE),
    (-ONE, ONE), (-ONE, -ONE), (ONE, 2 * ONE), (-3 * ONE, 4 * ONE), (1, ONE),
    (ONE, 1), (1 << 40, 1 << 41), (-(1 << 62), 1 << 62), (ONE // 3, 7 * ONE),
]
ACOS_CASES = [
    0, 1, -1, ONE, -ONE, ONE // 2, -ONE // 2, ONE // 4, 3 * ONE // 4, ONE - 1, -ONE + 1,
    3037000500, -3037000500, 2147483648, 123456789,
]


def print_tables(m):
    print("// sin / cos / sin_cos")
    for raw in SIN_CASES:
        s, c = m.sin_cos(raw)
        print(f"    ({hexi(raw)}, {hexi(s)}, {hexi(c)}),")
    print("// atan2 (y, x, expected)")
    for y, x in ATAN2_CASES:
        print(f"    ({hexi(y)}, {hexi(x)}, {hexi(m.atan2(y, x))}),")
    print("// acos / asin")
    for raw in ACOS_CASES:
        print(f"    ({hexi(raw)}, {hexi(m.acos(raw))}, {hexi(m.asin(raw))}),")
    print("// atan")
    for raw in (0, 1, -1, ONE, -ONE, ONE // 2, 4 * ONE, -4 * ONE, 1 << 40, -(1 << 62)):
        print(f"    ({hexi(raw)}, {hexi(m.atan(raw))}),")
    print("// tan")
    for raw in (0, 1, -1, ONE, -ONE, FRAC_PI_4_RAW, -FRAC_PI_4_RAW, PI_RAW, ONE // 3):
        print(f"    ({hexi(raw)}, {hexi(m.tan(raw))}),")
    print("// to_radians / to_degrees")
    for raw in (0, ONE, -ONE, 90 * ONE, 180 * ONE, -45 * ONE, 1, 1 << 40):
        print(f"    ({hexi(raw)}, {hexi(to_radians(raw))}, {hexi(to_degrees(raw))}),")


# Maximum error tolerated per function, in ULP. The brief budgets 4 ULP for the circular
# functions and 8 for the inverse ones; since every final rescale rounds to nearest
# (`docs/DESIGN.md` section 2, second exception) the measured errors are roughly half that, and
# these budgets lock the improvement in: they are ~20 % above what the sweeps return.
BUDGET = {"sin": 2.5, "cos": 2.5, "tan": 3.0, "atan": 3.5, "atan2": 4.0, "acos": 3.5,
          "asin": 3.0, "to_radians": 1.5, "to_degrees": 1.5}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["emit", "check", "sweep", "tables"])
    args = ap.parse_args()
    m = build()
    check_identities(m)
    if args.cmd == "tables":
        print_tables(m)
        return
    errors = sweep(m)
    for name, v in errors.items():
        budget = BUDGET[name.split(" (")[0]]
        if v > budget:
            sys.exit(f"{name}: {v:.2f} ULP exceeds the {budget} ULP budget")
    if args.cmd == "sweep":
        print(f"{'function':<32} max error (ULP)")
        for name, v in errors.items():
            print(f"{name:<32} {v:.3f}")
        return
    alt = build_alt()
    write = args.cmd == "emit"
    ok = splice(LIB, "trig", emit_lib(m, errors), write)
    ok &= splice(ALT, "trig", emit_alt(m, *alt), write)
    if args.cmd == "check" and not ok:
        sys.exit("the generated blocks are stale: run `scripts/gen_trig.py emit`")


if __name__ == "__main__":
    main()
