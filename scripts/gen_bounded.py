#!/usr/bin/env python3
"""Generates the bounded-int plumbing of the `fixed` package.

  packages/fixed/src/internal/bounded.cairo   raw kernels on `i64`: every `BoundedInt` bound and
                                              every bias constant is computed here, none is typed
                                              by hand in Cairo
  packages/fixed/src/internal/acc.cairo       the public wide accumulator types `W1..W16`
                                              (Q64.64), `T1..T16` (Q96.96), their typed
                                              `add` / `sub` / `neg` / `mul` / `lift` / `narrow` /
                                              `sqrt` impls and the count-agnostic `Acc`
                                              (re-exported by `fixed::wide`)
  packages/benches/src/alt/fixed.cairo        the losing formulations (prototype rescale, floor
                                              division, flat sign split, ...) and the stable-API
                                              fallback of `mul` / `div`, benchmarked by
                                              `bench_fixed::alt_*` and `bench_wide::alt_*`

usage: scripts/gen_bounded.py [--check]
  --check   regenerate in memory and fail if the committed files differ

`core::internal::bounded_int` is an unstable corelib API: a wrong bound is a compiler panic at
Sierra specialisation time, not a diagnostic. This script is the single source of truth for the
bounds: the helper impls are emitted by the same calls that compute the result ranges, so they
cannot drift apart, and every kernel below is exercised by the test-suite.

Limits of the libfuncs (cairo 2.19.4) this layout is designed around:
  * `bounded_int_div_rem`: non-negative dividend, quotient < 2^128, divisor bound <= 2^128 and
    (divisor bound) * 2^128 < P.
  * `downcast`: source range at most 2^128 wide.
  * `bounded_int_constrain`: each side of the boundary at most 2^128 wide.
  * a helper `Result` type must be spelled `BoundedInt<lo, hi>` even when the range is the one of
    a native integer.
  * the corelib already implements negation (`MulHelper<_, UnitInt<-1>>`) for ranges whose bounds
    are native integer limits: redefining them is an ambiguity error.

The rescale ("narrow") does not use the bias-and-downcast formulation of the research prototype
(5 range checks, `mul` = 2 050 gas) but a cheaper one (4 range checks, `mul` = 1 680 gas):
    result = floor(x / 2^k) fits i64  <=>  0 <= (x + 2^(63+k)) * 2^(64-k) < 2^128
which is ONE `felt252 -> u128` conversion; the biased result is then `u128 div 2^64`. The static
bounds tracked by the accumulator types guarantee that the felt252 value never wraps.
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "packages" / "fixed" / "src" / "internal"

NW = 16  # widest Q64.64 accumulator: W16 = sum of 16 raw products
NT = 16  # widest Q96.96 accumulator: T16 = sum of 16 raw triple products

ONE = 1 << 32
PRIME = (1 << 251) + 17 * (1 << 192) + 1
OVERFLOW = "'Fixed: overflow'"
DIV_ZERO = "'Fixed: division by zero'"
SQRT_NEG = "'Fixed: sqrt negative'"


class Nat(tuple):
    """Range of a value held in a native integer type (spelled by its name in Cairo). Plain
    tuples are ranges of `BoundedInt` values: a libfunc result is always a `BoundedInt`, even when
    its range is the one of a native type."""

    def __new__(cls, lo, hi, name):
        self = super().__new__(cls, (lo, hi))
        self.name = name
        return self


I64 = Nat(-(1 << 63), (1 << 63) - 1, "i64")
I32 = Nat(-(1 << 31), (1 << 31) - 1, "i32")
U16 = Nat(0, (1 << 16) - 1, "u16")
U64 = Nat(0, (1 << 64) - 1, "u64")
U128 = Nat(0, (1 << 128) - 1, "u128")

# Magnitudes for which the corelib declares `NegFelt252` (its generic `MulMinus1` impl then exists).
CORE_NEG = {0, 1} | {(1 << b) - d for b in (7, 15, 31, 63, 127) for d in (0, 1, 2)}


def h(v):
    return ("-" if v < 0 else "") + hex(abs(v))


def tyr(r):
    if r[0] == r[1]:
        return f"UnitInt<{h(r[0])}>"
    return f"BoundedInt<{h(r[0])}, {h(r[1])}>"


def ty(r):
    return r.name if isinstance(r, Nat) else tyr(r)


def unit(v):
    return (v, v)


def within(r, outer):
    return outer[0] <= r[0] and r[1] <= outer[1]


IMPLS = {}


def _emit(trait, args, body):
    key = (trait, args)
    if key not in IMPLS:
        IMPLS[key] = f"pub impl H{len(IMPLS)} of {trait}<{args}> {{\n{body}\n}}"


class V:
    """A Cairo expression together with the exact range of its value."""

    def __init__(self, expr, rng):
        self.expr, self.rng = expr, rng

    def __str__(self):
        return self.expr

    def _const(self, op, c, rng):
        return V(f"bounded_int::{op}::<_, UnitInt<{h(c)}>>({self.expr}, {h(c)})", rng)

    def add(self, o):
        a, b = self.rng, (unit(o) if isinstance(o, int) else o.rng)
        r = (a[0] + b[0], a[1] + b[1])
        _emit("AddHelper", f"{ty(a)}, {ty(b)}", f"    type Result = {tyr(r)};")
        if isinstance(o, int):
            return self._const("add", o, r)
        return V(f"bounded_int::add({self.expr}, {o.expr})", r)

    def sub(self, o):
        a, b = self.rng, (unit(o) if isinstance(o, int) else o.rng)
        r = (a[0] - b[1], a[1] - b[0])
        _emit("SubHelper", f"{ty(a)}, {ty(b)}", f"    type Result = {tyr(r)};")
        if isinstance(o, int):
            return self._const("sub", o, r)
        return V(f"bounded_int::sub({self.expr}, {o.expr})", r)

    def mul(self, o):
        a, b = self.rng, (unit(o) if isinstance(o, int) else o.rng)
        c = [a[0] * b[0], a[0] * b[1], a[1] * b[0], a[1] * b[1]]
        r = (min(c), max(c))
        _emit("MulHelper", f"{ty(a)}, {ty(b)}", f"    type Result = {tyr(r)};")
        if isinstance(o, int):
            return self._const("mul", o, r)
        return V(f"bounded_int::mul({self.expr}, {o.expr})", r)

    def neg(self):
        a = self.rng
        r = (-a[1], -a[0])
        if not (abs(a[0]) in CORE_NEG and abs(a[1]) in CORE_NEG):
            _emit("MulHelper", f"{ty(a)}, UnitInt<-0x1>", f"    type Result = {tyr(r)};")
        return V(f"{self.expr}.negate()", r)

    def div_rem(self, o):
        """-> (quotient range, remainder range, expr). `o` is an int (constant divisor) or a V
        whose Cairo expression is a `NonZero<..>` value of the given range."""
        a, b = self.rng, (unit(o) if isinstance(o, int) else o.rng)
        assert a[0] >= 0 and b[0] >= 0, "div_rem needs a non-negative dividend and divisor"
        q = (a[0] // b[1], a[1] // max(b[0], 1))
        r = (0, b[1] - 1)
        assert q[1] < (1 << 128), "div_rem quotient must stay below 2^128"
        assert b[1] <= (1 << 128) and b[1] * (1 << 128) < PRIME, "div_rem divisor too large"
        _emit(
            "DivRemHelper",
            f"{ty(a)}, {ty(b)}",
            f"    type DivT = {tyr(q)};\n    type RemT = {tyr(r)};",
        )
        if isinstance(o, int):
            e = f"bounded_int::div_rem::<_, UnitInt<{h(o)}>>({self.expr}, {h(o)})"
        else:
            e = f"bounded_int::div_rem({self.expr}, {o.expr})"
        return q, r, e

    def up(self, target):
        assert within(self.rng, target), f"upcast {self.rng} -> {target}"
        return f"upcast({self.expr})"

    def down(self, target=I64):
        assert self.rng[1] - self.rng[0] + 1 <= (1 << 128), "downcast source wider than 2^128"
        return f"or_overflow(downcast({self.expr}))"

    def trim_max(self, target=None):
        """The value, or an overflow panic when it equals the upper bound of its range: an
        equality test (no range check), much cheaper than `downcast` when the overflow region is
        that single value."""
        a = self.rng
        t = (a[0], a[1] - 1)
        assert not isinstance(a, Nat) and (target is None or within(t, target))
        _emit("TrimMaxHelper", ty(a), f"    type Target = {tyr(t)};")
        return (
            f"match bounded_int::trim_max::<{tyr(a)}>({self.expr}) {{\n"
            f"    OptionRev::Some(v) => upcast(v),\n"
            f"    OptionRev::None => core::panic_with_const_felt252::<{OVERFLOW}>(),\n}}"
        )

    def felt(self):
        """Hands the value to a felt252 rescale (`narrow32` / `narrow64*` / `norm*`). Soundness of
        those: the biased and scaled value `(x + 2^127) * 2^32` must never wrap around P, so that
        an out-of-range (in particular a negative) value always fails the `u128` conversion."""
        assert (max(abs(self.rng[0]), abs(self.rng[1])) + (1 << 127)) * ONE < PRIME // 2
        return f"upcast({self.expr})"


def constrain0(r):
    """Declares `ConstrainHelper<r, 0>` when the corelib does not; -> (low range, high range)."""
    assert r[0] < 0 <= r[1] and -r[0] <= (1 << 128) and r[1] + 1 <= (1 << 128)
    lo, hi = (r[0], -1), (0, r[1])
    if not isinstance(r, Nat):
        _emit(
            "ConstrainHelper",
            f"{ty(r)}, 0",
            f"    type LowT = {tyr(lo)};\n    type HighT = {tyr(hi)};",
        )
    return lo, hi


FNS = []


def fn(doc, sig, body):
    doc = "\n".join(f"/// {line}".rstrip() for line in doc.strip().splitlines())
    FNS.append(f"{doc}\n#[inline(always)]\npub fn {sig} {{\n{body.rstrip()}\n}}")


PMAX, TMAX = 1 << 126, 1 << 189
BW = {n: (-n * PMAX, n * PMAX) for n in range(1, NW + 1)}  # symmetric hull of n products
BT = {n: (-n * TMAX, n * TMAX) for n in range(1, NT + 1)}  # symmetric hull of n triple products
ALIASES = [f"pub type BW{n} = {tyr(BW[n])};" for n in BW]
ALIASES += [f"pub type BT{n} = {tyr(BT[n])};" for n in BT]


# ------------------------------------------------------------------ rescale (felt252 based)
def narrow(name, shift, rounding, doc):
    off, scale = 1 << (63 + shift), 1 << (64 - shift)
    bias = off + ((1 << (shift - 1)) if rounding else 0)
    q, _, e = V("u", U128).div_rem(1 << 64)
    res = V("q", q).sub(1 << 63)
    assert tuple(res.rng) == tuple(I64)
    biased = f"(f + {h(bias)}) * {h(scale)}" if scale != 1 else f"f + {h(bias)}"
    fn(
        doc,
        f"{name}(f: felt252) -> i64",
        f"    let u: u128 = or_overflow(({biased}).try_into());\n"
        f"    let (q, _r) = {e};\n    {res.up(I64)}",
    )


narrow(
    "narrow32", 32, False,
    "`floor(f / 2^32)` of a Q64.64 accumulator held in a felt252 (`|f| << P`), range-checked into\n"
    "`i64` by a single `felt252 -> u128` conversion: the result fits iff\n"
    "`0 <= (f + 2^95) * 2^32 < 2^128`; the biased result is then the high 64 bits.",
)
narrow(
    "narrow64", 64, False,
    "`floor(f / 2^64)` of a Q96.96 accumulator held in a felt252 (`|f| << P`): the result fits\n"
    "`i64` iff `0 <= f + 2^127 < 2^128`.",
)
narrow(
    "narrow64_round", 64, True,
    "`floor(f / 2^64 + 1/2)` (round to nearest, ties toward +infinity) of a felt252 (`|f| << P`).",
)

# ------------------------------------------------------------------ accumulators
a, b, c, t, x = (V(name, I64) for name in "abctx")
p1 = a.mul(b)
fn(
    "Raw Q64.64 product of two raw Q32.32 values: one step, no range check.",
    "wide(a: i64, b: i64) -> BW1",
    f"    {p1.up(BW[1])}",
)
fn(
    "Lifts a raw Q32.32 value to the Q64.64 scale (`x * 2^32`, exact).",
    "lift(x: i64) -> BW1",
    f"    {x.mul(ONE).up(BW[1])}",
)
for n in BW:
    for m in BW:
        if n + m <= NW:
            assert V("", BW[n]).add(V("", BW[m])).rng == BW[n + m]
            assert V("", BW[n]).sub(V("", BW[m])).rng == BW[n + m]
    assert V("", BW[n]).neg().rng == BW[n]
    V("", BW[n]).felt()
for n in BT:
    assert V("", BW[n]).mul(V("", I64)).rng == BT[n]
    assert within(V("", BW[n]).mul(ONE).rng, BT[n])
    for m in BT:
        if n + m <= NT:
            assert V("", BT[n]).add(V("", BT[m])).rng == BT[n + m]
            assert V("", BT[n]).sub(V("", BT[m])).rng == BT[n + m]
    assert V("", BT[n]).neg().rng == BT[n]
    V("", BT[n]).felt()

# ------------------------------------------------------------------ square roots of accumulators
for n in (1, 2, 3):  # `constrain` needs each side of the boundary to be at most 2^128 wide
    lo, hi = constrain0(BW[n])
    fn(
        f"`floor(sqrt(x))` of a Q64.64 sum of {n} product(s): the integer square root of the raw\n"
        "sum is the raw Q32.32 result (no rescale).",
        f"sqrt_w{n}(x: BW{n}) -> i64",
        f"    match bounded_int::constrain::<BW{n}, 0>(x) {{\n"
        f"        Ok(_) => core::panic_with_const_felt252::<{SQRT_NEG}>(),\n"
        "        Err(v) => {\n"
        f"            let s: u128 = {V('v', hi).up(U128)};\n"
        "            let r: u64 = Sqrt::sqrt(s);\n"
        f"            or_overflow(downcast(r))\n        }},\n    }}",
    )
fn(
    "`floor(sqrt(f))` for a signed Q64.64 value held modulo P. Values above P/2 are the signed\n"
    "negative half of the field; non-negative values wider than `u128` cannot have a root that\n"
    "fits `Fixed`, so the conversion is also the final overflow check.",
    "sqrt_acc(f: felt252) -> i64",
    "    let canonical: u256 = f.into();\n"
    f"    if canonical > {h(PRIME // 2)} {{\n"
    f"        core::panic_with_const_felt252::<{SQRT_NEG}>();\n"
    "    }\n"
    "    let s: u128 = or_overflow(f.try_into());\n"
    "    let r: u64 = Sqrt::sqrt(s);\n"
    "    or_overflow(downcast(r))",
)
fn(
    "Integer square root of a sum of raw squares held in a felt252. The sum is known to be\n"
    "non-negative, which the type system cannot see: one checked `felt252 -> u128` conversion\n"
    "(it fails only for a sum >= 2^128, whose root does not fit the scalar range anyway).",
    "norm_u64(f: felt252) -> u64",
    "    let s: u128 = or_overflow(f.try_into());\n    Sqrt::sqrt(s)",
)
assert 3 * PMAX < (1 << 128)
fn(
    "Same as `norm_u64` for a sum of at most 3 squares of `i64` values: `3 * 2^126 < 2^128`, the\n"
    "conversion cannot fail and only converts the type. Its (unreachable) failure branch\n"
    "deliberately differs from `'Fixed: overflow'`: two identical panic sites in a row cost the\n"
    "success path 200 gas (measured on `norm3`: 4 720 -> 4 520).",
    "norm_u64_le3(f: felt252) -> u64",
    "    let s: u128 = f.try_into().unwrap();\n    Sqrt::sqrt(s)",
)
fn(
    "`norm_u64_le3`, range-checked into `i64`.",
    "norm_le3(f: felt252) -> i64",
    "    norm_to_i64(norm_u64_le3(f))",
)
fn(
    "Range-checks an unsigned raw length into `i64`.",
    "norm_to_i64(len: u64) -> i64",
    f"    or_overflow(downcast(len))",
)
fn(
    "Same as `norm_u64`, range-checked into `i64`.",
    "norm(f: felt252) -> i64",
    "    norm_to_i64(norm_u64(f))",
)

# ------------------------------------------------------------------ distances
# (a - b) is exact on 65 bits, its square on 130 bits: sums of 2, 3, 4 squared differences.
def _dsq(i):
    d = V(f"a{i}", I64).sub(V(f"b{i}", I64))
    return V(f"d{i}", d.rng), f"    let d{i} = {d};\n"


for n in (2, 3, 4):
    lets, total = "", None
    for i in range(n):
        dv, let = _dsq(i)
        lets += let
        sq = dv.mul(dv)
        total = sq if total is None else total.add(sq)
    args = ", ".join(f"a{i}: i64, b{i}: i64" for i in range(n))
    fn(
        f"Sum of the {n} squared differences `(a_i - b_i)^2` at the Q64.64 scale, as a felt252.\n"
        "Exact: the differences are computed on 65 bits and cannot overflow.",
        f"dist_sq{n}({args}) -> felt252",
        f"{lets}    {total.felt()}",
    )

# ------------------------------------------------------------------ scalar: mul family
fn("`floor(a * b / 2^32)`.", "mul(a: i64, b: i64) -> i64", f"    narrow32({p1.felt()})")
fn(
    "`floor((a * b + c * 2^32) / 2^32)`: fused multiply-add, one rescale.",
    "mul_add(a: i64, b: i64, c: i64) -> i64",
    f"    narrow32({p1.add(c.mul(ONE)).felt()})",
)
fn(
    "`floor((a * 2^32 + (b - a) * t) / 2^32)`: `b - a` is exact (65 bits), one rescale.",
    "lerp(a: i64, b: i64, t: i64) -> i64",
    f"    narrow32({a.mul(ONE).add(b.sub(a).mul(t)).felt()})",
)
k = t.mul(-2).add(3 * ONE)
fn(
    "`floor(t^2 * (3 - 2 t))` evaluated exactly at the Q96.96 scale, one rescale.",
    "smooth(t: i64) -> i64",
    f"    let k = {k};\n    narrow64({t.mul(t).mul(V('k', k.rng)).felt()})",
)
fn(
    "`floor(a * b * c / 2^64)`: exact triple product, one rescale.",
    "mul3(a: i64, b: i64, c: i64) -> i64",
    f"    narrow64({p1.mul(c).felt()})",
)

# ------------------------------------------------------------------ scalar: integers, rounding
fn("`v * 2^32`: always fits.", "from_int(v: i32) -> i64", f"    {V('v', I32).mul(ONE).up(I64)}")
fn(
    "`v * 2^32` for an unsigned 16-bit integer: always fits.",
    "from_u16(v: u16) -> i64",
    f"    {V('v', U16).mul(ONE).up(I64)}",
)
biased = x.add(1 << 63)
bq, br, be = V("biased", biased.rng).div_rem(ONE)
bi = V("q", bq).sub(1 << 31)
assert tuple(bi.rng) == tuple(I32)
PRE = f"    let biased = {biased};\n"
fn(
    "`floor(x / 2^32)` as an integer.",
    "to_int_floor(x: i64) -> i32",
    f"{PRE}    let (q, _r) = {be};\n    {bi.up(I32)}",
)
fn(
    "Largest multiple of 2^32 that is `<= x`: never leaves the `i64` range.",
    "floor(x: i64) -> i64",
    f"{PRE}    let (q, _r) = {be};\n    {bi.mul(ONE).up(I64)}",
)
fn(
    "`x - floor(x)`, in `[0, 2^32)`.",
    "fract_floor(x: i64) -> i64",
    f"{PRE}    let (_q, r) = {be};\n    {V('r', br).up(I64)}",
)
cb = x.add((1 << 63) + ONE - 1)  # ceil(x) = floor(x + 2^32 - 1)
cq, _, ce = V("biased", cb.rng).div_rem(ONE)
fn(
    "Smallest multiple of 2^32 that is `>= x`; overflows above `2^31 - 1`.",
    "ceil(x: i64) -> i64",
    f"    let biased = {cb};\n    let (q, _r) = {ce};\n"
    f"    let i: i32 = {V('q', cq).sub(1 << 31).trim_max(I32)};\n    {V('i', I32).mul(ONE).up(I64)}",
)
NEG, POS = constrain0(I64)  # [-2^63, -1], [0, 2^63 - 1]
n_, p_ = V("n", NEG), V("p", POS)
m_ = V("m", n_.neg().rng)  # [1, 2^63]


def sign_split(neg_body, pos_body):
    return (
        "    match bounded_int::constrain::<i64, 0>(x) {\n"
        f"        Ok(n) => {{\n            let m = {n_.neg()};\n{neg_body}        }},\n"
        f"        Err(p) => {{\n{pos_body}        }},\n    }}"
    )


pq, pr, pe = p_.div_rem(ONE)
mq, mr, me = m_.div_rem(ONE)
fn(
    "Rounds toward zero to a multiple of 2^32: never leaves the `i64` range.",
    "trunc(x: i64) -> i64",
    sign_split(
        f"            let (q, _r) = {me};\n            {V('q', mq).mul(ONE).neg().up(I64)}\n",
        f"            let (q, _r) = {pe};\n            {V('q', pq).mul(ONE).up(I64)}\n",
    ),
)
fn(
    "`x - trunc(x)`: in `(-2^32, 2^32)`, with the sign of `x`.",
    "fract_trunc(x: i64) -> i64",
    sign_split(
        f"            let (_q, r) = {me};\n            {V('r', mr).neg().up(I64)}\n",
        f"            let (_q, r) = {pe};\n            {V('r', pr).up(I64)}\n",
    ),
)
fn(
    "`trunc(x / 2^32)` as an integer.",
    "to_int_trunc(x: i64) -> i32",
    sign_split(
        f"            let (q, _r) = {me};\n            {V('q', mq).neg().up(I32)}\n",
        f"            let (q, _r) = {pe};\n            {V('q', pq).up(I32)}\n",
    ),
)
HALF = 1 << 31
ph, mh = p_.add(HALF), m_.add(HALF)
phq, _, phe = V("h", ph.rng).div_rem(ONE)
mhq, _, mhe = V("h", mh.rng).div_rem(ONE)
fn(
    "Rounds to the nearest multiple of 2^32, ties away from zero; overflows above\n`2^31 - 1/2`.",
    "round(x: i64) -> i64",
    sign_split(
        f"            let h = {mh};\n            let (q, _r) = {mhe};\n"
        f"            {V('q', mhq).mul(ONE).neg().up(I64)}\n",
        f"            let h = {ph};\n            let (q, _r) = {phe};\n"
        f"            let i: i32 = {V('q', phq).trim_max(I32)};\n"
        f"            {V('i', I32).mul(ONE).up(I64)}\n",
    ),
)
fn(
    "`round(x / 2^32)` as an integer, ties away from zero; overflows above `2^31 - 1/2`.",
    "to_int_round(x: i64) -> i32",
    sign_split(
        f"            let h = {mh};\n            let (q, _r) = {mhe};\n"
        f"            {V('q', mhq).neg().up(I32)}\n",
        f"            let h = {ph};\n            let (q, _r) = {phe};\n"
        f"            {V('q', phq).trim_max(I32)}\n",
    ),
)

# ------------------------------------------------------------------ scalar: sign
fn(
    "`|x|`; overflows for `i64::MIN`.",
    "abs(x: i64) -> i64",
    "    match bounded_int::constrain::<i64, 0>(x) {\n"
    f"        Ok(n) => {n_.neg().trim_max(I64)},\n        Err(_) => x,\n    }}",
)
fn(
    "`x < 0` with one range check.",
    "is_negative(x: i64) -> bool",
    "    // `.is_ok()` is not inlined: 1 270 gas instead of 770.\n"
    "    #[allow(manual_is_ok)]\n"
    "    match bounded_int::constrain::<i64, 0>(x) {\n"
    "        Ok(_) => true,\n        Err(_) => false,\n    }",
)
fn(
    "`|x|` carrying the sign of `sign`; overflows when the result would be `2^63`.",
    "copysign(x: i64, sign: i64) -> i64",
    "    match bounded_int::constrain::<i64, 0>(sign) {\n"
    "        Ok(_) => match bounded_int::constrain::<i64, 0>(x) {\n"
    "            Ok(_) => x,\n"
    f"            Err(p) => {p_.neg().up(I64)},\n        }},\n"
    "        Err(_) => match bounded_int::constrain::<i64, 0>(x) {\n"
    f"            Ok(n) => {n_.neg().trim_max(I64)},\n"
    "            Err(_) => x,\n        },\n    }",
)
diff = a.sub(b)
dlo, dhi = constrain0(diff.rng)
fn(
    "`|a - b|` as a `u64` (the difference is exact: it cannot overflow).",
    "abs_diff(a: i64, b: i64) -> u64",
    f"    match bounded_int::constrain::<{tyr(diff.rng)}, 0>({diff}) {{\n"
    f"        Ok(n) => {V('n', dlo).neg().up(U64)},\n"
    f"        Err(p) => {V('p', dhi).up(U64)},\n    }}",
)

# ------------------------------------------------------------------ scalar: sqrt
fn(
    "`floor(sqrt(x * 2^32))`: the raw square root of a raw Q32.32 value.",
    "sqrt(x: i64) -> i64",
    f"    let m: u64 = or_sqrt_negative(x.try_into());\n"
    f"    let s: u128 = {V('m', U64).mul(ONE).up(U128)};\n"
    "    let r: u64 = Sqrt::sqrt(s);\n"
    "    // sqrt(2^95) < 2^48: the conversion cannot fail.\n"
    f"    or_overflow(downcast(r))",
)

# ------------------------------------------------------------------ scalar: division family
# Sign-split both operands with `constrain`, unsigned `div_rem`, re-sign. `constrain` on a
# `NonZero<i64>` yields `NonZero` halves, which is what `div_rem` wants as a divisor.
DP = V("dp", POS)  # NonZero<[0, 2^63 - 1]>: a positive divisor
DN = V("dn", m_.rng)  # NonZero<[1, 2^63]>: the magnitude of a negative divisor
NZ = f"    let b_nz: NonZero<i64> = or_division_by_zero(b.try_into());\n"


def ind(lines):
    return "".join(f"                    {line}\n" for line in lines)


def four_way(leaf):
    """leaf(a_negative, b_negative, |a|: V, |b|: V) -> body of the leaf."""
    out = NZ + "    match bounded_int::constrain::<NonZero<i64>, 0>(b_nz) {\n"
    for b_neg in (True, False):
        arm, den = ("Ok(bn)", DN) if b_neg else ("Err(dp)", DP)
        out += f"        {arm} => {{\n"
        if b_neg:
            out += "            let dn = bn.negate();\n"
        out += "            match bounded_int::constrain::<i64, 0>(a) {\n"
        out += "                Ok(n) => {\n" + leaf(True, b_neg, n_.neg(), den) + "                },\n"
        out += "                Err(p) => {\n" + leaf(False, b_neg, p_, den) + "                },\n"
        out += "            }\n        },\n"
    return out + "    }"


def div_leaf(floor):
    def leaf(a_neg, b_neg, mag, den):
        num = mag.mul(ONE)
        nv = V("num", num.rng)
        lines = [f"let num = {num};"]
        if a_neg == b_neg:  # non-negative quotient: floor == trunc
            q, _, e = nv.div_rem(den)
            lines += [f"let (q, _r) = {e};", V("q", q).down()]
        elif not floor:
            q, _, e = nv.div_rem(den)
            lines += [f"let (q, _r) = {e};", V("q", q).neg().down()]
        elif a_neg:  # num > 0: floor(-num / d) = -((num - 1) div d) - 1
            n1 = nv.sub(1)
            q, _, e = V("num1", n1.rng).div_rem(den)
            lines += [f"let num1 = {n1};", f"let (q, _r) = {e};", V("q", q).neg().sub(1).down()]
        else:  # divisor < 0, |d| in [1, 2^63]: floor(num / -d) = -((num + d - 1) div d)
            n1 = nv.add(V("dv", den.rng)).sub(1)
            q, _, e = V("num1", n1.rng).div_rem(den)
            lines += [
                f"let dv: {tyr(den.rng)} = dn.into();",
                f"let num1 = {n1};",
                f"let (q, _r) = {e};",
                V("q", q).neg().down(),
            ]
        return ind(lines)

    return leaf




def rem_leaf(a_neg, b_neg, mag, den):
    _, r, e = mag.div_rem(den)
    rv = V("r", r)
    return ind([f"let (_q, r) = {e};", rv.neg().up(I64) if a_neg else rv.up(I64)])


fn(
    "Remainder of the truncated division (sign of `a`), `|result| < |b|`.",
    "rem_trunc(a: i64, b: i64) -> i64",
    four_way(rem_leaf),
)


def rem_euclid_leaf(a_neg, b_neg, mag, den):
    if not a_neg:
        _, r, e = mag.div_rem(den)
        return ind([f"let (_q, r) = {e};", V("r", r).up(I64)])
    m1 = mag.sub(1)  # a < 0: a mod d = d - 1 - ((|a| - 1) mod d)
    _, r, e = V("m1", m1.rng).div_rem(den)
    res = V("dv", den.rng).sub(1).sub(V("r", r))
    return ind([
        f"let m1 = {m1};",
        f"let (_q, r) = {e};",
        f"let dv: {tyr(den.rng)} = {'dn' if b_neg else 'dp'}.into();",
        res.up(I64),
    ])


fn(
    "Least non-negative remainder of `a` modulo `|b|`.",
    "rem_euclid(a: i64, b: i64) -> i64",
    four_way(rem_euclid_leaf),
)


def div_euclid_leaf(a_neg, b_neg, mag, den):
    if not a_neg:
        q, _, e = mag.div_rem(den)
        qv = V("q", q)
        return ind([f"let (q, _r) = {e};", (qv.neg() if b_neg else qv).mul(ONE).down()])
    m1 = mag.sub(1)
    q, _, e = V("m1", m1.rng).div_rem(den)
    qv = V("q", q).add(1)  # ceil(|a| / d)
    return ind([
        f"let m1 = {m1};",
        f"let (q, _r) = {e};",
        (qv if b_neg else qv.neg()).mul(ONE).down(),
    ])


fn(
    "Integer quotient `n` (as `n * 2^32`) such that `a = n * b + rem_euclid(a, b)`.",
    "div_euclid(a: i64, b: i64) -> i64",
    four_way(div_euclid_leaf),
)


def const_v(v):
    return V("c", unit(v)), f"let c: UnitInt<{h(v)}> = {h(v)};"


def recip_body(floor):
    out = NZ + "    match bounded_int::constrain::<NonZero<i64>, 0>(b_nz) {\n"
    out += "        Ok(bn) => {\n            let dn = bn.negate();\n"
    if floor:  # floor(2^64 / -d) = -((2^64 - 1) div d) - 1
        cv, decl = const_v((1 << 64) - 1)
        q, _, e = cv.div_rem(DN)
        res = V("q", q).neg().sub(1)
    else:
        cv, decl = const_v(1 << 64)
        q, _, e = cv.div_rem(DN)
        res = V("q", q).neg()
    out += f"            {decl}\n            let (q, _r) = {e};\n            {res.down()}\n"
    cv, decl = const_v(1 << 64)
    q, _, e = cv.div_rem(DP)
    out += "        },\n        Err(dp) => {\n"
    out += f"            {decl}\n            let (q, _r) = {e};\n"
    return out + f"            {V('q', q).down()}\n        }},\n    }}"




# Round half to even of `num / den` on magnitudes, then re-sign and range-check. Two formulations
# of the rounding step (benchmarked, the loser goes to `benches::alt::fixed`):
#   "cmp":  (q, r) = num div_rem den; c = 2 r - den: c < 0 -> q, c > 0 -> q + 1, c == 0 (tie)
#           -> q + (q mod 2);
#   "bias": (Q, R) = (2 num + den) div_rem (2 den) (round half up); R == 0 (tie) -> 2 (Q div 2).
def fin(qv, neg):
    return (qv.neg() if neg else qv).down()


def nearest_lines(num, den, dname, neg, variant):
    """num: V (bound to `num`), den: the `NonZero` divisor V named `dname`."""
    nv, dv = V("num", num.rng), V("dv", den.rng)
    lines = [f"let num: {tyr(num.rng)} = {num};", f"let dv: {tyr(den.rng)} = {dname}.into();"]
    if variant == "bias":
        n2 = nv.mul(2).add(dv)
        d2 = V("d2", dv.mul(2).rng)
        q, _, e = V("n2", n2.rng).div_rem(d2)
        hq, _, he = V("q", q).div_rem(2)
        return lines + [
            f"let n2 = {n2};",
            f"let d2 = bounded_int::mul::<_, NonZero<UnitInt<0x2>>>({dname}, 0x2);",
            f"let (q, r) = {e};",
            "match Into::<_, felt252>::into(r) {",
            f"    0 => {{\n        let (hq, _p) = {he};\n"
            f"        {fin(V('hq', hq).mul(2), neg)}\n    }},",
            f"    _ => {fin(V('q', q), neg)},",
            "}",
        ]
    q, r, e = nv.div_rem(den)
    c = V("r", r).mul(2).sub(dv)
    constrain0(c.rng)
    _, p, pe = V("q", q).div_rem(2)
    return lines + [
        f"let (q, r) = {e};",
        f"let c = {c};",
        f"match bounded_int::constrain::<{tyr(c.rng)}, 0>(c) {{",
        f"    Ok(_) => {fin(V('q', q), neg)},",
        "    Err(nn) => if Into::<_, felt252>::into(nn) == 0 {",
        f"        let (_h, p) = {pe};\n        {fin(V('q', q).add(V('p', p)), neg)}",
        f"    }} else {{\n        {fin(V('q', q).add(1), neg)}\n    }},",
        "}",
    ]


def div_nearest_body(variant):
    def leaf(a_neg, b_neg, mag, den):
        dname = "dn" if b_neg else "dp"
        return ind(nearest_lines(mag.mul(ONE), den, dname, a_neg != b_neg, variant))

    return four_way(leaf)


def recip_nearest_body(variant):
    num = V(h(1 << 64), unit(1 << 64))
    out = NZ + "    match bounded_int::constrain::<NonZero<i64>, 0>(b_nz) {\n"
    out += "        Ok(bn) => {\n            let dn = bn.negate();\n"
    out += "".join(f"            {x}\n" for x in nearest_lines(num, DN, "dn", True, variant))
    out += "        },\n        Err(dp) => {\n"
    out += "".join(f"            {x}\n" for x in nearest_lines(num, DP, "dp", False, variant))
    return out + "        },\n    }"


DIV_NEAREST = "bias"  # the winner (see gas/fixed.snap: div vs alt_div_nearest_*)
fn(
    "`round_half_even((a * 2^32) / b)`: the correctly rounded quotient (ties to even).",
    "div_nearest(a: i64, b: i64) -> i64",
    div_nearest_body(DIV_NEAREST),
)
fn(
    "`round_half_even(2^64 / b)`: the correctly rounded reciprocal (one sign split).",
    "recip_nearest(b: i64) -> i64",
    recip_nearest_body(DIV_NEAREST),
)

# ------------------------------------------------------------------ wide reciprocal
R96 = 1 << 96
BR = (-R96, R96)
ALIASES.append(f"pub type BR = {tyr(BR)};")
cv, decl = const_v(R96)
qn, _, en = cv.div_rem(DN)
qp, _, ep = cv.div_rem(DP)
fn(
    "`trunc(2^96 / b)`, signed: the Q32.96 reciprocal consumed by `recip_mul`.",
    "recip_wide(b: i64) -> BR",
    NZ + f"    {decl}\n"
    "    match bounded_int::constrain::<NonZero<i64>, 0>(b_nz) {\n"
    "        Ok(bn) => {\n            let dn = bn.negate();\n"
    f"            let (q, _r) = {en};\n            {V('q', qn).neg().up(BR)}\n        }},\n"
    f"        Err(dp) => {{\n            let (q, _r) = {ep};\n"
    f"            {V('q', qp).up(BR)}\n        }},\n    }}",
)
qu, _, eu = cv.div_rem(V("d", U64))
fn(
    "`floor(2^96 / d)` for a non-zero unsigned raw length (no sign split).",
    "recip_wide_nz(d: NonZero<u64>) -> BR",
    f"    {decl}\n    let (q, _r) = {eu};\n    {V('q', qu).up(BR)}",
)
fn(
    "`floor(2^96 / len)` for an unsigned raw length; panics on zero.",
    "recip_wide_u64(len: u64) -> BR",
    f"    recip_wide_nz(or_division_by_zero(len.try_into()))",
)
fn(
    "`round(x * r / 2^64)`: `x / b` through the reciprocal `r = 2^96 / b`. Within\n"
    "`1/2 + |x| / 2^64` ULP of the exact quotient (ties toward +infinity).",
    "recip_mul(r: BR, x: i64) -> i64",
    f"    narrow64_round({V('r', BR).mul(x).felt()})",
)

# Correctly rounded division by a shared divisor `d` (`wide::RecipNearest`): the divisor is
# prepared once (`2 |d|` as a `NonZero` divisor and `|d|`, tagged by the sign of `d`: `upcast`
# does not accept `NonZero` types, so each sign keeps its own ranges), each division is then the
# "bias" rounding step of `div_nearest` without the zero test and the sign split of `d`
# (measured cheaper than a 96-bit reciprocal plus an exact remainder correction, which stays in
# `benches::alt::fixed` as `recip_nearest_recip_*`).
RD = (0, 1 << 63)  # |d|, used by the alternative below
D2N, D2P = V("dn", DN.rng).mul(2), V("dp", DP.rng).mul(2)  # declares the `NonZero` product helpers
DIVISOR = (
    "/// A non-zero divisor prepared for `recip_nearest_div`: `(2 |d|, |d|)`, tagged by the sign\n"
    "/// of `d`.\n#[derive(Copy, Drop)]\npub enum Divisor {\n"
    f"    Neg: (NonZero<{tyr(D2N.rng)}>, {tyr(DN.rng)}),\n"
    f"    Pos: (NonZero<{tyr(D2P.rng)}>, {tyr(DP.rng)}),\n}}"
)
ALIASES.append(DIVISOR)


def prepared_arm(dname, den):
    return (
        f"            let d2 = bounded_int::mul::<_, NonZero<UnitInt<0x2>>>({dname}, 0x2);\n"
        f"            let dv: {tyr(den.rng)} = {dname}.into();\n"
    )


fn(
    "`Divisor` of `b`: `(2 |b|, |b|)` tagged by the sign of `b`.",
    "recip_nearest_new(b: i64) -> Divisor",
    NZ
    + "    match bounded_int::constrain::<NonZero<i64>, 0>(b_nz) {\n"
    "        Ok(bn) => {\n            let dn = bn.negate();\n"
    + prepared_arm("dn", DN) + "            Divisor::Neg((d2, dv))\n        },\n"
    "        Err(dp) => {\n" + prepared_arm("dp", DP) + "            Divisor::Pos((d2, dv))\n"
    "        },\n    }",
)


def prepared_leaf(mag, neg, den):
    num = mag.mul(ONE)
    n2 = V("num", num.rng).mul(2).add(V("d", den.rng))
    q, _, e = V("n2", n2.rng).div_rem(V("d2", V("", den.rng).mul(2).rng))
    hq, _, he = V("q", q).div_rem(2)
    return [
        f"let num: {tyr(num.rng)} = {num};",
        f"let n2 = {n2};",
        f"let (q, r) = {e};",
        "match Into::<_, felt252>::into(r) {",
        f"    0 => {{\n        let (hq, _p) = {he};\n"
        f"        {fin(V('hq', hq).mul(2), neg)}\n    }},",
        f"    _ => {fin(V('q', q), neg)},",
        "}",
    ]


def x_split(leaf, d_neg):
    out = "        match bounded_int::constrain::<i64, 0>(x) {\n"
    for x_neg in (True, False):
        arm, mag = ("Ok(n)", n_.neg()) if x_neg else ("Err(p)", p_)
        out += f"            {arm} => {{\n"
        out += "".join(f"                {l}\n" for l in leaf(mag, x_neg != d_neg))
        out += "            },\n"
    return out + "        }\n"


fn(
    "`round_half_even(x * 2^32 / b)` from `recip_nearest_new(b)`: bit-identical to\n"
    "`div_nearest(x, b)` (same rounding step, divisor prepared).",
    "recip_nearest_div(p: Divisor, x: i64) -> i64",
    "    match p {\n"
    "        Divisor::Neg((d2, d)) => {\n"
    + x_split(lambda m, ng: prepared_leaf(m, ng, DN), True)
    + "        },\n        Divisor::Pos((d2, d)) => {\n"
    + x_split(lambda m, ng: prepared_leaf(m, ng, DP), False)
    + "        },\n    }",
)


def shared_div_body(leaf):
    out = "    if neg {\n"
    out += x_split(leaf, True)
    out += "    } else {\n"
    out += x_split(leaf, False)
    return out + "    }"


# Alternative of `wide::RecipNearest` (emitted in `benches::alt::fixed`): the magnitudes
# `v = floor(2^96 / |d|)`, `|d|` and the sign of `d` are kept. For `|x| <= 2^63` the approximation
# `y = |x| v / 2^64` satisfies `0 <= t - y < |x| / 2^64 <= 1/2`, `t = |x| 2^32 / |d|` being the
# exact quotient, and `q0 = ceil(y - 1/2) = floor((|x| v + 2^63 - 1) / 2^64)` satisfies
# `y - 1/2 <= q0 < y + 1/2`: hence `-1/2 < t - q0 < 1` and `round_half_even(t)` is `q0` or
# `q0 + 1`. The exact remainder `e = |x| 2^32 - q0 |d|` (`= |d| (t - q0)`) decides it with one
# sign test of `2 e - |d|` (negative: `q0`, positive: `q0 + 1`, zero: the even one of the two).
# `q0 >= 2^64` (the `felt252 -> u128` conversion fails) implies `t > 2^64 - 1/2`: an overflow of
# the exact division as well, so the panics are those of `div_nearest`.
RV = (0, R96)  # v = floor(2^96 / |d|)


def recip_nearest_leaf(mag, neg):
    q0, _, e0 = V("u", U128).div_rem(1 << 64)
    q0v, dv = V("q0", q0), V("d", RD)
    err = V("ax", mag.rng).mul(ONE).sub(q0v.mul(dv))
    c = V("e", err.rng).mul(2).sub(dv)
    constrain0(c.rng)
    _, p, pe = q0v.div_rem(2)
    return [
        f"let ax: {tyr(mag.rng)} = {mag};",
        f"let f: felt252 = {V('ax', mag.rng).mul(V('v', RV)).felt()} + {h((1 << 63) - 1)};",
        f"let u: u128 = or_overflow(f.try_into());",
        f"let (q0, _r) = {e0};",
        f"let e = {err};",
        f"let c = {c};",
        f"match bounded_int::constrain::<{tyr(c.rng)}, 0>(c) {{",
        f"    Ok(_) => {fin(q0v, neg)},",
        "    Err(nn) => if Into::<_, felt252>::into(nn) == 0 {",
        f"        let (_h, p) = {pe};\n        {fin(q0v.add(V('p', p)), neg)}",
        f"    }} else {{\n        {fin(q0v.add(1), neg)}\n    }},",
        "}",
    ]


def emit_recip_nearest_recip():
    qn, _, en = cv.div_rem(DN)
    qp, _, ep = cv.div_rem(DP)
    fn(
        "`(floor(2^96 / |b|), |b|, b < 0)`: the divisor of `recip_nearest_recip_div_raw`.",
        f"recip_nearest_recip_new_raw(b: i64) -> ({tyr(RV)}, {tyr(RD)}, bool)",
        NZ + f"    {decl}\n"
        "    match bounded_int::constrain::<NonZero<i64>, 0>(b_nz) {\n"
        "        Ok(bn) => {\n            let dn = bn.negate();\n"
        f"            let (q, _r) = {en};\n            let dv: {tyr(DN.rng)} = dn.into();\n"
        f"            ({V('q', qn).up(RV)}, {V('dv', DN.rng).up(RD)}, true)\n        }},\n"
        f"        Err(dp) => {{\n            let (q, _r) = {ep};\n"
        f"            let dv: {tyr(DP.rng)} = dp.into();\n"
        f"            ({V('q', qp).up(RV)}, {V('dv', DP.rng).up(RD)}, false)\n        }},\n    }}",
    )
    fn(
        "`round_half_even(x * 2^32 / b)` from `recip_nearest_recip_new_raw(b)`: bit-identical to\n"
        "`div_nearest(x, b)` (one approximate quotient through `v`, one exact remainder check).",
        f"recip_nearest_recip_div_raw(v: {tyr(RV)}, d: {tyr(RD)}, neg: bool, x: i64) -> i64",
        shared_div_body(recip_nearest_leaf),
    )


# ------------------------------------------------------------------ output
HEADER = "// GENERATED by scripts/gen_bounded.py - do not edit by hand.\n"
FEATURE = '#[feature("bounded-int-utils")]\n'


def _or(name, msg):
    return (
        f"/// Unwraps `o` or panics with `{msg[1:-1]}` (out-of-line `panic_with_const_felt252`).\n"
        f"#[inline(always)]\npub fn {name}<T>(o: Option<T>) -> T {{\n    match o {{\n"
        f"        Some(v) => v,\n        None => core::panic_with_const_felt252::<{msg}>(),\n    }}\n}}"
    )


PANIC_HELPERS = [
    _or("or_overflow", OVERFLOW),
    _or("or_division_by_zero", DIV_ZERO),
    _or("or_sqrt_negative", SQRT_NEG),
]


def bounded_file():
    out = [
        HEADER
        + "//! Raw kernels on `i64` written with `core::internal::bounded_int` (unstable corelib\n"
        "//! API, hence generated: every bound below is computed by the script).\n"
        + FEATURE
        + "pub use core::internal::bounded_int::UnitInt;\n"
        + FEATURE
        + "use core::internal::bounded_int::{\n"
        "    self, AddHelper, BoundedInt, ConstrainHelper, DivRemHelper, MulHelper, NegateHelper,\n"
        "    SubHelper, TrimMaxHelper, downcast, upcast,\n};\n"
        "use core::internal::OptionRev;\n"
        "use core::num::traits::Sqrt;\n"
    ]
    impls = "\n".join(IMPLS.values())
    for name, rng in [(f"BW{n}", BW[n]) for n in BW] + [(f"BT{n}", BT[n]) for n in BT]:
        impls = impls.replace(tyr(rng), name)  # spell the accumulator ranges by their alias
    return "\n".join(out + ALIASES + [impls] + PANIC_HELPERS + FNS) + "\n"


LIB_BOUNDED = bounded_file()

# ====================================================================== benches::alt
# Losing formulations, kept with their benches so that the comparison stays reproducible across
# compiler upgrades (DESIGN rule 9). They need their own helper impls: fresh context.
IMPLS.clear()
FNS.clear()
ALT = ROOT / "packages" / "benches" / "src" / "alt"
d, e = V("d", I64), V("e", I64)

# -- mul: the rescale of the research prototype, bias + div_rem + downcast (5 range checks)
prod = a.mul(b)
POFF = 1 << 126
assert POFF >= -prod.rng[0] and POFF % ONE == 0
pbq, _, pbe = V("biased", prod.add(POFF).rng).div_rem(ONE)
fn(
    "`floor(a * b / 2^32)`: bias, `div_rem`, un-bias, `downcast` (research prototype, 2 050 gas).",
    "mul_bias_downcast_raw(a: i64, b: i64) -> i64",
    f"    let biased = {prod.add(POFF)};\n    let (q, _r) = {pbe};\n"
    f"    {V('q', pbq).sub(POFF >> 32).down()}",
)
# -- triple product narrow: formulations that stay in bounded-int space
t2 = a.mul(b).sub(c.mul(d)).mul(e)
assert within(t2.rng, BT[2])
TOFF = 2 * TMAX
tsq, _, tse = V("biased", t2.add(TOFF).rng).div_rem(1 << 64)
fn(
    "`floor((a * b - c * d) * e / 2^64)`: single `div_rem` by 2^64 then `downcast`. Only possible\n"
    "for up to 3 triple products (the biased quotient must stay below 2^128).",
    "triple_single_downcast_raw(a: i64, b: i64, c: i64, d: i64, e: i64) -> i64",
    f"    let biased = {t2.add(TOFF)};\n    let (q, _r) = {tse};\n"
    f"    {V('q', tsq).sub(TOFF >> 64).down()}",
)
tq1, tr1, te1 = V("biased", t2.add(TOFF).rng).div_rem(1 << 96)
thi = V("q1", tq1).sub(TOFF >> 96)
tq2, _, te2 = V("r1", tr1).div_rem(1 << 64)
tres = V("hi", I32).mul(ONE).add(V("lo", tq2))
fn(
    "`floor((a * b - c * d) * e / 2^64)` in two stages (`div_rem` by 2^96, `downcast` of the high\n"
    "part to `i32`, `div_rem` of the remainder by 2^64): works for any accumulator width.",
    "triple_two_stage_raw(a: i64, b: i64, c: i64, d: i64, e: i64) -> i64",
    f"    let biased = {t2.add(TOFF)};\n    let (q1, r1) = {te1};\n"
    f"    let hi: i32 = {thi.down(I32)};\n    let (lo, _r) = {te2};\n    {tres.up(I64)}",
)
# -- div / recip: floor rounding, and the prototype's flat sign split (truncation)
fn(
    "`floor((a * 2^32) / b)`: rounds toward negative infinity (200 gas more than truncation).",
    "div_floor_raw(a: i64, b: i64) -> i64",
    four_way(div_leaf(True)),
)
fn(
    "`trunc((a * 2^32) / b)`: rounds toward zero, like the corelib signed division (the `/` of\n"
    "`fixed` up to 0.2; 400 gas less than round half to even).",
    "div_trunc_raw(a: i64, b: i64) -> i64",
    four_way(div_leaf(False)),
)
fn(
    "`trunc(2^64 / b)`: the reciprocal rounded toward zero (`recip` up to 0.2).",
    "recip_trunc_raw(b: i64) -> i64",
    recip_body(False),
)
fn(
    "`floor(2^64 / b)`: reciprocal rounded toward negative infinity.",
    "recip_floor_raw(b: i64) -> i64",
    recip_body(True),
)
numn, nump = m_.mul(ONE), p_.mul(ONE)
NUM = (0, numn.rng[1])
for den in (DP, DN):
    flat_q, _, _ = V("num", NUM).div_rem(den)
    assert flat_q == NUM
V("q", NUM).neg()
fn(
    "`trunc((a * 2^32) / b)` with the prototype's flat structure: two sequential sign splits\n"
    "carrying boolean flags, then one conditional negation (1 000 gas more than the nested\n"
    "4-way match of the library).",
    "div_trunc_flat_raw(a: i64, b: i64) -> i64",
    NZ
    + f"    let (num, a_neg): ({tyr(NUM)}, bool) = match bounded_int::constrain::<i64, 0>(a) {{\n"
    f"        Ok(n) => {{\n            let m = {n_.neg()};\n"
    f"            ({numn.up(NUM)}, true)\n        }},\n"
    f"        Err(p) => ({nump.up(NUM)}, false),\n    }};\n"
    f"    let (q, neg): ({tyr(NUM)}, bool) = "
    "match bounded_int::constrain::<NonZero<i64>, 0>(b_nz) {\n"
    "        Ok(bn) => {\n            let (q, _r) = bounded_int::div_rem(num, bn.negate());\n"
    "            (q, !a_neg)\n        },\n"
    "        Err(dp) => {\n            let (q, _r) = bounded_int::div_rem(num, dp);\n"
    "            (q, a_neg)\n        },\n    };\n"
    f"    if neg {{\n        {V('q', NUM).neg().down()}\n    }} else {{\n"
    f"        {V('q', NUM).down()}\n    }}",
)
# -- div_nearest / recip_nearest: the losing rounding step
ALT_NEAREST = "bias" if DIV_NEAREST == "cmp" else "cmp"
fn(
    f"`round_half_even((a * 2^32) / b)` with the `{ALT_NEAREST}` rounding step.",
    f"div_nearest_{ALT_NEAREST}_raw(a: i64, b: i64) -> i64",
    div_nearest_body(ALT_NEAREST),
)
fn(
    f"`round_half_even(2^64 / b)` with the `{ALT_NEAREST}` rounding step.",
    f"recip_nearest_{ALT_NEAREST}_raw(b: i64) -> i64",
    recip_nearest_body(ALT_NEAREST),
)
# -- RecipNearest through a 96-bit reciprocal plus an exact remainder correction
emit_recip_nearest_recip()
# -- abs / round with `downcast` instead of `trim_max`; sqrt with a `constrain` sign test
fn(
    "`|x|` with a `downcast` (one more range check than `trim_max`).",
    "abs_downcast_raw(x: i64) -> i64",
    "    match bounded_int::constrain::<i64, 0>(x) {\n"
    f"        Ok(n) => {n_.neg().down()},\n        Err(_) => x,\n    }}",
)
for half_v in (m_, p_):
    V("h", half_v.add(HALF).rng).div_rem(ONE)
fn(
    "Round half away from zero with a `downcast` instead of `trim_max`.",
    "round_downcast_raw(x: i64) -> i64",
    sign_split(
        f"            let h = {mh};\n            let (q, _r) = {mhe};\n"
        f"            {V('q', mhq).mul(ONE).neg().up(I64)}\n",
        f"            let h = {ph};\n            let (q, _r) = {phe};\n"
        f"            {V('q', phq).mul(ONE).down()}\n",
    ),
)
fn(
    "`floor(sqrt(x * 2^32))` with a `constrain` sign test instead of `i64 -> u64`.",
    "sqrt_constrain_raw(x: i64) -> i64",
    "    match bounded_int::constrain::<i64, 0>(x) {\n"
    f"        Ok(_) => core::panic_with_const_felt252::<{SQRT_NEG}>(),\n"
    "        Err(p) => {\n"
    f"            let s: u128 = {p_.mul(ONE).up(U128)};\n"
    "            let r: u64 = Sqrt::sqrt(s);\n"
    f"            or_overflow(downcast(r))\n        }},\n    }}",
)

ALT_FIXED_STATIC = """
const TWO_POW_64: NonZero<u128> = 0x10000000000000000;

