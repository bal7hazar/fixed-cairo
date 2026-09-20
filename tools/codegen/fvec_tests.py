"""Test template (`packages/glam/tests/test_<m>.cairo`) of tools/codegen/fvec.py.

Three layers, as in docs/DESIGN.md section 5:
  * the glam-rs test cases of `tests/vec{2,3,4}.rs` (`impl_vecN_tests!`, `_signed_tests!`,
    `_float_tests!`), ported as rows of the tables below;
  * tables over pools of edge values (0, +-1 raw, +-1, MIN, MAX, fractions): the expected values
    are computed here, in Python, by the exact Q32.32 oracle of `RAW SEMANTICS` below - the same
    floor / truncation / round-to-nearest rules as `fixed::fixed` and `fixed::wide`;
  * seeded fuzz properties (relations, not values) and one `#[should_panic]` per panic path with
    the exact message.

The glam-rs values themselves are the subject of the golden vectors
(`tools/refgen/specs/<m>.toml` -> `tests/golden_<m>.cairo`), which compare against `DVec*` run on
the same inputs; this file pins the bit-exact fixed-point semantics instead.

Compile budget. The Cairo compiler pays for every call site: each `assert_eq!` inlines the
operators under test and a formatting path, so an unrolled table of cases costs (cases x checks)
call sites. A table here is one `const` of `[i64; W]` rows and ONE `#[test]` that loops over it:
the cost is (checks) call sites, independent of the number of rows. Keep it that way: the CI
runner is killed when the `glam_tests` modules need more than a few GB to compile.
"""
import math
import re
from math import isqrt

import fvec as g

ONE = 1 << 32
MIN_RAW, MAX_RAW = -(1 << 63), (1 << 63) - 1


# --------------------------------------------------------------------------------------------
# RAW SEMANTICS: the Q32.32 oracle (mirrors `fixed::internal::bounded`)
# --------------------------------------------------------------------------------------------
def fits(v):
    return MIN_RAW <= v <= MAX_RAW


def mul(a, b):
    """`floor(a * b)`: the single rescale of `Fixed * Fixed`."""
    return (a * b) >> 32


def div(a, b):
    """`trunc(a / b)`: the corelib signed division."""
    q = (abs(a) << 32) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def rem(a, b):
    """The remainder of the truncated division (sign of `a`, exact)."""
    return a - b * div_int(a, b)


