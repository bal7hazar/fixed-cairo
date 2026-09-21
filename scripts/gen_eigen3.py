#!/usr/bin/env python3
"""Bit-exact Python mirror, accuracy study and generator of `glamx::eigen3`.

Two algorithms are mirrored in Python integer arithmetic, bit for bit:

* `jacobi`  - the shipped one (`packages/glamx/src/eigen3.cairo`): power-of-two scaling, cyclic
  Jacobi rotations computed without trigonometry, Gram-Schmidt polish of the eigenvectors,
  Rayleigh-quotient refinement of the eigenvalues on the exact (scaled) input.
* `closed`  - the loser (`packages/benches/src/alt/eigen3.cairo`): the closed form of glamx 0.3.1
  (trigonometric roots of the characteristic cubic, eigenvectors by cross products), with the
  scaling and the most-isolated-eigenvalue ordering of Eberly's paper.

Commands:

    scripts/gen_eigen3.py study [--n 1000]   accuracy tables of both algorithms (needs mpmath)
    scripts/gen_eigen3.py sweeps             convergence of the Jacobi sweeps (needs mpmath)
    scripts/gen_eigen3.py vectors            bit-exact test vectors (the table of test_eigen3.cairo)
    scripts/gen_eigen3.py emit [--check]     (re)generates the scale search trees of both files

The generated blocks are delimited by `// GENERATED-BEGIN eigen3` / `// GENERATED-END eigen3`.
"""

import argparse
import math
import random
import re
import sys
from math import isqrt
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "packages/glamx/src/eigen3.cairo"
ALT = ROOT / "packages/benches/src/alt/eigen3.cairo"

FRAC = 32
ONE = 1 << FRAC
I64_MIN, I64_MAX = -(1 << 63), (1 << 63) - 1

# Number of cyclic sweeps of the shipped algorithm (3 rotations each).
SWEEPS = 6
# The scaled matrix has its largest magnitude in [2^54, 2^58) raw (value in [2^22, 2^26)).
TOP = 58
# The closed form needs squares: largest magnitude in [2^40, 2^44) raw (value in [2^8, 2^12)).
CLOSED_DROP = 14
# Below this cross-product length (raw, scaled domain) the closed form treats `A - lambda I` as
# the zero matrix: the 1 ULP rounding of `lambda` moves each cross product by up to
# `|A| * 1 ULP <= 2^12` raw, so a shorter cross product is noise.
CLOSED_CROSS_MIN = 1 << 13


class Panic(Exception):
    pass


# ----------------------------------------------------------------- fixed / wide primitives

def i64(v):
    if not I64_MIN <= v <= I64_MAX:
        raise Panic("Fixed: overflow")
    return v


def narrow32(w):
    """`Wn::narrow`: floor of a Q64.64 accumulator."""
    return i64(w >> 32)


def narrow32r(w):
    """`Wn.add(HALF_ULP).narrow()`: a Q64.64 accumulator rounded to nearest (ties toward
    +infinity)."""
    return i64((w + (1 << 31)) >> 32)


def narrow64(t):
    """`Tn::narrow`: floor of a Q96.96 accumulator."""
    return i64(t >> 64)


def div_trunc(a, b):
    """`Fixed / Fixed`: truncated."""
    if b == 0:
        raise Panic("Fixed: division by zero")
    q = (abs(a) << FRAC) // abs(b)
    return i64(-q if (a < 0) != (b < 0) else q)


def recip_new(d):
    """`RecipTrait::new`: trunc(2^96 / d), signed."""
    if d == 0:
        raise Panic("Fixed: division by zero")
    q = (1 << 96) // abs(d)
    return -q if d < 0 else q


def recip_mul(r, x):
    """`RecipTrait::mul`: round to nearest, ties toward +infinity."""
    return i64((r * x + (1 << 63)) >> 64)


def wsqrt(w):
    """`WideSqrt::sqrt`: floor(sqrt) of a Q64.64 accumulator."""
    if w < 0:
        raise Panic("Fixed: sqrt negative")
    return i64(isqrt(w))