/// `Fixed * Fixed` on the **stable** corelib API only (no `core::internal::bounded_int`): the
/// documented fallback should the unstable API break. Same result as the library (floor), same
/// single `felt252 -> u128` range check, but a `u128` divmod and a checked `felt252 -> i64`.
#[inline(always)]
pub fn mul_stable(a: Fixed, b: Fixed) -> Fixed {
    let p: felt252 = a.raw.into() * b.raw.into();
    let u: u128 = ((p + 0x800000000000000000000000) * 0x100000000)
        .try_into()
        .expect('Fixed: overflow');
    let (q, _r) = DivRem::div_rem(u, TWO_POW_64);
    let biased: felt252 = q.into();
    Fixed { raw: (biased - 0x8000000000000000).try_into().unwrap() }
}

/// Naive stable-API `mul`: signed `i128` division (truncates toward zero: NOT the library
/// rounding). What a straightforward port would write.
#[inline(always)]
pub fn mul_stable_i128(a: Fixed, b: Fixed) -> Fixed {
    let p: i128 = WideMul::wide_mul(a.raw, b.raw);
    Fixed { raw: (p / 0x100000000).try_into().expect('Fixed: overflow') }
}

/// `Fixed / Fixed` on the stable corelib API only: signed `i128` division (truncation, same
/// result as the library). The documented fallback of `div`.
#[inline(always)]
pub fn div_stable(a: Fixed, b: Fixed) -> Fixed {
    assert(b.raw != 0, 'Fixed: division by zero');
    let n: i128 = WideMul::wide_mul(a.raw, 0x100000000_i64);
    Fixed { raw: (n / b.raw.into()).try_into().expect('Fixed: overflow') }
}

