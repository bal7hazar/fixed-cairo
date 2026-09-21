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
    ]),
]

GLAM = [
    Table("`Vec2`", [
        ("`add`", "vec2::add"),
        ("`mul_scalar`", "vec2::mul_scalar"),
        ("`dot`", "vec2::dot"),
        ("`perp_dot`", "vec2::perp_dot"),
        ("`length`", "vec2::length"),
        ("`normalize`", "vec2::normalize"),
        ("`rotate`", "vec2::rotate"),
        ("`from_angle`", "vec2::from_angle"),
        ("`to_angle`", "vec2::to_angle"),
    ]),
    Table("`Vec3`", [
        ("`add`", "vec3::add"),
        ("`mul_scalar`", "vec3::mul_scalar"),
        ("`dot`", "vec3::dot"),
        ("`cross`", "vec3::cross"),
        ("`length`", "vec3::length"),
        ("`normalize`", "vec3::normalize"),
        ("`distance`", "vec3::distance"),
        ("`lerp`", "vec3::lerp"),
        ("`reflect`", "vec3::reflect"),
        ("`angle_between`", "vec3::angle_between"),
    ]),
    Table("`Vec4`", [
        ("`add`", "vec4::add"),
        ("`mul_scalar`", "vec4::mul_scalar"),
        ("`dot`", "vec4::dot"),
        ("`length`", "vec4::length"),
        ("`normalize`", "vec4::normalize"),
        ("`lerp`", "vec4::lerp"),
    ]),
    Table("`Mat2`", [
        ("`mul_vec2`", "mat2::mul_vec2"),
        ("`mul_mat2`", "mat2::mul_mat2"),
        ("`determinant`", "mat2::determinant"),
        ("`inverse`", "mat2::inverse"),
        ("`transpose`", "mat2::transpose"),
        ("`from_angle`", "mat2::from_angle"),
    ]),
    Table("`Mat3`", [
        ("`mul_vec3`", "mat3::mul_vec3"),
        ("`mul_mat3`", "mat3::mul_mat3"),
        ("`determinant`", "mat3::determinant"),
        ("`inverse`", "mat3::inverse"),
        ("`transpose`", "mat3::transpose"),
        ("`from_quat`", "mat3::from_quat"),
        ("`from_axis_angle`", "mat3::from_axis_angle"),
        ("`from_rotation_z`", "mat3::from_rotation_z"),
    ]),
    Table("`Mat4`", [
        ("`mul_vec4`", "mat4::mul_vec4"),
        ("`mul_mat4`", "mat4::mul_mat4"),
        ("`transform_point3`", "mat4::transform_point3"),
        ("`project_point3`", "mat4::project_point3"),
        ("`determinant`", "mat4::determinant"),
        ("`inverse`", "mat4::inverse"),
        ("`transpose`", "mat4::transpose"),
        ("`from_quat`", "mat4::from_quat"),
        ("`from_rotation_translation`", "mat4::from_rotation_translation"),
        ("`look_at_rh`", "mat4::look_at_rh"),
    ]),
    Table("`Quat`", [
        ("`mul_quat`", "quat::mul_quat"),
        ("`mul_vec3`", "quat::mul_vec3"),
        ("`conjugate`", "quat::conjugate"),
        ("`normalize`", "quat::normalize"),
        ("`slerp`", "quat::slerp"),
        ("`lerp`", "quat::lerp"),
        ("`from_axis_angle`", "quat::from_axis_angle"),
        ("`from_rotation_arc`", "quat::from_rotation_arc"),
        ("`from_mat3`", "quat::from_mat3"),
        ("`to_axis_angle`", "quat::to_axis_angle"),
    ]),
    Table("`Affine2`", [
        ("`transform_point2`", "affine2::transform_point2"),
        ("`transform_vector2`", "affine2::transform_vector2"),
        ("`mul_affine2`", "affine2::mul_affine2"),
        ("`inverse`", "affine2::inverse"),
        ("`from_angle_translation`", "affine2::from_angle_translation"),
    ]),
    Table("`Affine3`", [
        ("`transform_point3`", "affine3::transform_point3"),
        ("`transform_vector3`", "affine3::transform_vector3"),
        ("`mul_affine3`", "affine3::mul_affine3"),
        ("`inverse`", "affine3::inverse"),
        ("`inverse_rigid`", "affine3::inverse_rigid"),
        ("`from_rotation_translation`", "affine3::from_rotation_translation"),
        ("`look_to_rh`", "affine3::look_to_rh"),
    ]),
    Table("Euler angles (`EulerRot`, worst case: generic order)", [
        ("`Quat::from_euler`", "euler::quat_from_euler"),
        ("`Quat::to_euler`", "euler::quat_to_euler"),
        ("`Mat3::from_euler`", "euler::mat3_from_euler"),
        ("`Mat3::to_euler`", "euler::mat3_to_euler"),
        ("`Mat4::from_euler`", "euler::mat4_from_euler"),
    ]),
    Table("Camera (`glam::camera`)", [
        ("`rh::proj::opengl::perspective`", "camera::rh_opengl_perspective"),
        ("`rh::proj::vulkan::perspective`", "camera::rh_vulkan_perspective"),
        ("`rh::proj::vulkan::perspective_infinite_reverse`",
         "camera::rh_vulkan_perspective_infinite_reverse"),
        ("`rh::proj::opengl::orthographic`", "camera::rh_opengl_orthographic"),
        ("`rh::proj::opengl::frustum`", "camera::rh_opengl_frustum"),
        ("`rh::view::look_at_mat4`", "camera::rh_view_look_at_mat4"),
        ("`rh::view::look_to_mat4`", "camera::rh_view_look_to_mat4"),
    ]),
]

