"""Test template (`packages/glam/tests/test_<m>.cairo`) of tools/codegen/intvec.py.

Three layers, as in docs/DESIGN.md section 5:
  * the glam-rs test cases of `tests/vec{2,3,4}.rs` (`impl_vecN_tests!`, `_signed_tests!`,
    `_signed_integer_tests!` / `_unsigned_integer_tests!`, the wrapping / saturating macros),
    ported as rows of the tables below or as a few unrolled assertions;
  * tables over a pool of eight pairs of edge values (0, +-1, MIN, MAX, 2^16, 2^31 ...): the
    expected values are computed here with Python integers, the oracle of two's complement
    arithmetic;
  * seeded fuzz properties against an `i128` reference written in the test file, and one
    `#[should_panic]` per panic path with the exact message.

Compile budget. The Cairo compiler pays for every call site: each `assert_eq!` inlines the
operators under test and a formatting path, so an unrolled table of cases costs (cases x checks)
call sites. A table here is one `const` of `[i64; W]` rows and ONE `#[test]` that loops over it:
the cost is (checks) call sites, independent of the number of rows. Keep it that way: the CI
runner is killed when the six `glam_tests` modules need more than a few GB to compile.
"""
import intvec as g

MIN, MAX, UMAX = g.I32_MIN, g.I32_MAX, g.U32_MAX


# --------------------------------------------------------------------------------------------
# Reference semantics (Rust i32 / u32)
# --------------------------------------------------------------------------------------------
def wrap(t, v):
    v &= 0xFFFFFFFF
    return v - 2**32 if t.signed and v >= 2**31 else v


def sat(t, v):
    return max(t.smin, min(t.smax, v))


def fits(t, v):
    return t.smin <= v <= t.smax


def tdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def trem(a, b):
    return a - b * tdiv(a, b)


def div_euclid(a, b):
    r = a % abs(b)
    return (a - r) // b


def rem_euclid(a, b):
    return a % abs(b)


# --------------------------------------------------------------------------------------------
# Emit helpers
# --------------------------------------------------------------------------------------------
def num(v):
    return str(v)


# Column kinds of a table row: (width in i64 cells given n, Cairo reader of the prelude).
KINDS = {
    "v": (lambda n: n, "vc"),        # vector of the tested type
    "o": (lambda n: n, "vo"),        # vector of the other signedness
    "s": (lambda n: 1, "sc"),        # scalar of the tested type
    "u": (lambda n: 1, "su"),        # u32
    "us": (lambda n: 1, "us"),       # usize
    "b": (lambda n: n, "bv"),        # BVecN
    "opt": (lambda n: n + 1, "opt"),  # Option<T>: flag, then the vector
    "opto": (lambda n: n + 1, "opto"),  # Option<other type>
    "optu": (lambda n: 2, "optu"),   # Option<u32>
}


class Gen:
    def __init__(self, t):
        self.t = t
        self.out = []

    def V(self, vals, t=None):
        t = t or self.t
        return f"{t.mod}(" + ", ".join(num(v) for v in list(vals)[:t.n]) + ")"

    def B(self, vals):
        return f"{self.t.bmod}(" + ", ".join("true" if v else "false"
                                             for v in list(vals)[:self.t.n]) + ")"

    def test(self, name, lines, attrs=()):
        body = "\n".join("    " + l for l in lines)
        a = "".join(f"#[{x}]\n" for x in attrs)
        self.out.append(f"#[test]\n{a}fn {name}() {{\n{body}\n}}\n")

    def panic(self, name, msg, lines):
        self.test(name, lines, attrs=[f"should_panic(expected: {msg})"])

    def cells(self, kind, v):
        n = self.t.n
        if kind in ("v", "o"):
            return [int(k) for k in list(v)[:n]]
        if kind in ("s", "u", "us"):
            return [int(v)]
        if kind == "b":
            return [1 if k else 0 for k in list(v)[:n]]
        if kind in ("opt", "opto"):
            return [0] * (n + 1) if v is None else [1] + [int(k) for k in list(v)[:n]]
        if kind == "optu":
            return [0, 0] if v is None else [1, int(v)]
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
        data = ",\n".join("    [" + ", ".join(map(str, r)) + "]" for r in flat)
        const = name.upper()
        self.out.append(f"const {const}: [[i64; {off}]; {len(rows)}] = [\n{data},\n];\n")
        lines = [f"for row in {const}.span() {{", "    let r = row.span();"]
        lines += ["    " + l for l in body(acc)]
        lines += ["}"]
        self.test(f"test_{name}", lines)


# Eight pairs of 4-vectors: every edge value of the pool meets another one on some component,
# on every 2-, 3- and 4-component prefix.
POOL_S = [
    ([MIN, MIN + 1, -65536, -46341], [MAX, MAX - 1, 65536, 46340]),
    ([MAX, MAX - 1, 46340, 65536], [MAX, 1, 2, -1]),
    ([-1, 0, 1, 2], [-1, 0, 1, 2]),
    ([-7, 5, -46341, 46340], [3, -2, -46341, 46340]),
    ([MIN, MAX, MIN, MAX], [-1, -1, 1, 1]),
    ([0, 0, 0, 0], [MIN, MAX, 65536, -65536]),
    ([65536, -65536, 65536, -65536], [65536, 65536, -65536, -65536]),
    ([1, 2, 5, -1], [-5, 7, MIN, MIN + 1]),
]
POOL_U = [
    ([0, 1, 2, 7], [UMAX, UMAX - 1, 2**31, 2**31 + 1]),
    ([UMAX, UMAX - 1, 2**31, 2**31 - 1], [UMAX, 1, 2, 65536]),
    ([0, 1, 2, 3], [0, 1, 2, 3]),
    ([65535, 65536, 7, 5], [65536, 65535, 3, 2]),
    ([UMAX, 2**31, 65536, 1], [1, 2, 65536, UMAX]),
    ([0, 0, 0, 0], [UMAX, 2**31, 65536, 1]),
    ([2**31 + 1, 2**31, 2**31 - 1, 65535], [2**31, 2**31 + 1, 65535, 65536]),
    ([3, 5, 7, 11], [13, 2, 1, 0]),
]
MASKS = {2: [0, 1, 2, 3], 3: list(range(8)), 4: [0, 15, 1, 2, 4, 8, 5, 10]}


def pairs(t):
    return POOL_S if t.signed else POOL_U


def small_pairs(t):
    if t.signed:
        return [([3, -7, 11, -13], [-5, 2, 9, 4]), ([-1, -2, -3, -4], [4, 3, 2, 1]),
                ([0, 1, -1, 2], [7, -7, 7, -7]), ([100, -200, 300, -400], [-9, 8, -7, 6]),
                ([46340, -3, 1, 0], [46340, 5, -1, 5])]
    return [([30, 7, 110, 13], [5, 2, 9, 4]), ([1, 2, 3, 4], [4, 3, 2, 1]),
            ([0, 1, 5, 2], [7, 9, 7, 3]), ([100, 200, 300, 400], [9, 8, 7, 6]),
            ([65535, 3, 1, 0], [65535, 5, 1, 5])]