/// `%` through the corelib signed remainder.
#[inline(always)]
pub fn rem_native(a: Fixed, b: Fixed) -> Fixed {
    assert(b.raw != 0, 'Fixed: division by zero');
    Fixed { raw: a.raw % b.raw }
}

/// `powi` as a pure square-and-multiply loop (no small-exponent fast path).
pub fn powi_loop(x: Fixed, n: i32) -> Fixed {
    let wide: i64 = n.into();
    let negative = wide < 0;
    let mut e: u32 = (if negative {
        -wide
    } else {
        wide
    }).try_into().unwrap();
    let mut base = x;
    let mut acc = ONE;
    while e != 0 {
        let (q, r) = DivRem::div_rem(e, 2);
        if r == 1 {
            acc = acc * base;
        }
        e = q;
        if e != 0 {
            base = base * base;
        }
    }
    if negative {
        acc.recip()
    } else {
        acc
    }
}
"""

ALT_FIXED_STATIC += f"""
/// `wide::RecipNearest` through a 96-bit reciprocal `v = floor(2^96 / |d|)`, an approximate
/// quotient within `(-1/2, 1)` of the exact one and an exact remainder correction (see
/// `scripts/gen_bounded.py`): bit-identical to the library, but each division costs more than a
/// plain `div_nearest`, so the library prepares the divisor instead.
#[derive(Copy, Drop)]
pub struct RecipNearestRecip {{
    v: {tyr(RV)},
    d: {tyr(RD)},
    neg: bool,
}}