# A module without a snapshot yet (still being ported) is skipped without error.
GLAMX = [
    Table("`Pose3`", [
        ("`mul_pose3`", "pose3::mul_pose3"),
        ("`inv_mul`", "pose3::inv_mul"),
        ("`inverse`", "pose3::inverse"),
        ("`transform_point`", "pose3::transform_point"),
        ("`transform_vector`", "pose3::transform_vector"),
        ("`inverse_transform_point`", "pose3::inverse_transform_point"),
        ("`nlerp`", "pose3::nlerp"),
        ("`to_mat4`", "pose3::to_mat4"),
    ], optional=True),
    Table("`Pose2`", [
        ("`mul`", "pose2::mul"),
        ("`inv_mul`", "pose2::inv_mul"),
        ("`inverse`", "pose2::inverse"),
        ("`transform_point`", "pose2::transform_point"),
        ("`transform_vector`", "pose2::transform_vector"),
    ], optional=True),
    Table("`Rot2`", [
        ("`mul`", "rot2::mul"),
        ("`mul_vec2`", "rot2::mul_vec2"),
        ("`inverse`", "rot2::inverse"),
        ("`from_angle`", "rot2::from_angle"),
        ("`angle`", "rot2::angle"),
        ("`normalize`", "rot2::normalize"),
        ("`lerp`", "rot2::lerp"),
        ("`slerp`", "rot2::slerp"),
    ], optional=True),
    Table("`SdpMatrix3`", [
        ("`mul_vec`", "sdp::mul_vec"),
        ("`mul_mat`", "sdp::mul_mat"),
        ("`add`", "sdp::add"),
        ("`quadform`", "sdp::quadform"),
        ("`inverse_regular`", "sdp::inverse_regular"),
        ("`from_rotated_diagonal`", "sdp::from_rotated_diagonal"),
    ], optional=True),
]

# Root README.  Figures of the cubit-style sign-magnitude scalar: docs/research/00-synthesis.md
# section 2 (prototype measurements, same operations).
CUBIT_SOURCE = "docs/research/00-synthesis.md"
CUBIT = [
    ("`+`", "fixed::add", 4050),
    ("`*`", "fixed::mul", 2970),
    ("`/`", "fixed::div", 2970),
    ("`Vec3::dot`", "vec3::dot", 15750),
    ("`Mat3 * Mat3`", "mat3::mul_mat3", 134250),
    ("`Mat4 * Mat4`", "mat4::mul_mat4", 335800),
    ("`Quat * Quat`", "quat::mul_quat", 87780),
    ("`Quat * Vec3`", "quat::mul_vec3", 115910),
    ("`sin`", "trig::sin__small", 128670),
    ("`sin_cos`", "trig::sin_cos__small", 263610),
]

GLANCE = [
    ("`fixed`", "`+`", "fixed::add"),
    ("`fixed`", "`*`", "fixed::mul"),
    ("`fixed`", "`/`", "fixed::div"),
    ("`fixed`", "`sqrt`", "fixed::sqrt"),
    ("`fixed`", "`dot3`", "wide::dot3"),
    ("`fixed`", "`sin_cos`", "trig::sin_cos__small"),
    ("`fixed`", "`atan2`", "trig::atan2__quadrant1"),
    ("`fixed`", "`exp`", "exp::exp__small"),
    ("`fixed`", "`ln`", "exp::ln__large"),
    ("`glam`", "`Vec3::normalize`", "vec3::normalize"),
    ("`glam`", "`Vec3::cross`", "vec3::cross"),
    ("`glam`", "`Mat3 * Vec3`", "mat3::mul_vec3"),
    ("`glam`", "`Mat4 * Mat4`", "mat4::mul_mat4"),
    ("`glam`", "`Mat4::inverse`", "mat4::inverse"),
    ("`glam`", "`Quat * Quat`", "quat::mul_quat"),
    ("`glam`", "`Quat::slerp`", "quat::slerp"),
    ("`glam`", "`Affine3::transform_point3`", "affine3::transform_point3"),
    ("`glamx`", "`Pose3::transform_point`", "pose3::transform_point"),
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


def ratio(a, b):
    return f"{a / b:.1f}x"


def render_package(tables, snaps, errors):
    return "\n".join([caption("../../"), ""] + op_table(tables, snaps, errors, "###")).rstrip()


def render_root(snaps, errors):
    out = [caption(""), "", "### Against a cubit-style scalar", ""]
    out += [
        f"Same operations on a sign-magnitude `{{mag, sign}}` scalar (prototype figures of "
        f"[`{CUBIT_SOURCE}`]({CUBIT_SOURCE})) and on `glam.cairo`, in Sierra gas.", "",
        "| op | cubit-style | glam.cairo | speed-up |", "|---|---:|---:|---:|",
    ]
    for label, key, cubit in CUBIT:
        r = snaps.get(key, errors)
        if r is not None:
            out.append(
                f"| {label} | {group(cubit)} | {group(r['l2_gas'])} | {ratio(cubit, r['l2_gas'])} |"
            )
    out += ["", "### Headline operations", "", "| package | op | l2 gas | steps | range checks |",
            "|---|---|---:|---:|---:|"]
    for pkg, label, key in GLANCE:
        if pkg == "`glamx`" and not snaps.has(key):
            continue
        r = snaps.get(key, errors)
        if r is not None:
            out.append(
                f"| {pkg} | {label} | {group(r['l2_gas'])} | {group(r['steps'])} | "
                f"{group(r['range_check'])} |"
            )
    out += ["", "Full tables: [`fixed`](packages/fixed#gas), [`glam`](packages/glam#gas), "
            "[`glamx`](packages/glamx#gas)."]
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
        "packages/glam/README.md": render_package(GLAM, snaps, errors),
        "packages/glamx/README.md": render_package(GLAMX, snaps, errors),
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