def fsqrt(x):
    """`Fixed::sqrt`."""
    if x < 0:
        raise Panic("Fixed: sqrt negative")
    return isqrt(x << FRAC)


def fabs(x):
    return i64(abs(x))


def normalize3(v):
    """`fixed::wide::normalize3`."""
    n = isqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if n == 0:
        raise Panic("Fixed: division by zero")
    r = (1 << 96) // n
    return [recip_mul(r, c) for c in v]


def cross(a, b):
    return [
        narrow32(a[1] * b[2] - b[1] * a[2]),
        narrow32(a[2] * b[0] - b[2] * a[0]),
        narrow32(a[0] * b[1] - b[0] * a[1]),
    ]


def dot3(a, b):
    return narrow32(a[0] * b[0] + a[1] * b[1] + a[2] * b[2])


# ----------------------------------------------------------------- scaling

def buckets(top):
    """[(exclusive upper bound of the magnitude, exponent e)], the scale is 2^e (e even / 2)."""
    out = []
    e = top - 2
    while e >= 0:
        out.append((1 << (top - e), e))
        e -= 4
    out.append((None, -6))
    return out


def scale_of(m, drop=0):
    """(P, Q, H): `x * P * P / 2^64` scales up, `(y + H) * Q * Q / 2^64` scales back."""
    for bound, e in buckets(TOP):
        if bound is None or m < bound:
            e -= drop
            half = e // 2
            return 1 << (32 + half), 1 << (32 - half), (1 << (e - 1)) if e > 0 else 0
    raise AssertionError


def scale_up(x, p):
    return narrow64(x * p * p)


def scale_down(y, q, h):
    return narrow64(i64(y + h) * q * q)


# ----------------------------------------------------------------- the shipped algorithm

def rotate(app, aqq, apq, arp, arq, vp, vq):
    """One Jacobi rotation zeroing `apq`. Returns (app, aqq, arp, arq, vp, vq)."""
    if apq == 0:
        return app, aqq, arp, arq, vp, vq
    d = i64(aqq - app)
    two = i64(apq + apq)
    r = i64(isqrt(d * d + two * two))
    den = i64(d + r) if d >= 0 else i64(d - r)
    t = div_trunc(two, den)
    h = wsqrt(t * t + (ONE << FRAC))
    rec = recip_new(h)
    c = recip_mul(rec, ONE)
    s = recip_mul(rec, t)
    x = narrow32r(t * apq)
    n_vp = [narrow32r(c * vp[i] - s * vq[i]) for i in range(3)]
    n_vq = [narrow32r(s * vp[i] + c * vq[i]) for i in range(3)]
    return (
        i64(app - x), i64(aqq + x),
        narrow32r(c * arp - s * arq), narrow32r(s * arp + c * arq),
        n_vp, n_vq,
    )


def sweep(st):
    a11, a12, a13, a22, a23, a33, v1, v2, v3 = st
    a11, a22, a13, a23, v1, v2 = rotate(a11, a22, a12, a13, a23, v1, v2)
    a12 = 0
    a11, a33, a12, a23, v1, v3 = rotate(a11, a33, a13, a12, a23, v1, v3)
    a13 = 0
    a22, a33, a12, a13, v2, v3 = rotate(a22, a33, a23, a12, a13, v2, v3)
    a23 = 0
    return a11, a12, a13, a22, a23, a33, v1, v2, v3


def rayleigh(a, v):
    a11, a12, a13, a22, a23, a33 = a
    x, y, z = v
    t = (x * x * a11 + y * y * a22 + z * z * a33
         + 2 * x * y * a12 + 2 * x * z * a13 + 2 * y * z * a23)
    r = narrow64(t)
    e = x * x + y * y + z * z - (ONE << FRAC)
    return i64(r - narrow64(e * r))