/// Prepares `d` for `recip_nearest_recip_div`.
#[inline(always)]
pub fn recip_nearest_recip_new(d: Fixed) -> RecipNearestRecip {{
    let (v, d, neg) = recip_nearest_recip_new_raw(d.raw);
    RecipNearestRecip {{ v, d, neg }}
}}

/// `x / d` rounded half to even through the reciprocal of `recip_nearest_recip_new(d)`.
#[inline(always)]
pub fn recip_nearest_recip_div(r: RecipNearestRecip, x: Fixed) -> Fixed {{
    Fixed {{ raw: recip_nearest_recip_div_raw(r.v, r.d, r.neg, x.raw) }}
}}
"""

FIVE = "a: Fixed, b: Fixed, c: Fixed, d: Fixed, e: Fixed"
ALT_WRAPPERS = [
    ("mul_bias_downcast", "a: Fixed, b: Fixed", "a.raw, b.raw", "Prototype rescale of `mul`."),
    ("div_floor", "a: Fixed, b: Fixed", "a.raw, b.raw", "Floor-rounded `div`."),
    ("div_trunc", "a: Fixed, b: Fixed", "a.raw, b.raw", "Truncated `div` (up to 0.2)."),
    ("recip_trunc", "b: Fixed", "b.raw", "Truncated `recip` (up to 0.2)."),
    ("div_trunc_flat", "a: Fixed, b: Fixed", "a.raw, b.raw", "Flat sign-split `div`."),
    ("recip_floor", "b: Fixed", "b.raw", "Floor-rounded `recip`."),
    (
        f"div_nearest_{ALT_NEAREST}", "a: Fixed, b: Fixed", "a.raw, b.raw",
        f"`div_nearest` with the `{ALT_NEAREST}` rounding step.",
    ),
    (
        f"recip_nearest_{ALT_NEAREST}", "b: Fixed", "b.raw",
        f"`recip_nearest` with the `{ALT_NEAREST}` rounding step.",
    ),
    ("abs_downcast", "x: Fixed", "x.raw", "`abs` with `downcast`."),
    ("round_downcast", "x: Fixed", "x.raw", "`round` with `downcast`."),
    ("sqrt_constrain", "x: Fixed", "x.raw", "`sqrt` with `constrain`."),
    (
        "triple_single_downcast", FIVE, "a.raw, b.raw, c.raw, d.raw, e.raw",
        "`(a * b - c * d) * e`, single-stage bounded narrow.",
    ),
    (
        "triple_two_stage", FIVE, "a.raw, b.raw, c.raw, d.raw, e.raw",
        "`(a * b - c * d) * e`, two-stage bounded narrow.",
    ),
]


def alt_fixed_file():
    out = [
        HEADER
        + "//! Alternative implementations benchmarked against `fixed` (scalar operators and the\n"
        "//! rescale of the fused kernels). The winners live in `fixed`; the losers stay here with\n"
        "//! their benches (`bench_fixed::alt_*`, `bench_wide::alt_*`) so that the comparison\n"
        "//! stays reproducible across compiler upgrades. `mul_stable` / `div_stable` are the\n"
        "//! documented stable-API fallback of the `core::internal::bounded_int` kernels.\n"
        + FEATURE
        + "use core::internal::bounded_int::{\n"
        "    self, AddHelper, BoundedInt, ConstrainHelper, DivRemHelper, MulHelper, NegateHelper,\n"
        "    SubHelper, UnitInt, downcast, upcast,\n};\n"
        "use core::num::traits::{Sqrt, WideMul};\n"
        "use fixed::{Fixed, FixedTrait, ONE};\n",
        ALT_FIXED_STATIC,
    ]
    impls = [i.replace("pub impl", "impl") for i in IMPLS.values()]
    fns = [f.replace("pub fn", "fn") for f in FNS]
    wrappers = [
        f"/// {doc}\n#[inline(always)]\npub fn {name}({params}) -> Fixed {{\n"
        f"    Fixed {{ raw: {name}_raw({args}) }}\n}}"
        for name, params, args, doc in ALT_WRAPPERS
    ]
    helpers = [f.replace("pub fn", "fn") for f in PANIC_HELPERS]
    return "\n".join(out + impls + helpers + fns + wrappers) + "\n"


TRAITS = """/// Typed addition of two wide accumulators: `Wn + Wm -> W(n+m)`, `Tn + Tm -> T(n+m)`.
/// One step, no range check: the bound of the sum is tracked by the result type.
pub trait WideAdd<L, R> {
    /// The accumulator type wide enough for the sum.
    type Output;
    /// Returns `self + rhs` (exact, cannot overflow).
    fn add(self: L, rhs: R) -> Self::Output;
}
/// Typed subtraction of two wide accumulators: `Wn - Wm -> W(n+m)`, `Tn - Tm -> T(n+m)`.
/// One step, no range check.
pub trait WideSub<L, R> {
    /// The accumulator type wide enough for the difference.
    type Output;
    /// Returns `self - rhs` (exact, cannot overflow).
    fn sub(self: L, rhs: R) -> Self::Output;
}
/// Negation of a wide accumulator (bounds are symmetric, the type is unchanged).
pub trait WideNeg<S> {
    /// Returns `-self` (exact, cannot overflow).
    fn neg(self: S) -> S;
}
/// Multiplication of a Q64.64 accumulator by a `Fixed`: `Wn * Fixed -> Tn` (Q96.96).
/// One step, no range check. This is how `a * (b * c - d * e)` is fused.
pub trait WideMul<S> {
    /// The Q96.96 accumulator type wide enough for the product.
    type Output;
    /// Returns `self * rhs` at the Q96.96 scale (exact, cannot overflow).
    fn mul(self: S, rhs: Fixed) -> Self::Output;
}
/// Change of scale `Wn -> Tn` (`* 2^32`, exact), to add a Q64.64 term to a Q96.96 sum.
pub trait WideLift<S> {
    /// The Q96.96 accumulator type of the same width.
    type Output;
    /// Returns `self` at the Q96.96 scale.
    fn lift(self: S) -> Self::Output;
}
/// The single rescale of a fused kernel: wide accumulator -> `Fixed`, rounding toward negative
/// infinity (floor), like `Fixed * Fixed`.
pub trait WideNarrow<S> {
    /// Returns `floor(self)` at the Q32.32 scale.
    /// #### Panics
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    fn narrow(self: S) -> Fixed;
}
/// Square root of a Q64.64 accumulator. The integer square root of a raw Q64.64 value is the raw
/// Q32.32 result: no rescale, no precision loss.
pub trait WideSqrt<S> {
    /// Returns `floor(sqrt(self))` at the Q32.32 scale.
    /// #### Panics
    /// * `'Fixed: sqrt negative'` if `self` is negative.
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    fn sqrt(self: S) -> Fixed;
}
/// Operations on the count-agnostic exact Q64.64 accumulator [`Acc`].
pub trait AccTrait {
    /// Returns the empty sum.
    fn zero() -> Acc;
    /// Adds the exact product `a * b`, without a range check.
    fn add_prod(self: Acc, a: Fixed, b: Fixed) -> Acc;
    /// Subtracts the exact product `a * b`, without a range check.
    fn sub_prod(self: Acc, a: Fixed, b: Fixed) -> Acc;
    /// Adds `c`, aligned exactly to the Q64.64 accumulator scale.
    fn add(self: Acc, c: Fixed) -> Acc;
    /// Subtracts `c`, aligned exactly to the Q64.64 accumulator scale.
    fn sub(self: Acc, c: Fixed) -> Acc;
    /// Returns `floor(self)` at the Q32.32 scale.
    /// #### Panics
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    fn narrow(self: Acc) -> Fixed;
    /// Returns `floor(sqrt(self))` at the Q32.32 scale.
    /// #### Panics
    /// * `'Fixed: sqrt negative'` if `self` is negative.
    /// * `'Fixed: overflow'` if the root does not fit the scalar range.
    fn sqrt(self: Acc) -> Fixed;
    /// Multiplies by `s` exactly, then returns the once-rounded Q32.32 result.
    ///
    /// The caller must keep the signed exact product in `(-P / 2, P / 2)`. Given the operation
    /// bounds documented on [`Acc`], this holds for fewer than `2^61` accumulated operations.
    /// #### Panics
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    fn mul_narrow(self: Acc, s: Fixed) -> Fixed;
}"""


def acc_file():
    o = [
        HEADER
        + "//! Wide accumulator types, re-exported (and documented) by `fixed::wide`.\n"
        + FEATURE
        + "use core::internal::bounded_int::{self, NegateHelper, upcast};\n"
        "use crate::fixed::Fixed;\nuse super::bounded::*;\n",
        TRAITS,
        """/// A count-agnostic exact Q64.64 accumulator backed by one opaque `felt252`.
