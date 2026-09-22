"""Test template (`packages/glam/tests/test_<m>.cairo`) of tools/codegen/fmat.py.

Three layers, as in docs/DESIGN.md section 5:
  * the glam-rs test cases of `tests/mat{2,3,4}.rs`, ported as rows of the tables below;
  * tables over pools of matrices (identity, diagonal, singular, fractional, edge magnitudes):
    the expected values are computed here, in Python, by the exact Q32.32 oracle of
    `RAW SEMANTICS` below, which mirrors `fixed::wide` kernel by kernel (floor rescales,
    truncated divisions, the round-to-nearest shared reciprocal);
  * seeded fuzz properties (relations, not values) and one `#[should_panic]` per panic path with
    the exact message.

The glam-rs values themselves are the subject of the golden vectors
(`tools/refgen/specs/<m>.toml` -> `tests/golden_<m>.cairo`), which compare against `DMat*` run on
the same inputs; this file pins the bit-exact fixed-point semantics instead.

Compile budget (see `tools/codegen/README.md`): one `const [[i64; W]; K]` table and ONE looping
`#[test]` per function group, at most 6 fuzz properties per module. Add a row, never an assertion.
"""
import math
import re

import fvec_tests as ft
import fmat as g

ONE = ft.ONE
MIN_RAW, MAX_RAW = ft.MIN_RAW, ft.MAX_RAW


# --------------------------------------------------------------------------------------------
# RAW SEMANTICS: the Q32.32 matrix oracle (mirrors `glam::mat*` kernel by kernel)
# --------------------------------------------------------------------------------------------
def col(m, i):
    return m[i]


def el(m, i, j):
    """The element of column `i`, row `j`."""
    return m[i][j]


def transpose(m):
    n = len(m)
    return [[m[j][i] for j in range(n)] for i in range(n)]


def mul_vec(m, v):
    """One `dotN` per row: the exact sum of products, floored once."""
    n = len(m)
    return [ft.dot([m[i][j] for i in range(n)], v) for j in range(n)]


def mul_transpose_vec(m, v):
    return [ft.dot(m[i], v) for i in range(len(m))]


def mul_mat(a, b):
    return [mul_vec(a, b[i]) for i in range(len(b))]


def mul_sub(a, b, c, d):
    return (a * b - c * d) >> 32


def det(m):
    n = len(m)
    if n == 2:
        return mul_sub(m[0][0], m[1][1], m[0][1], m[1][0])
    if n == 3:
        a, b, c = m
        x = (b[1] * c[2] - c[1] * b[2]) * a[0]
        y = (b[2] * c[0] - c[2] * b[0]) * a[1]
        z = (b[0] * c[1] - c[0] * b[1]) * a[2]
        return (x + y + z) >> 64
    return mat4_det(m)[0]


def coefs(m):
    """The 18 fused 2x2 minors of `Mat4::inverse`, floored once each."""
    return {name: mul_sub(el(m, *a), el(m, *b), el(m, *c), el(m, *d))
            for name, a, b, c, d in g.COEFS}


def wide_terms(m, i, j, cf):
    """The exact Q64.64 adjugate element of column `i`, row `j` (the sign is folded in)."""
    total = 0
    for a, b, s in g.adjugate_terms(g.Ty(4), i, j, "m"):
        row = "xyzw".index(a.split(".")[-1])
        column = 1 if "y_axis" in a else 0
        total += s * m[column][row] * cf[b]
    return total


def mat4_det(m):
    cf = coefs(m)
    q = [wide_terms(m, i, 0, cf) for i in range(4)]
    return (sum(q[k] * m[0][k] for k in range(4)) >> 64), cf, q


def inverse(m):
    """`None` when the determinant is zero; otherwise the adjugate divided ONCE (round to
    nearest, ties toward +infinity) by the determinant."""
    n = len(m)
    if n == 4:
        d, cf, q = mat4_det(m)
        if d == 0:
            return None
        # the adjugate elements are Q64.64 sums of products: one floor rescale each
        adj = [[(q[i] >> 32) if j == 0 else (wide_terms(m, i, j, cf) >> 32)
                for j in range(4)] for i in range(4)]
    else:
        d = det(m)
        if d == 0:
            return None
        if n == 2:
            adj = [[m[1][1], -m[0][1]], [-m[1][0], m[0][0]]]
        else:
            cross = lambda a, b: [mul_sub(a[(k + 1) % 3], b[(k + 2) % 3],
                                          a[(k + 2) % 3], b[(k + 1) % 3]) for k in range(3)]
            t0, t1, t2 = cross(m[1], m[2]), cross(m[2], m[0]), cross(m[0], m[1])
            adj = [[t0[i], t1[i], t2[i]] for i in range(3)]
    r = ft.recip_wide(d)
    return [[ft.recip_mul(r, adj[i][j]) for j in range(n)] for i in range(n)]


def div_scalar(m, k):
    r = ft.recip_wide(k)
    return [[ft.recip_mul(r, x) for x in c] for c in m]


def mul_scalar(m, k):
    return [[ft.mul(x, k) for x in c] for c in m]


def cw(f, *ms):
    """Element-wise `f` over matrices."""
    n = len(ms[0])
    return [[f(*[m[i][j] for m in ms]) for j in range(n)] for i in range(n)]


def quat_axes(q, n, scale=None, translation=None):
    """`Mat3::from_quat` / `Mat4::from_scale_rotation_translation` on raw values: every element
    is one exact two-term sum of raw products, rescaled once (floored)."""
    x, y, z, w = q
    d = {"x": x, "y": y, "z": z, "w": w}
    dbl = {"x": 2 * x, "y": 2 * y, "z": 2 * z}
    off = {(0, 1): ("x", "y", "w", "z", 1), (0, 2): ("x", "z", "w", "y", -1),
           (1, 0): ("x", "y", "w", "z", -1), (1, 2): ("y", "z", "w", "x", 1),
           (2, 0): ("x", "z", "w", "y", 1), (2, 1): ("y", "z", "w", "x", -1)}

    def el(i, j):
        if i == 3:
            return ONE if j == 3 else (translation[j] if translation else 0)
        if j == 3:
            return 0
        if i == j:
            a, b = [c for c in "xyz" if c != "xyz"[i]]
            acc = ONE * ONE - d[a] * dbl[a] - d[b] * dbl[b]
        else:
            a, b, c, e, sg = off[(i, j)]
            acc = d[a] * dbl[b] + sg * d[c] * dbl[e]
        return (acc * scale[i]) >> 64 if scale else acc >> 32

    return [[el(i, j) for j in range(n)] for i in range(n)]


def from_rotation_axes(m):
    """`Quat::from_rotation_axes` on the three raw columns of a 3x3 matrix."""
    (m00, m01, m02), (m10, m11, m12), (m20, m21, m22) = (c[:3] for c in m[:3])
    rm = ft.recip_mul

    def shared(v):
        # `Fixed::sqrt`: the integer square root of the raw value scaled back to Q32.32.
        s = math.isqrt(v << 32)
        return ft.recip_wide(s + s)

    if m22 <= 0:
        dif10, omm22 = m11 - m00, ONE - m22
        if dif10 <= 0:
            v = omm22 - dif10
            r = shared(v)
            return [rm(r, v), rm(r, m01 + m10), rm(r, m02 + m20), rm(r, m12 - m21)]
        v = omm22 + dif10
        r = shared(v)
        return [rm(r, m01 + m10), rm(r, v), rm(r, m12 + m21), rm(r, m20 - m02)]
    sum10, opm22 = m11 + m00, ONE + m22
    if sum10 <= 0:
        v = opm22 - sum10
        r = shared(v)
        return [rm(r, m02 + m20), rm(r, m12 + m21), rm(r, v), rm(r, m01 - m10)]
    v = opm22 + sum10
    r = shared(v)
    return [rm(r, m12 - m21), rm(r, m20 - m02), rm(r, m01 - m10), rm(r, v)]


def to_scale_rotation_translation(m):
    """`Mat4::to_scale_rotation_translation` on the raw columns of a 4x4 matrix."""
    r = [[m[i][j] for j in range(3)] for i in range(3)]
    lx = ft.norm(r[0])
    scale = [-lx if det(r) < 0 else lx, ft.norm(r[1]), ft.norm(r[2])]
    cols = []
    for i in range(3):
        rec = ft.recip_wide(scale[i])
        cols.append([ft.recip_mul(rec, r[i][j]) for j in range(3)])
    return scale, from_rotation_axes(cols), [m[3][j] for j in range(3)]


def transform_point(m, v):
    """`dotN_add`: the translation column is added exactly inside the single rescale."""
    n = len(m) - 1
    return [ft.dot([m[i][j] for i in range(n)] + [ONE], list(v) + [m[n][j]])
            for j in range(n)]


def transform_vector(m, v):
    n = len(m) - 1
    return [ft.dot([m[i][j] for i in range(n)], v) for j in range(n)]