def div_int(a, b):
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def div_euclid(a, b):
    """`a = q * b + rem_euclid(a, b)` with `0 <= r < |b|`, as a whole `Fixed`."""
    return ((a - a % abs(b)) // b) * ONE


def rem_euclid(a, b):
    return a % abs(b)


def mul_add(a, b, c):
    """`floor(a * b + c)`: one rescale."""
    return (a * b + c * ONE) >> 32


def mul_sub(a, b, c, d):
    """`floor(a * b - c * d)`: one rescale."""
    return (a * b - c * d) >> 32


def lerp(a, b, t):
    """`floor(a + (b - a) * t)`: one rescale, exact at `t = 0` and `t = 1`."""
    return (a * ONE + (b - a) * t) >> 32


def dot(xs, ys):
    """The fused kernel: the exact sum of products, floored once."""
    return sum(x * y for x, y in zip(xs, ys)) >> 32


def norm(xs):
    """`isqrt` of the raw sum of squares: the raw length, floored."""
    return isqrt(sum(x * x for x in xs))


def norm_squared(xs):
    return sum(x * x for x in xs) >> 32


def recip(x):
    """`Fixed::recip`: `trunc(2^64 / x)`."""
    q = (1 << 64) // abs(x)
    return q if x > 0 else -q


def recip_wide(d):
    """`RecipTrait::new`: `trunc(2^96 / d)`."""
    q = (1 << 96) // abs(d)
    return q if d > 0 else -q


def recip_mul(r, x):
    """`RecipTrait::mul`: `round(x * r / 2^64)`, ties toward +infinity."""
    return (r * x + (1 << 63)) >> 64


def floor_(x):
    return (x >> 32) << 32


def ceil_(x):
    return -floor_(-x)


def trunc_(x):
    return -((-x >> 32) << 32) if x < 0 else (x >> 32) << 32


def round_(x):
    return -(((-x + (1 << 31)) >> 32) << 32) if x < 0 else (((x + (1 << 31)) >> 32) << 32)


def fract_(x):
    return x - trunc_(x)


def fract_gl_(x):
    return x - floor_(x)


def signum(x):
    return -ONE if x < 0 else ONE


def copysign(x, s):
    return -abs(x) if s < 0 else abs(x)


def to_int_trunc(x):
    return trunc_(x) >> 32


def normalize(xs):
    """`Norm` + `try_recip`: one square root, one division, one rounded product each."""
    length = norm(xs)
    if length == 0:
        return None
    r = (1 << 96) // length
    return [recip_mul(r, x) for x in xs]


def scaled(xs, target):
    """`clamp_length`: `v * (target / len)`."""
    r = (1 << 96) // norm(xs)
    k = recip_mul(r, target)
    return [mul(x, k) for x in xs]


def project_onto(xs, ys):
    k = div(dot(xs, ys), dot(ys, ys))
    return [mul(y, k) for y in ys]


def reject_from(xs, ys):
    k = div(dot(xs, ys), dot(ys, ys))
    return [(x * ONE - y * k) >> 32 for x, y in zip(xs, ys)]


def project_onto_normalized(xs, ys):
    d = dot(xs, ys)
    return [mul(y, d) for y in ys]


def reject_from_normalized(xs, ys):
    d = dot(xs, ys)
    return [(x * ONE - y * d) >> 32 for x, y in zip(xs, ys)]


def reflect(xs, ns):
    t = -2 * dot(xs, ns)
    return [mul_add(t, nc, x) for x, nc in zip(xs, ns)]


def refract(xs, ns, eta):
    n_dot_i = dot(ns, xs)
    s = (ONE * ONE - n_dot_i * n_dot_i) >> 32
    k = (ONE * ONE * ONE - eta * eta * s) >> 64
    if k < 0:
        return [0] * len(xs)
    f = mul_add(eta, n_dot_i, isqrt(k << 32))
    return [mul_sub(eta, x, f, nc) for x, nc in zip(xs, ns)]


def move_towards(xs, ys, d):
    a = [y - x for x, y in zip(xs, ys)]
    length = norm(a)
    if length == 0 or length <= d:
        return list(ys)
    k = recip_mul((1 << 96) // length, d)
    return [mul_add(ac, k, x) for ac, x in zip(a, xs)]


def any_orthonormal_vector(v):
    x, y, z = v
    sign = signum(z)
    a = -recip(sign + z)
    return [(x * y * a) >> 64, (sign * ONE * ONE + y * y * a) >> 64, -y]


def any_orthonormal_pair(v):
    x, y, z = v
    neg = z < 0
    sign = -ONE if neg else ONE
    sx = -x if neg else x
    a = -recip(sign + z)
    b = (x * y * a) >> 64
    first = [(ONE * ONE * ONE + sx * x * a) >> 64, -b if neg else b, -sx]
    return first, any_orthonormal_vector(v)


def element_product(xs):
    if len(xs) == 2:
        return mul(xs[0], xs[1])
    p = (xs[0] * xs[1] * xs[2]) >> 64
    return p if len(xs) == 3 else mul(p, xs[3])


# --------------------------------------------------------------------------------------------
# Input pools (values in units; `(num, den)` is a fraction, `("raw", k)` a raw leaf)
# --------------------------------------------------------------------------------------------
def raw(v):
    if isinstance(v, tuple):
        return v[1] if v[0] == "raw" else v[0] * ONE // v[1]
    return v * ONE


def rawv(vals, n):
    return [raw(v) for v in vals[:n]]


# |x| <= 20: products, sums of squares and triple products stay far from the scalar range.
SMALL = [
    ([1, 2, 3, 4], [5, 6, 7, 8]),
    ([(-3, 2), (7, 4), (-11, 8), (13, 16)], [(5, 2), (-1, 2), (9, 4), (-5, 4)]),
    ([0, 0, 0, 0], [1, 2, 3, 4]),
    ([("raw", 1), ("raw", -1), ("raw", 3), ("raw", -7)],
     [("raw", 5), ("raw", -9), ("raw", 1), ("raw", -1)]),
    ([(1, 3), (2, 3), (-1, 3), (1, 7)], [(-1, 7), (3, 5), (2, 9), (-4, 3)]),
    ([8, -8, 8, -8], [8, 8, -8, -8]),
    ([(-1, 2), (1, 2), (-1, 2), (1, 2)], [1, 1, 1, 1]),
    ([2, -3, 5, -7], [-11, 13, -17, 19]),
    ([(1, 1024), (-1, 1024), (3, 512), 0], [(7, 1024), (1, 2048), (-1, 256), 1]),
]
# Exact operations only (comparisons, min / max, select, ...): the whole scalar range.
EDGE = [
    ([("raw", MIN_RAW), ("raw", MIN_RAW + 1), -65536, -1],
     [("raw", MAX_RAW), ("raw", MAX_RAW - 1), 65536, 1]),
    ([("raw", MAX_RAW), 1, 0, ("raw", -1)], [("raw", MAX_RAW), ("raw", 1), 0, ("raw", 1)]),
    ([-1, 0, 1, 2], [-1, 0, 1, 2]),
    ([0, 0, 0, 0], [("raw", MIN_RAW), ("raw", MAX_RAW), 65536, -65536]),
    ([(1, 2), (-1, 2), (3, 4), (-3, 4)], [(1, 4), (1, 2), (-3, 4), (3, 4)]),
    ([("raw", MIN_RAW), ("raw", MAX_RAW), ("raw", MIN_RAW), ("raw", MAX_RAW)],
     [-1, -1, 1, 1]),
]
# Rounding: fractions around the integers, both signs, plus the extremes `round` / `ceil` accept.
ROUNDING = [
    [0, ("raw", 1), ("raw", -1), (1, 2)],
    [(-1, 2), (3, 2), (-3, 2), (5, 2)],
    [(-5, 2), 7, -7, (99, 8)],
    [(-99, 8), 1000, -1000, (-1, 1024)],
    [("raw", 0x7FFFFFFF), ("raw", -0x7FFFFFFF), ("raw", 0x80000001), ("raw", -0x80000001)],
]
# Non-zero vectors for the normalization family, from 1 raw ULP to 2^15.
LENGTHS = [
    [1, 0, 0, 0],
    [0, -2, 0, 0],
    [3, 4, 0, 0],
    [1, 1, 1, 1],
    [(-3, 2), (7, 4), (-11, 8), (13, 16)],
    [("raw", 1), ("raw", -1), ("raw", 1), ("raw", -1)],
    [("raw", 1), 0, 0, 0],
    [32768, -16384, 8192, -4096],
    [(1, 1024), (1, 2048), (-1, 4096), (1, 8192)],
]
MASKS = {2: [0, 1, 2, 3], 3: list(range(8)), 4: [0, 15, 1, 2, 4, 8, 5, 10]}


# --------------------------------------------------------------------------------------------
# Trigonometry (`fixed::trig`): float references. The inputs are exact doubles (|raw| < 2^53) and
# the reference is correct to 1e-16, i.e. 4e-7 ULP: it is the exact value up to the rounding of
# the quantization (0.5 ULP), so a bound of `e` ULP on the implementation is a tolerance of
# `floor(e + 0.5)` raw units on the integer comparison.
# --------------------------------------------------------------------------------------------
PI_RAW = 13493037705
ANGLES = [0, 1, -1, 429497, -429497, 2147483648, -2147483648, 4294967296, -4294967296,
          6746518852, -6746518852, 3373259426, -3373259426, 8589934592, -8589934592,
          12884901888, -12884901888, 13485000000, -13485000000]
"""Raw angles strictly inside (-pi, pi): 0, +-1 ULP, 1e-4, 0.5, 1, pi/2, pi/4, 2, 3, 3.14 rad."""


def qr(x):
    """The nearest raw value of a real number of radians / units."""
    return round(x * ONE)


def sin_cos_ref(a):
    """`(cos, sin)` of the raw angle `a`, quantized: `<= 1.02` ULP from `fixed::trig`."""
    r = a / ONE
    return [qr(math.cos(r)), qr(math.sin(r))]


def atan2_ref(y, x):
    """`atan2` of two raw values (the ratio is scale free), quantized."""
    return qr(math.atan2(y, x))


def det3(a, b, c):
    """`wide::det3`: the exact triple product `a . (b x c)`, floored once (Q96.96 -> Q32.32)."""
    x = (b[1] * c[2] - c[1] * b[2]) * a[0]
    y = (b[2] * c[0] - c[2] * b[0]) * a[1]
    z = (b[0] * c[1] - c[0] * b[1]) * a[2]
    return (x + y + z) >> 64


def angle_to_2d(v, w):
    """`Vec2::angle_to` on the kernel values (`mul_sub`, `dot2`, one `atan2`)."""
    return atan2_ref(mul_sub(v[0], w[1], v[1], w[0]), dot(v, w))


def rotate_towards_2d(v, w, m):
    """`Vec2::rotate_towards`, from the exact `atan2` of the kernel values."""
    a = math.atan2(mul_sub(v[0], w[1], v[1], w[0]), dot(v, w))
    abs_a = abs(a)
    ang = min(max(m / ONE, abs_a - PI_RAW / ONE), abs_a) * (-1 if a < 0 else 1)
    c, s = math.cos(ang), math.sin(ang)
    return [qr(c * v[0] / ONE - s * v[1] / ONE), qr(s * v[0] / ONE + c * v[1] / ONE)]


# --------------------------------------------------------------------------------------------
# Emission
# --------------------------------------------------------------------------------------------
KINDS = {
    "v": (lambda n: n, "vc"),        # VecN
    "s": (lambda n: 1, "fx"),        # Fixed
    "b": (lambda n: n, "bv"),        # BVecN
    "i": (lambda n: n, "iv"),        # IVecN
    "u": (lambda n: n, "uv"),        # UVecN
    "us": (lambda n: 1, "us"),       # usize
    "bl": (lambda n: 1, "bl"),       # bool
    "opt": (lambda n: n + 1, "ov"),  # Option<VecN>
}


class Gen:
    def __init__(self, t):
        self.t = t
        self.out = []

    def test(self, name, lines, attrs=()):
        body = "\n".join("    " + l for l in lines)
        a = "".join(f"#[{x}]\n" for x in attrs)
        self.out.append(f"#[test]\n{a}fn {name}() {{\n{body}\n}}\n")

    def panic(self, name, msg, lines):
        self.test(name, lines, attrs=[f"should_panic(expected: {msg})"])

    def fuzz(self, name, seed, args, lines):
        body = "\n".join("    " + l for l in lines)
        self.out.append(f"#[test]\n#[fuzzer(runs: 128, seed: {seed})]\n"
                        f"fn {name}({args}) {{\n{body}\n}}\n")

    def cells(self, kind, v):
        n = self.t.n
        if kind in ("v", "i", "u"):
            return [int(k) for k in list(v)[:n]]
        if kind in ("s", "us"):
            return [int(v)]
        if kind == "bl":
            return [1 if v else 0]
        if kind == "b":
            return [1 if k else 0 for k in list(v)[:n]]
        if kind == "opt":
            return [0] * (n + 1) if v is None else [1] + [int(k) for k in list(v)[:n]]
        raise ValueError(kind)

    def table(self, name, spec, rows, body):
        """`const <NAME>: [[i64; W]; K]` (one row per case, one cell per scalar) and
        `test_<name>`: one loop over the rows. `body(a)` gets the Cairo reader expression of every
        column (`a['x']` = `vc(r, 0)`) and returns the lines of the loop body."""
        n = self.t.n
        acc, off = {}, 0
        for col, kind in spec:
            width, reader = KINDS[kind]
            acc[col] = f"{reader}(r, {off})"
            off += width(n)
        flat = [[c for col, kind in spec for c in self.cells(kind, row[col])] for row in rows]
        assert all(len(r) == off for r in flat), name
        assert all(fits(c) for r in flat for c in r), name
        data = ",\n".join("    [" + ", ".join(map(str, r)) + "]" for r in flat)
        const = name.upper()
        self.out.append(f"#[cairofmt::skip]\nconst {const}: [[i64; {off}]; {len(rows)}] = "
                        f"[\n{data},\n];\n")
        lines = [f"for row in {const}.span() {{", "    let r = row.span();"]
        lines += ["    " + l for l in body(acc)]
        lines += ["}"]
        self.test(f"test_{name}", lines)


def gen_tests(t):
    T, n = t.name, t.n
    G = Gen(t)
    test, panic, table = G.test, G.panic, G.table
    cs = t.c
    Tt = f"{T}Trait"
    eq = lambda a, b: f"assert_eq!({a}, {b});"
    V = lambda vals: f"{t.mod}(" + ", ".join(f"f({raw(v)})" for v in list(vals)[:n]) + ")"
    F = lambda v: f"f({raw(v)})"
    small = [(rawv(x, n), rawv(y, n)) for x, y in SMALL]
    edge = [(rawv(x, n), rawv(y, n)) for x, y in EDGE]
    lengths = [rawv(v, n) for v in LENGTHS]

    # ------------------------------------------------------------ constructors and accessors
    one = [1, 2, 3, 4]
    test("test_new_array_tuple", [
        f"let v = {Tt}::new(" + ", ".join(F(k) for k in one[:n]) + ");",
        *[eq(f"v.{c}", F(one[i])) for i, c in enumerate(cs)],
        eq("v", V(one)),
        "let tu = (" + ", ".join(F(k) for k in one[:n]) + ");",
        f"let v: {T} = tu.into();", eq("v", V(one)),
        f"let tu2: ({', '.join(['Fixed'] * n)}) = v.into();", eq("tu2", "tu"),
        "let a = [" + ", ".join(F(k) for k in one[:n]) + "];",
        f"let v: {T} = a.into();", eq("v", V(one)), eq(f"{Tt}::from_array(a)", V(one)),
        f"let a2: [Fixed; {n}] = v.into();", eq("a2", "a"), eq("v.to_array()", "a"),
        eq(f"Default::<{T}>::default()", f"{Tt}::ZERO"),
        eq(f"{Tt}::splat({F(7)})", V([7] * 4)),
        *[eq(f"{V(one)}.with_{c}({F(9)})",
             V([9 if j == i else one[j] for j in range(4)])) for i, c in enumerate(cs)],
        *[eq(f"{V(one)}[{i}]", F(one[i])) for i in range(n)],
    ])
    lines = [eq(f"{Tt}::ZERO", V([0] * 4)), eq(f"{Tt}::ONE", V([1] * 4)),
             eq(f"{Tt}::NEG_ONE", V([-1] * 4)),
             eq(f"{Tt}::MIN", V([("raw", MIN_RAW)] * 4)),
             eq(f"{Tt}::MAX", V([("raw", MAX_RAW)] * 4))]
    unit = lambda i, v=1: [v if j == i else 0 for j in range(4)]
    lines += [eq(f"{Tt}::{c.upper()}", V(unit(i))) for i, c in enumerate(cs)]
    lines += [eq(f"{Tt}::NEG_{c.upper()}", V(unit(i, -1))) for i, c in enumerate(cs)]
    lines += [f"let [{', '.join('a' + c for c in cs)}] = {Tt}::AXES;"]
    lines += [eq(f"a{c}", f"{Tt}::{c.upper()}") for c in cs]
    test("test_consts", lines)
    lines = []
    if n < 4:
        lines.append(eq(f"{V(one)}.extend({F(one[n])})",
                        f"{t.dim(n + 1).mod}(" + ", ".join(F(k) for k in one[:n + 1]) + ")"))
    if n > 2:
        lines.append(eq(f"{V(one)}.truncate()",
                        f"{t.dim(n - 1).mod}(" + ", ".join(F(k) for k in one[:n - 1]) + ")"))
    if n == 3:
        lines += [f"let v: {T} = ({t.dim(2).mod}({F(1)}, {F(2)}), {F(3)}).into();",
                  eq("v", V(one))]
    if n == 4:
        v3 = f"{t.dim(3).mod}({F(1)}, {F(2)}, {F(3)})"
        v2 = f"{t.dim(2).mod}({F(1)}, {F(2)})"
        lines += [f"let v: {T} = ({v3}, {F(4)}).into();", eq("v", V(one)),
                  f"let v: {T} = ({F(1)}, {t.dim(3).mod}({F(2)}, {F(3)}, {F(4)})).into();",
                  eq("v", V(one)),
                  f"let v: {T} = ({v2}, {F(3)}, {F(4)}).into();", eq("v", V(one)),
                  f"let v: {T} = ({v2}, {t.dim(2).mod}({F(3)}, {F(4)})).into();", eq("v", V(one))]
    test("test_extend_truncate", lines)
    a, b = [1, 2, 3, 4], [5, 6, 7, 8]
    table("select", [("m", "b"), ("a", "v"), ("b", "v"), ("e", "v")],
          [{"m": [(m >> i) & 1 for i in range(4)], "a": rawv(a, n), "b": rawv(b, n),
            "e": [raw(a[i]) if (m >> i) & 1 else raw(b[i]) for i in range(n)]}
           for m in MASKS[n]],
          lambda c: [eq(f"{Tt}::select({c['m']}, {c['a']}, {c['b']})", c["e"])])

    # ---------------------------------------------------------------------------- products
    rows = [{"x": x, "y": y, "d": dot(x, y), "l": dot(x, x), "q": dot([p - q for p, q in
                                                                      zip(x, y)],
                                                                     [p - q for p, q in
                                                                      zip(x, y)]),
             "dist": norm([p - q for p, q in zip(x, y)]), "len": norm(x),
             "sum": sum(x), "prod": element_product(x)} for x, y in small]
    table("dot_length", [("x", "v"), ("y", "v"), ("d", "s"), ("l", "s"), ("q", "s"),
                         ("dist", "s"), ("len", "s"), ("sum", "s"), ("prod", "s")], rows,
          lambda c: [eq(f"{c['x']}.dot({c['y']})", c["d"]),
                     eq(f"{c['x']}.dot({c['y']})", f"{c['y']}.dot({c['x']})"),
                     eq(f"{c['x']}.dot_into_vec({c['y']})", f"{Tt}::splat({c['d']})"),
                     eq(f"{c['x']}.length_squared()", c["l"]),
                     eq(f"{c['x']}.distance_squared({c['y']})", c["q"]),
                     eq(f"{c['x']}.distance({c['y']})", c["dist"]),
                     eq(f"{c['x']}.length()", c["len"]),
                     eq(f"{c['x']}.element_sum()", c["sum"]),
                     eq(f"{c['x']}.element_product()", c["prod"])])
    if n == 3:
        cross = lambda p, q: [mul_sub(p[1], q[2], q[1], p[2]), mul_sub(p[2], q[0], q[2], p[0]),
                              mul_sub(p[0], q[1], q[0], p[1])]
        table("cross", [("x", "v"), ("y", "v"), ("e", "v")],
              [{"x": x, "y": y, "e": cross(x, y)} for x, y in small],
              # floor(-p) = -ceil(p): the antisymmetry holds up to the 1 ULP of the rescale
              lambda c: [eq(f"{c['x']}.cross({c['y']})", c["e"]),
                         f"assert!({c['y']}.cross({c['x']}).abs_diff_eq(-{c['e']}, f(1)));"])
        test("test_cross_axes", [
            eq(f"{Tt}::X.cross({Tt}::Y)", f"{Tt}::Z"), eq(f"{Tt}::Y.cross({Tt}::Z)", f"{Tt}::X"),
            eq(f"{Tt}::Z.cross({Tt}::X)", f"{Tt}::Y"),
            eq(f"{Tt}::Y.cross({Tt}::X)", f"{Tt}::NEG_Z"),
            eq(f"{Tt}::X.dot({Tt}::X)", F(1)), eq(f"{Tt}::X.dot({Tt}::Y)", F(0))])
    if n == 2:
        rot = lambda p, q: [mul_sub(p[0], q[0], p[1], q[1]),
                            (p[1] * q[0] + p[0] * q[1]) >> 32]
        table("perp_rotate", [("x", "v"), ("y", "v"), ("p", "v"), ("pd", "s"), ("r", "v")],
              [{"x": x, "y": y, "p": [-x[1], x[0]], "pd": mul_sub(x[0], y[1], x[1], y[0]),
                "r": rot(x, y)} for x, y in small],
              lambda c: [eq(f"{c['x']}.perp()", c["p"]),
                         eq(f"{c['x']}.perp_dot({c['y']})", c["pd"]),
                         eq(f"{c['x']}.perp_dot({c['y']})", f"{c['x']}.perp().dot({c['y']})"),
                         eq(f"{c['x']}.rotate({c['y']})", c["r"])])
        test("test_perp_axes", [
            eq(f"{Tt}::X.perp()", f"{Tt}::Y"), eq(f"{Tt}::Y.perp()", f"{Tt}::NEG_X"),
            eq(f"{Tt}::X.rotate({Tt}::Y)", f"{Tt}::Y"),
            eq(f"{Tt}::Y.rotate({V([3, 4])})", V([-4, 3]))])

    # ------------------------------------------------------------- min / max / clamp / reduce
    cw = lambda f, *vs: [f(*[v[i] for v in vs]) for i in range(n)]
    table("min_max", [("x", "v"), ("y", "v"), ("lo", "v"), ("hi", "v"), ("emin", "s"),
                      ("emax", "s"), ("pmin", "us"), ("pmax", "us")],
          [{"x": x, "y": y, "lo": cw(min, x, y), "hi": cw(max, x, y), "emin": min(x),
            "emax": max(x), "pmin": min(range(n), key=lambda i: (x[i], i)),
            "pmax": min(range(n), key=lambda i: (-x[i], i))} for x, y in edge],
          lambda c: [eq(f"{c['x']}.min({c['y']})", c["lo"]),
                     eq(f"{c['y']}.min({c['x']})", c["lo"]),
                     eq(f"{c['x']}.max({c['y']})", c["hi"]),
                     eq(f"{c['y']}.max({c['x']})", c["hi"]),
                     eq(f"{c['x']}.min_element()", c["emin"]),
                     eq(f"{c['x']}.max_element()", c["emax"]),
                     eq(f"{c['x']}.min_position()", c["pmin"]),
                     eq(f"{c['x']}.max_position()", c["pmax"])])
    lo, hi = rawv([1, 3, 3, 2], n), rawv([6, 8, 8, 9], n)
    clamp = lambda v: [min(max(v[i], lo[i]), hi[i]) for i in range(n)]
    rows = [{"v": rawv([k] * 4, n), "lo": lo, "hi": hi, "e": clamp(rawv([k] * 4, n))}
            for k in (0, 5, 9)]
    rows += [{"v": rawv([0, 4, 7, 10], n), "lo": lo, "hi": hi, "e": clamp(rawv([0, 4, 7, 10], n))},
             {"v": [MIN_RAW] * n, "lo": lo, "hi": hi, "e": lo},
             {"v": [MAX_RAW] * n, "lo": lo, "hi": hi, "e": hi},
             {"v": lo, "lo": [MIN_RAW] * n, "hi": [MAX_RAW] * n, "e": lo}]
    table("clamp", [("v", "v"), ("lo", "v"), ("hi", "v"), ("e", "v")], rows,
          lambda c: [eq(f"{c['v']}.clamp({c['lo']}, {c['hi']})", c["e"])])

    # ---------------------------------------------------------------------------- comparisons
    cmps = [("cmpeq", lambda p, q: p == q), ("cmpne", lambda p, q: p != q),
            ("cmpge", lambda p, q: p >= q), ("cmpgt", lambda p, q: p > q),
            ("cmple", lambda p, q: p <= q), ("cmplt", lambda p, q: p < q)]
    table("cmp", [("x", "v"), ("y", "v")] + [(f, "b") for f, _ in cmps],
          [{"x": x, "y": y, **{f: cw(op, x, y) for f, op in cmps}} for x, y in edge],
          lambda c: [eq(f"{c['x']}.{f}({c['y']})", c[f]) for f, _ in cmps])
    test("test_cmp_all_any", [
        f"let a = {V([1] * 4)};", f"let b = {V([2] * 4)};",
        "assert!(a.cmplt(b).all() && a.cmple(b).all() && b.cmpgt(a).all() && b.cmpge(a).all());",
        "assert!(a.cmpne(b).all() && a.cmpeq(a).all() && !a.cmpeq(b).any() && !a.cmplt(a).any());",
        "assert!(a == a && a != b);"])

    # ------------------------------------------------------------------- sign and rounding
    sign_rows = []
    for x, y in edge:
        if MIN_RAW in x:
            continue
        sign_rows.append({"v": x, "s": y, "abs": [abs(k) for k in x],
                          "sig": [signum(k) for k in x],
                          "cop": [copysign(p, q) for p, q in zip(x, y)],
                          "bm": sum(1 << i for i in range(n) if x[i] < 0),
                          "mask": [k < 0 for k in x]})
    table("sign", [("v", "v"), ("s", "v"), ("abs", "v"), ("sig", "v"), ("cop", "v"),
                   ("bm", "us"), ("mask", "b")], sign_rows,
          lambda c: [eq(f"{c['v']}.abs()", c["abs"]), eq(f"{c['v']}.signum()", c["sig"]),
                     eq(f"{c['v']}.copysign({c['s']})", c["cop"]),
                     eq(f"{c['v']}.is_negative_bitmask()", c["bm"]),
                     eq(f"{c['v']}.is_negative_mask()", c["mask"])])
    rows = []
    for v in ROUNDING:
        v = rawv(v, n)
        rows.append({"v": v, "r": [round_(k) for k in v], "f": [floor_(k) for k in v],
                     "c": [ceil_(k) for k in v], "t": [trunc_(k) for k in v],
                     "fr": [fract_(k) for k in v], "fg": [fract_gl_(k) for k in v]})
    table("rounding", [("v", "v"), ("r", "v"), ("f", "v"), ("c", "v"), ("t", "v"), ("fr", "v"),
                       ("fg", "v")], rows,
          lambda c: [eq(f"{c['v']}.round()", c["r"]), eq(f"{c['v']}.floor()", c["f"]),
                     eq(f"{c['v']}.ceil()", c["c"]), eq(f"{c['v']}.trunc()", c["t"]),
                     eq(f"{c['v']}.fract()", c["fr"]), eq(f"{c['v']}.fract_gl()", c["fg"]),
                     eq(f"{c['v']}.fract()", f"{c['v']} - {c['v']}.trunc()"),
                     eq(f"{c['v']}.fract_gl()", f"{c['v']} - {c['v']}.floor()")])

    # ----------------------------------------------------------------- normalization family
    rows = []
    for v in lengths:
        nv = normalize(v)
        length = norm(v)
        rows.append({"v": v, "n": nv, "len": length,
                     "nl": nv if nv is not None else rawv([1, 0, 0, 0], n),
                     "nlen": length if nv is not None else 0})
    rows.append({"v": [0] * n, "n": None, "len": 0,
                 "nl": rawv([1, 0, 0, 0], n), "nlen": 0})
    table("normalize", [("v", "v"), ("n", "opt"), ("len", "s"), ("nl", "v"), ("nlen", "s")], rows,
          lambda c: [eq(f"{c['v']}.try_normalize()", c["n"]),
                     eq(f"{c['v']}.length()", c["len"]),
                     f"if let Some(u) = {c['n']} {{",
                     f"    assert_eq!({c['v']}.normalize(), u);",
                     f"    assert_eq!({c['v']}.normalize_or_zero(), u);",
                     f"    assert_eq!({c['v']}.normalize_or({Tt}::Y), u);",
                     "} else {",
                     f"    assert_eq!({c['v']}.normalize_or_zero(), {Tt}::ZERO);",
                     f"    assert_eq!({c['v']}.normalize_or({Tt}::Y), {Tt}::Y);",
                     "}",
                     f"assert_eq!({c['v']}.normalize_and_length(), ({c['nl']}, {c['nlen']}));"])
    # `length_recip` is `1 / length` truncated: it needs a length of at least 1 raw ULP whose
    # reciprocal fits the scalar range (`Fixed::recip` overflows for a raw length of 1 or 2).
    table("length_recip", [("v", "v"), ("e", "s")],
          [{"v": v, "e": recip(norm(v))} for v in lengths if fits(recip(norm(v)) if norm(v) else 1)
           and norm(v) > 2],
          lambda c: [eq(f"{c['v']}.length_recip()", c["e"]),
                     eq(f"{c['v']}.length_recip()", f"{c['v']}.length().recip()")])
    test("test_normalize_axes", [
        *[eq(f"{Tt}::{c.upper()}.normalize()", f"{Tt}::{c.upper()}") for c in cs],
        *[eq(f"{Tt}::NEG_{c.upper()}.normalize()", f"{Tt}::NEG_{c.upper()}") for c in cs],
        *[f"assert!({Tt}::{c.upper()}.is_normalized());" for c in cs],
        f"assert!(!{Tt}::ONE.is_normalized());",
        f"assert!(!{Tt}::ZERO.is_normalized());",
        f"assert!({Tt}::ONE.normalize().is_normalized());",
        *([eq(f"{V([3, 4])}.normalize()",
              V([("raw", k) for k in normalize(rawv([3, 4], 2))]))] if n == 2 else []),
    ])

    # ------------------------------------------------------------ projection and reflection
    rows = []
    for x, y in small:
        if dot(y, y) == 0:  # `project_onto` divides by `rhs.dot(rhs)`
            continue
        rows.append({"x": x, "y": y, "p": project_onto(x, y), "r": reject_from(x, y),
                     "pn": project_onto_normalized(x, y), "rn": reject_from_normalized(x, y)})
    table("project_reject", [("x", "v"), ("y", "v"), ("p", "v"), ("r", "v"), ("pn", "v"),
                             ("rn", "v")], rows,
          lambda c: [eq(f"{c['x']}.project_onto({c['y']})", c["p"]),
                     eq(f"{c['x']}.reject_from({c['y']})", c["r"]),
                     eq(f"{c['x']}.project_onto_normalized({c['y']})", c["pn"]),
                     eq(f"{c['x']}.reject_from_normalized({c['y']})", c["rn"])])
    units = [normalize(v) for v in lengths[:5]]
    rows = []
    for u, (x, _) in zip(units, [c for c in small if norm(c[0]) > 0]):
        rows.append({"x": x, "u": u, "e": reflect(x, u),
                     "r1": refract(normalize(x), u, raw((1, 2))),
                     "r2": refract(normalize(x), u, raw(4)),
                     "nx": normalize(x), "eta1": raw((1, 2)), "eta2": raw(4)})
    table("reflect_refract", [("x", "v"), ("u", "v"), ("e", "v"), ("nx", "v"), ("eta1", "s"),
                              ("r1", "v"), ("eta2", "s"), ("r2", "v")], rows,
          lambda c: [eq(f"{c['x']}.reflect({c['u']})", c["e"]),
                     eq(f"{c['nx']}.refract({c['u']}, {c['eta1']})", c["r1"]),
                     eq(f"{c['nx']}.refract({c['u']}, {c['eta2']})", c["r2"])])
    if n == 3:
        rows = []
        for v in [normalize(x) for x in lengths[:6]] + [rawv([0, 0, -1, 0], 3),
                                                        rawv([0, 0, 1, 0], 3)]:
            first, second = any_orthonormal_pair(v)
            rows.append({"v": v, "o": any_orthonormal_vector(v), "a": first, "b": second})
        table("orthonormal", [("v", "v"), ("o", "v"), ("a", "v"), ("b", "v")], rows,
              lambda c: [eq(f"{c['v']}.any_orthonormal_vector()", c["o"]),
                         eq(f"{c['v']}.any_orthonormal_pair()", f"({c['a']}, {c['b']})"),
                         eq(f"{c['v']}.any_orthonormal_pair()",
                            f"({c['a']}, {c['v']}.any_orthonormal_vector())")])

    # ------------------------------------------------------- interpolation and clamp_length
    ss = [0, ONE, ONE // 2, ONE // 4, -ONE, 2 * ONE]
    rows = []
    for (x, y), s in zip(small, ss * 2):
        rows.append({"x": x, "y": y, "s": s, "l": [lerp(p, q, s) for p, q in zip(x, y)],
                     "m": [lerp(p, q, ONE // 2) for p, q in zip(x, y)],
                     "ma": [mul_add(p, q, r) for p, q, r in zip(x, y, rawv([1, 2, 3, 4], n))],
                     "mv": rawv([1, 2, 3, 4], n),
                     "t1": move_towards(x, y, raw(100)), "t2": move_towards(x, y, raw((1, 8))),
                     "d1": raw(100), "d2": raw((1, 8))})
    table("lerp_mul_add", [("x", "v"), ("y", "v"), ("s", "s"), ("l", "v"), ("m", "v"),
                           ("mv", "v"), ("ma", "v"), ("d1", "s"), ("t1", "v"), ("d2", "s"),
                           ("t2", "v")], rows,
          lambda c: [eq(f"{c['x']}.lerp({c['y']}, {c['s']})", c["l"]),
                     eq(f"{c['x']}.lerp({c['y']}, {F(0)})", c["x"]),
                     eq(f"{c['x']}.lerp({c['y']}, {F(1)})", c["y"]),
                     eq(f"{c['x']}.midpoint({c['y']})", c["m"]),
                     eq(f"{c['x']}.mul_add({c['y']}, {c['mv']})", c["ma"]),
                     eq(f"{c['x']}.move_towards({c['y']}, {c['d1']})", c["t1"]),
                     eq(f"{c['x']}.move_towards({c['y']}, {c['d2']})", c["t2"]),
                     eq(f"{c['x']}.move_towards({c['y']}, {F(0)})", c["x"])])
    rows = []
    lo2, hi2 = raw(1), raw(4)
    for v in lengths:
        length = norm(v)
        # stretching a vector shorter than `min / MAX` overflows: that is its own panic test
        if length == 0 or not fits(recip_mul((1 << 96) // length, hi2)):
            continue
        below = scaled(v, lo2) if length < lo2 else list(v)
        above = scaled(v, hi2) if length > hi2 else list(v)
        rows.append({"v": v, "lo": lo2, "hi": hi2, "cl": below if length < lo2 else above,
                     "cmax": above, "cmin": below})
    table("clamp_length", [("v", "v"), ("lo", "s"), ("hi", "s"), ("cl", "v"), ("cmax", "v"),
                           ("cmin", "v")], rows,
          lambda c: [eq(f"{c['v']}.clamp_length({c['lo']}, {c['hi']})", c["cl"]),
                     eq(f"{c['v']}.clamp_length_max({c['hi']})", c["cmax"]),
                     eq(f"{c['v']}.clamp_length_min({c['lo']})", c["cmin"])])
    test("test_abs_diff_eq", [
        f"let a = {V([1, 2, 3, 4])};",
        f"let b = {V([('raw', raw(1) + 3), ('raw', raw(2) - 3), 3, 4])};",
        f"assert!(a.abs_diff_eq(a, {F(0)}));",
        f"assert!(a.abs_diff_eq(b, f(3)));",
        f"assert!(!a.abs_diff_eq(b, f(2)));",
        f"assert!(!{Tt}::MIN.abs_diff_eq({Tt}::MAX, {F(0)}));",
        f"assert!(!{Tt}::MIN.abs_diff_eq({Tt}::MAX, f({MAX_RAW})));"])

    # --------------------------------------------------------------------- operators, casts
    ops = [("+", "add"), ("-", "sub"), ("*", "mul"), ("/", "div"), ("%", "rem")]
    fops = {"add": lambda p, q: p + q, "sub": lambda p, q: p - q, "mul": mul, "div": div,
            "rem": rem}
    rows = []
    for x, y in small:
        if any(k == 0 for k in y):
            y = [k if k != 0 else raw(3) for k in y]
        k = y[0] if y[0] != 0 else raw(3)
        r = {"x": x, "y": y, "k": k, "neg": [-p for p in x],
             "ds": [recip_mul(recip_wide(k), p) for p in x]}
        for _, name in ops:
            r[name] = cw(fops[name], x, y)
            r[name + "s"] = [fops[name](p, k) for p in x]
        r["divs"] = r["ds"]
        rows.append(r)
    table("ops", [("x", "v"), ("y", "v"), ("k", "s"), ("neg", "v")]
          + [(m, "v") for _, m in ops] + [(m + "s", "v") for _, m in ops], rows,
          lambda c: [eq(f"{c['x']} {sym} {c['y']}", c[m]) for sym, m in ops]
          + [eq(f"{c['x']}.{m}_scalar({c['k']})", c[m + "s"]) for _, m in ops]
          + [eq(f"-{c['x']}", c["neg"]), eq(f"-(-{c['x']})", c["x"])]
          + [l for sym, m in ops for l in (
              f"let mut v = {c['x']};", f"v {sym}= {c['y']};", eq("v", c[m]),
              f"let mut v = {c['x']};", f"v {sym}= {c['k']};", eq("v", c[m + 's']))])
    rows = []
    for v in [rawv([1, 2, 3, 4], n), rawv([(-3, 2), (7, 4), (-11, 8), (13, 16)], n),
              rawv([0, ("raw", 1), ("raw", -1), 1000], n), rawv([-1, -2, -3, -4], n),
              [MAX_RAW, MIN_RAW, 0, MAX_RAW][:n]]:
        rows.append({"v": v, "i": [to_int_trunc(k) for k in v],
                     "u": [to_int_trunc(k) if to_int_trunc(k) >= 0 else 0 for k in v],
                     "fi": [to_int_trunc(k) * ONE for k in v]})
    table("casts", [("v", "v"), ("i", "i"), ("fi", "v")], rows,
          lambda c: [eq(f"{c['v']}.as_{t.imod}()", c["i"]),
                     f"let back: {T} = {c['i']}.into();", eq("back", c["fi"])])
    test("test_casts_unsigned", [
        f"let v = {V([1, 2, 3, 4])};",
        eq(f"v.as_{t.umod}()", f"{t.umod}(" + ", ".join(["1", "2", "3", "4"][:n]) + ")"),
        f"let u = {t.umod}(" + ", ".join(["1", "2", "3", "4"][:n]) + ");",
        f"let back: {T} = u.into();", eq("back", V([1, 2, 3, 4])),
        f"let v = {V([(3, 2), (-5, 2), (7, 2), (-9, 2)])};",
        eq(f"v.as_{t.imod}()", f"{t.imod}(" + ", ".join(["1", "-2", "3", "-4"][:n]) + ")"),
    ])
    test("test_hash_serde", [
        f"let a = {V([1, 2, 3, 4])};", f"let b = {V([4, 3, 2, 1])};",
        "assert_eq!(hash(a), hash(a));", "assert!(hash(a) != hash(b));",
        "let mut out = array![];", "a.serialize(ref out);",
        eq("out.len()", n), "let mut span = out.span();",
        eq(f"Serde::<{T}>::deserialize(ref span)", "Some(a)")])

    # ---------------------------------------------------------------------------- euclidean
    rows = []
    for x, y in small:
        y = [k if k != 0 else raw(3) for k in y]
        rows.append({"x": x, "y": y, "q": cw(div_euclid, x, y), "r": cw(rem_euclid, x, y)})
    table("euclid", [("x", "v"), ("y", "v"), ("q", "v"), ("r", "v")], rows,
          lambda c: [eq(f"{c['x']}.div_euclid({c['y']})", c["q"]),
                     eq(f"{c['x']}.rem_euclid({c['y']})", c["r"]),
                     f"assert!({c['r']}.cmpge({Tt}::ZERO).all());"])
    table("recip", [("x", "v"), ("e", "v")],
          [{"x": v, "e": [recip(k) for k in v]}
           for v in [rawv([1, 2, 4, 8], n), rawv([(1, 2), (-1, 4), 3, -5], n),
                     rawv([-1, 1, -1, 1], n), rawv([1000, -1000, (1, 1024), (-1, 1024)], n)]],
          lambda c: [eq(f"{c['x']}.recip()", c["e"])])

    # ------------------------------------------------------------------------------- panics
    sp = lambda name, msg, expr: panic(name, msg, [f"let _ = {expr};"])
    zero = f"{Tt}::ZERO"
    sp("test_normalize_zero", f"'{T}: normalize zero'", f"{zero}.normalize()")
    sp("test_index_out_of_bounds", f"'{T}: index out of bounds'", f"{Tt}::ONE[{n}]")
    sp("test_as_uvec_negative", f"'{T}: cast out of range'", f"{Tt}::NEG_ONE.as_{t.umod}()")
    sp("test_from_uvec_overflow", f"'{T}: cast out of range'",
       f"Into::<{t.U}, {T}>::into({t.umod}(" + ", ".join(["0x80000000"] * n) + "))")
    sp("test_add_overflow", "'i64_add Overflow'", f"{Tt}::MAX + {Tt}::ONE")
    sp("test_sub_underflow", "'i64_sub Underflow'", f"{Tt}::MIN - {Tt}::ONE")
    sp("test_neg_overflow", "'i64_neg Underflow'", f"-{Tt}::MIN")
    sp("test_abs_overflow", "'Fixed: overflow'", f"{Tt}::MIN.abs()")
    sp("test_mul_overflow", "'Fixed: overflow'", f"{Tt}::MAX * {Tt}::MAX")
    sp("test_mul_scalar_overflow", "'Fixed: overflow'", f"{Tt}::MAX.mul_scalar(f({MAX_RAW}))")
    sp("test_div_by_zero", "'Fixed: division by zero'", f"{Tt}::ONE / {zero}")
    sp("test_rem_by_zero", "'Fixed: division by zero'", f"{Tt}::ONE % {zero}")
    sp("test_div_scalar_by_zero", "'Fixed: division by zero'", f"{Tt}::ONE.div_scalar(f(0))")
    sp("test_rem_scalar_by_zero", "'Fixed: division by zero'", f"{Tt}::ONE.rem_scalar(f(0))")
    sp("test_recip_zero", "'Fixed: division by zero'", f"{zero}.recip()")
    sp("test_div_euclid_by_zero", "'Fixed: division by zero'", f"{Tt}::ONE.div_euclid({zero})")
    sp("test_rem_euclid_by_zero", "'Fixed: division by zero'", f"{Tt}::ONE.rem_euclid({zero})")
    sp("test_dot_overflow", "'Fixed: overflow'", f"{Tt}::MAX.dot({Tt}::MAX)")
    sp("test_length_squared_overflow", "'Fixed: overflow'", f"{Tt}::MAX.length_squared()")
    sp("test_length_overflow", "'Fixed: overflow'", f"{Tt}::MAX.length()")
    sp("test_distance_overflow", "'Fixed: overflow'", f"{Tt}::MAX.distance({Tt}::MIN)")
    sp("test_element_sum_overflow", "'i64_add Overflow'", f"{Tt}::MAX.element_sum()")
    sp("test_element_product_overflow", "'Fixed: overflow'", f"{Tt}::MAX.element_product()")
    sp("test_ceil_overflow", "'Fixed: overflow'", f"{Tt}::MAX.ceil()")
    sp("test_round_overflow", "'Fixed: overflow'", f"{Tt}::MAX.round()")
    sp("test_project_onto_zero", "'Fixed: division by zero'", f"{Tt}::ONE.project_onto({zero})")
    sp("test_reject_from_zero", "'Fixed: division by zero'", f"{Tt}::ONE.reject_from({zero})")
    sp("test_clamp_length_min_zero", "'Fixed: division by zero'",
       f"{zero}.clamp_length_min(f({ONE}))")
    sp("test_is_normalized_overflow", "'Fixed: overflow'", f"{Tt}::MAX.is_normalized()")
    big = f"{Tt}::X.mul_scalar(f({MAX_RAW}))"
    sp("test_clamp_length_min_overflow", "'Fixed: overflow'",
       f"{Tt}::X.mul_scalar(f(1)).clamp_length_min(f({ONE}))")
    if n == 3:
        sp("test_cross_overflow", "'Fixed: overflow'",
           f"{big}.cross({Tt}::Y.mul_scalar(f({MAX_RAW})))")
    if n == 2:
        sp("test_perp_overflow", "'i64_neg Underflow'", f"{V([0, 0])}.with_y(f({MIN_RAW})).perp()")
        sp("test_perp_dot_overflow", "'Fixed: overflow'",
           f"{big}.perp_dot({Tt}::Y.mul_scalar(f({MAX_RAW})))")
        sp("test_angle_to_overflow", "'Fixed: overflow'", f"{Tt}::MAX.angle_to({Tt}::MAX)")
        sp("test_rotate_angle_overflow", "'Fixed: overflow'",
           f"{Tt}::MAX.rotate_angle(f(3373259426))")
        sp("test_rotate_towards_overflow", "'Fixed: overflow'",
           f"{Tt}::MAX.rotate_towards({Tt}::MAX, f({ONE}))")
    if n == 3:
        sp("test_angle_between_overflow", "'Fixed: overflow'",
           f"{Tt}::MAX.angle_between({Tt}::MAX)")
        sp("test_angle_to_overflow", "'Fixed: overflow'",
           f"{Tt}::MAX.angle_to({Tt}::MAX, {Tt}::Z)")
        for ax in "xyz":
            sp(f"test_rotate_{ax}_overflow", "'Fixed: overflow'",
               f"{Tt}::MAX.rotate_{ax}(f(3373259426))")

    # ----------------------------------------------------------- angles and rotations
    nz = [(x, y) for x, y in small if any(x) and any(y)]
    if n == 2:
        # `from_angle`: the two components are the `sin_cos` of `fixed::trig` (cos 0.86 ULP, sin
        # 1.02 ULP): the integer distance to the correctly rounded value is at most 1.
        # `to_angle(from_angle(a))`: the vector is off by hypot(0.86, 1.02) = 1.34 ULP across
        # the radius (|v| = 1) and `atan2` adds 3.22: 4.56 ULP, i.e. at most 4 raw units.
        table("from_angle", [("a", "s"), ("e", "v")],
              [{"a": a, "e": sin_cos_ref(a)} for a in ANGLES],
              lambda c: [f"let (s, c) = {c['a']}.sin_cos();",
                         eq(f"{Tt}::from_angle({c['a']})", f"{t.mod}(c, s)"),
                         f"assert!({Tt}::from_angle({c['a']}).abs_diff_eq({c['e']}, f(1)));",
                         f"assert!({Tt}::from_angle({c['a']}).to_angle().abs_diff_eq({c['a']}, "
                         "f(4)));",
                         "// sin is odd and cos is even, exactly",
                         eq(f"{Tt}::from_angle(-{c['a']})", f"{t.mod}(c, -s)")])
        test("test_from_angle_axes", [
            eq(f"{Tt}::from_angle(f(0))", f"{Tt}::X"),
            f"assert!({Tt}::from_angle(FRAC_PI_2).abs_diff_eq({Tt}::Y, f(1)));",
            f"assert!({Tt}::from_angle(-FRAC_PI_2).abs_diff_eq({Tt}::NEG_Y, f(1)));",
            f"assert!({Tt}::from_angle(PI).abs_diff_eq({Tt}::NEG_X, f(1)));",
            "// the example of the glam-rs documentation",
            f"assert!({Tt}::from_angle(PI).rotate({Tt}::Y).abs_diff_eq({Tt}::NEG_Y, f(1)));",
            f"assert!({Tt}::from_angle(FRAC_PI_4).abs_diff_eq({t.mod}(f(0xB504F334), "
            "f(0xB504F334)), f(1)));"])
        # `to_angle`: one `atan2` of the raw components (3.22 ULP): tolerance 3.
        table("to_angle", [("v", "v"), ("e", "s")],
              [{"v": v, "e": atan2_ref(v[1], v[0])} for v, _ in small],
              lambda c: [f"assert!({c['v']}.to_angle().abs_diff_eq({c['e']}, f(3)));"])
        test("test_to_angle_axes", [
            eq(f"{Tt}::X.to_angle()", "f(0)"), eq(f"{Tt}::Y.to_angle()", "FRAC_PI_2"),
            eq(f"{Tt}::NEG_X.to_angle()", "PI"), eq(f"{Tt}::NEG_Y.to_angle()", "-FRAC_PI_2"),
            eq(f"{V([1, 1])}.to_angle()", "FRAC_PI_4"), eq(f"{Tt}::ZERO.to_angle()", "f(0)"),
            eq(f"{V([3, 4])}.to_angle()", f"{V([6, 8])}.to_angle()")])
        # `angle_to`: `atan2` of the two floored products (`mul_sub`, `dot2`), 3.22 ULP.
        table("angle_to", [("x", "v"), ("y", "v"), ("e", "s")],
              [{"x": x, "y": y, "e": angle_to_2d(x, y)} for x, y in small],
              lambda c: [f"assert!({c['x']}.angle_to({c['y']}).abs_diff_eq({c['e']}, f(3)));",
                         eq(f"{c['x']}.rotate_angle({c['e']})",
                            f"{c['x']}.rotate({Tt}::from_angle({c['e']}))")])
        test("test_angle_to_axes", [
            eq(f"{Tt}::X.angle_to({Tt}::Y)", "FRAC_PI_2"),
            eq(f"{Tt}::Y.angle_to({Tt}::X)", "-FRAC_PI_2"),
            eq(f"{Tt}::X.angle_to({Tt}::NEG_X)", "PI"), eq(f"{Tt}::NEG_X.angle_to({Tt}::X)", "PI"),
            eq(f"{Tt}::X.angle_to({Tt}::X)", "f(0)"),
            eq(f"{V([3, 4])}.angle_to({V([6, 8])})", "f(0)"),
            "// the round trip of the glam-rs documentation: `self.rotate_angle(angle_to) = rhs`",
            f"let v = {V([3, 4])};", f"let w = {V([-4, 3])};",
            "// |v| = 5: 5 * (3.22 + 1.42 / 25 + 1.34) + 1 = 24.2 ULP",
            "assert!(v.rotate_angle(v.angle_to(w)).abs_diff_eq(w, f(25)));"])
        # `rotate_towards`. The reference rotates by `clamp(m, |a| - pi, |a|) * sign(a)` with `a`
        # the exact angle of the kernel values. The implementation differs by `atan2` (3.22 ULP),
        # the `angle_to` inputs (1.42 / (|v| |w|) ULP) and `from_angle` (1.34 ULP) on the
        # angle, times `|v|` on the vector, plus the floor and the quantization (1.5 ULP).
        rt = []
        for x, y in nz:
            lx, ly = math.hypot(*x) / ONE, math.hypot(*y) / ONE
            for m in [0, ONE // 4, ONE, 100 * ONE, -100 * ONE]:
                tol = math.ceil(lx * (3.22 + 1.34 + 1.42 / (lx * ly)) + 1.5)
                rt.append({"x": x, "y": y, "m": m, "e": rotate_towards_2d(x, y, m), "tol": tol})
        table("rotate_towards", [("x", "v"), ("y", "v"), ("m", "s"), ("e", "v"), ("tol", "s")], rt,
              lambda c: [f"let res = {c['x']}.rotate_towards({c['y']}, {c['m']});",
                         f"assert!(res.abs_diff_eq({c['e']}, {c['tol']}));",
                         f"if {c['m']} == f(0) {{",
                         f"    assert_eq!(res, {c['x']});",
                         "}"])
    if n == 3:
        cross3 = lambda p, q: [mul_sub(p[1], q[2], q[1], p[2]), mul_sub(p[2], q[0], q[2], p[0]),
                               mul_sub(p[0], q[1], q[0], p[1])]
        test("test_angle_between_axes", [
            eq(f"{Tt}::X.angle_between({Tt}::Y)", "FRAC_PI_2"),
            eq(f"{Tt}::Y.angle_between({Tt}::X)", "FRAC_PI_2"),
            eq(f"{Tt}::X.angle_between({Tt}::X)", "f(0)"),
            eq(f"{Tt}::X.angle_between({Tt}::NEG_X)", "PI"),
            eq(f"{Tt}::X.angle_between({V([1, 1, 0])}) + {Tt}::X.angle_between({V([1, 1, 0])})",
               "FRAC_PI_2"),
            eq(f"{V([1, 2, 3])}.angle_between({V([2, 4, 6])})", "f(0)"),
            eq(f"{Tt}::ZERO.angle_between({Tt}::X)", "f(0)"),
            "// where the acos form loses the angle: the cosine of 1.5e-5 rad is 1 - 1.2e-10, half",
            "// a raw ULP below 1; the atan2 form keeps the angle to a few ULP (atan(2^-16))",
            f"let w = {V([1, 0, 0])}.with_y(f(65536));",
            f"assert!({Tt}::X.angle_between(w).abs_diff_eq(f(65536), f(3)));"])
        # `angle_between` = `atan2(|cross|, dot)` and `angle_to` = `atan2(det3, dot)` on the
        # kernel values: 3.22 ULP each.
        axes = [[0, 0, 1], [0, 0, -1], [1, 0, 0], [(3, 7), (6, 7), (2, 7)], [0, -1, 0]]
        rows = [{"x": x, "y": y, "a": rawv(a, 3),
                 "eb": atan2_ref(norm(cross3(x, y)), dot(x, y)),
                 "et": atan2_ref(det3(rawv(a, 3), x, y), dot(x, y))}
                for (x, y), a in zip(small, axes * 2)]
        table("angles", [("x", "v"), ("y", "v"), ("a", "v"), ("eb", "s"), ("et", "s")], rows,
              lambda c: [f"assert!({c['x']}.angle_between({c['y']}).abs_diff_eq({c['eb']}, "
                         "f(3)));",
                         f"assert!({c['x']}.angle_to({c['y']}, {c['a']}).abs_diff_eq({c['et']}, "
                         "f(3)));"])
        test("test_angle_to_axes", [
            eq(f"{Tt}::X.angle_to({Tt}::Y, {Tt}::Z)", "FRAC_PI_2"),
            eq(f"{Tt}::Y.angle_to({Tt}::X, {Tt}::Z)", "-FRAC_PI_2"),
            eq(f"{Tt}::X.angle_to({Tt}::Y, {Tt}::NEG_Z)", "-FRAC_PI_2"),
            eq(f"{Tt}::Y.angle_to({Tt}::Z, {Tt}::X)", "FRAC_PI_2"),
            eq(f"{Tt}::Z.angle_to({Tt}::X, {Tt}::Y)", "FRAC_PI_2"),
            eq(f"{Tt}::X.angle_to({Tt}::NEG_X, {Tt}::Z)", "PI"),
            eq(f"{Tt}::X.angle_to({Tt}::X, {Tt}::Z)", "f(0)")])
        # `rotate_x/y/z`: the exact rotation with the float `(cos, sin)` of the angle. Each
        # component differs by `|b| * 1.02 + |c| * 1.02` ULP (the `sin_cos` error times the two
        # inputs) plus the floor and the quantization (1.5 ULP).
        rr = []
        for x, _ in small:
            for a in [0, ANGLES[5], ANGLES[9], ANGLES[16]]:
                c_, s_ = math.cos(a / ONE), math.sin(a / ONE)
                vx, vy, vz = (k / ONE for k in x)
                ex = [x[0], qr(vy * c_ - vz * s_), qr(vy * s_ + vz * c_)]
                ey = [qr(vx * c_ + vz * s_), x[1], qr(-vx * s_ + vz * c_)]
                ez = [qr(vx * c_ - vy * s_), qr(vx * s_ + vy * c_), x[2]]
                tol = math.ceil(1.02 * (abs(vx) + abs(vy) + abs(vz)) + 1.5)
                rr.append({"x": x, "a": a, "ex": ex, "ey": ey, "ez": ez, "tol": tol})
        table("rotate_xyz", [("x", "v"), ("a", "s"), ("ex", "v"), ("ey", "v"), ("ez", "v"),
                             ("tol", "s")], rr,
              lambda c: [f"assert!({c['x']}.rotate_x({c['a']}).abs_diff_eq({c['ex']}, {c['tol']}));",
                         f"assert!({c['x']}.rotate_y({c['a']}).abs_diff_eq({c['ey']}, {c['tol']}));",
                         f"assert!({c['x']}.rotate_z({c['a']}).abs_diff_eq({c['ez']}, {c['tol']}));",
                         f"if {c['a']} == f(0) {{",
                         f"    assert_eq!({c['x']}.rotate_x({c['a']}), {c['x']});",
                         f"    assert_eq!({c['x']}.rotate_y({c['a']}), {c['x']});",
                         f"    assert_eq!({c['x']}.rotate_z({c['a']}), {c['x']});",
                         "}"])
        test("test_rotate_axes", [
            f"assert!({Tt}::Y.rotate_x(FRAC_PI_2).abs_diff_eq({Tt}::Z, f(1)));",
            f"assert!({Tt}::Z.rotate_y(FRAC_PI_2).abs_diff_eq({Tt}::X, f(1)));",
            f"assert!({Tt}::X.rotate_z(FRAC_PI_2).abs_diff_eq({Tt}::Y, f(1)));",
            f"assert!({Tt}::Z.rotate_x(-FRAC_PI_2).abs_diff_eq({Tt}::Y, f(1)));",
            f"assert!({Tt}::X.rotate_y(FRAC_PI_2).abs_diff_eq({Tt}::NEG_Z, f(1)));",
            f"assert!({Tt}::Y.rotate_z(FRAC_PI_2).abs_diff_eq({Tt}::NEG_X, f(1)));",
            "// the rotation axis is fixed exactly",
            f"assert_eq!({Tt}::X.rotate_x(FRAC_PI_2), {Tt}::X);",
            f"assert_eq!({Tt}::Y.rotate_y(PI), {Tt}::Y);",
            f"assert_eq!({Tt}::Z.rotate_z(f(1)), {Tt}::Z);"])

    # --------------------------------------------------------------------------------- fuzz
    seed = 100 * n
    args = ", ".join(f"{k}: i64" for k in "abcd")
    rot = lambda names: [names[i % len(names)] for i in range(n)]
    va = f"{t.mod}(" + ", ".join(f"small({k})" for k in rot(list("abcd"))) + ")"
    vb = f"{t.mod}(" + ", ".join(f"small({k})" for k in rot(list("cdba"))) + ")"
    G.fuzz("fuzz_dot_length", seed + 1, args, [
        f"let va = {va};", f"let vb = {vb};",
        "assert_eq!(va.dot(vb), vb.dot(va));",
        "assert_eq!(va.length_squared(), va.dot(va));",
        "assert_eq!(va.distance_squared(vb), (va - vb).length_squared());",
        "assert_eq!(va.distance(vb), (va - vb).length());",
        "// the length is the floor of the exact root: len^2 <= |v|^2 < (len + 1)^2",
        "let len = va.length();",
        "assert!(len.to_raw() >= 0);",
        "assert!(mul_raw(len, len) <= sq_raw(va));",
        "assert!(mul_raw(len + f(1), len + f(1)) > sq_raw(va));",
        "assert_eq!(va.element_sum(), " + " + ".join(f"va.{c}" for c in cs) + ");",
        "// the fused product is the floor of the exact one; the chain floors after every",
        f"// multiplication and the error is amplified by the remaining factors (|x| < 8)",
        f"assert!(va.element_product().abs_diff_eq({' * '.join('va.' + c for c in cs)}, "
        f"f({ {2: 0, 3: 9, 4: 73}[n] })));",
    ])
    G.fuzz("fuzz_normalize", seed + 2, args, [
        f"let va = {va};",
        f"if va == {Tt}::ZERO {{",
        "    assert_eq!(va.try_normalize(), None);",
        f"    assert_eq!(va.normalize_or_zero(), {Tt}::ZERO);",
        f"    assert_eq!(va.normalize_and_length(), ({Tt}::X, f(0)));",
        "} else {",
        "    let u = va.normalize();",
        "    assert_eq!(va.try_normalize(), Some(u));",
        "    assert_eq!(va.normalize_or_zero(), u);",
        f"    assert_eq!(va.normalize_or({Tt}::Y), u);",
        "    assert_eq!(va.normalize_and_length(), (u, va.length()));",
        "    // one rounded division per component: the squared length stays within the",
        "    // `is_normalized` threshold as long as the input is at least 1 raw ULP long",
        "    assert!(u.length_squared().abs_diff_eq(f(0x100000000), f(1024)));",
        "}",
    ])
    G.fuzz("fuzz_min_max_clamp_cmp", seed + 3, args, [
        f"let va = {va};", f"let vb = {vb};",
        "let lo = va.min(vb);", "let hi = va.max(vb);",
        "assert!(lo.cmple(hi).all());",
        "assert!(lo.cmple(va).all() && lo.cmple(vb).all());",
        "assert!(hi.cmpge(va).all() && hi.cmpge(vb).all());",
        f"assert_eq!({Tt}::select(va.cmplt(vb), va, vb), lo);",
        f"assert_eq!({Tt}::select(va.cmpgt(vb), va, vb), hi);",
        "assert_eq!(va.cmpeq(vb), !va.cmpne(vb));",
        "assert_eq!(va.cmpge(vb), !va.cmplt(vb));",
        "assert_eq!(va.cmple(vb), !va.cmpgt(vb));",
        "assert_eq!(va.clamp(lo, hi), va);",
        "assert_eq!(va[va.min_position()], va.min_element());",
        "assert_eq!(va[va.max_position()], va.max_element());",
        "assert!(va.min_element() <= va.max_element());",
    ])
    G.fuzz("fuzz_sign_rounding", seed + 4, args, [
        f"let va = {va};",
        "assert_eq!(va.abs(), va.abs().abs());",
        "assert_eq!((-va).abs(), va.abs());",
        "assert_eq!(va.signum() * va.abs(), va);",
        "assert_eq!(va.copysign(va), va);",
        f"assert_eq!(va.copysign({Tt}::ONE), va.abs());",
        f"assert_eq!(va.copysign({Tt}::NEG_ONE), -va.abs());",
        f"assert_eq!(va.is_negative_mask(), va.cmplt({Tt}::ZERO));",
        "assert_eq!(va.is_negative_bitmask(), va.is_negative_mask().bitmask());",
        "assert!(va.floor().cmple(va).all() && va.ceil().cmpge(va).all());",
        "assert_eq!(va.fract(), va - va.trunc());",
        "assert_eq!(va.fract_gl(), va - va.floor());",
        f"assert!(va.fract_gl().cmpge({Tt}::ZERO).all() && va.fract_gl().cmplt({Tt}::ONE).all());",
        "assert!(va.round().abs().cmpge(va.trunc().abs()).all());",
    ])
    G.fuzz("fuzz_ops", seed + 5, args, [
        f"let va = {va};", f"let vb = {vb};",
        "assert_eq!((va + vb) - vb, va);",
        "assert_eq!(va + vb, vb + va);",
        "assert_eq!(va.midpoint(vb), va.lerp(vb, f(0x80000000)));",
        "assert_eq!(va.lerp(vb, f(0)), va);",
        "assert_eq!(va.lerp(vb, f(0x100000000)), vb);",
        "assert_eq!(va.move_towards(vb, f(0)), va);",
        f"assert_eq!(va.move_towards(vb, f({1 << 40})), vb);",
        f"assert_eq!(va.mul_add(vb, {Tt}::ZERO), mul_exact(va, vb));",
        "assert!(va.abs_diff_eq(va, f(0)));",
        f"assert!(va.abs_diff_eq(vb, f({MAX_RAW})));",
        f"assert_eq!(va.dot_into_vec(vb), {Tt}::splat(va.dot(vb)));",
        "assert_eq!(va.add_scalar(f(0x100000000)), va + " + Tt + "::ONE);",
        "assert_eq!(va.sub_scalar(f(0x100000000)), va - " + Tt + "::ONE);",
        "assert_eq!(va.mul_scalar(f(0x100000000)), va);",
    ])
    extra = {
        2: ["assert_eq!(va.perp().perp(), -va);",
            "assert_eq!(va.perp_dot(vb), va.perp().dot(vb));",
            "assert_eq!(va.perp_dot(va), f(0));",
            "assert_eq!(va.rotate(vb), vb.rotate(va));",
            f"assert_eq!({Tt}::X.rotate(vb), vb);"],
        3: ["let c = va.cross(vb);",
            "assert!(vb.cross(va).abs_diff_eq(-c, f(1)));",
            f"assert_eq!(va.cross(va), {Tt}::ZERO);",
            "// one floor rescale per component of the cross product, then one more in the",
            "// dot product: |c . a| <= (sum |a_i| + 1) ULP, and |a_i| <= 8",
            "assert!(c.dot(va).abs() <= f(25));",
            "assert!(c.dot(vb).abs() <= f(25));"],
        4: ["assert_eq!(Vec3Trait::extend(va.truncate(), va.w), va);",
            "// the 4D kernel floors once, the 3D one plus the last product twice",
            "let split = Vec3Trait::dot(va.truncate(), vb.truncate()) + va.w * vb.w;",
            "assert!(va.dot(vb).abs_diff_eq(split, f(2)));"],
    }[n]
    G.fuzz("fuzz_geometry", seed + 6, args, [
        f"let va = {va};", f"let vb = {vb};",
        *extra,
        f"if vb.dot(vb) != f(0) {{",
        "    let p = va.project_onto(vb);",
        "    let r = va.reject_from(vb);",
        "    // `p + r` is `va` up to the floor rescales of both",
        f"    assert!((p + r).abs_diff_eq(va, f({2 * n})));",
        "}",
    ])
    ang = "f(a % 13493037705)"
    if n == 2:
        G.fuzz("fuzz_from_angle", seed + 7, args, [
            f"let ang = {ang};", f"let va = {va};",
            f"let v = {Tt}::from_angle(ang);",
            "// (cos + e1)^2 + (sin + e2)^2 with |e| <= 1.02 ULP: 2 * 1.02 * (|cos| + |sin|) = 2.9",
            "// ULP from 1, and the floor of `length_squared` adds one: at most 3 raw units",
            "assert!(v.length_squared().abs_diff_eq(f(0x100000000), f(3)));",
            "// hypot(0.86, 1.02) = 1.34 ULP across the radius, plus the 3.22 ULP of `atan2`",
            "assert!(v.to_angle().abs_diff_eq(ang, f(4)));",
            f"assert_eq!({Tt}::from_angle(-ang), {t.mod}(v.x, -v.y));",
            "assert_eq!(va.rotate_angle(ang), v.rotate(va));",
        ])
        G.fuzz("fuzz_angle_to", seed + 8, args, [
            f"let va = {va};",
            "assert_eq!(va.angle_to(va), f(0));",
            "if va.length_squared() != f(0) {",
            "    assert_eq!(va.angle_to(-va), PI);",
            "    assert_eq!(va.angle_to(va.perp()), FRAC_PI_2);",
            "    assert_eq!(va.perp().angle_to(va), -FRAC_PI_2);",
            "}",
        ])
    if n == 3:
        G.fuzz("fuzz_angle_between", seed + 7, args, [
            f"let va = {va};", f"let vb = {vb};",
            "assert_eq!(va.angle_between(va), f(0));",
            f"assert_eq!(va.angle_to(va, {Tt}::Z), f(0));",
            "// `atan2` of a non-negative first argument: in `[0, pi]` up to its 3.22 ULP",
            "let ab = va.angle_between(vb);",
            "assert!(ab >= f(0) && ab <= PI + f(4));",
            "if va.dot(va) != f(0) {",
            "    assert_eq!(va.angle_between(-va), PI);",
            "}",
        ])
        G.fuzz("fuzz_rotate", seed + 8, args, [
            f"let va = {va};", "let ang = f(a % 13493037705);",
            "assert_eq!(va.rotate_x(f(0)), va);",
            "assert_eq!(va.rotate_y(f(0)), va);",
            "assert_eq!(va.rotate_z(f(0)), va);",
            "assert_eq!(va.rotate_x(ang).x, va.x);",
            "assert_eq!(va.rotate_y(ang).y, va.y);",
            "assert_eq!(va.rotate_z(ang).z, va.z);",
            "// |R v| = sqrt(c^2 + s^2) |v_yz| up to the floors: the length moves by at most",
            "// 1.34 * |v_yz| + sqrt(2) (|v_yz| <= 8 sqrt(2)) + 1 (two floored lengths) < 18 ULP",
            "let len = va.length();",
            "assert!(va.rotate_x(ang).length().abs_diff_eq(len, f(17)));",
            "assert!(va.rotate_y(ang).length().abs_diff_eq(len, f(17)));",
            "assert!(va.rotate_z(ang).length().abs_diff_eq(len, f(17)));",
        ])
    at = lambda i: "o" if i == 0 else f"o + {i}"
    body = "\n".join(G.out)
    neighbours = ""
    for k in (2, 3, 4):
        if k == n or abs(k - n) > (2 if n == 4 else 1):
            continue
        d = t.dim(k)
        items = ([f"{d.name}Trait"] if f"{d.name}Trait" in body else []) + [d.mod]
        neighbours += f"use glam::{d.mod}::{{{', '.join(items)}}};\n"
    consts = [c for c in ("FRAC_PI_2", "FRAC_PI_4", "PI") if re.search(r"\b" + c + r"\b", body)]
    fixed_uses = "use fixed::fixed::{" + ", ".join(sorted(["Fixed", "FixedTrait"] + consts)) + "};\n"
    if ".sin_cos()" in body:
        fixed_uses += "use fixed::trig::TrigTrait;\n"
    prelude = f"""{g.HEADER}//! Tests of `glam::{t.mod}`: the glam-rs vector test macros of `tests/vec{n}.rs`, tables over pools
//! of edge values (expected values computed by the generator with an exact Q32.32 Python oracle,
//! one `const` table and one looping test per function group), seeded fuzz properties, and one
//! test per panic path.
//!
//! The glam-rs results themselves are checked by `golden_{t.mod}.cairo` (generated by
//! `tools/refgen` with `DVec{n}` as the oracle); this file pins the bit-exact fixed-point
//! semantics: floor rescales, truncated divisions and the round-to-nearest shared reciprocal.

use core::hash::{{HashStateExTrait, HashStateTrait}};
use core::poseidon::PoseidonTrait;
{fixed_uses}use glam::{t.bmod}::{{{t.B}, {t.B}Trait}};
use glam::{t.imod}::{{{t.I}, {t.imod}}};
use glam::{t.mod}::{{{T}, {T}Trait, {t.mod}}};
use glam::{t.umod}::{{{t.U}, {t.umod}}};
{neighbours}
/// A `Fixed` from its raw Q32.32 value (every table cell is a raw value).
fn f(raw: i64) -> Fixed {{
    FixedTrait::from_raw(raw)
}}

fn hash(v: {T}) -> felt252 {{
    PoseidonTrait::new().update_with(v).finalize()
}}

// Readers of the table rows (`[i64; W]`): the value of a column at an offset.

fn fx(r: Span<i64>, o: u32) -> Fixed {{
    f(*r[o])
}}

fn us(r: Span<i64>, o: u32) -> usize {{
    (*r[o]).try_into().unwrap()
}}

fn bl(r: Span<i64>, o: u32) -> bool {{
    *r[o] != 0
}}

fn vc(r: Span<i64>, o: u32) -> {T} {{
    {t.mod}({", ".join(f"fx(r, {at(i)})" for i in range(n))})
}}

fn iv(r: Span<i64>, o: u32) -> {t.I} {{
    {t.imod}({", ".join(f"(*r[{at(i)}]).try_into().unwrap()" for i in range(n))})
}}

fn uv(r: Span<i64>, o: u32) -> {t.U} {{
    {t.umod}({", ".join(f"(*r[{at(i)}]).try_into().unwrap()" for i in range(n))})
}}

fn bv(r: Span<i64>, o: u32) -> {t.B} {{
    {t.B}Trait::new({", ".join(f"*r[{at(i)}] != 0" for i in range(n))})
}}

fn ov(r: Span<i64>, o: u32) -> Option<{T}> {{
    if *r[o] == 0 {{
        None
    }} else {{
        Some(vc(r, o + 1))
    }}
}}

// Fuzz helpers: the raw input is reduced to |x| <= 8 so that no product overflows, and the
// reference arithmetic is done in `i128` (exact for products of two raw values).

fn small(v: i64) -> Fixed {{
    f(v % 0x800000000)
}}

fn mul_raw(a: Fixed, b: Fixed) -> i128 {{
    let x: i128 = a.to_raw().into();
    let y: i128 = b.to_raw().into();
    x * y
}}

fn sq_raw(v: {T}) -> i128 {{
    {" + ".join(f"mul_raw(v.{c}, v.{c})" for c in cs)}
}}

/// `self * rhs` component-wise, the reference of `mul_add(rhs, ZERO)`.
fn mul_exact(a: {T}, b: {T}) -> {T} {{
    {t.mod}({", ".join(f"a.{c} * b.{c}" for c in cs)})
}}

"""
    return prelude + body