///
/// Each `add_prod` / `sub_prod` changes the signed exact value by at most `2^126`; each `add` /
/// `sub` changes it by at most `2^95`. After `k` operations, therefore, `|value| <= k * 2^126`.
/// The field modulus is approximately `2^251`, so the signed representation cannot alias modulo
/// P until approximately `2^124` operations, beyond any executable trace. `narrow`, `sqrt`, and
/// `mul_narrow` range-check their exact result, so an out-of-range sum never wraps silently.
/// `mul_narrow` additionally requires fewer than `2^61` accumulated operations, ensuring that
/// multiplying by any `Fixed` (`|raw| <= 2^63`) remains in the signed half of the field.
///
/// Mirrors nothing in glam-rs: this is a fused-kernel building block for downstream libraries.
/// #### Panics
/// * Never on construction or accumulation; exit operations document their own panic paths.
/// #### Deviations
/// * None.
#[derive(Copy, Drop)]
pub struct Acc {
    pub(crate) v: felt252,
}

pub impl AccImpl of AccTrait {
    #[inline(always)]
    fn zero() -> Acc {
        Acc { v: 0 }
    }

    #[inline(always)]
    fn add_prod(self: Acc, a: Fixed, b: Fixed) -> Acc {
        Acc { v: self.v + upcast(wide(a.raw, b.raw)) }
    }