def jacobi(a11, a12, a13, a22, a23, a33, sweeps=SWEEPS, polish=True, refine=True, trace=None):
    """Returns (eigenvalues ascending [3], eigenvectors as 3 columns)."""
    m = max(fabs(a11), fabs(a12), fabs(a13), fabs(a22), fabs(a23), fabs(a33))
    if m == 0:
        return [0, 0, 0], [[ONE, 0, 0], [0, ONE, 0], [0, 0, ONE]]
    p, q, h = scale_of(m)
    a = [scale_up(x, p) for x in (a11, a12, a13, a22, a23, a33)]
    st = (a[0], a[1], a[2], a[3], a[4], a[5], [ONE, 0, 0], [0, ONE, 0], [0, 0, ONE])
    for _ in range(sweeps):
        if st[1] == 0 and st[2] == 0 and st[4] == 0:
            break
        st = sweep(st)
        if trace is not None:
            trace.append(max(abs(st[1]), abs(st[2]), abs(st[4])))
    v1, v2, v3 = st[6], st[7], st[8]
    if polish:
        v1 = normalize3(v1)
        k = dot3(v1, v2)
        v2 = normalize3([narrow32((v2[i] << FRAC) - k * v1[i]) for i in range(3)])
        v3 = normalize3(cross(v1, v2))
    if refine:
        lam = [rayleigh(a, v) for v in (v1, v2, v3)]
    else:
        lam = [st[0], st[3], st[5]]
    lam = [scale_down(x, q, h) for x in lam]
    vs = [v1, v2, v3]
    odd = False
    for i, j in ((0, 1), (1, 2), (0, 1)):
        if lam[i] > lam[j]:
            lam[i], lam[j] = lam[j], lam[i]
            vs[i], vs[j] = vs[j], vs[i]
            odd = not odd
    if odd:
        vs[2] = [i64(-c) for c in vs[2]]
    return lam, vs


# ----------------------------------------------------------------- the closed form (alt)

_TRIG = None


def trig():
    global _TRIG
    if _TRIG is None:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import gen_trig
        _TRIG = gen_trig.build()
    return _TRIG


PI_3 = 4497679235  # fixed::FRAC_PI_3
TWO_PI_3 = 2 * PI_3


def closed_eigenvalues(a):
    """Scaled-domain eigenvalues, ascending."""
    a11, a12, a13, a22, a23, a33 = a
    if a12 == 0 and a13 == 0 and a23 == 0:
        return sorted([a11, a22, a33])
    q = div_trunc(i64(a11 + a22 + a33), 3 * ONE)
    d1, d2, d3 = a11 - q, a22 - q, a33 - q
    p2 = narrow32(d1 * d1 + d2 * d2 + d3 * d3 + 2 * (a12 * a12 + a13 * a13 + a23 * a23))
    p = fsqrt(div_trunc(p2, 6 * ONE))
    if p != 0:
        rec = recip_new(p)
        b = [recip_mul(rec, x) for x in (d1, a12, a13, d2, a23, d3)]
        b11, b12, b13, b22, b23, b33 = b
        det = narrow64(
            (b22 * b33 - b23 * b23) * b11 + (b23 * b13 - b33 * b12) * b12
            + (b12 * b23 - b13 * b22) * b13
        )
        r = narrow32(det * (ONE >> 1))
    else:
        r = ONE
    if r <= -ONE:
        phi = PI_3
    elif r >= ONE:
        phi = 0
    else:
        phi = div_trunc(trig().acos(r), 3 * ONE)
    two_p = i64(p + p)
    e1 = narrow32(two_p * trig().cos(phi) + (q << FRAC))
    e3 = narrow32(two_p * trig().cos(i64(phi + TWO_PI_3)) + (q << FRAC))
    e2 = i64(i64(a11 + a22 + a33) - e1 - e3)
    return [e3, e2, e1], r


def closed_eigenvector1(a, lam):
    a11, a12, a13, a22, a23, a33 = a
    c0 = [i64(a11 - lam), a12, a13]
    c1 = [a12, i64(a22 - lam), a23]
    c2 = [a13, a23, i64(a33 - lam)]
    xs = [cross(c0, c1), cross(c0, c2), cross(c1, c2)]
    ds = [i64(isqrt(x[0] * x[0] + x[1] * x[1] + x[2] * x[2])) for x in xs]
    best = 0
    if ds[1] > ds[best]:
        best = 1
    if ds[2] > ds[best]:
        best = 2
    if ds[best] < CLOSED_CROSS_MIN:
        return [ONE, 0, 0]
    return normalize3(xs[best])


