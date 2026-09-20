#!/usr/bin/env python3
"""Runs the benchmark suite and maintains the gas snapshot.

usage:
  scripts/bench.py run   [FILTER]   run snforge twice (sierra-gas + cairo-steps), write
                                    results/raw/*.txt, results/results.csv, results/results.md
  scripts/bench.py snapshot [FILTER] same as `run`, then (re)write ./gas-snapshot
  (add --tag NAME to write results/results.NAME.* instead of results/results.*, for side experiments)
  scripts/bench.py check [FILTER]   same as `run`, then diff against ./gas-snapshot; exit 1 on any change
                                    (use --tolerance PCT to allow small drifts)

Convention: a benchmark `X` is a pair of tests `X__base` / `X__op`; its cost is op - base for every
metric. A test without the `__base`/`__op` suffix is reported as-is (absolute cost, test overhead
included).
"""
import argparse
import csv
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
RAW = os.path.join(ROOT, "results", "raw")
SNAPSHOT = os.path.join(ROOT, "gas-snapshot")
METRICS = ["l2_gas", "steps", "range_check", "bitwise", "other_builtins", "memory_holes"]

PASS_RE = re.compile(r"^\[(PASS|FAIL)\] (\S+)(?: \(l1_gas: ~(\d+), l1_data_gas: ~(\d+), l2_gas: ~(\d+)\))?")


TAG = ""


def run_snforge(mode, flt):
    cmd = ["snforge", "test", "--detailed-resources", "--tracked-resource", mode]
    if flt:
        cmd.insert(2, flt)
    print("$", " ".join(cmd), file=sys.stderr)
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    out = p.stdout + p.stderr
    os.makedirs(RAW, exist_ok=True)
    suffix = (("." + re.sub(r"\W+", "_", flt)) if flt else "") + (("." + TAG) if TAG else "")
    with open(os.path.join(RAW, f"snforge.{mode}{suffix}.txt"), "w") as f:
        f.write("$ " + " ".join(cmd) + "\n" + out)
    if p.returncode != 0:
        tail = "\n".join(out.splitlines()[-25:])
        sys.exit(f"snforge failed (mode={mode}):\n{tail}")
    return out


def parse(out):
    """-> {test_name: {metric: int}}"""
    res, cur = {}, None
    for line in out.splitlines():
        m = PASS_RE.match(line)
        if m:
            cur = res.setdefault(m.group(2).split("::", 1)[1] if "::" in m.group(2) else m.group(2), {})
            if m.group(5):
                cur["l2_gas_line"] = int(m.group(5))
            continue
        if cur is None:
            continue
        s = line.strip()
        if s.startswith("sierra gas:"):
            cur["sierra_gas"] = int(s.split(":")[1])
        elif s.startswith("steps:"):
            cur["steps"] = int(s.split(":")[1])
        elif s.startswith("memory holes:"):
            cur["memory_holes"] = int(s.split(":")[1])
        elif s.startswith("builtins:"):
            cur["range_check"] = cur["bitwise"] = cur["other_builtins"] = 0
            for name, n in re.findall(r"Builtin\((\w+)\): (\d+)", s):
                key = name if name in ("range_check", "bitwise") else "other_builtins"
                cur[key] += int(n)
    return res


def collect(flt):
    gas = parse(run_snforge("sierra-gas", flt))
    steps = parse(run_snforge("cairo-steps", flt))
    tests = {}
    for name, g in gas.items():
        s = steps.get(name, {})
        tests[name] = {
            "l2_gas": g.get("sierra_gas", g.get("l2_gas_line", 0)),
            "steps": s.get("steps", 0),
            "range_check": s.get("range_check", 0),
            "bitwise": s.get("bitwise", 0),
            "other_builtins": s.get("other_builtins", 0),
            "memory_holes": s.get("memory_holes", 0),
        }
    rows = {}
    for name, t in tests.items():
        if name.endswith("__op"):
            base = tests.get(name[: -len("__op")] + "__base")
            if base is None:
                sys.exit(f"missing baseline for {name}")
            rows[name[: -len("__op")]] = {k: t[k] - base[k] for k in METRICS}
        elif not name.endswith("__base") and not name.startswith("correctness"):
            rows[name + " (abs)"] = dict(t)
    return rows


def write_reports(rows):
    os.makedirs(os.path.join(ROOT, "results"), exist_ok=True)
    stem = "results." + TAG if TAG else "results"
    with open(os.path.join(ROOT, "results", stem + ".csv"), "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["bench"] + METRICS)
        for name in sorted(rows):
            w.writerow([name] + [rows[name][k] for k in METRICS])
    with open(os.path.join(ROOT, "results", stem + ".md"), "w") as f:
        f.write("| bench | l2_gas (sierra gas) | steps | range_check | bitwise | other builtins | memory holes |\n")
        f.write("|---|---:|---:|---:|---:|---:|---:|\n")
        for name in sorted(rows):
            r = rows[name]
            f.write(f"| `{name}` | " + " | ".join(str(r[k]) for k in METRICS) + " |\n")


def fmt_snapshot(rows):
    lines = ["# bench: l2_gas steps range_check bitwise other_builtins memory_holes"]
    for name in sorted(rows):
        lines.append(f"{name}: " + " ".join(str(rows[name][k]) for k in METRICS))
    return "\n".join(lines) + "\n"


def read_snapshot():
    snap = {}
    with open(SNAPSHOT) as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            name, vals = line.rsplit(":", 1)
            snap[name] = dict(zip(METRICS, map(int, vals.split())))
    return snap


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["run", "snapshot", "check"])
    ap.add_argument("filter", nargs="?", default="")
    ap.add_argument("--tolerance", type=float, default=0.0, help="allowed relative drift in %% (check)")
    ap.add_argument("--tag", default="", help="suffix for the result files (experiments), e.g. --tag inline-avoid")
    a = ap.parse_args()
    global TAG
    TAG = a.tag
    rows = collect(a.filter)
    write_reports(rows)
    print(f"{len(rows)} benchmarks -> results/results.md, results/results.csv", file=sys.stderr)
    if a.cmd == "snapshot":
        if a.filter:
            sys.exit("refusing to write a partial snapshot (remove the filter)")
        with open(SNAPSHOT, "w") as f:
            f.write(fmt_snapshot(rows))
        print("wrote gas-snapshot", file=sys.stderr)
    elif a.cmd == "check":
        snap = read_snapshot()
        bad = 0
        for name in sorted(set(rows) | (set(snap) if not a.filter else set())):
            new, old = rows.get(name), snap.get(name)
            if new is None or old is None:
                print(f"{'ADDED  ' if old is None else 'REMOVED'} {name}")
                bad += 1
                continue
            for k in ("l2_gas", "steps", "range_check", "bitwise"):
                if new[k] != old[k]:
                    drift = 100.0 * (new[k] - old[k]) / old[k] if old[k] else float("inf")
                    if abs(drift) > a.tolerance:
                        print(f"CHANGED {name}: {k} {old[k]} -> {new[k]} ({drift:+.2f}%)")
                        bad += 1
        if bad:
            sys.exit(f"gas snapshot mismatch: {bad} difference(s). Run `scripts/bench.py snapshot` to accept.")
        print("gas snapshot OK", file=sys.stderr)


if __name__ == "__main__":
    main()
