#!/usr/bin/env python3
"""Generate the glam-rs 0.33.8 versus glam-cairo public API inventory.

The parser is intentionally dependency free.  It is not a Rust or Cairo parser: it masks
comments, finds balanced brace blocks, and recognizes the small set of declarations used by the
two projects.  The Rust inventory is embedded in the generated Markdown so the normal CI check
does not need a glam-rs checkout.
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


VERSION = "0.33.8"
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "API_PARITY.md"
INVENTORY_START = "<!-- api-parity-rust-inventory\n"
INVENTORY_END = "\napi-parity-rust-inventory -->"

TYPE_FILES = {
    "src/f32/vec2.rs": "Vec2",
    "src/f32/vec3.rs": "Vec3",
    "src/f32/affine2.rs": "Affine2",
    "src/f32/affine3.rs": "Affine3",
    "src/f32/mat3.rs": "Mat3",
    "src/f32/scalar/vec4.rs": "Vec4",
    "src/f32/scalar/quat.rs": "Quat",
    "src/f32/scalar/mat2.rs": "Mat2",
    "src/f32/scalar/mat4.rs": "Mat4",
    "src/bool/bvec2.rs": "BVec2",
    "src/bool/bvec3.rs": "BVec3",
    "src/bool/bvec4.rs": "BVec4",
    "src/i32/ivec2.rs": "IVec2",
    "src/i32/ivec3.rs": "IVec3",
    "src/i32/ivec4.rs": "IVec4",
    "src/u32/uvec2.rs": "UVec2",
    "src/u32/uvec3.rs": "UVec3",
    "src/u32/uvec4.rs": "UVec4",
    "src/euler.rs": "EulerRot",
    "src/f32/float.rs": "Fixed",
    "src/f32/math.rs": "Fixed",
}

PORT_TYPES = (
    "Affine2", "Affine3", "BVec2", "BVec3", "BVec4", "EulerRot", "Fixed", "IVec2",
    "IVec3", "IVec4", "Mat2", "Mat3", "Mat4", "Quat", "UVec2", "UVec3", "UVec4",
    "Vec2", "Vec3", "Vec4",
)
VECTOR_TYPES = tuple(t for t in PORT_TYPES if re.fullmatch(r"[BIU]?Vec[234]", t))

# Only impls that are part of the requested operator/conversion API.  Reference variants are
# deliberately folded into the owned form because Cairo values are Copy and passed by value.
RUST_IMPL_TRAITS = {
    "Add", "AddAssign", "AsMut", "AsRef", "BitAnd", "BitAndAssign", "BitOr",
    "BitOrAssign", "BitXor", "BitXorAssign", "Default", "Deref", "DerefMut", "Display",
    "Div", "DivAssign", "From", "Index", "IndexMut", "Mul", "MulAssign", "Neg", "Not",
    "Product", "Rem", "RemAssign", "Shl", "ShlAssign", "Shr", "ShrAssign", "Sub",
    "SubAssign", "Sum",
}

CAIRO_CORE_TRAITS = {
    "Add", "AddAssign", "BitAnd", "BitAndAssign", "BitNot", "BitOr", "BitOrAssign",
    "BitXor", "BitXorAssign", "Default", "Div", "DivAssign", "IndexView", "Into", "Mul",
    "MulAssign", "Neg", "Not", "Rem", "RemAssign", "Shl", "ShlAssign", "Shr", "ShrAssign",
    "Sub", "SubAssign", "TryInto",
}


@dataclass(frozen=True, order=True)
class Item:
    owner: str
    kind: str
    name: str
    source: str = ""

    @property
    def key(self) -> tuple[str, str, str]:
        return (self.owner, self.kind, self.name)

    def as_json(self) -> dict[str, str]:
        return {"owner": self.owner, "kind": self.kind, "name": self.name, "source": self.source}


@dataclass(frozen=True)
class Rule:
    owner: re.Pattern[str]
    item: re.Pattern[str]
    status: str
    reason: str
    replacement: str = ""


def rule(owner: str, item: str, status: str, reason: str, replacement: str = "") -> Rule:
    return Rule(re.compile(owner), re.compile(item), status, reason, replacement)


# Classification happens only after a direct match is attempted.  Keep these rules explicit and
# reviewable: an unmatched Rust item that has no rule is genuinely missing.
RULES = (
    rule(r".*", r"(?:const:)?(?:NAN|INFINITY|NEG_INFINITY)$", "dropped",
         "NaN and infinity do not exist in the fixed-point scalar."),
    rule(r".*", r"(?:const:)?USES_(?:CORE_SIMD|NEON|SCALAR_MATH|SSE2|WASM_SIMD|WASM32_SIMD)$",
         "dropped", "SIMD/backend capability constants are outside the pure Cairo scope."),
    rule(r".*", r"(?:is_nan|is_nan_mask|is_finite|is_finite_mask)$", "dropped",
         "Fixed values are always finite and never NaN."),
    rule(r".*", r"(?:from_(?:cols_|rows_)?slice|write_(?:cols_)?to_slice)$", "dropped",
         "Slice APIs are deliberately omitted from fixed-size Cairo math types."),
    rule(r".*", r"map$", "dropped",
         "Generic callback mapping is omitted from the monomorphic Cairo API."),
    rule(r".*", r"as_(?:d(?:affine[23]|mat[234]|quat|vec[234])|i8vec[234]|u8vec[234]|i16vec[234]|u16vec[234]|i64vec[234]|u64vec[234]|isizevec[234]|usizevec[234])$",
         "dropped", "Only Fixed, i32 and u32 vector families are in scope."),
    rule(r".*", r"(?:from_mat3a(?:_minor)?|mul_vec3a|to_vec3a|project_point3a|transform_point3a|transform_vector3a)$",
         "dropped", "Aligned Mat3A/Vec3A APIs collapse into Mat3/Vec3."),
    rule(r".*", r"(?:as_vec3a|from_affine3a)$", "dropped",
         "Aligned SIMD types collapse into their unaligned Cairo type."),
    rule(r".*", r"impl:From<.*(?:Mat3A|Vec3A|BVec3A|BVec4A).*> for .*", "dropped",
         "Aligned SIMD types collapse into their unaligned Cairo type."),
    rule(r".*", r"impl:.*(?:Mat3A|Vec3A|Affine3A).*", "dropped",
         "Aligned SIMD types collapse into their unaligned Cairo type."),
    rule(r"Mat[234]", r"(?:col_mut|set_row)$", "dropped",
         "Cairo has no borrowed mutable element or row references."),
    rule(r".*", r"impl:(?:AsRef|AsMut)<.*", "dropped",
         "Borrowed slice views are deliberately omitted."),
    rule(r".*", r"impl:(?:Sum|Product)(?:<.*)?", "dropped",
         "Iterator Sum/Product traits are deliberately omitted."),
    rule(r".*", r"impl:Display(?:<.*)?", "dropped", "Display is deliberately omitted."),
    rule(r".*", r"impl:Deref(?:Mut)?(?:<.*)?", "dropped",
         "Deref-based array views are deliberately omitted."),
    rule(r"[BIU]Vec[234]", r"impl:Bit(?:And|Or|Xor)Assign<.*>", "dropped",
         "Cairo core has no bitwise assignment traits."),
    rule(r"[IU]Vec[234]", r"impl:Bit(?:And|Or|Xor)<(?:i32|u32)>", "dropped",
         "Scalar bit operators are expressed by splatting the scalar first."),
    rule(r"[IU]Vec[234]", r"impl:(?:Shl|Shr)Assign<.*>", "dropped",
         "Cairo has no shift-assignment operator traits."),
    rule(r"[IU]Vec[234]", r"impl:(?:Shl|Shr)<(?:i8|i16|i32|i64|u8|u16|u64|[IU]Vec[234])>",
         "dropped", "Only the named u32 shift method is in the Cairo scope."),
    rule(r"[IU]Vec[234]", r"impl:(Shl|Shr)<u32>", "renamed",
         "Cairo has no shift operators; the u32 form is a named method.", r"\1"),
    rule(r"[IU]Vec[234]", r"impl:From<(?:I8|I16|U8|U16)Vec[234]> for [IU]Vec[234]", "dropped",
         "Integer vector widths other than i32/u32 are outside the port's scope."),
    rule(r".*", r"impl:(?:Index|IndexMut)<usize>", "renamed",
         "Cairo exposes read-only indexing through IndexView.", "impl:IndexView<usize>"),
    rule(r"(?:Vec|IVec|UVec)[234]", r"impl:(Add|Sub|Mul|Div|Rem)<(?:Fixed|i32|u32)>",
         "renamed", "Heterogeneous scalar operators are named *_scalar methods.", r"\1_scalar"),
    rule(r"(?:Vec|IVec|UVec)[234]", r"impl:(Add|Sub|Mul|Div|Rem)<(?:Vec|IVec|UVec)[234]> for (?:Fixed|i32|u32)",
         "dropped", "Scalar-on-the-left vector operators are deliberately omitted."),
    rule(r"Mat[234]", r"impl:(Mul|Div)<Fixed>", "renamed",
         "Heterogeneous scalar operators are named mul_scalar/div_scalar methods.", r"\1_scalar"),
    rule(r"Mat[234]", r"impl:(?:Mul|Div)<Mat[234]> for Fixed", "dropped",
         "Scalar-on-the-left matrix operators are deliberately omitted."),
    rule(r"Mat2", r"impl:Mul<Vec2>", "renamed",
         "Matrix/vector multiplication is a named method.", "mul_vec2"),
    rule(r"Mat3", r"impl:Mul<Vec3>", "renamed",
         "Matrix/vector multiplication is a named method.", "mul_vec3"),
    rule(r"Mat4", r"impl:Mul<Vec4>", "renamed",
         "Matrix/vector multiplication is a named method.", "mul_vec4"),
    rule(r"Quat", r"impl:(Mul|Div)<Fixed>", "renamed",
         "Quaternion/scalar operators are named mul_scalar/div_scalar methods.", r"\1_scalar"),
    rule(r"Quat", r"impl:Mul<Vec3>", "renamed",
         "Quaternion/vector multiplication is the named mul_vec3 method.", "mul_vec3"),
    rule(r"Affine2", r"impl:Mul<Mat3>", "renamed",
         "Heterogeneous multiplication is the named mul_mat3 method.", "mul_mat3"),
    rule(r"Mat3", r"impl:Mul<Affine2> for Mat3", "renamed",
         "Convert Affine2 to Mat3 before using homogeneous multiplication.", "Mul<Mat3>"),
    rule(r"Mat3", r"impl:MulAssign<Affine2> for Mat3", "renamed",
         "Cairo's assignment trait encodes the target as a generic parameter.",
         "MulAssign<Affine2>"),
    rule(r"Affine3", r"impl:Mul<Mat4>", "renamed",
         "Heterogeneous multiplication is the named mul_mat4 method.", "mul_mat4"),
    rule(r"Mat4", r"impl:Mul<Affine3> for Mat4", "renamed",
         "Heterogeneous multiplication is the named mul_affine3 method.", "mul_affine3"),
    rule(r"Mat4", r"impl:MulAssign<Affine3> for Mat4", "renamed",
         "Cairo's assignment trait encodes the target as a generic parameter.",
         "MulAssign<Affine3>"),
    rule(r"(?:I|U)Vec([234])", r"as_vec[234]$", "renamed",
         "The conversion is exposed as Into/From on the Fixed vector type.", "Into<Vec>"),
    rule(r"Mat3", r"look_(?:at|to)_(?:lh|rh)$", "renamed",
         "Deprecated matrix view constructors moved to the camera module.", "camera view function"),
    rule(r"camera::(?:lh|rh)::view", r"look_(at|to)_(mat3a|affine3a)$", "renamed",
         "Aligned Mat3A/Affine3A variants collapse into Mat3/Affine3.", r"look_\1"),
    rule(r"Mat4", r"(?:perspective|orthographic|frustum)_[a-z0-9_]+$", "renamed",
         "Deprecated Mat4 projection constructors moved to the camera module.", "camera module"),
)


def mask_comments(text: str) -> str:
    """Replace comments and strings by spaces while preserving offsets and newlines."""
    out = list(text)
    i = 0
    state = "code"
    quote = ""
    while i < len(text):
        pair = text[i:i + 2]
        if state == "code" and pair == "//":
            state = "line"
            out[i] = out[i + 1] = " "
            i += 2
            continue
        if state == "code" and pair == "/*":
            state = "block"
            out[i] = out[i + 1] = " "
            i += 2
            continue
        if state == "code" and text[i] == '"':
            state, quote = "string", text[i]
            out[i] = " "
            i += 1
            continue
        if state == "line":
            if text[i] == "\n":
                state = "code"
            else:
                out[i] = " "
            i += 1
            continue
        if state == "block":
            if pair == "*/":
                out[i] = out[i + 1] = " "
                state = "code"
                i += 2
            else:
                if text[i] != "\n":
                    out[i] = " "
                i += 1
            continue
        if state == "string":
            if text[i] == "\\" and i + 1 < len(text):
                if text[i] != "\n":
                    out[i] = " "
                if text[i + 1] != "\n":
                    out[i + 1] = " "
                i += 2
                continue
            if text[i] == quote:
                state = "code"
            if text[i] != "\n":
                out[i] = " "
            i += 1
            continue
        i += 1
    return "".join(out)


def closing_brace(text: str, opening: int) -> int:
    depth = 0
    for i in range(opening, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    raise ValueError(f"unclosed brace at byte {opening}")


def blocks(text: str, pattern: re.Pattern[str]) -> list[tuple[re.Match[str], int, int]]:
    found = []
    for match in pattern.finditer(text):
        opening = text.find("{", match.start(), match.end() + 2)
        if opening >= 0:
            found.append((match, opening, closing_brace(text, opening)))
    return found


def clean_type(value: str, self_type: str = "") -> str:
    value = re.sub(r"'[_a-zA-Z0-9]+", "", value)
    value = value.replace("crate::", "").replace("std::", "").replace("core::", "")
    value = re.sub(r"\bSelf\b", self_type, value)
    value = re.sub(r"\bself::", "", value)
    value = value.replace("f32", "Fixed")
    value = value.replace("&", "").replace("mut ", "")
    return re.sub(r"\s+", "", value).strip(",")


def owner_from_types(*values: str) -> str:
    joined = " ".join(values)
    candidates = [t for t in PORT_TYPES if re.search(rf"\b{re.escape(t)}\b", joined)]
    non_fixed = [t for t in candidates if t != "Fixed"]
    return non_fixed[0] if non_fixed else (candidates[0] if candidates else "Fixed")


def rust_impl_item(trait_expr: str, target: str, default_owner: str) -> Item | None:
    target = clean_type(target, default_owner)
    trait_expr = clean_type(trait_expr, target)
    match = re.match(r"([A-Za-z][A-Za-z0-9_:]*)(?:<(.*)>)?$", trait_expr)
    if not match:
        return None
    trait = match.group(1).split("::")[-1]
    if trait not in RUST_IMPL_TRAITS:
        return None
    arg = match.group(2)
    binary = trait in {
        "Add", "AddAssign", "BitAnd", "BitAndAssign", "BitOr", "BitOrAssign", "BitXor",
        "BitXorAssign", "Div", "DivAssign", "Mul", "MulAssign", "Rem", "RemAssign", "Shl",
        "ShlAssign", "Shr", "ShrAssign", "Sub", "SubAssign",
    }
    if binary and not arg:
        arg = target
    if trait == "Not" and target.startswith(("I", "U")):
        trait = "BitNot"
    if trait == "From":
        name = f"From<{arg}> for {target}"
    elif arg:
        name = f"{trait}<{arg}>"
        if target != default_owner and default_owner in arg:
            name += f" for {target}"
    else:
        name = trait
    if target == "Fixed" and arg and owner_from_types(arg) != "Fixed":
        owner = owner_from_types(arg)
    elif trait in ("From", "TryFrom"):
        owner = target if target in PORT_TYPES else owner_from_types(arg or "", target)
    elif target in PORT_TYPES:
        owner = target
    else:
        owner = owner_from_types(arg or "", default_owner)
    return Item(owner, "impl", name, "")


def parse_rust(glam_root: Path) -> list[Item]:
    src = glam_root / "src"
    if not src.is_dir():
        raise SystemExit(f"glam-rs source directory not found: {src}")
    items: set[Item] = set()
    impl_re = re.compile(r"(?m)^\s*impl(?:\s*<[^\n{]*>)?\s+(.+?)\s+for\s+([^\n{]+)\s*\{")

    for rel, owner in TYPE_FILES.items():
        path = glam_root / rel
        if not path.is_file():
            raise SystemExit(f"required glam-rs source missing: {path}")
        text = mask_comments(path.read_text())
        source = rel.removeprefix("src/")

        # Public inherent methods and constants. math.rs repeats its functions in cfg modules;
        # set semantics intentionally collapse those identical public surfaces.
        for match in re.finditer(r"\bpub\s+(?:const\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)", text):
            items.add(Item(owner, "method", match.group(1), source))
        for match in re.finditer(r"\bpub\s+const\s+([A-Z][A-Z0-9_]*)\s*:", text):
            items.add(Item(owner, "const", match.group(1), source))

        # FloatExt's methods are public through the public trait in src/float.rs, while this
        # selected scalar implementation contains non-pub method declarations.
        if rel == "src/f32/float.rs":
            for match in re.finditer(r"(?m)^\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", text):
                items.add(Item("Fixed", "method", match.group(1), source))

        for match in impl_re.finditer(text):
            item = rust_impl_item(match.group(1), match.group(2), owner)
            if item:
                items.add(Item(item.owner, item.kind, item.name, source))

    # One generic Rust swizzle trait is implemented by each scalar family in scope.  Expand it
    # into the nine concrete Cairo traits so the table reports parity per concrete type.
    swizzle = glam_root / "src/swizzles/vec_traits.rs"
    text = mask_comments(swizzle.read_text())
    trait_re = re.compile(r"pub\s+trait\s+Vec([234])Swizzles[^\{]*\{")
    for match, opening, end in blocks(text, trait_re):
        dim = match.group(1)
        names = set(re.findall(r"\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", text[opening + 1:end]))
        for prefix in ("Vec", "IVec", "UVec"):
            owner = f"{prefix}{dim}"
            for name in names:
                items.add(Item(owner, "method", name, "swizzles/vec_traits.rs"))

    # Camera functions belong to their module paths, not to Mat4. Track nested public modules by
    # brace containment; private generic helpers are intentionally excluded.
    camera_root = glam_root / "src/camera"
    for path in sorted(camera_root.rglob("*.rs")):
        rel = path.relative_to(glam_root / "src")
        text = mask_comments(path.read_text())
        base = ["camera", *rel.parent.parts[1:]]
        if path.stem not in ("mod", "camera_impl"):
            base.append(path.stem)
        module_re = re.compile(r"\bpub\s+mod\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\{")
        module_blocks = [(m.group(1), start, end) for m, start, end in blocks(text, module_re)]
        for match in re.finditer(r"\bpub\s+(?:const\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)", text):
            nested = [name for name, start, end in module_blocks if start < match.start() < end]
            owner = "::".join(base + nested)
            items.add(Item(owner, "function", match.group(1), str(rel)))
    return unique_items(items)


def cairo_file_owner(path: Path, package: str) -> str:
    rel = path.relative_to(ROOT / "packages" / package / "src")
    stem = path.stem
    if package == "fixed":
        return "fixed::wide" if stem == "wide" else "Fixed"
    if rel.parts[0] == "camera":
        parts = ["camera", *rel.parent.parts[1:]]
        if stem not in ("camera", "camera_impl", "lib"):
            parts.append(stem)
        return "::".join(parts)
    if rel.parts[0] == "swizzles" and len(rel.parts) > 1:
        return type_from_stem(stem)
    if stem == "euler":
        return "EulerRot"
    return type_from_stem(stem)


def type_from_stem(stem: str) -> str:
    special = {"bvec": "BVec", "ivec": "IVec", "uvec": "UVec", "vec": "Vec", "mat": "Mat"}
    match = re.fullmatch(r"([a-z]+)([234])", stem)
    if match and match.group(1) in special:
        return special[match.group(1)] + match.group(2)
    return {"quat": "Quat", "affine2": "Affine2", "affine3": "Affine3", "fixed": "Fixed",
            "trig": "Fixed", "exp": "Fixed"}.get(stem, stem)


def trait_owner(name: str, fallback: str) -> str:
    for owner in PORT_TYPES:
        if name.startswith(owner):
            return owner
    if name in ("FixedTrait", "TrigTrait", "ExpTrait"):
        return "Fixed"
    return fallback


def split_generics(value: str) -> list[str]:
    parts, start, depth = [], 0, 0
    for i, char in enumerate(value):
        if char in "<[(":
            depth += 1
        elif char in ">])":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(value[start:i].strip())
            start = i + 1
    parts.append(value[start:].strip())
    return [part for part in parts if part]


def cairo_impl_item(trait_expr: str, impl_name: str, body: str, fallback: str) -> Item | None:
    trait_expr = clean_type(trait_expr)
    match = re.match(r"([A-Za-z][A-Za-z0-9_]*)(?:<(.*)>)?$", trait_expr)
    if not match or match.group(1) not in CAIRO_CORE_TRAITS:
        return None
    trait, generic = match.group(1), match.group(2) or ""
    args = split_generics(generic)
    fn_match = re.search(r"\bfn\s+\w+\s*\(([^)]*)\)", body, re.S)
    signature = fn_match.group(1) if fn_match else ""
    owner = owner_from_types(impl_name, signature, generic)
    if owner == "Fixed" and fallback in PORT_TYPES:
        owner = fallback

    if trait in ("Into", "TryInto") and len(args) >= 2:
        source, target = args[0], args[1]
        owner = target if target in PORT_TYPES else owner_from_types(source, target)
        rust_trait = "From" if trait == "Into" else "TryFrom"
        return Item(owner, "impl", f"{rust_trait}<{source}> for {target}")
    if trait == "Default":
        target = args[0] if args else owner
        return Item(owner_from_types(target), "impl", "Default")
    if trait == "IndexView" and len(args) >= 2:
        return Item(owner, "impl", f"IndexView<{args[1]}>")
    if trait in ("Neg", "Not", "BitNot"):
        return Item(owner, "impl", trait)
    if trait.endswith("Assign") and len(args) >= 2:
        rhs = args[1]
    elif args:
        rhs = args[-1]
    else:
        rhs = owner
    return Item(owner, "impl", f"{trait}<{rhs}>")


def parse_cairo() -> list[Item]:
    items: set[Item] = set()
    trait_re = re.compile(r"\bpub\s+trait\s+([A-Za-z_][A-Za-z0-9_]*)[^\{]*\{")
    impl_re = re.compile(
        r"\bpub\s+impl\s+([A-Za-z_][A-Za-z0-9_]*)\s+of\s+([^\{\n]+)\s*\{"
    )
    module_re = re.compile(r"\bpub\s+mod\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{")

    paths = sorted((ROOT / "packages/glam/src").rglob("*.cairo"))
    paths += sorted((ROOT / "packages/fixed/src").glob("*.cairo"))
    for path in paths:
        package = "glam" if "packages/glam" in str(path) else "fixed"
        fallback = cairo_file_owner(path, package)
        source = str(path.relative_to(ROOT))
        text = mask_comments(path.read_text())
        trait_blocks = blocks(text, trait_re)
        impl_blocks = blocks(text, impl_re)
        excluded = [(start, end) for _, start, end in trait_blocks + impl_blocks]

        for match, opening, end in trait_blocks:
            owner = trait_owner(match.group(1), fallback)
            body = text[opening + 1:end]
            for fn in re.finditer(r"\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^;{()]*>)?\s*\(", body):
                items.add(Item(owner, "method", fn.group(1), source))
            for const in re.finditer(r"\bconst\s+([A-Z][A-Z0-9_]*)\s*:", body):
                items.add(Item(owner, "const", const.group(1), source))

        for match, opening, end in impl_blocks:
            body = text[opening + 1:end]
            item = cairo_impl_item(match.group(2), match.group(1), body, fallback)
            if item:
                items.add(Item(item.owner, item.kind, item.name, source))

        modules = [(m.group(1), start, end) for m, start, end in blocks(text, module_re)]
        # A derived Default is just as public as an explicit core-trait impl.
        for derived in re.finditer(
            r"#\s*\[\s*derive\s*\(([^)]*)\)\s*\]\s*pub\s+(?:struct|enum)\s+([A-Za-z_][A-Za-z0-9_]*)",
            text,
            re.S,
        ):
            if re.search(r"\bDefault\b", derived.group(1)):
                owner = derived.group(2)
                items.add(Item(owner, "impl", "Default", source))
        for match in re.finditer(r"\bpub\s+fn\s+([A-Za-z_][A-Za-z0-9_]*)", text):
            if any(start < match.start() < end for start, end in excluded):
                continue
            nested = [name for name, start, end in modules if start < match.start() < end]
            owner = "::".join([fallback, *nested]) if nested else fallback
            kind = "function" if owner.startswith("camera::") else "method"
            items.add(Item(owner, kind, match.group(1), source))
        for match in re.finditer(r"\bpub\s+const\s+([A-Z][A-Z0-9_]*)\s*:", text):
            if any(start < match.start() < end for start, end in excluded):
                continue
            items.add(Item(fallback, "const", match.group(1), source))
    return unique_items(items)


def unique_items(items: set[Item] | list[Item]) -> list[Item]:
    """Deduplicate declarations by API identity, retaining the lexicographically first source."""
    result: dict[tuple[str, str, str], Item] = {}
    for item in sorted(items):
        result.setdefault(item.key, item)
    return sorted(result.values())


def load_inventory(path: Path) -> list[Item]:
    if not path.is_file():
        raise SystemExit(f"{path} does not exist; run with --refresh and --glam-rs first")
    text = path.read_text()
    start = text.find(INVENTORY_START)
    end = text.find(INVENTORY_END, start + len(INVENTORY_START))
    if start < 0 or end < 0:
        raise SystemExit(f"{path} has no embedded Rust inventory; run with --refresh")
    data = json.loads(text[start + len(INVENTORY_START):end])
    return sorted(Item(**entry) for entry in data)


def direct_key(item: Item) -> tuple[str, str, str]:
    return item.key


def find_rule(item: Item) -> Rule | None:
    rendered = f"{item.kind}:{item.name}" if item.kind in ("const", "impl") else item.name
    for candidate in RULES:
        if candidate.owner.fullmatch(item.owner) and candidate.item.fullmatch(rendered):
            return candidate
    return None


def replacement_name(item: Item, matched: Rule) -> str:
    rendered = f"{item.kind}:{item.name}" if item.kind in ("const", "impl") else item.name
    replacement = matched.item.sub(matched.replacement, rendered)
    return replacement.removeprefix("impl:").removeprefix("method:")


def classify(rust: list[Item], cairo: list[Item]) -> tuple[dict[Item, tuple[str, str]], list[Item]]:
    cairo_by_key = {direct_key(item): item for item in cairo}
    consumed: set[tuple[str, str, str]] = set()
    result: dict[Item, tuple[str, str]] = {}
    for item in rust:
        if item.key in cairo_by_key:
            result[item] = ("ported", "")
            consumed.add(item.key)
            continue
        matched = find_rule(item)
        if matched:
            detail = matched.reason
            if matched.status == "renamed":
                replacement = replacement_name(item, matched)
                detail = f"{replacement} — {detail}"
                # Named replacements are methods on the same owner; camera is deliberately a
                # cross-owner move and does not consume an arbitrary item.
                replacement_key = (item.owner, "method", replacement)
                if replacement_key in cairo_by_key:
                    consumed.add(replacement_key)
            result[item] = (matched.status, detail)
        else:
            result[item] = ("missing", "Not found in the Cairo public surface.")
    extras = [item for item in cairo if item.key not in consumed]
    return result, extras


def anchor(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")


def display_item(item: Item) -> str:
    return f"{item.kind} `{item.name}`"


def render(rust: list[Item], cairo: list[Item]) -> str:
    statuses, extras = classify(rust, cairo)
    owners = sorted(set(item.owner for item in rust) | set(item.owner for item in extras))
    lines = [
        "# API parity with glam-rs 0.33.8",
        "",
        "Generated by `python3 scripts/api_parity.py --refresh --glam-rs /path/to/glam-rs`.",
        "The committed Rust inventory lets `python3 scripts/api_parity.py --check` run without a",
        "Rust checkout. Reference-based Rust impl variants are collapsed because Cairo values are",
        "passed by value. Percent is `(ported + renamed) / all glam-rs items`.",
        "",
        "## Summary",
        "",
        "| Type/module | Ported | Dropped | Renamed | Missing | Extra | Parity |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    owner_rows: dict[str, tuple[int, int, int, int, int, str]] = {}
    for owner in owners:
        owned = [item for item in rust if item.owner == owner]
        counts = {name: sum(statuses[item][0] == name for item in owned)
                  for name in ("ported", "dropped", "renamed", "missing")}
        extra_count = sum(item.owner == owner for item in extras)
        denominator = len(owned)
        parity = 100.0 if denominator == 0 else 100.0 * (counts["ported"] + counts["renamed"]) / denominator
        owner_rows[owner] = (counts["ported"], counts["dropped"], counts["renamed"],
                             counts["missing"], extra_count, f"{parity:.1f}%")
        lines.append(
            f"| [{owner}](#{anchor(owner)}) | {counts['ported']} | {counts['dropped']} | "
            f"{counts['renamed']} | {counts['missing']} | {extra_count} | {parity:.1f}% |"
        )
    total = tuple(sum(row[i] for row in owner_rows.values()) for i in range(5))
    denominator = len(rust)
    parity = 100.0 if not denominator else 100.0 * (total[0] + total[2]) / denominator
    lines.append(f"| **Total** | **{total[0]}** | **{total[1]}** | **{total[2]}** | "
                 f"**{total[3]}** | **{total[4]}** | **{parity:.1f}%** |")

    for owner in owners:
        lines += ["", f"## {owner}", "", "### glam-rs items", "",
                  "| Item | Status | Rule/detail |", "|---|---|---|"]
        owned = [item for item in rust if item.owner == owner]
        if owned:
            for item in owned:
                status, detail = statuses[item]
                lines.append(f"| {display_item(item)} | {status} | {detail or 'Same public name.'} |")
        else:
            lines.append("| _None_ | — | Cairo-only module. |")
        lines += ["", "### Cairo-only items", ""]
        owner_extras = [item for item in extras if item.owner == owner]
        if owner_extras:
            lines.extend(f"- {display_item(item)}" for item in owner_extras)
        else:
            lines.append("- None.")

    inventory = json.dumps([item.as_json() for item in rust], indent=2, sort_keys=True)
    lines += ["", "## Embedded glam-rs inventory", "",
              "This machine-readable block is updated only by `--refresh`.", "",
              INVENTORY_START + inventory + INVENTORY_END, ""]
    return "\n".join(lines)


def write_or_check(generated: str, check: bool) -> int:
    current = OUTPUT.read_text() if OUTPUT.exists() else ""
    if check:
        if current == generated:
            print(f"{OUTPUT.relative_to(ROOT)} is up to date")
            return 0
        print(f"{OUTPUT.relative_to(ROOT)} is stale; run python3 scripts/api_parity.py", file=sys.stderr)
        diff = difflib.unified_diff(current.splitlines(), generated.splitlines(),
                                    fromfile=str(OUTPUT), tofile="generated", lineterm="")
        for line in list(diff)[:80]:
            print(line, file=sys.stderr)
        return 1
    OUTPUT.write_text(generated)
    print(f"wrote {OUTPUT.relative_to(ROOT)}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", action="store_true", help="fail if docs/API_PARITY.md is stale")
    modes.add_argument("--refresh", action="store_true", help="refresh the embedded glam-rs inventory")
    parser.add_argument("--glam-rs", type=Path, default=Path("/tmp/glam-rs"),
                        help="glam-rs 0.33.8 checkout (used only with --refresh)")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rust = parse_rust(args.glam_rs) if args.refresh else load_inventory(OUTPUT)
    cairo = parse_cairo()
    generated = render(rust, cairo)
    return write_or_check(generated, args.check)


if __name__ == "__main__":
    raise SystemExit(main())