def any_orthonormal_pair(v):
    """`glam::Vec3::any_orthonormal_pair`."""
    neg = v[2] < 0
    sign = -ONE if neg else ONE
    sx = -v[0] if neg else v[0]
    den = i64(sign + v[2])
    a = -i64(((1 << 64) // abs(den)) * (-1 if den < 0 else 1))
    b = narrow64(v[0] * v[1] * a)
    u = [narrow64((ONE << 64) + sx * v[0] * a), -b if neg else b, -sx]
    w = [b, narrow64((sign << 64) + v[1] * v[1] * a), -v[1]]
    return u, w


def closed_eigenvector2(a, w, lam):
    a11, a12, a13, a22, a23, a33 = a
    u, v = any_orthonormal_pair(w)

    def mul(x):
        return [
            narrow32(a11 * x[0] + a12 * x[1] + a13 * x[2]),
            narrow32(a12 * x[0] + a22 * x[1] + a23 * x[2]),
            narrow32(a13 * x[0] + a23 * x[1] + a33 * x[2]),
        ]

    au, av = mul(u), mul(v)
    m00 = i64(dot3(u, au) - lam)
    m01 = dot3(u, av)
    m11 = i64(dot3(v, av) - lam)

    def unit(big, small):
        """(1, small / big) normalised: returns (n_big, n_small)."""
        ratio = div_trunc(small, big)
        rec = recip_new(wsqrt(ratio * ratio + (ONE << FRAC)))
        return recip_mul(rec, ONE), recip_mul(rec, ratio)

    def comb(cu, cv):
        return [narrow32(cu * u[i] - cv * v[i]) for i in range(3)]

    if fabs(m00) >= fabs(m11):
        if max(fabs(m00), fabs(m01)) > 0:
            if fabs(m00) >= fabs(m01):
                n00, n01 = unit(m00, m01)
            else:
                n01, n00 = unit(m01, m00)
            return comb(n01, n00)
    else:
        if max(fabs(m11), fabs(m01)) > 0:
            if fabs(m11) >= fabs(m01):
                n11, n01 = unit(m11, m01)
            else:
                n01, n11 = unit(m01, m11)
            return comb(n11, n01)
    return u


def closed(a11, a12, a13, a22, a23, a33):
    m = max(fabs(a11), fabs(a12), fabs(a13), fabs(a22), fabs(a23), fabs(a33))
    if m == 0:
        return [0, 0, 0], [[ONE, 0, 0], [0, ONE, 0], [0, 0, ONE]]
    p, q, h = scale_of(m, CLOSED_DROP)
    a = [scale_up(x, p) for x in (a11, a12, a13, a22, a23, a33)]
    res = closed_eigenvalues(a)
    if isinstance(res, tuple):
        lam, r = res
    else:
        lam, r = res, ONE
    if r >= 0:
        w2 = closed_eigenvector1(a, lam[2])
        w1 = closed_eigenvector2(a, w2, lam[1])
        w0 = cross(w1, w2)
    else:
        w0 = closed_eigenvector1(a, lam[0])
        w1 = closed_eigenvector2(a, w0, lam[1])
        w2 = cross(w0, w1)
    return [scale_down(x, q, h) for x in lam], [w0, w1, w2]


# ----------------------------------------------------------------- study

def to_raw(x):
    return int(round(x * ONE))


def quantize_sym(mat):
    """6 raw entries (a11, a12, a13, a22, a23, a33) of a float symmetric matrix."""
    return tuple(to_raw(mat[i][j]) for i, j in ((0, 0), (0, 1), (0, 2), (1, 1), (1, 2), (2, 2)))


def rand_rotation(rng):
    while True:
        qx, qy, qz, qw = (rng.gauss(0, 1) for _ in range(4))
        n = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
        if n > 1e-3:
            break
    x, y, z, w = qx / n, qy / n, qz / n, qw / n
    return [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ]


def compose(rot, lam):
    return [[sum(rot[i][k] * lam[k] * rot[j][k] for k in range(3)) for j in range(3)]
            for i in range(3)]


def corpora(n, seed=0xE16E3):
    rng = random.Random(seed)
    out = {}

    def scale(lo=-10, hi=25):
        return 2.0 ** rng.uniform(lo, hi)

    out["spd cond<=1e6"] = [
        quantize_sym(compose(rand_rotation(rng), [s * 10 ** -rng.uniform(0, 6) for _ in range(3)]))
        for s in (scale() for _ in range(n))
    ]
    out["indefinite"] = [
        quantize_sym(compose(rand_rotation(rng), [s * rng.uniform(-1, 1) for _ in range(3)]))
        for s in (scale() for _ in range(n))
    ]
    out["diagonal"] = [
        (to_raw(s * rng.uniform(-1, 1)), 0, 0, to_raw(s * rng.uniform(-1, 1)), 0,
         to_raw(s * rng.uniform(-1, 1)))
        for s in (scale() for _ in range(n // 4))
    ]
    two = []
    for _ in range(n):
        s = scale()
        a, b = s * rng.uniform(0.01, 1), s * rng.uniform(0.01, 1)
        lam = [a, a, b]
        rng.shuffle(lam)
        two.append(quantize_sym(compose(rand_rotation(rng), lam)))
    for k in (1, 3, 1000, 1 << 20):
        two.append((2 * k * ONE >> 4, k * ONE >> 4, k * ONE >> 4, 2 * k * ONE >> 4, k * ONE >> 4,
                    2 * k * ONE >> 4))
    out["two equal"] = two
    near = []
    for _ in range(n):
        s = scale()
        a = s * rng.uniform(0.1, 1)
        lam = [a, a * (1 + 10 ** -rng.uniform(3, 10)), s * rng.uniform(0.1, 1)]
        rng.shuffle(lam)
        near.append(quantize_sym(compose(rand_rotation(rng), lam)))
    out["two nearly equal"] = near
    three = [(r, 0, 0, r, 0, r) for r in (1, 2, 3, ONE, 5 * ONE, -7 * ONE, (1 << 57) + 12345,
                                          (1 << 62) // 3, I64_MAX >> 1)]
    for _ in range(n // 4):
        s = scale()
        three.append(quantize_sym(compose(rand_rotation(rng), [s, s, s])))
    out["three equal"] = three
    rank = []
    for _ in range(n):
        s = math.sqrt(scale(-6, 24))
        u = [s * rng.gauss(0, 1) for _ in range(3)]
        v = [s * rng.gauss(0, 1) for _ in range(3)] if rng.random() < 0.5 else [0, 0, 0]
        rank.append(quantize_sym([[u[i] * u[j] + v[i] * v[j] for j in range(3)]
                                  for i in range(3)]))
    out["rank deficient psd"] = rank
    inertia = []
    for _ in range(n):
        mass = 10 ** rng.uniform(-2, 3)
        length = 10 ** rng.uniform(-1, 2)
        thin = length * 10 ** -rng.uniform(1, 4)
        if rng.random() < 0.5:  # rod along x: (thin, L, L)
            lam = [mass * thin * thin / 6, mass * length * length / 12,
                   mass * length * length / 12]
        else:  # plate normal to z
            w = length * rng.uniform(0.2, 1)
            lam = [mass * (w * w + thin * thin) / 12, mass * (length * length + thin * thin) / 12,
                   mass * (length * length + w * w) / 12]
        inertia.append(quantize_sym(compose(rand_rotation(rng), lam)))
    out["rod / plate inertia"] = [x for x in inertia if max(map(abs, x)) < (1 << 62)]
    tiny = [tuple(rng.randint(-40, 40) for _ in range(6)) for _ in range(n // 2)]
    out["tiny (|raw| <= 40)"] = tiny
    huge = []
    for _ in range(n // 2):
        s = 2.0 ** rng.uniform(25, 30.4)
        huge.append(quantize_sym(compose(rand_rotation(rng), [s * rng.uniform(-1, 1)
                                                              for _ in range(3)])))
    out["huge (2^25..2^30.4)"] = huge
    return out


def reference(a):
    import mpmath as mp
    mp.mp.dps = 60
    a11, a12, a13, a22, a23, a33 = a
    mat = mp.matrix([[a11, a12, a13], [a12, a22, a23], [a13, a23, a33]])
    ev = mp.eigsy(mat, eigvals_only=True)
    return sorted(ev)


def metrics(a, lam, vs, ref):
    """All in raw ULPs: (eigenvalue error, residual, orthonormality, reconstruction)."""
    a11, a12, a13, a22, a23, a33 = a
    rows = ((a11, a12, a13), (a12, a22, a23), (a13, a23, a33))
    err = max(abs(lam[i] - float(ref[i])) for i in range(3))
    res = 0.0
    for k in range(3):
        v = vs[k]
        for i in range(3):
            av = sum(rows[i][j] * v[j] for j in range(3)) / ONE
            res = max(res, abs(av - lam[k] * v[i] / ONE))
    orth = 0.0
    for i in range(3):
        for j in range(3):
            d = sum(vs[i][k] * vs[j][k] for k in range(3)) / ONE - (ONE if i == j else 0)
            orth = max(orth, abs(d))
    rec = 0.0
    for i in range(3):
        for j in range(3):
            x = sum(vs[k][i] * lam[k] * vs[k][j] for k in range(3)) / (ONE * ONE)
            rec = max(rec, abs(x - rows[i][j]))
    return err, res, orth, rec


def det_sign(vs):
    c = cross(vs[0], vs[1])
    return dot3(c, vs[2])


def study(n):
    sets = corpora(n)
    print(f"sweeps = {SWEEPS}; errors in raw ULPs (1 ULP = 2^-32); 'rel' = ULPs / max|a_ij| "
          f"(value), i.e. the error of a matrix of unit scale")
    for algo_name, algo in (("jacobi", jacobi), ("closed", closed)):
        print(f"\n## {algo_name}")
        print("| corpus | n | panics | eig max | eig rel max | resid rel max | orth max "
              "| recon rel max | det<0 | unsorted |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for name, mats in sets.items():
            worst = [0.0] * 5
            panics = 0
            neg = 0
            unsorted = 0
            for a in mats:
                try:
                    lam, vs = algo(*a)
                except Panic:
                    panics += 1
                    continue
                ref = reference(a)
                err, res, orth, rec = metrics(a, lam, vs, ref)
                norm = max(1.0, max(map(abs, a)) / ONE)
                vals = (err, err / norm, res / norm, orth, rec / norm)
                worst = [max(w, v) for w, v in zip(worst, vals)]
                if det_sign(vs) < 0:
                    neg += 1
                if not lam[0] <= lam[1] <= lam[2]:
                    unsorted += 1
            print(f"| {name} | {len(mats)} | {panics} | {worst[0]:.1f} | {worst[1]:.2f} "
                  f"| {worst[2]:.2f} | {worst[3]:.1f} | {worst[4]:.2f} | {neg} | {unsorted} |")


def sweeps_study(n):
    sets = corpora(n)
    print("largest off-diagonal magnitude (raw, scaled domain, max over the corpus) after k sweeps")
    print("| corpus | " + " | ".join(str(k + 1) for k in range(8)) + " |")
    print("|---|" + "---|" * 8)
    for name, mats in sets.items():
        worst = [0] * 8
        for a in mats:
            tr = []
            try:
                jacobi(*a, sweeps=8, trace=tr)
            except Panic:
                continue
            tr += [0] * (8 - len(tr))
            worst = [max(w, t) for w, t in zip(worst, tr)]
        print(f"| {name} | " + " | ".join(str(w) for w in worst) + " |")


# ----------------------------------------------------------------- test vectors

VECTORS = [
    # upstream unit test
    (2 * ONE, 7 * ONE, 8 * ONE, 6 * ONE, 3 * ONE, 0),
    # two equal eigenvalues (1, 1, 4), three equal, diagonal unsorted, rank one
    (2 * ONE, ONE, ONE, 2 * ONE, ONE, 2 * ONE),
    (5 * ONE, 0, 0, 5 * ONE, 0, 5 * ONE),
    (2 * ONE, 0, 0, 5 * ONE, 0, 3 * ONE),
    (ONE, 2 * ONE, 3 * ONE, 4 * ONE, 6 * ONE, 9 * ONE),
    # thin rod inertia, tiny, huge, indefinite
    (35791394, -71582788, 0, 143165576, 0, 178956970),
    (3, -2, 1, 0, 5, -4),
    (3 << 60, 1 << 59, -(1 << 60), 1 << 61, 1 << 58, -(3 << 59)),
    (-3 * ONE, ONE >> 1, -(ONE >> 2), ONE, 7 * ONE >> 3, 2 * ONE),
    (12345678901, -2345678901, 345678901, 22345678901, -45678901, 32345678901),
]


def vectors():
    for a in VECTORS:
        lam, vs = jacobi(*a)
        flat = list(a) + lam + vs[0] + vs[1] + vs[2]
        print("    [" + ", ".join(str(x) for x in flat) + "],")


# ----------------------------------------------------------------- generated search trees

def hexi(v):
    return f"-0x{-v:x}" if v < 0 else f"0x{v:x}"


def tree(entries, indent):
    """Balanced search tree over [(bound, leaf)], the last bound is None."""
    pad = "    " * indent
    if len(entries) == 1:
        return f"{pad}{entries[0][1]}\n"
    mid = len(entries) // 2
    bound = entries[mid - 1][0]
    return (f"{pad}if m < {hexi(bound)} {{\n" + tree(entries[:mid], indent + 1)
            + f"{pad}}} else {{\n" + tree(entries[mid:], indent + 1) + f"{pad}}}\n")


def block(drop):
    entries = []
    for bound, e in buckets(TOP):
        p, q, h = scale_of(bound - 1 if bound is not None else 1 << 62, drop)
        leaf = f"scale({hexi(p)}, {hexi(q)}, {hexi(h)})"
        entries.append((bound, leaf))
    lo = TOP - 4 - drop
    body = (
        f"/// The power-of-two scale `2^e` that brings a largest raw magnitude `m > 0` into\n"
        f"/// `[2^{lo}, 2^{lo + 4})`: `e` is even, from `{TOP - 2 - drop}` down to `{-drop}` in "
        f"steps of 4, then `{-6 - drop}` for\n"
        f"/// `m >= 2^{TOP}` (scaled into `[2^{lo - 2}, 2^{lo + 3}]`). An unrolled binary search "
        f"on constant\n/// thresholds (4 comparisons, no loop, no bitwise operation). "
        f"`up = 2^(32 + e/2)`,\n/// `down = 2^(32 - e/2)`, `half = 2^(e - 1)` (`0` if "
        f"`e <= 0`), as raw values.\n"
        f"#[allow(collapsible_if_else)]\nfn scale_of(m: i64) -> Scale {{\n"
        + tree(entries, 1) + "}\n"
    )
    return body


def splice(path, body, write):
    text = path.read_text()
    pat = re.compile(r"(// GENERATED-BEGIN eigen3\n).*?(// GENERATED-END eigen3\n)", re.S)
    if not pat.search(text):
        sys.exit(f"{path}: generated block markers not found")
    new = pat.sub(lambda mo: mo.group(1) + body + mo.group(2), text)
    if new == text:
        return True
    if write:
        path.write_text(new)
        print(f"updated {path.relative_to(ROOT)}")
        return True
    print(f"{path.relative_to(ROOT)} is stale: run scripts/gen_eigen3.py emit")
    return False


def emit(check):
    ok = splice(LIB, block(0), not check)
    ok = splice(ALT, block(CLOSED_DROP), not check) and ok
    if not ok:
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("study")
    s.add_argument("--n", type=int, default=1000)
    s = sub.add_parser("sweeps")
    s.add_argument("--n", type=int, default=1000)
    sub.add_parser("vectors")
    s = sub.add_parser("emit")
    s.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if args.cmd == "study":
        study(args.n)
    elif args.cmd == "sweeps":
        sweeps_study(args.n)
    elif args.cmd == "vectors":
        vectors()
    else:
        emit(args.check)


if __name__ == "__main__":
    main()
