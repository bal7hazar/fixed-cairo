#!/usr/bin/env python3
"""Generate the gas tables of the READMEs from the committed snapshots (gas/*.snap).

usage:
  scripts/gas_tables.py           rewrite the tables in the READMEs
  scripts/gas_tables.py --check   exit 1 if a README is stale (CI and scripts/check.sh)

Each README carries one generated region between `<!-- gas:begin -->` and `<!-- gas:end -->`.
What goes into it is the curated data below: a list of headline operations per table, each one a
bench name as it appears in the snapshots (`bench_<module>::<name>`, written `<module>::<name>`
here).  A listed bench that is missing from an existing snapshot is an error, so the lists cannot
rot silently when a bench is renamed; a table whose snapshot does not exist yet is skipped when it
is marked optional (modules that are still being ported).  `alt_*` and `composite_*` benches are
never listed: they are the losing variants and the composed references of the benches.

Numbers are the net cost of one call (`X__op - X__base`, see scripts/bench.py), so they are
deterministic; the output is a pure function of gas/*.snap and .tool-versions.  Dependency free.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAS = ROOT / "gas"
BEGIN = "<!-- gas:begin -->"
END = "<!-- gas:end -->"
METRICS = ["l2_gas", "steps", "range_check", "bitwise", "other_builtins"]
EXCLUDED_PREFIXES = ("alt_", "composite_")


class Table:
    """One table: a title, and the (label, `module::name`) rows in display order."""

    def __init__(self, title, rows, optional=False):
        self.title = title
        self.rows = rows
        self.optional = optional


# ------------------------------------------------------------------------------------------
# Curated data.  Labels are Markdown (code spans); the bench name is the snapshot key without
# its `bench_` prefix.  Benches with a `__variant` suffix are the representative input of an
# input-independent or worst-case function.
# ------------------------------------------------------------------------------------------

FIXED = [
    Table("Scalar (`fixed::fixed`)", [
        ("`+` / `-`", "fixed::add"),
        ("`*`", "fixed::mul"),
        ("`/`", "fixed::div"),
        ("`%`", "fixed::rem"),
        ("`<`", "fixed::lt"),
        ("`sqrt`", "fixed::sqrt"),
        ("`recip`", "fixed::recip"),
        ("`floor`", "fixed::floor"),
        ("`round`", "fixed::round"),
        ("`lerp`", "fixed::lerp"),
        ("`smoothstep`", "fixed::smoothstep"),
        ("`powi(5)`", "fixed::powi_5"),
    ]),
    Table("Fused kernels (`fixed::wide`)", [
        ("`dot2`", "wide::dot2"),
        ("`dot3`", "wide::dot3"),
        ("`dot4`", "wide::dot4"),
        ("`mul_add`", "wide::mul_add"),
        ("`mul_sub`", "wide::mul_sub"),
        ("`det3`", "wide::det3"),
        ("`norm3`", "wide::norm3"),
        ("`distance3`", "wide::distance3"),
        ("`normalize3`", "wide::normalize3"),
        ("`Recip::new`", "wide::recip_new"),
        ("`Recip::mul`", "wide::recip_mul"),
    ]),
    Table("Trigonometry (`fixed::trig`)", [
        ("`sin`", "trig::sin__small"),
        ("`cos`", "trig::cos__small"),
        ("`sin_cos`", "trig::sin_cos__small"),
        ("`tan`", "trig::tan__small"),
        ("`atan`", "trig::atan__small"),
        ("`atan2`", "trig::atan2__quadrant1"),
        ("`asin`", "trig::asin__small"),
        ("`acos`", "trig::acos__small"),
        ("`acos_clamped`", "trig::acos_clamped__outside"),
        ("`to_radians`", "trig::to_radians"),
    ]),
    Table("Exponentials (`fixed::exp`)", [
        ("`exp`", "exp::exp__small"),
        ("`exp2`", "exp::exp2__small"),
        ("`exp_m1`", "exp::exp_m1"),
        ("`ln`", "exp::ln__large"),
        ("`log2`", "exp::log2__large"),
        ("`log10`", "exp::log10"),
        ("`ln_1p`", "exp::ln_1p"),
        ("`log`", "exp::log"),
        ("`powf`", "exp::powf__positive"),
        ("`sinh`", "exp::sinh__mid"),
        ("`cosh`", "exp::cosh__mid"),
        ("`tanh`", "exp::tanh__small"),
        ("`sinhc`", "exp::sinhc__large"),
        ("`coshc`", "exp::coshc"),
    ]),
]

GLANCE = [
    ("`+`", "fixed::add"),
    ("`*`", "fixed::mul"),
    ("`/`", "fixed::div"),
    ("`sqrt`", "fixed::sqrt"),
    ("`dot3`", "wide::dot3"),
    ("`sin_cos`", "trig::sin_cos__small"),
    ("`atan2`", "trig::atan2__quadrant1"),
    ("`exp`", "exp::exp__small"),
    ("`ln`", "exp::ln__large"),
]


# ------------------------------------------------------------------------------------------


class Snapshots:
    def __init__(self):
        self.files = {}  # module -> {bench name (without `bench_<module>::`): {metric: int}}
        for path in sorted(GAS.glob("*.snap")):
            rows = {}
            for line in path.read_text().splitlines():
                if line.startswith("#") or not line.strip():
                    continue
                name, vals = line.rsplit(":", 1)
                rows[name.split("::", 1)[1]] = dict(zip(METRICS, map(int, vals.split())))
            self.files[path.stem] = rows

    def has(self, key):
        return key.split("::", 1)[0] in self.files

    def get(self, key, errors):
        module, name = key.split("::", 1)
        if name.startswith(EXCLUDED_PREFIXES):
            errors.append(f"{key}: alt_* and composite_* benches are never listed")
            return None
        if module not in self.files:
            errors.append(f"{key}: no snapshot gas/{module}.snap")
            return None
        row = self.files[module].get(name)
        if row is None:
            errors.append(f"{key}: bench_{module}::{name} is not in gas/{module}.snap")
        return row


def group(n):
    s = str(n)
    parts = []
    while len(s) > 3:
        parts.insert(0, s[-3:])
        s = s[:-3]
    return " ".join([s] + parts)


def toolchain():
    tools = []
    for line in (ROOT / ".tool-versions").read_text().splitlines():
        fields = line.split("#")[0].split()
        if len(fields) >= 2:
            tools.append(f"{fields[0]} {fields[1]}")
    return ", ".join(tools)


def caption(prefix):
    return (
        f"Sierra gas (`l2 gas`, what a transaction pays) and prover cost (steps, range checks) "
        f"of one call, net of the test overhead (`X__op - X__base`, see "
        f"[`scripts/bench.py`]({prefix}scripts/bench.py)), measured with {toolchain()} "
        f"(`.tool-versions`). Source of truth: `gas/*.snap`; this region is generated by "
        f"`scripts/gas_tables.py`, do not edit it."
    )


def op_table(tables, snaps, errors, heading):
    out = []
    for t in tables:
        rows = []
        for label, key in t.rows:
            if t.optional and not snaps.has(key):
                continue
            r = snaps.get(key, errors)
            if r is not None:
                rows.append(
                    f"| {label} | {group(r['l2_gas'])} | {group(r['steps'])} | "
                    f"{group(r['range_check'])} |"
                )
        if not rows:
            continue
        out += [
            f"{heading} {t.title}", "",
            "| op | l2 gas | steps | range checks |", "|---|---:|---:|---:|", *rows, "",
        ]
    return out


def render_package(tables, snaps, errors):
    return "\n".join([caption("../../"), ""] + op_table(tables, snaps, errors, "###")).rstrip()


def render_root(snaps, errors):
    out = [caption(""), "", "### Headline operations", "", "| op | l2 gas | steps | range checks |",
           "|---|---:|---:|---:|"]
    for label, key in GLANCE:
        r = snaps.get(key, errors)
        if r is not None:
            out.append(
                f"| {label} | {group(r['l2_gas'])} | {group(r['steps'])} | "
                f"{group(r['range_check'])} |"
            )
    out += ["", "Full tables: [`packages/fixed`](packages/fixed#gas)."]
    return "\n".join(out)


def replace_region(path, body):
    text = path.read_text()
    b, e = text.find(BEGIN), text.find(END)
    if b < 0 or e < b or text.count(BEGIN) != 1 or text.count(END) != 1:
        sys.exit(f"{path.relative_to(ROOT)}: needs exactly one {BEGIN} ... {END} region")
    return text[: b + len(BEGIN)] + "\n\n" + body + "\n\n" + text[e:]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--check", action="store_true", help="exit 1 if a README is stale")
    args = ap.parse_args()

    snaps, errors = Snapshots(), []
    outputs = {
        "README.md": render_root(snaps, errors),
        "packages/fixed/README.md": render_package(FIXED, snaps, errors),
    }
    if errors:
        sys.exit("gas_tables.py: the curated lists do not match gas/*.snap:\n  " +
                 "\n  ".join(sorted(set(errors))))

    stale = []
    for rel, body in outputs.items():
        path = ROOT / rel
        new = replace_region(path, body)
        if new != path.read_text():
            stale.append(rel)
            if not args.check:
                path.write_text(new)
    if args.check:
        if stale:
            sys.exit("stale gas tables: " + ", ".join(stale) +
                     "\nrun `python3 scripts/gas_tables.py` and commit the result")
        print("gas tables are up to date")
    else:
        print("rewrote: " + (", ".join(stale) if stale else "nothing (already up to date)"))


if __name__ == "__main__":
    main()