    #[inline(always)]
    fn sub_prod(self: Acc, a: Fixed, b: Fixed) -> Acc {
        Acc { v: self.v - upcast(wide(a.raw, b.raw)) }
    }

    #[inline(always)]
    fn add(self: Acc, c: Fixed) -> Acc {
        Acc { v: self.v + upcast(lift(c.raw)) }
    }

    #[inline(always)]
    fn sub(self: Acc, c: Fixed) -> Acc {
        Acc { v: self.v - upcast(lift(c.raw)) }
    }

    #[inline(always)]
    fn narrow(self: Acc) -> Fixed {
        Fixed { raw: narrow32(self.v) }
    }

    #[inline(always)]
    fn sqrt(self: Acc) -> Fixed {
        Fixed { raw: sqrt_acc(self.v) }
    }

    #[inline(always)]
    fn mul_narrow(self: Acc, s: Fixed) -> Fixed {
        Fixed { raw: narrow64(self.v * s.raw.into()) }
    }
}

pub impl AccAdd of Add<Acc> {
    #[inline(always)]
    fn add(lhs: Acc, rhs: Acc) -> Acc {
        Acc { v: lhs.v + rhs.v }
    }
}

pub impl AccSub of Sub<Acc> {
    #[inline(always)]
    fn sub(lhs: Acc, rhs: Acc) -> Acc {
        Acc { v: lhs.v - rhs.v }
    }
}