def gen_tests(t):
    T, S, n, o, s = t.name, t.S, t.n, t.other, t.signed
    G = Gen(t)
    V, Bm, test, panic, table = G.V, G.B, G.test, G.panic, G.table
    cs = t.c
    Tt = f"{T}Trait"
    oT = f"{o.name}Trait"
    eq = lambda a, b: f"assert_eq!({a}, {b});"
    some = lambda v: f"Some({v})"
    # component-wise map over the first n components (the others may be anything)
    cw = lambda f, *vs: [f(*[v[i] for v in vs]) for i in range(n)]
    nz = lambda y: [k if k != 0 else 3 for k in y]

    # ---------------------------------------------------------------- glam-rs: impl_vecN_tests
    one = [1, 2, 3, 4]
    test("test_new", [
        f"let v = {Tt}::new({', '.join(map(str, one[:n]))});",
        *[eq(f"v.{c}", one[i]) for i, c in enumerate(cs)],
        eq("v", V(one)),
        f"let t = ({', '.join(f'{x}_{S}' for x in one[:n])});",
        f"let v: {T} = t.into();", eq("v", V(one)),
        f"let t2: ({', '.join([S] * n)}) = v.into();", eq("t2", "t"),
        f"let a = [{', '.join(f'{x}_{S}' for x in one[:n])}];",
        f"let v: {T} = a.into();", eq("v", V(one)), eq(f"{Tt}::from_array(a)", V(one)),
        f"let a2: [{S}; {n}] = v.into();", eq("a2", "a"), eq("v.to_array()", "a"),
        eq(f"Default::<{T}>::default()", f"{Tt}::ZERO"),
    ])
    unit = lambda i, v=1: [v if j == i else 0 for j in range(4)]
    lines = [eq(f"{Tt}::ZERO", V([0] * 4)), eq(f"{Tt}::ONE", V([1] * 4)),
             eq(f"{Tt}::MIN", V([t.smin] * 4)), eq(f"{Tt}::MAX", V([t.smax] * 4))]
    lines += [eq(f"{Tt}::{c.upper()}", V(unit(i))) for i, c in enumerate(cs)]
    if s:
        lines += [eq(f"{Tt}::NEG_ONE", V([-1] * 4))]
        lines += [eq(f"{Tt}::NEG_{c.upper()}", V(unit(i, -1))) for i, c in enumerate(cs)]
    lines += [f"let [{', '.join('a' + c for c in cs)}] = {Tt}::AXES;"]
    lines += [eq(f"a{c}", f"{Tt}::{c.upper()}") for c in cs]
    test("test_consts", lines)
    test("test_splat_with", [
        eq(f"{Tt}::splat(7)", V([7] * 4)), eq(f"{Tt}::splat({t.smin})", f"{Tt}::MIN"),
        *[eq(f"{V(one)}.with_{c}(9)", V([9 if j == i else one[j] for j in range(4)]))
          for i, c in enumerate(cs)]])
    test("test_accessors", [
        f"let mut a = {Tt}::ZERO;",
        *[f"a.{c} = {one[i]};" for i, c in enumerate(cs)],
        eq("a", V(one)),
        *[eq(f"a[{i}]", one[i]) for i in range(n)],
    ])
    panic("test_index_out_of_bounds", f"'{T}: index out of bounds'",
          [f"let _ = {V(one)}[{n}];"])
    lines = []
    if n < 4:
        lines.append(eq(f"{V(one)}.extend({one[n]})", V(one, t.dim(n + 1))))
    if n > 2:
        lines.append(eq(f"{V(one)}.truncate()", V(one, t.dim(n - 1))))
    if n == 3:
        lines += [f"let v: {T} = ({V(one, t.dim(2))}, 3_{S}).into();", eq("v", V(one))]
    if n == 4:
        lines += [f"let v: {T} = ({V(one, t.dim(3))}, 4_{S}).into();", eq("v", V(one)),
                  f"let v: {T} = (1_{S}, {V([2, 3, 4], t.dim(3))}).into();", eq("v", V(one)),
                  f"let v: {T} = ({V(one, t.dim(2))}, 3_{S}, 4_{S}).into();", eq("v", V(one)),
                  f"let v: {T} = ({V(one, t.dim(2))}, {V([3, 4], t.dim(2))}).into();",
                  eq("v", V(one))]
    test("test_extend_truncate", lines)
    a, b = [1, 2, 3, 4], [5, 6, 7, 8]
    table("select", [("m", "b"), ("a", "v"), ("b", "v"), ("e", "v")],
          [{"m": [(m >> i) & 1 for i in range(4)], "a": a, "b": b,
            "e": [a[i] if (m >> i) & 1 else b[i] for i in range(4)]} for m in MASKS[n]],
          lambda c: [eq(f"{Tt}::select({c['m']}, {c['a']}, {c['b']})", c["e"])])
    test("test_from_bvec", [f"let v: {T} = {Bm([1, 0, 1, 0])}.into();", eq("v", V([1, 0, 1, 0])),
                            f"let v: {T} = {Bm([0, 1, 0, 1])}.into();", eq("v", V([0, 1, 0, 1]))])

    # dot / length / cross (glam: test_dot_unsigned, test_length_squared_unsigned, test_cross)
    rows = []
    for x, y in small_pairs(t):
        d = sum(x[i] * y[i] for i in range(n))
        rows.append({"x": x, "y": y, "d": d, "l": sum(x[i] * x[i] for i in range(n)),
                     "q": sum((x[i] - y[i])**2 for i in range(n))})
    table("dot_length", [("x", "v"), ("y", "v"), ("d", "s"), ("l", "s")] + ([("q", "s")] if s else []),
          rows,
          lambda c: [eq(f"{c['x']}.dot({c['y']})", c["d"]),
                     eq(f"{c['x']}.dot_into_vec({c['y']})", f"{Tt}::splat({c['d']})"),
                     eq(f"{c['x']}.length_squared()", c["l"]),
                     *([eq(f"{c['x']}.distance_squared({c['y']})", c["q"])] if s else [])])
    if n == 3:
        cross = lambda a, b: [a[1] * b[2] - b[1] * a[2], a[2] * b[0] - b[2] * a[0],
                              a[0] * b[1] - b[0] * a[1], 0]
        cases = small_pairs(t) + [([46340, 0, 0, 0], [0, 46340, 1, 0])] if s else \
            [([3, 0, 0, 0], [2, 5, 0, 0]), ([0, 4, 0, 0], [0, 0, 6, 0]),
             ([0, 0, 5, 0], [7, 0, 0, 0]), ([5, 7, 0, 0], [5, 7, 0, 0]),
             ([1, 2, 3, 0], [1, 2, 3, 0])]
        assert all(k >= 0 for x, y in cases for k in cross(x, y)[:3]) or s
        table("cross", [("x", "v"), ("y", "v"), ("e", "v")],
              [{"x": x, "y": y, "e": cross(x, y)} for x, y in cases],
              lambda c: [eq(f"{c['x']}.cross({c['y']})", c["e"])])
        lines = [eq(f"{Tt}::X.dot({Tt}::X)", 1), eq(f"{Tt}::X.dot({Tt}::Y)", 0),
                 eq(f"{Tt}::X.cross({Tt}::Y)", f"{Tt}::Z"),
                 eq(f"{Tt}::Y.cross({Tt}::Z)", f"{Tt}::X"),
                 eq(f"{Tt}::Z.cross({Tt}::X)", f"{Tt}::Y")]
        if s:
            lines += [eq(f"{Tt}::Y.cross({Tt}::X)", f"{Tt}::NEG_Z")]
        test("test_dot_cross_axes", lines)
    else:
        test("test_dot_axes", [eq(f"{Tt}::X.dot({Tt}::X)", 1), eq(f"{Tt}::X.dot({Tt}::Y)", 0)])
    if s and n == 2:
        table("perp_rotate", [("x", "v"), ("y", "v"), ("p", "v"), ("pd", "s"), ("r", "v")],
              [{"x": x, "y": y, "p": [-x[1], x[0]], "pd": x[0] * y[1] - x[1] * y[0],
                "r": [x[0] * y[0] - x[1] * y[1], x[1] * y[0] + x[0] * y[1]]}
               for x, y in small_pairs(t)],
              lambda c: [eq(f"{c['x']}.perp()", c["p"]), eq(f"{c['x']}.perp_dot({c['y']})", c["pd"]),
                         eq(f"{c['x']}.rotate({c['y']})", c["r"])])
        test("test_perp_axes", [
            eq(f"{Tt}::X.perp()", f"{Tt}::Y"), eq(f"{Tt}::Y.perp()", f"{Tt}::NEG_X"),
            eq(f"{Tt}::Y.rotate({Tt}::X)", f"{Tt}::Y"),
            eq(f"{Tt}::NEG_X.rotate({V([3, 4])})", V([-3, -4]))])

    # test_ops: vector and scalar operators
    rows = []
    for x, y in small_pairs(t):
        if not s:
            x, y = [max(x[i], y[i]) for i in range(4)], [min(x[i], y[i]) or 1 for i in range(4)]
        k = y[0] if s else min(x[:n])
        r = {"x": x, "y": y, "k": k,
             "add": cw(lambda p, q: p + q, x, y), "sub": cw(lambda p, q: p - q, x, y),
             "mul": cw(lambda p, q: p * q, x, y), "div": cw(tdiv, x, y), "rem": cw(trem, x, y),
             "adds": cw(lambda p: p + k, x), "subs": cw(lambda p: p - k, x),
             "muls": cw(lambda p: p * k, x), "divs": cw(lambda p: tdiv(p, k), x),
             "rems": cw(lambda p: trem(p, k), x)}
        assert all(fits(t, e) for key in ("add", "sub", "mul", "adds", "subs", "muls")
                   for e in r[key]), (x, y)
        rows.append(r)
    ops = [("+", "add"), ("-", "sub"), ("*", "mul"), ("/", "div"), ("%", "rem")]
    table("ops", [("x", "v"), ("y", "v"), ("k", "s")] + [(m, "v") for _, m in ops]
          + [(m + "s", "v") for _, m in ops],
          rows,
          lambda c: [eq(f"{c['x']} {sym} {c['y']}", c[m]) for sym, m in ops]
          + [eq(f"{c['x']}.{m}_scalar({c['k']})", c[m + "s"]) for _, m in ops])
    f_ops = [("+", lambda p, q: p + q), ("-", lambda p, q: p - q), ("*", lambda p, q: p * q),
             ("/", tdiv), ("%", trem)]
    cases = [([20, 40, 80, 160], [2, 3, 7, 9]),
             ([-20, 40, -80, 160], [3, -3, 7, -9]) if s else ([1000, 7, 65535, 42], [10, 7, 3, 42])]
    rows = []
    for x, y in cases:
        r = {"x": x, "y": y}
        for i, (sym, f) in enumerate(f_ops):
            r[f"v{i}"] = cw(f, x, y)
            r[f"s{i}"] = cw(lambda p: f(p, 3), x)
        rows.append(r)
    table("assign_ops", [("x", "v"), ("y", "v")] + [(f"v{i}", "v") for i in range(5)]
          + [(f"s{i}", "v") for i in range(5)],
          rows,
          lambda c: [l for i, (sym, _) in enumerate(f_ops) for l in (
              f"let mut a = {c['x']};", f"a {sym}= {c['y']};", eq("a", c[f"v{i}"]),
              f"let mut a = {c['x']};", f"a {sym}= 3;", eq("a", c[f"s{i}"]))])

    # min / max / clamp / reductions
    rows = [{"x": x, "y": y, "lo": cw(min, x, y), "hi": cw(max, x, y)} for x, y in pairs(t)]
    table("min_max", [("x", "v"), ("y", "v"), ("lo", "v"), ("hi", "v")], rows,
          lambda c: [eq(f"{c['x']}.min({c['y']})", c["lo"]), eq(f"{c['y']}.min({c['x']})", c["lo"]),
                     eq(f"{c['x']}.max({c['y']})", c["hi"]), eq(f"{c['y']}.max({c['x']})", c["hi"])])
    argmin = lambda v: min(range(n), key=lambda i: (v[i], i))
    argmax = lambda v: min(range(n), key=lambda i: (-v[i], i))
    glam_pos = {2: [[1, 2], [1, 1], [2, 1]],
                3: [[1, 2, 3], [1, 1, 1], [3, 2, 1], [1, 2, 1], [1, 0, 1]],
                4: [[1, 2, 3, 4], [1, 1, 1, 1], [4, 3, 2, 1], [1, 2, 1, 2], [1, 0, 1, 0],
                    [2, 2, 1, 1], [3, 3, 3, 4]]}[n]
    rows = []
    for v in glam_pos + [x[:n] for x, _ in pairs(t)[:3]]:
        v = list(v) + [0] * (4 - len(v))
        rows.append({"v": v, "amin": argmin(v), "amax": argmax(v), "emin": min(v[:n]),
                     "emax": max(v[:n])})
    table("min_max_position_element",
          [("v", "v"), ("amin", "us"), ("amax", "us"), ("emin", "s"), ("emax", "s")], rows,
          lambda c: [eq(f"{c['v']}.min_position()", c["amin"]),
                     eq(f"{c['v']}.max_position()", c["amax"]),
                     eq(f"{c['v']}.min_element()", c["emin"]),
                     eq(f"{c['v']}.max_element()", c["emax"])])
    lo, hi = [1, 3, 3, 2], [6, 8, 8, 9]
    clamp = lambda v, l, h: [min(max(v[i], l[i]), h[i]) for i in range(4)]
    rows = [{"v": [k] * 4, "lo": lo, "hi": hi, "e": clamp([k] * 4, lo, hi)} for k in (0, 5, 9)]
    rows += [{"v": [0, 4, 7, 10], "lo": lo, "hi": hi, "e": clamp([0, 4, 7, 10], lo, hi)},
             {"v": [t.smin] * 4, "lo": lo, "hi": hi, "e": lo},
             {"v": [t.smax] * 4, "lo": lo, "hi": hi, "e": hi},
             {"v": lo, "lo": [t.smin] * 4, "hi": [t.smax] * 4, "e": lo}]
    table("clamp", [("v", "v"), ("lo", "v"), ("hi", "v"), ("e", "v")], rows,
          lambda c: [eq(f"{c['v']}.clamp({c['lo']}, {c['hi']})", c["e"])])
    rows = []
    for x in [one] + [x for x, _ in small_pairs(t)[:4]] + [[-1, -1, -1, -1] if s else [2] * 4]:
        p = 1
        for k in x[:n]:
            p *= k
        if not (fits(t, p) and fits(t, sum(x[:n]))):
            continue
        rows.append({"v": x, "sum": sum(x[:n]), "prod": p})
    table("sum_product", [("v", "v"), ("sum", "s"), ("prod", "s")], rows,
          lambda c: [eq(f"{c['v']}.element_sum()", c["sum"]),
                     eq(f"{c['v']}.element_product()", c["prod"])])

    # comparisons
    cmps = [("cmpeq", lambda p, q: p == q), ("cmpne", lambda p, q: p != q),
            ("cmpge", lambda p, q: p >= q), ("cmpgt", lambda p, q: p > q),
            ("cmple", lambda p, q: p <= q), ("cmplt", lambda p, q: p < q)]
    table("cmp", [("x", "v"), ("y", "v")] + [(f, "b") for f, _ in cmps],
          [{"x": x, "y": y, **{f: cw(op, x, y) for f, op in cmps}} for x, y in pairs(t)],
          lambda c: [eq(f"{c['x']}.{f}({c['y']})", c[f]) for f, _ in cmps])
    test("test_cmp_all_any", [
        f"let a = {V([1] * 4)};", f"let b = {V([2] * 4)};",
        "assert!(a.cmplt(b).all() && a.cmple(b).all() && b.cmpgt(a).all() && b.cmpge(a).all());",
        "assert!(a.cmpne(b).all() && a.cmpeq(a).all() && !a.cmpeq(b).any() && !a.cmplt(a).any());",
        "assert!(a == a && a != b);"])

    # ------------------------------------------------------------------------------- signed
    if s:
        test("test_neg", [
            eq(f"-{V(one)}", V([-k for k in one])), eq(f"-{Tt}::ZERO", f"{Tt}::ZERO"),
            eq(f"-{Tt}::MAX", V([-MAX] * 4)), eq(f"-{Tt}::ONE", f"{Tt}::NEG_ONE")])
        rows = []
        for m in MASKS[n]:
            v = [-(i + 1) if (m >> i) & 1 else i + 1 for i in range(4)]
            rows.append({"v": v, "bm": m, "mask": [(m >> i) & 1 for i in range(4)]})
        table("is_negative", [("v", "v"), ("bm", "u"), ("mask", "b")], rows,
              lambda c: [eq(f"{c['v']}.is_negative_bitmask()", c["bm"]),
                         eq(f"{c['v']}.is_negative_mask()", c["mask"])])
        sg = lambda p: (p > 0) - (p < 0)
        rows = [{"v": v, "abs": cw(abs, v), "sig": cw(sg, v)}
                for v in ([0, 1, -1, 2], [MAX, MIN + 1, 65536, -65536], [-7, 5, -46341, 46340],
                          [MIN + 1, MAX - 1, 2, -3])]
        table("abs_signum", [("v", "v"), ("abs", "v"), ("sig", "v")], rows,
              lambda c: [eq(f"{c['v']}.abs()", c["abs"]), eq(f"{c['v']}.signum()", c["sig"])])
        test("test_signum_extremes", [
            eq(f"{Tt}::MIN.signum()", f"{Tt}::NEG_ONE"), eq(f"{Tt}::MAX.signum()", f"{Tt}::ONE"),
            eq(f"{Tt}::NEG_ONE.abs()", f"{Tt}::ONE")])

    # ------------------------------------------------- truncated / euclidean division (glam:
    # test_div_euclid / test_rem_euclid, then the pool with a non-zero divisor, then extremes)
    def safe(x, y):
        y = nz(y)
        return [-2 if (x[i] == MIN and y[i] == -1) else y[i] for i in range(4)]

    cases = []
    if s:
        cases += [([3, -3, 3, -3], [2, 2, -2, -2]), ([4, -4, 4, -4], [3, 3, -3, -3])]
    cases += [(x, safe(x, y)) for x, y in pairs(t)[:4 if s else 6]]
    cases += [([MIN, MAX, MAX, MIN], [MIN, MIN, MAX, 1]) if s else
              ([UMAX, UMAX, 0, 1], [UMAX, 1, UMAX, UMAX]),
              ([MAX, MIN + 1, 5, -MAX], [-2, MAX, -MAX, 7]) if s else
              ([UMAX, 2**31, 5, 7], [2, 3, 7, 5])]
    rows = [{"x": x, "y": y, "q": cw(tdiv, x, y), "r": cw(trem, x, y),
             "qe": cw(div_euclid, x, y) if s else None,
             "re": cw(rem_euclid, x, y) if s else None} for x, y in cases]
    table("div_rem", [("x", "v"), ("y", "v"), ("q", "v"), ("r", "v")]
          + ([("qe", "v"), ("re", "v")] if s else []), rows,
          lambda c: [eq(f"{c['x']} / {c['y']}", c["q"]), eq(f"{c['x']} % {c['y']}", c["r"]),
                     eq(f"{c['x']}.wrapping_div({c['y']})", c["q"]),
                     eq(f"{c['x']}.saturating_div({c['y']})", c["q"]),
                     eq(f"{c['x']}.checked_div({c['y']})", some(c["q"])),
                     *([eq(f"{c['x']}.div_euclid({c['y']})", c["qe"]),
                        eq(f"{c['x']}.rem_euclid({c['y']})", c["re"])] if s else [])])
    rows = []
    for i, (x, y) in enumerate(pairs(t)):
        y = list(y)
        if i in (1, 6):
            y[i % n] = 0
        bad = any(y[j] == 0 or (x[j] == MIN and y[j] == -1 and s) for j in range(n))
        rows.append({"x": x, "y": y,
                     "e": None if bad else cw(tdiv, x, [k if j < n else 1 for j, k in enumerate(y)])})
    table("checked_div", [("x", "v"), ("y", "v"), ("e", "opt")], rows,
          lambda c: [eq(f"{c['x']}.checked_div({c['y']})", c["e"])])
    if s:
        test("test_div_extremes", [
            eq(f"{Tt}::MIN.wrapping_div({Tt}::NEG_ONE)", f"{Tt}::MIN"),
            eq(f"{Tt}::MIN.saturating_div({Tt}::NEG_ONE)", f"{Tt}::MAX"),
            eq(f"{Tt}::MAX.checked_div({Tt}::NEG_ONE)", some(V([-MAX] * 4))),
            eq(f"{Tt}::MIN.rem_euclid({Tt}::NEG_ONE)", f"{Tt}::ZERO")])

    # --------------------------------------------------- checked / wrapping / saturating
    fops = [("add", lambda p, q: p + q), ("sub", lambda p, q: p - q),
            ("mul", lambda p, q: p * q)]
    cases = list(pairs(t))
    rows = []
    for x, y in cases:
        r = {"x": x, "y": y}
        for op, f in fops:
            exact = cw(f, x, y)
            r["w" + op] = [wrap(t, k) for k in exact]
            r["s" + op] = [sat(t, k) for k in exact]
            r["c" + op] = exact if all(fits(t, k) for k in exact) else None
        rows.append(r)
    kinds = [("w", "wrapping", "v"), ("s", "saturating", "v"), ("c", "checked", "opt")]
    table("wrapping_saturating_checked", [("x", "v"), ("y", "v")]
          + [(p + op, k) for op, _ in fops for p, _, k in kinds], rows,
          lambda c: [eq(f"{c['x']}.{name}_{op}({c['y']})", c[p + op])
                     for op, _ in fops for p, name, _ in kinds])

    # mixed signedness
    mixed, sfx = ([("add", 1), ("sub", -1)], "unsigned") if s else ([("add", 1)], "signed")
    cases = [(x, pairs(o)[(i + 3) % 8][1]) for i, (x, _) in enumerate(pairs(t))]
    # glam: MAX + 1 and MIN - 1 wrap, saturate and fail the checked form
    cases[7] = ([t.smax, t.smin, 0, t.smin], [1, 1, 1, UMAX] if s else [1, -1, -1, MIN])
    rows = []
    for x, y in cases:
        r = {"x": x, "y": y}
        for op, sign in mixed:
            exact = cw(lambda p, q: p + sign * q, x, y)
            r["w" + op] = [wrap(t, k) for k in exact]
            r["s" + op] = [sat(t, k) for k in exact]
            r["c" + op] = exact if all(fits(t, k) for k in exact) else None
        rows.append(r)
    table(f"{sfx}_ops", [("x", "v"), ("y", "o")]
          + [(p + op, k) for op, _ in mixed for p, _, k in kinds], rows,
          lambda c: [eq(f"{c['x']}.{name}_{op}_{sfx}({c['y']})", c[p + op])
                     for op, _ in mixed for p, name, _ in kinds])

    # distances
    cases = list(pairs(t)) + [([3, 27, 98, 5], [20, 65, 97, 9])]
    if s:
        cases += [([-23, 2, -99, 4], [22, -12, 24, -4])]
    rows = []
    for x, y in cases:
        d = [abs(x[i] - y[i]) for i in range(n)]
        rows.append({"x": x, "y": y, "man": sum(d) if sum(d) <= UMAX else None, "cheb": max(d)})
    table("distances", [("x", "v"), ("y", "v"), ("man", "optu"), ("cheb", "u")], rows,
          lambda c: [eq(f"{c['x']}.checked_manhattan_distance({c['y']})", c["man"]),
                     f"if let Some(d) = {c['man']} {{",
                     f"    assert_eq!({c['x']}.manhattan_distance({c['y']}), d);", "}",
                     eq(f"{c['x']}.chebyshev_distance({c['y']})", c["cheb"])])

    # casts
    rows = []
    for x, _ in pairs(t):
        ok = all(fits(o, k) for k in x[:n])
        rows.append({"x": x, "xo": [wrap(o, k) for k in x], "ok": x if ok else None})
    table("casts", [("x", "v"), ("xo", "o"), ("ok", "opto")], rows,
          lambda c: [eq(f"{c['x']}.as_{o.mod}()", c["xo"]), eq(f"{c['xo']}.as_{t.mod}()", c["x"]),
                     f"let res: Option<{o.name}> = {c['x']}.try_into();",
                     eq("res", c["ok"])])

    # bit operators and shifts
    bits = [("&", lambda p, q: p & q), ("|", lambda p, q: p | q), ("^", lambda p, q: p ^ q)]
    table("bit_ops", [("x", "v"), ("y", "v")] + [(f"b{i}", "v") for i in range(4)],
          [{"x": x, "y": y, **{f"b{i}": cw(lambda p, q: wrap(t, f(p, q)), x, y)
                               for i, (_, f) in enumerate(bits)},
            "b3": cw(lambda p: wrap(t, ~p), x)} for x, y in pairs(t)],
          lambda c: [eq(f"{c['x']} {sym} {c['y']}", c[f"b{i}"]) for i, (sym, _) in enumerate(bits)]
          + [eq(f"~{c['x']}", c["b3"])])
    table("shifts", [("x", "v"), ("k", "u"), ("l", "v"), ("r", "v")],
          [{"x": x, "k": k, "l": cw(lambda p: wrap(t, p << k), x), "r": cw(lambda p: p >> k, x)}
           for (x, _), k in zip(pairs(t), [0, 1, 2, 5, 15, 16, 30, 31])],
          lambda c: [eq(f"{c['x']}.shl({c['k']})", c["l"]), eq(f"{c['x']}.shr({c['k']})", c["r"])])

    # derives
    test("test_hash_serde", [
        f"let a = {V(one)};", f"let b = {V(list(reversed(one[:n])) + [0] * 4)};",
        "assert_eq!(hash(a), hash(a));", "assert!(hash(a) != hash(b));",
        "let mut out = array![];", "a.serialize(ref out);",
        eq("out.len()", n), "let mut span = out.span();",
        eq(f"Serde::<{T}>::deserialize(ref span)", "Some(a)"),
    ])

    # ------------------------------------------------------------------------------ panics
    sp = lambda name, msg, expr: panic(name, msg, [f"let _ = {expr};"])
    add_msg = f"'{S}_add Overflow'"
    sp("test_add_overflow", add_msg, f"{Tt}::MAX + {Tt}::X")
    sp("test_add_scalar_overflow", add_msg, f"{Tt}::MAX.add_scalar(1)")
    if s:
        sp("test_add_underflow", "'i32_add Underflow'", f"{Tt}::MIN + {Tt}::NEG_X")
        sp("test_sub_underflow", "'i32_sub Underflow'", f"{Tt}::MIN - {Tt}::X")
        sp("test_sub_overflow", "'i32_sub Overflow'", f"{Tt}::MAX - {Tt}::NEG_X")
        sp("test_neg_overflow", "'i32_neg Underflow'", f"-{Tt}::MIN")
        sp("test_abs_overflow", "'i32_neg Underflow'", f"{Tt}::MIN.abs()")
        sp("test_div_overflow", "'attempt to divide with overflow'", f"{Tt}::MIN / {Tt}::NEG_ONE")
        sp("test_rem_overflow", "'attempt to divide with overflow'", f"{Tt}::MIN % {Tt}::NEG_ONE")
        sp("test_div_scalar_overflow", "'attempt to divide with overflow'",
           f"{Tt}::MIN.div_scalar(-1)")
        sp("test_div_euclid_overflow", "'attempt to divide with overflow'",
           f"{Tt}::MIN.div_euclid({Tt}::NEG_ONE)")
        sp("test_div_euclid_by_zero", "'Division by 0'", f"{Tt}::ONE.div_euclid({Tt}::X)")
        sp("test_rem_euclid_by_zero", "'Division by 0'", f"{Tt}::ONE.rem_euclid({Tt}::X)")
        sp("test_distance_squared_overflow", g.ovf(t),
           f"{Tt}::MAX.distance_squared({Tt}::MIN)")
        if n == 2:
            sp("test_perp_overflow", "'i32_neg Underflow'", f"{Tt}::MIN.perp()")
            sp("test_perp_dot_overflow", g.ovf(t), f"{V([MAX, 0])}.perp_dot({V([0, MAX])})")
            sp("test_rotate_overflow", g.ovf(t), f"{Tt}::MAX.rotate({Tt}::MIN)")
    else:
        sp("test_sub_overflow", "'u32_sub Overflow'", f"{Tt}::ZERO - {Tt}::X")
        sp("test_sub_scalar_overflow", "'u32_sub Overflow'", f"{Tt}::ZERO.sub_scalar(1)")
    sp("test_mul_overflow", f"'{S}_mul Overflow'", f"{Tt}::MAX * {V([2] * 4)}")
    sp("test_mul_scalar_overflow", f"'{S}_mul Overflow'", f"{Tt}::MAX.mul_scalar(2)")
    sp("test_div_by_zero", "'Division by 0'", f"{Tt}::ONE / {Tt}::X")
    sp("test_rem_by_zero", "'Division by 0'", f"{Tt}::ONE % {Tt}::X")
    sp("test_div_scalar_by_zero", "'Division by 0'", f"{Tt}::ONE.div_scalar(0)")
    sp("test_rem_scalar_by_zero", "'Division by 0'", f"{Tt}::ONE.rem_scalar(0)")
    sp("test_wrapping_div_by_zero", "'Division by 0'", f"{Tt}::ONE.wrapping_div({Tt}::X)")
    sp("test_saturating_div_by_zero", "'Division by 0'", f"{Tt}::ONE.saturating_div({Tt}::X)")
    sp("test_dot_overflow", g.ovf(t), f"{Tt}::MAX.dot({Tt}::MAX)")
    sp("test_dot_into_vec_overflow", g.ovf(t), f"{Tt}::MAX.dot_into_vec({Tt}::MAX)")
    sp("test_length_squared_overflow", g.ovf(t), f"{Tt}::MAX.length_squared()")
    sp("test_element_sum_overflow", g.ovf(t) if g.is_fused(t, "element_sum") else add_msg,
       f"{Tt}::MAX.element_sum()")
    sp("test_element_product_overflow",
       g.ovf(t) if g.is_fused(t, "element_product") else f"'{S}_mul Overflow'",
       f"{Tt}::MAX.element_product()")
    sp("test_manhattan_distance_overflow",
       g.ovf(t) if g.is_fused(t, "manhattan_distance") else "'u32_add Overflow'",
       f"{Tt}::MIN.manhattan_distance({Tt}::MAX)")
    if n == 3:
        sp("test_cross_overflow", g.ovf(t),
           f"{V([65536, 0, 0, 0])}.cross({V([0, 65536, 0, 0])})")
        if not s:
            sp("test_cross_negative", g.ovf(t), f"{Tt}::Y.cross({Tt}::X)")
    sp("test_shl_overflow", f"'{T}: shift overflow'", f"{Tt}::ONE.shl(32)")
    sp("test_shr_overflow", f"'{T}: shift overflow'", f"{Tt}::ONE.shr(32)")

    # the fused kernels only range-check the result
    lines = []
    if s:
        x, y = [MAX, MAX, 5, 5], [2, -2, 1, 1]
        lines.append(eq(f"{V(x)}.dot({V(y)})", sum(x[i] * y[i] for i in range(n))))
        if n >= 3:
            lines.append(eq(f"{V([MAX, 7, MIN, 1])}.element_sum()", sum([MAX, 7, MIN, 1][:n])))
            lines.append(eq(f"{V([MAX, 2, 0, 1])}.element_product()", 0))
    else:
        if n >= 3:
            lines.append(eq(f"{V([UMAX, 2, 0, 1])}.element_product()", 0))
    if lines:
        test("test_fused_kernels_check_the_result_only", lines)

    # -------------------------------------------------------------------------------- fuzz
    def fuzz(name, seed, args, lines):
        body = "\n".join("    " + l for l in lines)
        G.out.append(f"#[test]\n#[fuzzer(runs: 256, seed: {seed})]\nfn {name}({args}) {{\n"
                     f"{body}\n}}\n")

    rot = lambda names: [names[i % len(names)] for i in range(4)]
    seed = 1000 * n + (0 if s else 500)
    sc = ", ".join(f"{k}: {S}" for k in "abcd")
    va = V(rot(["a", "b"]))
    vb = V(rot(["c", "d", "a"]))
    la, lb = rot(["a", "b"])[:n], rot(["c", "d", "a"])[:n]
    mixed_fn = "add_unsigned" if s else "add_signed"
    fuzz("fuzz_wrapping_checked_saturating", seed + 1, sc, [
        f"let va = {va};", f"let vb = {vb};",
        *[l for op, sym in [("add", "+"), ("sub", "-"), ("mul", "*")] for l in (
            "let exact = [" + ", ".join(f"wide({p}) {sym} wide({q})" for p, q in zip(la, lb))
            + "];",
            f"assert_eq!(va.wrapping_{op}(vb).to_array(), map_wrap(exact));",
            f"assert_eq!(va.saturating_{op}(vb).to_array(), map_sat(exact));",
            f"assert_eq!(va.checked_{op}(vb), map_checked(exact));")],
        f"// mixed signedness: the other-signedness operand is `vb` reinterpreted",
        f"let ub = vb.as_{o.mod}();",
        f"let [{', '.join('u' + c for c in cs)}] = ub.to_array();",
        "let exact = [" + ", ".join(f"wide({p}) + wide_o(u{c})" for p, c in zip(la, cs)) + "];",
        f"assert_eq!(va.wrapping_{mixed_fn}(ub).to_array(), map_wrap(exact));",
        f"assert_eq!(va.saturating_{mixed_fn}(ub).to_array(), map_sat(exact));",
        f"assert_eq!(va.checked_{mixed_fn}(ub), map_checked(exact));",
        *([
            "let exact = [" + ", ".join(f"wide({p}) - wide_o(u{c})" for p, c in zip(la, cs))
            + "];",
            "assert_eq!(va.wrapping_sub_unsigned(ub).to_array(), map_wrap(exact));",
            "assert_eq!(va.saturating_sub_unsigned(ub).to_array(), map_sat(exact));",
            "assert_eq!(va.checked_sub_unsigned(ub), map_checked(exact));"] if s else []),
    ])
    fuzz("fuzz_min_max_clamp_select_cmp_distances", seed + 2, sc, [
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
        f"let vc = {V(rot(['d', 'a', 'c']))};",
        "assert_eq!(vc.clamp(lo, hi), vc.max(lo).min(hi));",
        "assert!(lo.min_element() <= lo.max_element());",
        "assert_eq!(va[va.min_position()], va.min_element());",
        "assert_eq!(va[va.max_position()], va.max_element());",
        "let d = [" + ", ".join(f"abs_wide(wide({p}) - wide({q}))" for p, q in zip(la, lb))
        + "];",
        f"let [{', '.join('d' + c for c in cs)}] = d;",
        f"let sum = {' + '.join('d' + c for c in cs)};",
        "let expected: Option<u32> = sum.try_into();",
        "assert_eq!(va.checked_manhattan_distance(vb), expected);",
        "assert_eq!(vb.checked_manhattan_distance(va), expected);",
        "let mut m = dx;",
        *[f"if d{c} > m {{ m = d{c}; }}" for c in cs[1:]],
        "assert_eq!(wide_u(va.chebyshev_distance(vb)), m);",
    ])
    small = lambda k: f"{k} / 0x40000"
    fuzz("fuzz_dot_casts_bits_shifts", seed + 4, sc + ", k: u32", [
        "// 14-bit operands: nothing overflows",
        f"let va = {V([small(k) for k in rot(['a', 'b'])])};",
        f"let vb = {V([small(k) for k in rot(['c', 'd', 'a'])])};",
        "let expected = " + " + ".join(f"wide({small(p)}) * wide({small(q)})"
                                       for p, q in zip(la, lb)) + ";",
        "assert_eq!(wide(va.dot(vb)), expected);",
        "assert_eq!(va.dot(vb), vb.dot(va));",
        "assert_eq!(va.length_squared(), va.dot(va));",
        "assert_eq!(wide(va.element_sum()), " + " + ".join(f"wide({small(p)})" for p in la) + ");",
        f"let tiny = {V([f'{k} / 0x1000000' for k in rot(['a', 'b'])])};",
        "assert_eq!(wide(tiny.element_product()), "
        + " * ".join(f"wide({p} / 0x1000000)" for p in la) + ");",
        *([f"assert_eq!(wide(va.distance_squared(vb)), "
           + " + ".join(f"(wide({small(p)}) - wide({small(q)})) * (wide({small(p)}) - "
                        f"wide({small(q)}))" for p, q in zip(la, lb)) + ");"] if s else []),
        *([f"let tb = {V([f'{k} / 0x1000000' for k in rot(['c', 'd', 'a'])])};",
           "let c = tiny.cross(tb);", "assert_eq!(c.dot(tiny), 0);", "assert_eq!(c.dot(tb), 0);",
           "assert_eq!(tb.cross(tiny), -c);"] if s and n == 3 else []),
        *(["assert_eq!(va.perp_dot(vb), va.perp().dot(vb));",
           "assert_eq!(va.rotate(vb), vb.rotate(va));"] if s and n == 2 else []),
        f"let va = {V(rot(['a', 'b']))};", f"let vb = {V(rot(['b', 'a', 'a']))};",
        f"assert_eq!(va.as_{o.mod}().as_{t.mod}(), va);",
        f"assert_eq!(wide_o(va.as_{o.mod}().x), wrap_o(wide(a)));",
        "// (a & b) + (a | b) == a + b and (a ^ b) + 2 * (a & b) == a + b",
        "assert_eq!(wide((va & vb).x) + wide((va | vb).x), wide(a) + wide(b));",
        "assert_eq!(wide((va ^ vb).x) + 2 * wide((va & vb).x), wide(a) + wide(b));",
        "assert_eq!((va ^ vb) ^ vb, va);", "assert_eq!(~(va & vb), ~va | ~vb);",
        "assert_eq!(wide((~va).x), -1 - wide(a)" + ("" if s else " + 0x100000000") + ");",
        "let k = k % 32;", "let p = pow2(k);",
        "assert_eq!(wide(va.shl(k).x), wrap(wide(a) * p));",
        "assert_eq!(wide(va.shr(k).x), floor_div(wide(a), p));",
    ])
    if s:
        fuzz("fuzz_div_euclid_rem_euclid_abs_signum", seed + 6, sc, [
            f"let va = {va};",
            f"let vb = {V([f'nz({k})' for k in rot(['c', 'd', 'a'])])};",
            f"if !({' || '.join(f'({p} == {MIN} && nz({q}) == -1)' for p, q in zip(la, lb))}) {{",
            "    let q = va.div_euclid(vb);", "    let r = va.rem_euclid(vb);",
            "    let tq = va / vb;", "    let tr = va % vb;",
            "    assert!(r.cmpge(" + Tt + "::ZERO).all());",
            f"    for i in 0..{n}_usize {{",
            "        assert!(wide(r[i]) < abs_wide(wide(vb[i])));",
            "        assert_eq!(wide(q[i]) * wide(vb[i]) + wide(r[i]), wide(va[i]));",
            "        assert_eq!(wide(tq[i]) * wide(vb[i]) + wide(tr[i]), wide(va[i]));",
            "        assert!(abs_wide(wide(tr[i])) < abs_wide(wide(vb[i])));",
            "        assert!(wide(tr[i]) == 0 || (tr[i] < 0) == (va[i] < 0));",
            "    }",
            "    assert_eq!(va.wrapping_div(vb), tq);",
            "}",
            f"let a = if a == {MIN} {{ 0 }} else {{ a }};",
            f"let b = if b == {MIN} {{ 0 }} else {{ b }};",
            f"let va = {V(rot(['a', 'b']))};",
            "assert_eq!(va.signum() * va.abs(), va);", "assert_eq!((-va).abs(), va.abs());",
            "assert_eq!(-(-va), va);", "assert!(va.abs().cmpge(" + Tt + "::ZERO).all());",
            f"assert_eq!(va.is_negative_mask(), va.cmplt({Tt}::ZERO));",
            "assert_eq!(va.is_negative_bitmask(), va.is_negative_mask().bitmask());",
        ])
    else:
        fuzz("fuzz_div_rem", seed + 6, sc, [
            f"let va = {va};",
            f"let vb = {V([f'nz({k})' for k in rot(['c', 'd', 'a'])])};",
            "let q = va / vb;", "let r = va % vb;", "assert!(r.cmplt(vb).all());",
            f"for i in 0..{n}_usize {{",
            "    assert_eq!(wide(q[i]) * wide(vb[i]) + wide(r[i]), wide(va[i]));", "}",
            "assert_eq!(va.wrapping_div(vb), q);", "assert_eq!(va.saturating_div(vb), q);",
            "assert_eq!(va.checked_div(vb), Some(q));",
        ])

    at = lambda i: "o" if i == 0 else f"o + {i}"
    arr = lambda f: "[" + ", ".join(f(c) for c in cs) + "]"
    lo_w, hi_w = (f"{MIN}", f"{MAX}") if s else ("0", f"{UMAX}")
    prelude = f"""{g.HEADER}//! Tests of `glam::{t.mod}`: the glam-rs integer vector test macros of `tests/vec{n}.rs`, tables over
//! a pool of edge values (expected values computed by the generator with Python integers, one
//! `const` table and one looping test per function group), seeded fuzz properties against the
//! `i128` reference below, and one test per panic path.

use core::hash::{{HashStateExTrait, HashStateTrait}};
use core::poseidon::PoseidonTrait;
use glam::{t.bmod}::{{{t.B}, {t.B}Trait, {t.bmod}}};
use glam::{t.mod}::{{{T}, {T}Trait, {t.mod}}};
use glam::{o.mod}::{{{o.name}, {o.name}Trait, {o.mod}}};
{"".join(f"use glam::{t.dim(k).mod}::{t.dim(k).mod};" + chr(10) for k in (2, 3, 4) if k != n and abs(k - n) <= (2 if n == 4 else 1))}
fn hash(v: {T}) -> felt252 {{
    PoseidonTrait::new().update_with(v).finalize()
}}

// Readers of the table rows (`[i64; W]`, one cell per scalar): the value of a column at an offset.

fn sc(r: Span<i64>, o: u32) -> {S} {{
    (*r[o]).try_into().unwrap()
}}

fn su(r: Span<i64>, o: u32) -> u32 {{
    (*r[o]).try_into().unwrap()
}}

fn us(r: Span<i64>, o: u32) -> usize {{
    (*r[o]).try_into().unwrap()
}}

fn vc(r: Span<i64>, o: u32) -> {T} {{
    {t.mod}({", ".join(f"sc(r, {at(i)})" for i in range(n))})
}}

fn vo(r: Span<i64>, o: u32) -> {o.name} {{
    {o.mod}({", ".join(f"(*r[{at(i)}]).try_into().unwrap()" for i in range(n))})
}}

fn bv(r: Span<i64>, o: u32) -> {t.B} {{
    {t.bmod}({", ".join(f"*r[{at(i)}] != 0" for i in range(n))})
}}

fn opt(r: Span<i64>, o: u32) -> Option<{T}> {{
    if *r[o] == 0 {{
        None
    }} else {{
        Some(vc(r, o + 1))
    }}
}}

fn opto(r: Span<i64>, o: u32) -> Option<{o.name}> {{
    if *r[o] == 0 {{
        None
    }} else {{
        Some(vo(r, o + 1))
    }}
}}

fn optu(r: Span<i64>, o: u32) -> Option<u32> {{
    if *r[o] == 0 {{
        None
    }} else {{
        Some(su(r, o + 1))
    }}
}}

// The reference of the fuzz tests: exact arithmetic in `i128`, reduced to `{S}` the way Rust does.

fn wide(v: {S}) -> i128 {{
    v.into()
}}

fn wide_o(v: {o.S}) -> i128 {{
    v.into()
}}

fn wide_u(v: u32) -> i128 {{
    v.into()
}}

fn abs_wide(v: i128) -> i128 {{
    if v < 0 {{
        -v
    }} else {{
        v
    }}
}}

/// Euclidean remainder of `v` by `2^32`.
fn low32(v: i128) -> i128 {{
    let m: i128 = 0x100000000;
    ((v % m) + m) % m
}}

/// Two's complement reduction to `{S}`.
fn wrap(v: i128) -> i128 {{
    let r = low32(v);
    {"if r >= 0x80000000 { r - 0x100000000 } else { r }" if s else "r"}
}}

/// Two's complement reduction to `{o.S}`.
fn wrap_o(v: i128) -> i128 {{
    let r = low32(v);
    {"r" if s else "if r >= 0x80000000 { r - 0x100000000 } else { r }"}
}}

fn sat(v: i128) -> i128 {{
    if v < {lo_w} {{
        {lo_w}
    }} else if v > {hi_w} {{
        {hi_w}
    }} else {{
        v
    }}
}}

fn narrow(v: i128) -> {S} {{
    v.try_into().unwrap()
}}

fn map_wrap(e: [i128; {n}]) -> [{S}; {n}] {{
    let [{', '.join(cs)}] = e;
    {arr(lambda c: f"narrow(wrap({c}))")}
}}

fn map_sat(e: [i128; {n}]) -> [{S}; {n}] {{
    let [{', '.join(cs)}] = e;
    {arr(lambda c: f"narrow(sat({c}))")}
}}

fn map_checked(e: [i128; {n}]) -> Option<{T}> {{
    let [{', '.join(cs)}] = e;
    if {' && '.join(f'sat({c}) == {c}' for c in cs)} {{
        Some({t.cw(lambda c: f"narrow({c})")})
    }} else {{
        None
    }}
}}

fn pow2(k: u32) -> i128 {{
    let mut p: i128 = 1;
    for _ in 0..k {{
        p *= 2;
    }}
    p
}}

/// `floor(a / p)` for `p > 0`.
fn floor_div(a: i128, p: i128) -> i128 {{
    let r = ((a % p) + p) % p;
    (a - r) / p
}}

/// A non-zero divisor.
fn nz(v: {S}) -> {S} {{
    if v == 0 {{
        3
    }} else {{
        v
    }}
}}

"""
    return prelude + "\n".join(G.out)