def project_point(m, v):
    w = transform_point(m, v + [0])[3] if False else ft.dot(
        [m[i][3] for i in range(3)] + [ONE], list(v) + [m[3][3]])
    r = ft.recip_wide(w)
    return [ft.recip_mul(r, ft.dot([m[i][j] for i in range(3)] + [ONE], list(v) + [m[3][j]]))
            for j in range(3)]


# --------------------------------------------------------------------------------------------
# Input pools (values in units; `(num, den)` is a fraction, `("raw", k)` a raw leaf)
# --------------------------------------------------------------------------------------------
H, Q = (1, 2), (1, 4)
# 4x4 templates, given column by column; every module takes the leading n x n block.
POOL = [
    # identity, diagonal, a 90 degree rotation of the first two axes
    [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
    [[2, 0, 0, 0], [0, -3, 0, 0], [0, 0, 5, 0], [0, 0, 0, 7]],
    [[0, 1, 0, 0], [-1, 0, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
    # general fractional blocks (|x| <= 8: every product and triple product stays in range)
    [[(3, 2), (-1, 2), Q, 1], [(1, 8), 2, (-3, 4), 0], [-1, H, (5, 2), Q], [2, -1, 0, 3]],
    [[3, (7, 4), (-5, 8), H], [(-9, 4), 4, (1, 16), -2], [H, (-3, 2), 6, 1], [0, 1, -1, 5]],
    [[8, -8, 8, -8], [8, 8, -8, -8], [-8, 8, 8, -8], [-8, -8, -8, 8]],
    # singular: rank 1, and a zero column
    [[1, 2, 3, 4], [2, 4, 6, 8], [3, 6, 9, 12], [4, 8, 12, 16]],
    [[0, 0, 0, 0], [1, 2, 3, 4], [2, 1, 4, 3], [3, 4, 1, 2]],
    [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]],
    # raw leaves: the low bits of the kernels
    [[("raw", 1), ("raw", -1), ("raw", 3), ("raw", -7)],
     [("raw", 5), ("raw", -9), ("raw", 1), ("raw", -1)],
     [("raw", -3), ("raw", 7), ("raw", 11), ("raw", 2)],
     [("raw", 1), ("raw", 1), ("raw", -1), ("raw", -1)]],
    [[1, ("raw", 1), 0, ("raw", -1)], [("raw", -1), 1, ("raw", 3), 0],
     [0, ("raw", 5), 1, ("raw", 1)], [("raw", 2), 0, ("raw", -2), 1]],
]
VECS = [[(3, 2), (-7, 4), (11, 8), (-13, 16)], [1, 2, 3, 4], [0, 0, 0, 0],
        [("raw", 1), ("raw", -1), ("raw", 3), ("raw", -7)], [8, -8, 8, -8], [1, 0, 0, 0]]
SCALARS = [1, 3, (1, 2), -2, (1, 1024)]


def raws(block, n):
    """The leading n x n block of a template, as raw Q32.32 integers."""
    return [[ft.raw(v) for v in c[:n]] for c in block[:n]]


def rawv(vals, n):
    return [ft.raw(v) for v in vals[:n]]


def fits(m):
    return all(ft.fits(x) for c in m for x in c)


# --------------------------------------------------------------------------------------------
# Emission
# --------------------------------------------------------------------------------------------
class Gen:
    def __init__(self, t):
        self.t = t
        self.out = []
        n = t.n
        self.kinds = {
            "m": (n * n, "mx"), "v": (n, "vc"), "s": (1, "fx"), "us": (1, "us"),
            "bl": (1, "bl"), "om": (n * n + 1, "om"), "q": (4, "qq"),
        }
        for k in (2, 3, 4):
            self.kinds[f"m{k}"] = (k * k, "mx" if k == n else f"mm{k}")
            self.kinds[f"v{k}"] = (k, "vc" if k == n else f"vv{k}")

    def test(self, name, lines, attrs=()):
        body = "\n".join("    " + l for l in lines)
        a = "".join(f"#[{x}]\n" for x in attrs)
        self.out.append(f"#[test]\n{a}fn {name}() {{\n{body}\n}}\n")

    def panic(self, name, msg, lines, marker=None):
        """`marker`: `<Owner>::<item>` of `scripts/panic_coverage.py`, when the name of the
        test does not attribute it."""
        start = len(self.out)
        self.test(name, lines, attrs=[f"should_panic(expected: {msg})"])
        if marker:
            self.out[start] = f"// panics: {marker}\n" + self.out[start]

    def fuzz(self, name, seed, args, lines):
        body = "\n".join("    " + l for l in lines)
        self.out.append(f"#[test]\n#[fuzzer(runs: 128, seed: {seed})]\n"
                        f"fn {name}({args}) {{\n{body}\n}}\n")

    def cells(self, kind, v):
        if kind == "q":
            return [int(x) for x in v]
        if kind[0] == "m" and kind != "om":
            return [int(x) for c in v for x in c]
        if kind[0] == "v":
            return [int(x) for x in v]
        if kind in ("s", "us"):
            return [int(v)]
        if kind == "bl":
            return [1 if v else 0]
        if kind == "om":
            width = self.t.n * self.t.n
            return [0] * (width + 1) if v is None else [1] + [int(x) for c in v for x in c]
        raise ValueError(kind)

    def table(self, name, spec, rows, body):
        """`const <NAME>: [[i64; W]; K]` (one row per case, one cell per scalar) and
        `test_<name>`: one loop over the rows."""
        acc, off = {}, 0
        for column, kind in spec:
            width, reader = self.kinds[kind]
            acc[column] = f"{reader}(r, {off})"
            off += width
        flat = [[c for column, kind in spec for c in self.cells(kind, row[column])]
                for row in rows]
        assert all(len(r) == off for r in flat), name
        assert all(ft.fits(c) for r in flat for c in r), name
        data = ",\n".join("    [" + ", ".join(map(str, r)) + "]" for r in flat)
        const = name.upper()
        self.out.append(f"#[cairofmt::skip]\nconst {const}: [[i64; {off}]; {len(rows)}] = "
                        f"[\n{data},\n];\n")
        lines = [f"for row in {const}.span() {{", "    let r = row.span();"]
        lines += ["    " + l for l in body(acc)]
        lines += ["}"]
        self.test(f"test_{name}", lines)


# The `M * M^-1 ~ IDENTITY` budget: each element of the inverse is the exact adjugate element
# floored (1 ULP) and divided once, rounded to nearest (< 1 ULP), plus the propagated error of the
# floored determinant (|inverse| / |det| ULP); each element of the product then multiplies those
# by |m| and floors once. 8 raw ULP covers every row of the table below (the rows where it does
# not are still checked element by element against the oracle).
# Unit quaternions, in raw Q32.32: the identity, the three half turns, a quarter turn about z,
# the four permutations of (1, 2, 2, 4) / 5 (one per branch of `Quat::from_rotation_axes`) and
# two generic ones. `1 + 4 + 4 + 16 = 25`, so the permutations are exactly rational.
def _q(v, den):
    return [k * ONE // den for k in v]


QUATS = [
    _q([0, 0, 0, 1], 1), _q([1, 0, 0, 0], 1), _q([0, 1, 0, 0], 1), _q([0, 0, 1, 0], 1),
    [0, 0, 3037000499, 3037000500],
    _q([1, 2, 2, 4], 5), _q([1, 2, 4, 2], 5), _q([4, 2, 2, 1], 5), _q([2, 4, 2, 1], 5),
    [-2063235552, 687745183, 1375490367, 3438725918],
    [2147483648, -3579139414, 715827882, -715827883],
]


IDENTITY_EPS = 8


def gen_tests(t):
    T, n, V = t.name, t.n, t.V
    G = Gen(t)
    test, panic, table, fuzz = G.test, G.panic, G.table, G.fuzz
    Tt, Vt = f"{T}Trait", f"{V}Trait"
    eq = lambda a, b: f"assert_eq!({a}, {b});"
    mats = [raws(b, n) for b in POOL]
    vecs = [rawv(v, n) for v in VECS]
    ident = raws(POOL[0], n)
    F = lambda v: f"f({ft.raw(v)})"
    M = lambda m: f"{Tt}::from_cols_array([" + ", ".join(f"f({x})" for c in m for x in c) + "])"
    Vx = lambda v, k=None: (f"{g.Ty(k or n).V}Trait::from_array([" 
                            + ", ".join(f"f({x})" for x in v) + "])")

    # ------------------------------------------------------------ consts, layout, conversions
    a = mats[3]
    test("test_consts_and_layout", [
        f"let m = {M(a)};",
        eq(f"{Tt}::ZERO", M([[0] * n for _ in range(n)])),
        eq(f"{Tt}::IDENTITY", M(ident)),
        eq(f"Default::<{T}>::default()", f"{Tt}::IDENTITY"),
        f"let cols = m.to_cols_array();",
        eq(f"{Tt}::from_cols_array(cols)", "m"),
        eq(f"{Tt}::from_cols_array_2d(m.to_cols_array_2d())", "m"),
        eq(f"{Tt}::from_rows_array(m.to_rows_array())", "m"),
        eq("m.to_rows_array()", "m.transpose().to_cols_array()"),
        f"let into: {t.arr} = m.into();", eq("into", "cols"),
        f"let back: {T} = into.into();", eq("back", "m"),
        f"let into2: {t.arr2d} = m.into();",
        f"let back2: {T} = into2.into();", eq("back2", "m"),
        eq(f"{t.mod}(" + ", ".join(f"m.{c}" for c in t.cols) + ")", "m"),
        eq(f"{Tt}::from_cols(" + ", ".join(f"m.{c}" for c in t.cols) + ")", "m"),
        eq(f"{Tt}::from_rows(" + ", ".join(f"m.row({j})" for j in range(n)) + ")", "m"),
        *[eq(f"m.col({i})", f"m.{c}") for i, c in enumerate(t.cols)],
        *[eq(f"m.row({j})", f"m.transpose().col({j})") for j in range(n)],
        eq(f"{Tt}::from_diagonal(m.diagonal())",
           M([[a[i][j] if i == j else 0 for j in range(n)] for i in range(n)])),
    ])
    test("test_hash_serde", [
        f"let m = {M(mats[3])};", f"let k = {M(mats[4])};",
        "assert_eq!(hash(m), hash(m));", "assert!(hash(m) != hash(k));",
        "let mut out = array![];", "m.serialize(ref out);",
        eq("out.len()", n * n), "let mut span = out.span();",
        eq(f"Serde::<{T}>::deserialize(ref span)", "Some(m)")])
    table("layout", [("m", "m"), ("tr", "m"), ("d", "v"), ("dm", "m")],
          [{"m": m, "tr": transpose(m), "d": [m[i][i] for i in range(n)],
            "dm": [[m[i][i] if i == j else 0 for j in range(n)] for i in range(n)]}
           for m in mats],
          lambda c: [eq(f"{c['m']}.transpose()", c["tr"]),
                     eq(f"{c['tr']}.transpose()", c["m"]),
                     eq(f"{c['m']}.diagonal()", c["d"]),
                     eq(f"{Tt}::from_diagonal({c['d']})", c["dm"]),
                     eq(f"{c['m']}.to_rows_array()", f"{c['tr']}.to_cols_array()")])

    # ------------------------------------------------------------------------------ products
    rows = [{"m": m, "v": v, "mv": mul_vec(m, v), "mt": mul_transpose_vec(m, v)}
            for m, v in zip(mats, vecs * 3)]
    table("mul_vec", [("m", "m"), ("v", "v"), ("mv", "v"), ("mt", "v")], rows,
          lambda c: [eq(f"{c['m']}.mul_vec{n}({c['v']})", c["mv"]),
                     eq(f"{c['m']}.mul_transpose_vec{n}({c['v']})", c["mt"]),
                     eq(f"{c['m']}.mul_transpose_vec{n}({c['v']})",
                        f"{c['m']}.transpose().mul_vec{n}({c['v']})"),
                     eq(f"{Tt}::IDENTITY.mul_vec{n}({c['v']})", c["v"])])
    pairs = [(mats[i], mats[(i + 3) % len(mats)]) for i in range(len(mats))]
    table("mul_mat", [("a", "m"), ("b", "m"), ("ab", "m"), ("ba", "m")],
          [{"a": x, "b": y, "ab": mul_mat(x, y), "ba": mul_mat(y, x)} for x, y in pairs],
          lambda c: [eq(f"{c['a']}.mul_mat{n}({c['b']})", c["ab"]),
                     eq(f"{c['a']} * {c['b']}", c["ab"]),
                     eq(f"{c['b']} * {c['a']}", c["ba"]),
                     eq(f"{c['a']} * {Tt}::IDENTITY", c["a"]),
                     eq(f"{Tt}::IDENTITY * {c['a']}", c["a"]),
                     f"let mut p = {c['a']};", f"p *= {c['b']};", eq("p", c["ab"])])

    # -------------------------------------------------------------- element-wise arithmetic
    rows = []
    for (x, y), k in zip(pairs, (SCALARS * 4)):
        k = ft.raw(k)
        rows.append({"a": x, "b": y, "k": k, "add": cw(lambda p, q: p + q, x, y),
                     "sub": cw(lambda p, q: p - q, x, y), "neg": cw(lambda p: -p, x),
                     "ms": mul_scalar(x, k), "ds": div_scalar(x, k),
                     "ab": cw(abs, x), "v": vecs[0],
                     "md": [[ft.mul(x[i][j], vecs[0][i]) for j in range(n)] for i in range(n)]})
    table("arith", [("a", "m"), ("b", "m"), ("k", "s"), ("add", "m"), ("sub", "m"),
                    ("neg", "m"), ("ms", "m"), ("ds", "m"), ("ab", "m"), ("v", "v"),
                    ("md", "m")], rows,
          lambda c: [eq(f"{c['a']} + {c['b']}", c["add"]),
                     eq(f"{c['a']}.add_mat{n}({c['b']})", c["add"]),
                     eq(f"{c['a']} - {c['b']}", c["sub"]),
                     eq(f"{c['a']}.sub_mat{n}({c['b']})", c["sub"]),
                     eq(f"-{c['a']}", c["neg"]),
                     eq(f"{c['a']}.mul_scalar({c['k']})", c["ms"]),
                     eq(f"{c['a']}.div_scalar({c['k']})", c["ds"]),
                     eq(f"{c['a']}.abs()", c["ab"]),
                     eq(f"{c['a']}.mul_diagonal_scale({c['v']})", c["md"]),
                     eq(f"{c['a']}.mul_diagonal_scale({c['v']})",
                        f"{c['a']}.mul_mat{n}({Tt}::from_diagonal({c['v']}))"),
                     f"let mut p = {c['a']};", f"p += {c['b']};", eq("p", c["add"]),
                     f"let mut p = {c['a']};", f"p -= {c['b']};", eq("p", c["sub"]),
                     f"let mut p = {c['a']};", f"p *= {c['k']};", eq("p", c["ms"]),
                     f"let mut p = {c['a']};", f"p /= {c['k']};", eq("p", c["ds"]),
                     f"assert!({c['a']}.abs_diff_eq({c['a']}, f(0)));"])
    # `Fixed::recip` overflows for a raw element of 1 or 2 and divides by zero at 0
    nonzero = [m for m in mats
               if all(x != 0 and ft.fits(ft.recip(x)) for c in m for x in c)]
    table("recip", [("m", "m"), ("e", "m")],
          [{"m": m, "e": cw(ft.recip, m)} for m in nonzero],
          lambda c: [eq(f"{c['m']}.recip()", c["e"])])

    # -------------------------------------------------------------- determinant and inverse
    rows = []
    for m in mats:
        inv = inverse(m)
        if inv is not None and not fits(inv):
            continue  # the inverse of a nearly singular matrix overflows: its own panic test
        p = mul_mat(m, inv) if inv is not None else None
        near = inv is not None and all(
            abs(p[i][j] - (ONE if i == j else 0)) <= IDENTITY_EPS
            for i in range(n) for j in range(n))
        rows.append({"m": m, "det": det(m), "dt": det(transpose(m)), "inv": inv,
                     "p": p if p is not None else [[0] * n for _ in range(n)], "near": near})
    table("det_inverse", [("m", "m"), ("det", "s"), ("dt", "s"), ("inv", "om"), ("p", "m"),
                          ("near", "bl")], rows,
          lambda c: [eq(f"{c['m']}.determinant()", c["det"]),
                     eq(f"{c['m']}.transpose().determinant()", c["dt"]),
                     eq(f"{c['m']}.try_inverse()", c["inv"]),
                     f"if let Some(k) = {c['inv']} {{",
                     f"    assert_eq!({c['m']}.inverse(), k);",
                     f"    assert_eq!({c['m']}.inverse_or_zero(), k);",
                     f"    assert_eq!({c['m']}.mul_mat{n}(k), {c['p']});",
                     f"    if {c['near']} {{",
                     f"        assert!({c['p']}.abs_diff_eq({Tt}::IDENTITY, IDENTITY_EPS));",
                     "    }",
                     "} else {",
                     f"    assert_eq!({c['m']}.inverse_or_zero(), {Tt}::ZERO);",
                     "}"])
    # det(a * b) = det(a) * det(b): exact on integer matrices (no rescale loses a bit)
    ints = [m for m in mats if all(x % ONE == 0 and abs(x) <= 8 * ONE for c in m for x in c)]
    table("det_product", [("a", "m"), ("b", "m"), ("d", "s")],
          [{"a": x, "b": y, "d": ft.mul(det(x), det(y))}
           for x, y in zip(ints, ints[1:] + ints[:1])],
          lambda c: [eq(f"({c['a']} * {c['b']}).determinant()", c["d"]),
                     eq(f"({c['a']} * {c['b']}).determinant()",
                        f"({c['b']} * {c['a']}).determinant()")])
    # ------------------------------------------------------------------ per-dimension tests
    up = [raws(b, n + 1) for b in POOL] if n < 4 else []
    if n == 2:
        rows = []
        for m in up[3:6]:
            for i in range(3):
                for j in range(3):
                    cs = [k for k in range(3) if k != i]
                    rs = [k for k in range(3) if k != j]
                    rows.append({"m": m, "i": i, "j": j,
                                 "e": [[m[cs[ci]][rs[rj]] for rj in range(2)]
                                       for ci in range(2)],
                                 "t": [[m[ci][rj] for rj in range(2)] for ci in range(2)]})
        table("from_mat3", [("m", "m3"), ("i", "us"), ("j", "us"), ("e", "m"), ("t", "m")], rows,
              lambda c: [eq(f"Mat2Trait::from_mat3_minor({c['m']}, {c['i']}, {c['j']})", c["e"]),
                         eq(f"Mat2Trait::from_mat3({c['m']})", c["t"])])
        test("test_from_angle", [
            "let a = f(0x59999999);",  # 0.35 rad
            "let (s, c) = a.sin_cos();",
            eq("Mat2Trait::from_angle(a)", "mat2(vec2(c, s), vec2(-s, c))"),
            "let scale = vec2(f(0x200000000), f(0x300000000));",
            eq("Mat2Trait::from_scale_angle(scale, a)",
               "mat2(vec2(c * scale.x, s * scale.x), vec2((-s) * scale.y, c * scale.y))"),
            "// a quarter turn is exact up to the 1 ULP of `sin_cos` at `FRAC_PI_2`",
            "let q = Mat2Trait::from_angle(fixed::fixed::FRAC_PI_2);",
            "assert!(q.abs_diff_eq(mat2(vec2(f(0), f(0x100000000)), "
            "vec2(f(-0x100000000), f(0))), f(2)));",
            "assert!(q.mul_vec2(vec2(f(0x100000000), f(0))).abs_diff_eq("
            "vec2(f(0), f(0x100000000)), f(2)));",
            "assert!(Mat2Trait::from_angle(f(0)).abs_diff_eq(Mat2Trait::IDENTITY, f(0)));"])
    if n == 3:
        test("test_mul_assign_affine2", [
            f"let lhs = {M(mats[3])};",
            f"let rhs_mat = {M(mats[4])};",
            "let rhs = glam::affine2::Affine2Trait::from_mat3(rhs_mat);",
            "let expected = lhs * Into::<glam::affine2::Affine2, Mat3>::into(rhs);",
            "let mut actual = lhs;",
            "actual *= rhs;",
            eq("actual", "expected"),
        ])
        rows = []
        for m in up[3:6]:
            for i in range(4):
                for j in range(4):
                    cs = [k for k in range(4) if k != i]
                    rs = [k for k in range(4) if k != j]
                    rows.append({"m": m, "i": i, "j": j,
                                 "e": [[m[cs[ci]][rs[rj]] for rj in range(3)]
                                       for ci in range(3)],
                                 "t": [[m[ci][rj] for rj in range(3)] for ci in range(3)]})
        table("from_mat4", [("m", "m4"), ("i", "us"), ("j", "us"), ("e", "m"), ("t", "m")], rows,
              lambda c: [eq(f"Mat3Trait::from_mat4_minor({c['m']}, {c['i']}, {c['j']})", c["e"]),
                         eq(f"Mat3Trait::from_mat4({c['m']})", c["t"])])
        rows = [{"m": raws(b, 2),
                 "e": [[raws(b, 2)[i][j] if i < 2 and j < 2 else (ONE if i == j == 2 else 0)
                        for j in range(3)] for i in range(3)]} for b in POOL[3:6]]
        table("from_mat2", [("m", "m2"), ("e", "m")], rows,
              lambda c: [eq(f"Mat3Trait::from_mat2({c['m']})", c["e"])])
        rows = [{"q": q, "e": quat_axes(q, 3), "b": from_rotation_axes(quat_axes(q, 3))}
                for q in QUATS]
        table("from_quat", [("q", "q"), ("e", "m"), ("b", "q")], rows,
              lambda c: [eq(f"Mat3Trait::from_quat({c['q']})", c["e"]),
                         "// the round trip through `Quat::from_mat3` closes to 1 raw ULP on",
                         "// this pool (4 over 50 000 random unit quaternions)",
                         eq(f"QuatTrait::from_mat3({c['e']})", c["b"]),
                         f"assert!({c['b']}.abs_diff_eq({c['q']}, f(1)) "
                         f"|| (-{c['b']}).abs_diff_eq({c['q']}, f(1)));",
                         "// a rotation matrix: unit columns, determinant one",
                         f"assert!({c['e']}.determinant().abs_diff_eq(f({ONE}), f(8)));",
                         f"assert!({c['e']}.x_axis.length().abs_diff_eq(f({ONE}), f(4)));"])
        test("test_from_quat_axes", [
            "let o = f(0x100000000);",
            "let z = f(0);",
            "// a half turn about each axis, exactly",
            eq("Mat3Trait::from_quat(QuatTrait::IDENTITY)", "Mat3Trait::IDENTITY"),
            eq("Mat3Trait::from_quat(quat(o, z, z, z))",
               "mat3(vec3(o, z, z), vec3(z, -o, z), vec3(z, z, -o))"),
            eq("Mat3Trait::from_quat(quat(z, o, z, z))",
               "mat3(vec3(-o, z, z), vec3(z, o, z), vec3(z, z, -o))"),
            eq("Mat3Trait::from_quat(quat(z, z, o, z))",
               "mat3(vec3(-o, z, z), vec3(z, -o, z), vec3(z, z, o))"),
            "// `from_quat` and `from_axis_angle` build the same rotation (2 ULP apart: the",
            "// quaternion halves the angle through `sin_cos`, the matrix does not)",
            "let a = f(0x59999999);",
            "let x = Mat3Trait::from_quat(QuatTrait::from_rotation_x(a));",
            "assert!(x.abs_diff_eq(Mat3Trait::from_rotation_x(a), f(2)));",
            "let y = Mat3Trait::from_quat(QuatTrait::from_rotation_y(a));",
            "assert!(y.abs_diff_eq(Mat3Trait::from_rotation_y(a), f(2)));",
            "let zz = Mat3Trait::from_quat(QuatTrait::from_rotation_z(a));",
            "assert!(zz.abs_diff_eq(Mat3Trait::from_rotation_z(a), f(2)));",
            "// rotating a vector through the matrix or through the quaternion agrees",
            "let q = QuatTrait::from_axis_angle(vec3(f(0x6db6db6e), f(0xdb6db6db), "
            "f(0x49249249)), a);",
            "let v = vec3(f(0x180000000), f(-0x1c0000000), f(0x160000000));",
            "assert!(Mat3Trait::from_quat(q).mul_vec3(v).abs_diff_eq(q.mul_vec3(v), f(8)));"])
        affine = [m for m in mats if m[0][2] == 0 and m[1][2] == 0 and m[2][2] == ONE]
        rows = [{"m": m, "v": rawv(v, 2), "p": transform_point(m, rawv(v, 2)),
                 "d": transform_vector(m, rawv(v, 2))}
                for m, v in zip(mats, VECS * 3)]
        table("transform2", [("m", "m"), ("v", "v2"), ("p", "v2"), ("d", "v2")], rows,
              lambda c: [eq(f"{c['m']}.transform_point2({c['v']})", c["p"]),
                         eq(f"{c['m']}.transform_vector2({c['v']})", c["d"])])
        test("test_rotations", [
            "let a = f(0x59999999);",
            "let (s, c) = a.sin_cos();",
            "let z = f(0);",
            "let o = f(0x100000000);",
            eq("Mat3Trait::from_rotation_x(a)",
               "mat3(vec3(o, z, z), vec3(z, c, s), vec3(z, -s, c))"),
            eq("Mat3Trait::from_rotation_y(a)",
               "mat3(vec3(c, z, -s), vec3(z, o, z), vec3(s, z, c))"),
            eq("Mat3Trait::from_rotation_z(a)",
               "mat3(vec3(c, s, z), vec3(-s, c, z), vec3(z, z, o))"),
            eq("Mat3Trait::from_angle(a)",
               "mat3(vec3(c, s, z), vec3(-s, c, z), vec3(z, z, o))"),
            "// `from_axis_angle` around an axis of the basis is `from_rotation_*` up to the",
            "// extra rescale of its triple products",
            "assert!(Mat3Trait::from_axis_angle(vec3(o, z, z), a)"
            ".abs_diff_eq(Mat3Trait::from_rotation_x(a), f(2)));",
            "assert!(Mat3Trait::from_axis_angle(vec3(z, o, z), a)"
            ".abs_diff_eq(Mat3Trait::from_rotation_y(a), f(2)));",
            "assert!(Mat3Trait::from_axis_angle(vec3(z, z, o), a)"
            ".abs_diff_eq(Mat3Trait::from_rotation_z(a), f(2)));",
            "// a rotation preserves the determinant and the length",
            "let r = Mat3Trait::from_axis_angle(vec3(f(0x6db6db6e), f(0xdb6db6db), "
            "f(0x49249249)), a);",
            "assert!(r.determinant().abs_diff_eq(o, f(8)));",
            "let v = vec3(f(0x180000000), f(-0x1c0000000), f(0x160000000));",
            "assert!(r.mul_vec3(v).length().abs_diff_eq(v.length(), f(8)));",
            "let scale = vec2(f(0x200000000), f(0x300000000));",
            "let tr = vec2(f(0x300000000), f(-0x200000000));",
            eq("Mat3Trait::from_scale_angle_translation(scale, a, tr)",
               "mat3(vec3(c * scale.x, s * scale.x, z), vec3((-s) * scale.y, c * scale.y, z), "
               "vec3(tr.x, tr.y, o))"),
            eq("Mat3Trait::from_scale(scale)",
               "mat3(vec3(scale.x, z, z), vec3(z, scale.y, z), vec3(z, z, o))"),
            eq("Mat3Trait::from_translation(tr)",
               "mat3(vec3(o, z, z), vec3(z, o, z), vec3(tr.x, tr.y, o))"),
            eq("Mat3Trait::from_translation(tr).transform_point2(scale)",
               "scale + tr"),
            eq("Mat3Trait::from_scale(scale).transform_vector2(tr)",
               "vec2(scale.x * tr.x, scale.y * tr.y)")])
    if n == 4:
        test("test_mul_affine3", [
            f"let lhs = {M(mats[3])};",
            f"let rhs_mat = {M(mats[4])};",
            "let rhs = glam::affine3::Affine3Trait::from_mat4(rhs_mat);",
            "let expected = lhs * Into::<glam::affine3::Affine3, Mat4>::into(rhs);",
            eq("lhs.mul_affine3(rhs)", "expected"),
            "let mut actual = lhs;",
            "actual *= rhs;",
            eq("actual", "expected"),
        ])
        rows = [{"m": raws(b, 3), "t": rawv(VECS[0], 3),
                 "e": [[raws(b, 3)[i][j] if i < 3 and j < 3 else (ONE if i == j == 3 else 0)
                        for j in range(4)] for i in range(4)],
                 "et": [[raws(b, 3)[i][j] if i < 3 and j < 3
                         else (ONE if i == j == 3 else
                               (rawv(VECS[0], 3)[j] if i == 3 else 0))
                         for j in range(4)] for i in range(4)]} for b in POOL[3:6]]
        table("from_mat3", [("m", "m3"), ("t", "v3"), ("e", "m"), ("et", "m")], rows,
              lambda c: [eq(f"Mat4Trait::from_mat3({c['m']})", c["e"]),
                         eq(f"Mat4Trait::from_mat3_translation({c['m']}, {c['t']})", c["et"]),
                         eq(f"Mat4Trait::from_mat3_translation({c['m']}, {c['t']})",
                            f"Mat4Trait::from_translation({c['t']}) "
                            f"* Mat4Trait::from_mat3({c['m']})")])
        # The TRS constructors and the decomposition. `scale` and `translation` are exactly
        # representable, so the round trip is only limited by the floored elements and by the
        # drift of the quantized quaternion's squared length (see `to_scale_rotation_translation`).
        trs, scales = [], [[ONE, ONE, ONE], [ONE * 2, ONE * 3, ONE // 2],
                           [-ONE, ONE * 2, ONE], [ONE // 4, ONE // 4, ONE // 4]]
        tvs = [[0, 0, 0], rawv(VECS[0], 3), rawv(VECS[1], 3), rawv(VECS[3], 3)]
        for k, qq in enumerate(QUATS):
            sc, tv = scales[k % len(scales)], tvs[k % len(tvs)]
            m = quat_axes(qq, 4, scale=sc, translation=tv)
            s2, q2, t2 = to_scale_rotation_translation(m)
            tol = max(abs(a - b) for a, b in zip(s2, sc))
            trs.append({"q": qq, "sc": sc, "tv": tv, "m": m,
                        "s2": s2, "q2": q2, "t2": t2, "tol": tol + 1})
        table("trs", [("q", "q"), ("sc", "v3"), ("tv", "v3"), ("m", "m"), ("s2", "v3"),
                      ("q2", "q"), ("t2", "v3"), ("tol", "s")], trs,
              lambda c: [eq(f"Mat4Trait::from_scale_rotation_translation({c['sc']}, {c['q']}, "
                            f"{c['tv']})", c["m"]),
                         "// the three constructors build the same linear part",
                         eq(f"Mat4Trait::from_quat({c['q']})",
                            f"Mat4Trait::from_mat3(Mat3Trait::from_quat({c['q']}))"),
                         eq(f"Mat4Trait::from_rotation_translation({c['q']}, {c['tv']})",
                            f"Mat4Trait::from_mat3_translation(Mat3Trait::from_quat({c['q']}), "
                            f"{c['tv']})"),
                         "// the decomposition, element by element against the oracle",
                         f"let (s, q, t) = {c['m']}.to_scale_rotation_translation();",
                         eq("s", c["s2"]), eq("q", c["q2"]), eq("t", c["t2"]),
                         "// and as a round trip: the translation is exact, the scale is within",
                         "// `5 |scale| + 2` ULP and the rotation within 13",
                         f"assert_eq!(t, {c['tv']});",
                         f"assert!(s.abs_diff_eq({c['sc']}, {c['tol']}));",
                         f"assert!(q.abs_diff_eq({c['q']}, f(13)) "
                         f"|| (-q).abs_diff_eq({c['q']}, f(13)));",
                         "// and rebuilding gives the same matrix back",
                         f"assert!(Mat4Trait::from_scale_rotation_translation(s, q, t)"
                         f".abs_diff_eq({c['m']}, f(64)));"])
        test("test_from_quat_axes", [
            "let o = f(0x100000000);",
            "let z = f(0);",
            eq("Mat4Trait::from_quat(QuatTrait::IDENTITY)", "Mat4Trait::IDENTITY"),
            eq("Mat4Trait::from_rotation_translation(QuatTrait::IDENTITY, Vec3Trait::ZERO)",
               "Mat4Trait::IDENTITY"),
            eq("Mat4Trait::from_scale_rotation_translation(Vec3Trait::ONE, "
               "QuatTrait::IDENTITY, Vec3Trait::ZERO)", "Mat4Trait::IDENTITY"),
            "// a half turn about x, exactly",
            eq("Mat4Trait::from_quat(quat(o, z, z, z))",
               "mat4(vec4(o, z, z, z), vec4(z, -o, z, z), vec4(z, z, -o, z), vec4(z, z, z, o))"),
            "// scale and translation are the `from_scale` / `from_translation` matrices",
            "let sc = vec3(f(0x200000000), f(0x300000000), f(0x80000000));",
            "let tv = vec3(f(0x300000000), f(-0x200000000), f(0x100000000));",
            eq("Mat4Trait::from_scale_rotation_translation(sc, QuatTrait::IDENTITY, tv)",
               "Mat4Trait::from_translation(tv) * Mat4Trait::from_scale(sc)"),
            eq("Mat4Trait::from_rotation_translation(QuatTrait::IDENTITY, tv)",
               "Mat4Trait::from_translation(tv)"),
            "// rotating a point through the TRS matrix: scale, then rotate, then translate",
            "let a = f(0x59999999);",
            "let q = QuatTrait::from_rotation_z(a);",
            "let m = Mat4Trait::from_scale_rotation_translation(sc, q, tv);",
            "let v = vec3(f(0x180000000), f(-0x1c0000000), f(0x160000000));",
            "assert!(m.transform_point3(v).abs_diff_eq(q.mul_vec3(sc * v) + tv, f(8)));",
            "assert!(m.transform_vector3(v).abs_diff_eq(q.mul_vec3(sc * v), f(8)));"])
        rows = []
        for m, v in zip(mats, VECS * 3):
            w = ft.dot([m[i][3] for i in range(3)] + [ONE], rawv(v, 3) + [m[3][3]])
            if w == 0:
                continue
            rows.append({"m": m, "v": rawv(v, 3), "p": transform_point(m, rawv(v, 3)),
                         "d": transform_vector(m, rawv(v, 3)),
                         "j": project_point(m, rawv(v, 3))})
        table("transform3", [("m", "m"), ("v", "v3"), ("p", "v3"), ("d", "v3"), ("j", "v3")],
              rows,
              lambda c: [eq(f"{c['m']}.transform_point3({c['v']})", c["p"]),
                         eq(f"{c['m']}.transform_vector3({c['v']})", c["d"]),
                         eq(f"{c['m']}.project_point3({c['v']})", c["j"])])
        test("test_rotations", [
            "let a = f(0x59999999);",
            "let (s, c) = a.sin_cos();",
            "let z = f(0);",
            "let o = f(0x100000000);",
            eq("Mat4Trait::from_rotation_x(a)",
               "mat4(vec4(o, z, z, z), vec4(z, c, s, z), vec4(z, -s, c, z), vec4(z, z, z, o))"),
            eq("Mat4Trait::from_rotation_y(a)",
               "mat4(vec4(c, z, -s, z), vec4(z, o, z, z), vec4(s, z, c, z), vec4(z, z, z, o))"),
            eq("Mat4Trait::from_rotation_z(a)",
               "mat4(vec4(c, s, z, z), vec4(-s, c, z, z), vec4(z, z, o, z), vec4(z, z, z, o))"),
            "assert!(Mat4Trait::from_axis_angle(vec3(z, z, o), a)"
            ".abs_diff_eq(Mat4Trait::from_rotation_z(a), f(2)));",
            "let scale = vec3(f(0x200000000), f(0x300000000), f(0x80000000));",
            "let tr = vec3(f(0x300000000), f(-0x200000000), f(0x100000000));",
            eq("Mat4Trait::from_scale(scale)",
               "mat4(vec4(scale.x, z, z, z), vec4(z, scale.y, z, z), vec4(z, z, scale.z, z), "
               "vec4(z, z, z, o))"),
            eq("Mat4Trait::from_translation(tr).transform_point3(scale)", "scale + tr"),
            eq("Mat4Trait::from_translation(tr).transform_vector3(scale)", "scale"),
            eq("Mat4Trait::from_scale(scale).transform_point3(tr)",
               "vec3(scale.x * tr.x, scale.y * tr.y, scale.z * tr.z)")])
        test("test_look", [
            "let eye = vec3(f(0x100000000), f(0x200000000), f(0x300000000));",
            "let center = vec3(f(0x400000000), f(-0x100000000), f(0x200000000));",
            "let up = vec3(f(0), f(0x100000000), f(0));",
            "let dir = Vec3Trait::normalize(center - eye);",
            eq("Mat4Trait::look_at_rh(eye, center, up)",
               "Mat4Trait::look_to_rh(eye, dir, up)"),
            eq("Mat4Trait::look_at_lh(eye, center, up)",
               "Mat4Trait::look_to_lh(eye, dir, up)"),
            eq("Mat4Trait::look_to_lh(eye, dir, up)",
               "Mat4Trait::look_to_rh(eye, -dir, up)"),
            "let m = Mat4Trait::look_to_rh(eye, dir, up);",
            "// the eye is the origin of the view space and the direction is -Z",
            "assert!(m.transform_point3(eye).abs_diff_eq(Vec3Trait::ZERO, f(8)));",
            "assert!(m.transform_vector3(dir).abs_diff_eq(vec3(f(0), f(0), f(-0x100000000)), "
            "f(8)));",
            "// the rotation part is orthonormal, so its determinant is +1",
            "assert!(Mat3Trait::from_mat4(m).determinant().abs_diff_eq(f(0x100000000), f(8)));"])

    # ------------------------------------------------------------------------------- panics
    sp = lambda name, msg, expr, marker=None: panic(name, msg, [f"let _ = {expr};"], marker)
    big = M([[MAX_RAW] * n for _ in range(n)])
    low = M([[MIN_RAW] * n for _ in range(n)])
    sing = M([[0] * n for _ in range(n)])
    sp("test_inverse_singular", f"'{T}: singular'", f"{sing}.inverse()")
    sp("test_col_out_of_bounds", f"'{T}: index out of bounds'", f"{Tt}::IDENTITY.col({n})")
    sp("test_row_out_of_bounds", f"'{T}: index out of bounds'", f"{Tt}::IDENTITY.row({n})")
    sp("test_div_scalar_by_zero", "'Fixed: division by zero'", f"{Tt}::IDENTITY.div_scalar(f(0))")
    sp("test_recip_zero", "'Fixed: division by zero'", f"{Tt}::ZERO.recip()")
    sp("test_add_overflow", "'i64_add Overflow'", f"{big} + {big}")
    sp("test_sub_underflow", "'i64_sub Underflow'", f"{low} - {big}")
    sp("test_neg_underflow", "'i64_neg Underflow'", f"-{low}")
    sp("test_abs_overflow", "'Fixed: overflow'", f"{low}.abs()")
    # the all-`MAX` matrix has a zero determinant; a `MAX` diagonal does overflow
    diag_max = M([[MAX_RAW if i == j else 0 for j in range(n)] for i in range(n)])
    sp("test_determinant_overflow", "'Fixed: overflow'", f"{diag_max}.determinant()")
    sp("test_mul_vec_overflow", "'Fixed: overflow'", f"{big}.mul_vec{n}({Vt}::ONE)",
       f"{T}::mul_vec{n}")
    sp("test_mul_scalar_overflow", "'Fixed: overflow'",
       f"{big}.mul_scalar(f({MAX_RAW}))")
    ovf = "'Fixed: overflow'"
    big, low = f"full({MAX_RAW})", f"full({MIN_RAW})"
    sp(f"test_mul_transpose_vec{n}_overflow", ovf, f"{big}.mul_transpose_vec{n}({Vt}::ONE)")
    sp(f"test_mul_mat{n}_overflow", ovf, f"{big}.mul_mat{n}({big})")
    sp(f"test_add_mat{n}_overflow", "'i64_add Overflow'", f"{big}.add_mat{n}({big})")
    sp(f"test_sub_mat{n}_underflow", "'i64_sub Underflow'", f"{low}.sub_mat{n}({big})")
    sp("test_div_scalar_overflow", ovf, f"{big}.div_scalar(f(0x80000000))")
    sp("test_mul_diagonal_scale_overflow", ovf,
       f"{big}.mul_diagonal_scale({Vt}::splat(f({MAX_RAW})))")
    # the determinant is 1 raw: the inverse of the `1.0` elements is 2^32
    tiny = M([[(1 if i == 0 else ONE) if i == j else 0 for j in range(n)] for i in range(n)])
    sp("test_inverse_overflow", ovf, f"{tiny}.inverse()")
    sp("test_try_inverse_overflow", ovf, f"{tiny}.try_inverse()")
    sp("test_inverse_or_zero_overflow", ovf, f"{tiny}.inverse_or_zero()")
    sp("test_recip_overflow", ovf, "full(1).recip()")
    v3 = lambda x, y, z: f"Vec3Trait::new(f({x}), f({y}), f({z}))"
    v2 = lambda x, y: f"Vec2Trait::new(f({x}), f({y}))"
    # `sin_cos(FRAC_PI_2)` is exactly `(1, 0)`: `-sin * MIN` overflows
    pi2 = "fixed::fixed::FRAC_PI_2"
    qbig = "QuatTrait::from_xyzw(" + ", ".join([f"f({1 << 48})"] * 4) + ")"
    qmax = f"QuatTrait::from_xyzw(f({MAX_RAW}), f(0), f(0), f(0))"
    if n == 2:
        sp("test_from_scale_angle_overflow", ovf,
           f"Mat2Trait::from_scale_angle({v2(MIN_RAW, MIN_RAW)}, {pi2})")
    if n == 3:
        sp("test_from_quat_overflow", ovf, f"Mat3Trait::from_quat({qbig})")
        sp("test_from_quat_add_overflow", "'i64_add Overflow'", f"Mat3Trait::from_quat({qmax})")
        sp("test_from_axis_angle_overflow", ovf,
           f"Mat3Trait::from_axis_angle(Vec3Trait::splat(f({MAX_RAW})), {pi2})")
        sp("test_from_scale_angle_translation_overflow", ovf,
           f"Mat3Trait::from_scale_angle_translation({v2(MIN_RAW, MIN_RAW)}, {pi2}, "
           "Vec2Trait::ZERO)")
        sp("test_transform_point2_overflow", ovf, f"{big}.transform_point2(Vec2Trait::ONE)")
        sp("test_transform_vector2_overflow", ovf, f"{big}.transform_vector2(Vec2Trait::ONE)")
    if n == 4:
        sp("test_mul_affine3_overflow", ovf,
           f"{big}.mul_affine3(glam::affine3::Affine3Trait::from_scale("
           f"Vec3Trait::splat(f({2 * ONE}))))")
        sp("test_from_quat_overflow", ovf, f"Mat4Trait::from_quat({qbig})")
        sp("test_from_quat_add_overflow", "'i64_add Overflow'", f"Mat4Trait::from_quat({qmax})")
        sp("test_from_rotation_translation_overflow", ovf,
           f"Mat4Trait::from_rotation_translation({qbig}, Vec3Trait::ZERO)")
        sp("test_from_rotation_translation_add_overflow", "'i64_add Overflow'",
           f"Mat4Trait::from_rotation_translation({qmax}, Vec3Trait::ZERO)")
        sp("test_from_scale_rotation_translation_overflow", ovf,
           f"Mat4Trait::from_scale_rotation_translation(Vec3Trait::ONE, {qbig}, Vec3Trait::ZERO)")
        sp("test_from_scale_rotation_translation_add_overflow", "'i64_add Overflow'",
           f"Mat4Trait::from_scale_rotation_translation(Vec3Trait::ONE, {qmax}, "
           "Vec3Trait::ZERO)")
        sp("test_to_scale_rotation_translation_zero", "'Fixed: division by zero'",
           "Mat4Trait::ZERO.to_scale_rotation_translation()")
        sp("test_to_scale_rotation_translation_overflow", ovf,
           f"{big}.to_scale_rotation_translation()")
        sp("test_from_axis_angle_overflow", ovf,
           f"Mat4Trait::from_axis_angle(Vec3Trait::splat(f({MAX_RAW})), {pi2})")
        sp("test_transform_point3_overflow", ovf, f"{big}.transform_point3(Vec3Trait::ONE)")
        sp("test_transform_vector3_overflow", ovf, f"{big}.transform_vector3(Vec3Trait::ONE)")
        sp("test_project_point3_overflow", ovf, f"{big}.project_point3(Vec3Trait::ONE)")
        # `dir = X`, `up = Y`: `s = Z`, `u = Y`, so the translation is `(-eye.z, -eye.y, eye.x)`
        # (`-MIN` underflows); with `up = (0, 1, 1)`, `s = (0, -1, 1) / sqrt(2)` and
        # `-dot(eye, s)` overflows for `eye = (0, MIN, MAX)`
        up11 = v3(0, ONE, ONE)
        e_min, e_ovf = v3(0, MIN_RAW, 0), v3(0, MIN_RAW, MAX_RAW)
        c_min, c_ovf = v3(ONE, MIN_RAW, 0), v3(ONE, MIN_RAW, MAX_RAW)
        for h in ("rh", "lh"):
            if h == "lh":
                sp("test_look_to_lh_parallel", "'Vec3: normalize zero'",
                   "Mat4Trait::look_to_lh(Vec3Trait::ZERO, Vec3Trait::Y, Vec3Trait::Y)")
            sp(f"test_look_to_{h}_overflow", ovf,
               f"Mat4Trait::look_to_{h}({e_ovf}, Vec3Trait::X, {up11})")
            sp(f"test_look_to_{h}_neg_underflow", "'i64_neg Underflow'",
               f"Mat4Trait::look_to_{h}({e_min}, Vec3Trait::X, Vec3Trait::Y)")
            sp(f"test_look_at_{h}_eye_is_center", "'Vec3: normalize zero'",
               f"Mat4Trait::look_at_{h}(Vec3Trait::ONE, Vec3Trait::ONE, Vec3Trait::Y)")
            sp(f"test_look_at_{h}_overflow", ovf,
               f"Mat4Trait::look_at_{h}({e_ovf}, {c_ovf}, {up11})")
            sp(f"test_look_at_{h}_neg_underflow", "'i64_neg Underflow'",
               f"Mat4Trait::look_at_{h}({e_min}, {c_min}, Vec3Trait::Y)")
            sp(f"test_look_at_{h}_sub_underflow", "'i64_sub Underflow'",
               f"Mat4Trait::look_at_{h}({v3(MAX_RAW, 0, 0)}, {v3(MIN_RAW, 0, 0)}, "
               "Vec3Trait::Y)")
    if n == 2:
        sp("test_from_mat3_minor_column", "'Mat2: index out of bounds'",
           "Mat2Trait::from_mat3_minor(Mat3Trait::IDENTITY, 3, 0)")
        sp("test_from_mat3_minor_row", "'Mat2: index out of bounds'",
           "Mat2Trait::from_mat3_minor(Mat3Trait::IDENTITY, 0, 3)")
    if n == 3:
        sp("test_from_mat4_minor_column", "'Mat3: index out of bounds'",
           "Mat3Trait::from_mat4_minor(Mat4Trait::IDENTITY, 4, 0)")
        sp("test_from_mat4_minor_row", "'Mat3: index out of bounds'",
           "Mat3Trait::from_mat4_minor(Mat4Trait::IDENTITY, 0, 4)")
    if n == 4:
        sp("test_project_point3_by_zero", "'Fixed: division by zero'",
           "Mat4Trait::ZERO.project_point3(Vec3Trait::ONE)")
        sp("test_look_to_parallel", "'Vec3: normalize zero'",
           "Mat4Trait::look_to_rh(Vec3Trait::ZERO, Vec3Trait::Y, Vec3Trait::Y)",
           "Mat4::look_to_rh")

    # --------------------------------------------------------------------------------- fuzz
    seed = 200 * n
    args = ", ".join(f"{k}: i64" for k in "abcd")
    # |element| <= 8, so a product is at most 64, a matrix product at most 8 * 8 * n and the
    # adjugate at most ADJ ULP; see the bound of `fuzz_inverse` below.
    adj_max = {2: 8, 3: 128, 4: 3072}[n]
    inv_bound = 8 * n * (adj_max + 2) + 1
    assoc = 16 * n + 2
    det_tol = {2: 0, 3: 0, 4: 1024}[n]
    approx = (lambda a, b, k: f"assert!({a}.abs_diff_eq({b}, f({k})));") if det_tol else \
        (lambda a, b, k: f"assert_eq!({a}, {b});")
    fuzz("fuzz_layout_ops", seed + 1, args, [
        "let x = ma(a, b, c, d);", "let y = mb(a, b, c, d);",
        "assert_eq!(x.transpose().transpose(), x);",
        f"assert_eq!({Tt}::from_cols_array(x.to_cols_array()), x);",
        f"assert_eq!({Tt}::from_rows_array(x.to_rows_array()), x);",
        f"assert_eq!({Tt}::from_cols_array_2d(x.to_cols_array_2d()), x);",
        f"assert_eq!({Tt}::from_rows(" + ", ".join(f"x.row({j})" for j in range(n)) + "), x);",
        f"assert_eq!({Tt}::from_cols(" + ", ".join(f"x.col({i})" for i in range(n)) + "), x);",
        "assert_eq!(x.col(0), x.transpose().row(0));",
        "assert_eq!((x + y) - y, x);",
        "assert_eq!(x + y, y + x);",
        "assert_eq!(x - y, x + (-y));",
        "assert_eq!(-(-x), x);",
        f"assert_eq!(x.add_mat{n}(y), x + y);",
        f"assert_eq!(x.sub_mat{n}(y), x - y);",
        "assert_eq!(x.mul_scalar(f(0x100000000)), x);",
        "assert_eq!(x.abs().abs(), x.abs());",
        "assert!(x.abs_diff_eq(x, f(0)));",
    ])
    fuzz("fuzz_mul_vec", seed + 2, args, [
        "let x = ma(a, b, c, d);", "let v = va(a, b, c, d);", "let w = vb(a, b, c, d);",
        f"assert_eq!({Tt}::IDENTITY.mul_vec{n}(v), v);",
        f"assert_eq!(x.mul_vec{n}({Vt}::ZERO), {Vt}::ZERO);",
        f"assert_eq!(x.mul_transpose_vec{n}(v), x.transpose().mul_vec{n}(v));",
        "// one floor rescale per component on each side: the two differ by at most 1 ULP",
        f"assert!(x.mul_vec{n}(v + w).abs_diff_eq(x.mul_vec{n}(v) + x.mul_vec{n}(w), f(1)));",
        f"assert_eq!({Tt}::from_diagonal(v).mul_vec{n}(w), v * w);",
        f"assert_eq!({Tt}::from_diagonal(v).diagonal(), v);",
    ])
    fuzz("fuzz_mul_mat", seed + 3, args, [
        "let x = ma(a, b, c, d);", "let y = mb(a, b, c, d);", "let v = va(a, b, c, d);",
        f"assert_eq!(x * {Tt}::IDENTITY, x);",
        f"assert_eq!({Tt}::IDENTITY * x, x);",
        f"assert_eq!(x * {Tt}::ZERO, {Tt}::ZERO);",
        f"assert_eq!(x.mul_mat{n}(y), x * y);",
        "assert_eq!((x * y).transpose(), y.transpose() * x.transpose());",
        "let mut p = x;", "p *= y;", "assert_eq!(p, x * y);",
        "// (x * y) * v and x * (y * v) floor twice each, with factors of at most 8:",
        f"// |diff| <= 2 * (8 * {n} + 1) ULP",
        f"assert!((x * y).mul_vec{n}(v).abs_diff_eq(x.mul_vec{n}(y.mul_vec{n}(v)), "
        f"f({assoc})));",
    ])
    cols = ", ".join(["v", "v"] + ["w"] * (n - 2))
    fuzz("fuzz_determinant", seed + 4, args, [
        "let x = ma(a, b, c, d);", "let v = va(a, b, c, d);",
    ] + (["let w = vb(a, b, c, d);"] if n > 2 else []) + [
        f"assert_eq!({Tt}::IDENTITY.determinant(), f(0x100000000));",
        f"assert_eq!({Tt}::ZERO.determinant(), f(0));",
        "// the determinant of the transpose is the same sum of products" + (
            ", up to the floor of the" if det_tol else ", in the same order of"),
        ("// six shared 2x2 minors (12 products of factors <= 64): |diff| <= 769 ULP"
         if det_tol else "// accumulation: it is bit-identical"),
        approx("x.transpose().determinant()", "x.determinant()", det_tol),
        "// two equal columns make the matrix singular",
        f"let s = {Tt}::from_cols({cols});",
        approx("s.determinant()", "f(0)", det_tol),
    ] + ([] if det_tol else ["assert_eq!(s.try_inverse(), None);"]))
    fuzz("fuzz_inverse", seed + 5, args, [
        "let x = ma(a, b, c, d);",
        "let d = x.determinant();",
        "if d.abs() >= f(0x100000000) {",
        "    let inv = x.inverse();",
        "    assert_eq!(x.try_inverse(), Some(inv));",
        "    assert_eq!(x.inverse_or_zero(), inv);",
        "    // each element of the inverse is the floored adjugate element (1 ULP) divided",
        "    // once (< 1 ULP), plus the propagated error of the floored determinant",
        f"    // (|inverse| <= {adj_max} ULP for |det| >= 1); the product multiplies that by",
        f"    // |element| <= 8 and floors once: |diff| <= 8 * {n} * ({adj_max} + 2) + 1",
        f"    assert!(x.mul_mat{n}(inv).abs_diff_eq({Tt}::IDENTITY, f({inv_bound})));",
        "} else if d == f(0) {",
        "    assert_eq!(x.try_inverse(), None);",
        f"    assert_eq!(x.inverse_or_zero(), {Tt}::ZERO);",
        "}",
    ])
    extra = {
        2: ["let r = Mat2Trait::from_angle(f(0x59999999));",
            "// a rotation preserves the determinant (1) and the length, up to `sin_cos`",
            "assert!(r.determinant().abs_diff_eq(f(0x100000000), f(4)));",
            "assert!(r.mul_vec2(v).length().abs_diff_eq(v.length(), f(8)));",
            "assert_eq!(Mat2Trait::from_scale_angle(Vec2Trait::ONE, f(0x59999999)), r);",
            "// det(x * r) = det(x) * det(r): the product floors each element (<= 2 * 8 * 8",
            "// ULP on the determinant) and det(r) is 1 within 4 ULP (|det(x)| <= 128)",
            "assert!((x * r).determinant().abs_diff_eq(x.determinant(), f(1024)));"],
        3: ["// `transform_point2` is `transform_vector2` plus the translation column, added",
            "// exactly inside the same rescale",
            "let p = Vec2Trait::new(v.x, v.y);",
            "assert_eq!(x.transform_point2(p), x.transform_vector2(p) "
            "+ Vec3Trait::truncate(x.z_axis));",
            "assert_eq!(Mat3Trait::from_translation(p).transform_point2(p), p + p);",
            "assert_eq!(Mat3Trait::IDENTITY.transform_vector2(p), p);"],
        4: ["let p = Vec3Trait::new(v.x, v.y, v.z);",
            "assert_eq!(x.transform_point3(p), x.transform_vector3(p) "
            "+ Vec4Trait::truncate(x.w_axis));",
            "assert_eq!(Mat4Trait::from_translation(p).transform_point3(p), p + p);",
            "assert_eq!(Mat4Trait::IDENTITY.transform_vector3(p), p);",
            "// an affine matrix has `w = 1`, so the projection is the affine transform",
            "let affine = Mat4Trait::from_translation(p);",
            "assert_eq!(affine.project_point3(p), affine.transform_point3(p));"],
    }[n]
    fuzz("fuzz_transform", seed + 6, args, [
        "let x = ma(a, b, c, d);", "let v = va(a, b, c, d);", *extra,
    ])

    # ------------------------------------------------------------------------------ prelude
    body = "\n".join(G.out)
    helpers = {
        "fx": f"""
fn fx(r: Span<i64>, o: u32) -> Fixed {{
    f(*r[o])
}}
""",
        "us": """
fn us(r: Span<i64>, o: u32) -> usize {
    (*r[o]).try_into().unwrap()
}
""",
        "bl": """
fn bl(r: Span<i64>, o: u32) -> bool {
    *r[o] != 0
}
""",
    }
    at = lambda i: "o" if i == 0 else f"o + {i}"
    for k in (2, 3, 4):
        d = g.Ty(k)
        name = "vc" if k == n else f"vv{k}"
        helpers[name] = f"""
fn {name}(r: Span<i64>, o: u32) -> {d.V} {{
    {d.V}Trait::from_array([{", ".join(f"fx(r, {at(i)})" for i in range(k))}])
}}
"""
        name = "mx" if k == n else f"mm{k}"
        helpers[name] = f"""
fn {name}(r: Span<i64>, o: u32) -> {d.name} {{
    {d.name}Trait::from_cols_array([{", ".join(f"fx(r, {at(i)})" for i in range(k * k))}])
}}
"""
    helpers["qq"] = """
fn qq(r: Span<i64>, o: u32) -> Quat {
    QuatTrait::from_array([fx(r, o), fx(r, o + 1), fx(r, o + 2), fx(r, o + 3)])
}
"""
    helpers["om"] = f"""
fn om(r: Span<i64>, o: u32) -> Option<{T}> {{
    if *r[o] == 0 {{
        None
    }} else {{
        Some(mx(r, o + 1))
    }}
}}
"""
    helpers["full"] = f"""
fn full(raw: i64) -> {T} {{
    let x = f(raw);
    {Tt}::from_cols_array([{", ".join(["x"] * (n * n))}])
}}
"""
    helpers["hash"] = f"""
fn hash(m: {T}) -> felt252 {{
    PoseidonTrait::new().update_with(m).finalize()
}}
"""
    helpers["cell"] = """
/// The `k`-th element of a fuzzed matrix: |value| <= 8, so every product of two elements is at
/// most 64 and no kernel of this module can overflow.
fn cell(v: i64, k: i64) -> Fixed {
    f((v / (k + 1) + k * 2654435761) % 0x800000000)
}
"""
    cells = lambda off: ", ".join(f"cell({'abcd'[(i + off) % 4]}, {i + off})"
                                 for i in range(n * n))
    helpers["ma"] = f"""
fn ma({args}) -> {T} {{
    {Tt}::from_cols_array([{cells(0)}])
}}
"""
    helpers["mb"] = f"""
fn mb({args}) -> {T} {{
    {Tt}::from_cols_array([{cells(1)}])
}}
"""
    vcells = lambda off: ", ".join(f"cell({'abcd'[(i + off) % 4]}, {i + off})" for i in range(n))
    helpers["va"] = f"""
fn va({args}) -> {V} {{
    {Vt}::from_array([{vcells(0)}])
}}
"""
    helpers["vb"] = f"""
fn vb({args}) -> {V} {{
    {Vt}::from_array([{vcells(2)}])
}}
"""
    # transitive: `ma` uses `cell`, the matrix readers use `fx`, ...
    keep, text = [], body
    for _ in range(3):
        for name, src in helpers.items():
            if name not in keep and re.search(rf"\b{name}\(", text):
                keep.append(name)
                text += src
    used = "".join(helpers[name] for name in helpers if name in keep)
    body_and_helpers = body + used
    uses = ["use core::hash::{HashStateExTrait, HashStateTrait};",
            "use core::poseidon::PoseidonTrait;"] if "hash(" in body else []
    uses.append("use fixed::fixed::{Fixed, FixedTrait};")
    if ".sin_cos()" in body:
        uses.append("use fixed::trig::TrigTrait;")
    glam = []
    for k in (2, 3, 4):
        for kind, prefix in (("Mat", "mat"), ("Vec", "vec")):
            items = [x for x in (f"{kind}{k}", f"{kind}{k}Trait", f"{prefix}{k}")
                     if re.search(rf"\b{x}\b(?!Trait)" if x[0].isupper() and
                                  not x.endswith("Trait") else rf"\b{x}\b",
                                  body_and_helpers)]
            if items:
                glam.append(f"use glam::{prefix}{k}::"
                            + (items[0] if len(items) == 1 else "{" + ", ".join(items) + "}")
                            + ";")
    qitems = [x for x in ("Quat", "QuatTrait", "quat")
              if re.search(rf"\b{x}\b(?!Trait)" if x == "Quat" else rf"\b{x}\b",
                           body_and_helpers)]
    if qitems:
        glam.append("use glam::quat::"
                    + (qitems[0] if len(qitems) == 1 else "{" + ", ".join(qitems) + "}") + ";")
    uses += sorted(glam)
    prelude = f"""{g.HEADER}//! Tests of `glam::{t.mod}`: the glam-rs matrix test cases of `tests/mat{n}.rs`, tables over pools
//! of matrices (expected values computed by the generator with an exact Q32.32 Python oracle that
//! mirrors `fixed::wide` kernel by kernel, one `const` table and one looping test per function
//! group), seeded fuzz properties, and one test per panic path.
//!
//! The glam-rs results themselves are checked by `golden_{t.mod}.cairo` (generated by
//! `tools/refgen` with `DMat{n}` as the oracle); this file pins the bit-exact fixed-point
//! semantics: floor rescales, the shared round-to-nearest reciprocal of `inverse` and
//! `div_scalar`, and the exact accumulation of the adjugate.

{chr(10).join(uses)}

/// The `M * M^-1 ~ IDENTITY` budget in raw ULP (see the generator).
const IDENTITY_EPS: Fixed = Fixed {{ raw: {IDENTITY_EPS} }};

/// A `Fixed` from its raw Q32.32 value (every table cell is a raw value).
fn f(raw: i64) -> Fixed {{
    FixedTrait::from_raw(raw)
}}

// Readers of the table rows (`[i64; W]`): the value of a column at an offset.
{used}"""
    return prelude + body