pub impl AccNeg of Neg<Acc> {
    #[inline(always)]
    fn neg(a: Acc) -> Acc {
        Acc { v: -a.v }
    }
}""",
    ]
    fams = (
        ("W", "BW", "Q64.64", "product", "2^126", NW, "narrow32"),
        ("T", "BT", "Q96.96", "triple product", "2^189", NT, "narrow64"),
    )
    for fam, bt, scale, what, mag, N, nar in fams:
        for n in range(1, N + 1):
            o.append(
                f"/// Exact sum of up to {n} raw {scale} {what}(s): `|value| <= {n} * {mag}`.\n"
                "/// Opaque: built and consumed by the functions and traits of `fixed::wide`.\n"
                f"#[derive(Copy, Drop)]\npub struct {fam}{n} {{\n    pub(crate) v: {bt}{n},\n}}"
            )
        for n in range(1, N + 1):
            o.append(
                f"pub impl {fam}{n}Narrow of WideNarrow<{fam}{n}> {{\n    #[inline(always)]\n"
                f"    fn narrow(self: {fam}{n}) -> Fixed {{\n"
                f"        Fixed {{ raw: {nar}(upcast(self.v)) }}\n    }}\n}}"
            )
            o.append(
                f"pub impl {fam}{n}Neg of WideNeg<{fam}{n}> {{\n    #[inline(always)]\n"
                f"    fn neg(self: {fam}{n}) -> {fam}{n} {{\n"
                f"        {fam}{n} {{ v: self.v.negate() }}\n    }}\n}}"
            )
            for m in range(1, N + 1 - n):
                for tr, op in (("Add", "add"), ("Sub", "sub")):
                    o.append(
                        f"pub impl {fam}{n}{tr}{fam}{m} of Wide{tr}<{fam}{n}, {fam}{m}> {{\n"
                        f"    type Output = {fam}{n + m};\n    #[inline(always)]\n"
                        f"    fn {op}(self: {fam}{n}, rhs: {fam}{m}) -> {fam}{n + m} {{\n"
                        f"        {fam}{n + m} {{ v: bounded_int::{op}(self.v, rhs.v) }}\n    }}\n}}"
                    )
    for n in range(1, min(NW, NT) + 1):
        o.append(
            f"pub impl W{n}Mul of WideMul<W{n}> {{\n    type Output = T{n};\n    #[inline(always)]\n"
            f"    fn mul(self: W{n}, rhs: Fixed) -> T{n} {{\n"
            f"        T{n} {{ v: bounded_int::mul(self.v, rhs.raw) }}\n    }}\n}}"
        )
        o.append(
            f"pub impl W{n}Lift of WideLift<W{n}> {{\n    type Output = T{n};\n    #[inline(always)]\n"
            f"    fn lift(self: W{n}) -> T{n} {{\n        T{n} {{ v: upcast("
            f"bounded_int::mul::<_, UnitInt<{h(ONE)}>>(self.v, {h(ONE)})) }}\n    }}\n}}"
        )
    for n in range(1, NW + 1):
        o.append(
            f"pub impl W{n}Sqrt of WideSqrt<W{n}> {{\n    #[inline(always)]\n"
            f"    fn sqrt(self: W{n}) -> Fixed {{\n"
            f"        Fixed {{ raw: "
            + (f"sqrt_w{n}(self.v)" if n <= 3 else "sqrt_acc(upcast(self.v))")
            + " }\n    }\n}"
        )
        o.append(
            f"pub impl W{n}IntoAcc of Into<W{n}, Acc> {{\n    #[inline(always)]\n"
            f"    fn into(self: W{n}) -> Acc {{\n        Acc {{ v: upcast(self.v) }}\n    }}\n}}"
        )
    return "\n".join(o) + "\n"


def fmt(text, name):
    """Formats through `scarb fmt` so that the committed file passes `scarb fmt --check`."""
    tmp = OUT / f"gen_tmp_{name}"
    tmp.write_text(text)
    try:
        subprocess.run(["scarb", "fmt", str(tmp)], cwd=ROOT, check=True, capture_output=True)
        return tmp.read_text()
    finally:
        tmp.unlink()


def main():
    check = "--check" in sys.argv[1:]
    if shutil.which("scarb") is None:
        sys.exit("scarb is required (the output is formatted with `scarb fmt`)")
    OUT.mkdir(parents=True, exist_ok=True)
    files = (
        (OUT / "bounded.cairo", LIB_BOUNDED),
        (OUT / "acc.cairo", acc_file()),
        (ALT / "fixed.cairo", alt_fixed_file()),
    )
    for path, text in files:
        text = fmt(text, path.name)
        if check:
            if not path.exists() or path.read_text() != text:
                sys.exit(f"{path.relative_to(ROOT)} is stale: run scripts/gen_bounded.py")
        else:
            path.write_text(text)
    names = ", ".join(str(path.relative_to(ROOT)) for path, _ in files)
    print(("up to date: " if check else "wrote ") + names)


if __name__ == "__main__":
    main()
