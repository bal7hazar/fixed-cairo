//! The per-module spec files (`specs/<module>.toml`). See `README.md` for the format.

use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use serde::Deserialize;

use crate::types::{LayoutOverride, Leaf, Ty};
use crate::value::{quantize, Value};

fn yes() -> bool {
    true
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Spec {
    /// Module name: the spec is `specs/<module>.toml`, the oracles `src/oracles/<module>.rs`,
    /// the output `packages/<package>/tests/golden_<module>.cairo`.
    pub module: String,
    /// `fixed` or `glam`.
    pub package: String,
    /// Master switch: `false` emits the bare stub whatever the functions say.
    #[serde(default = "yes")]
    pub enabled: bool,
    /// Extra `use` paths needed by the call expressions (traits, constants), one item per
    /// entry, e.g. `fixed::FixedTrait`. The types are imported automatically.
    #[serde(default)]
    pub imports: Vec<String>,
    /// Layout overrides, e.g. `[types.Mat3] fields = ["c0", "c1", "c2"]`.
    #[serde(default)]
    pub types: BTreeMap<String, LayoutOverride>,
    #[serde(default, rename = "function")]
    pub functions: Vec<FunctionSpec>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FunctionSpec {
    /// Test name suffix (`golden_<module>_<name>`) and, unless `oracle` is set, oracle name.
    pub name: String,
    /// Name of the oracle closure registered in `src/oracles/<module>.rs`.
    pub oracle: Option<String>,
    #[serde(default = "yes")]
    pub enabled: bool,
    /// Cairo expression; `{0}`, `{1}`, ... are the arguments.
    pub call: String,
    pub args: Vec<ArgSpec>,
    pub ret: String,
    /// Number of random cases (edge cases come on top).
    pub cases: usize,
    /// Accepted `|actual.raw - expected.raw|`, in raw ULPs (`2^-32`).
    pub tolerance: u64,
    /// Mandatory: where the tolerance comes from (`"exact"` style one-liners for 0).
    pub justification: String,
    /// f64 resolution guard: cases with a quantized `Fixed` result `>= max_abs` are skipped
    /// (default `2^20`, where the f64 oracle still resolves well below one raw ULP).
    pub max_abs: Option<f64>,
    /// Hand-picked cases: one array of argument values per case.
    #[serde(default)]
    pub edges: Vec<Vec<toml::Value>>,
    /// `#[should_panic]` cases.
    #[serde(default)]
    pub panics: Vec<PanicSpec>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PanicSpec {
    /// Test name suffix: `golden_<module>_<function>_panics_<name>`.
    pub name: String,
    pub args: Vec<toml::Value>,
    /// Exact panic message (short string when it fits 31 bytes, `ByteArray` otherwise).
    pub expected: String,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(untagged)]
pub enum ArgSpec {
    /// `"Vec3"`: the type with its default domain.
    Short(String),
    Full(Box<ArgFull>),
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(deny_unknown_fields)]
pub struct ArgFull {
    #[serde(rename = "type")]
    pub ty: String,
    /// Preset for the `Fixed` leaves: see `domain::preset`.
    pub domain: Option<String>,
    /// Bounds of each leaf, in value units (override the preset).
    pub min: Option<f64>,
    pub max: Option<f64>,
    /// Leaves are never zero.
    #[serde(default)]
    pub nonzero: bool,
    /// Leaves satisfy `|x| >= min_abs`.
    pub min_abs: Option<f64>,
    /// Whole-value constraint: `normalized`, `nonzero`, `invertible`, `rotation`, `trs`.
    pub constraint: Option<String>,
    /// `constraint = "nonzero"`: minimum length (default 0.001).
    pub min_len: Option<f64>,
    /// `constraint = "invertible"`: minimum `|det|` (default 0.01).
    pub min_det: Option<f64>,
    /// `constraint = "trs"`: scale range (default `[0.25, 4]`).
    pub scale_min: Option<f64>,
    pub scale_max: Option<f64>,
    /// Name of a generator registered with `Registry::generator` (overrides everything else).
    pub custom: Option<String>,
    /// Per-element specs of a tuple argument.
    #[serde(default)]
    pub elems: Vec<ArgSpec>,
}

impl ArgSpec {
    pub fn full(&self) -> ArgFull {
        match self {
            ArgSpec::Short(ty) => ArgFull {
                ty: ty.clone(),
                ..ArgFull::default()
            },
            ArgSpec::Full(full) => (**full).clone(),
        }
    }
}

fn is_ident(s: &str) -> bool {
    !s.is_empty()
        && s.chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
        && !s.starts_with(|c: char| c.is_ascii_digit())
}

impl Spec {
    pub fn load(path: &Path) -> Result<Spec, String> {
        let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
        let spec: Spec = toml::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))?;
        let stem = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or_default();
        if stem != spec.module {
            return Err(format!(
                "{}: module = {:?} must match the file name",
                path.display(),
                spec.module
            ));
        }
        spec.validate()
            .map_err(|e| format!("{}: {e}", path.display()))?;
        Ok(spec)
    }

    fn validate(&self) -> Result<(), String> {
        if !is_ident(&self.module) {
            return Err(format!("invalid module name {:?}", self.module));
        }
        if !matches!(self.package.as_str(), "fixed" | "glam") {
            return Err(format!(
                "package must be \"fixed\" or \"glam\", got {:?}",
                self.package
            ));
        }
        let mut seen = std::collections::BTreeSet::new();
        for f in &self.functions {
            let ctx = format!("function {:?}", f.name);
            if !is_ident(&f.name) {
                return Err(format!("{ctx}: name must match [a-z_][a-z0-9_]*"));
            }
            if !seen.insert(&f.name) {
                return Err(format!("{ctx}: duplicate name"));
            }
            if f.justification.trim().is_empty() {
                return Err(format!(
                    "{ctx}: `justification` is mandatory (also for tolerance 0)"
                ));
            }
            if f.cases == 0 && f.edges.is_empty() && f.panics.is_empty() {
                return Err(format!("{ctx}: no case at all"));
            }
            Ty::parse(&f.ret).map_err(|e| format!("{ctx}: ret: {e}"))?;
            for (i, a) in f.args.iter().enumerate() {
                Ty::parse(&a.full().ty).map_err(|e| format!("{ctx}: arg {i}: {e}"))?;
                if !f.call.contains(&format!("{{{i}}}")) {
                    return Err(format!("{ctx}: `call` never uses {{{i}}}"));
                }
            }
            let mut panic_names = std::collections::BTreeSet::new();
            for p in &f.panics {
                if !is_ident(&p.name) || !panic_names.insert(&p.name) {
                    return Err(format!(
                        "{ctx}: invalid or duplicate panic name {:?}",
                        p.name
                    ));
                }
                if p.expected.contains(['\'', '"', '\\']) || !p.expected.is_ascii() {
                    return Err(format!("{ctx}: panic {:?}: unsupported message", p.name));
                }
            }
        }
        Ok(())
    }
}

/// Parses one leaf of a hand-written case: a number (value units for `Fixed`), a bool, or a
/// `"raw:<int>"` string (decimal or 0x-hex, optionally negative) giving the raw leaf.
fn parse_leaf(leaf: Leaf, v: &toml::Value) -> Result<i64, String> {
    if let toml::Value::String(s) = v {
        let Some(body) = s.strip_prefix("raw:") else {
            return Err(format!("string leaf {s:?} must start with `raw:`"));
        };
        let (neg, digits) = match body.strip_prefix('-') {
            Some(rest) => (true, rest),
            None => (false, body),
        };
        let digits = digits.replace('_', "");
        let magnitude = match digits.strip_prefix("0x") {
            Some(hex) => i128::from_str_radix(hex, 16),
            None => digits.parse::<i128>(),
        }
        .map_err(|e| format!("{s:?}: {e}"))?;
        let raw = if neg { -magnitude } else { magnitude };
        return i64::try_from(raw).map_err(|_| format!("{s:?} does not fit an i64"));
    }
    let out_of_range = || format!("{v} is out of range for {leaf:?}");
    match (leaf, v) {
        (Leaf::Fixed, toml::Value::Float(x)) => quantize(*x).map_err(|_| out_of_range()),
        (Leaf::Fixed, toml::Value::Integer(n)) => quantize(*n as f64).map_err(|_| out_of_range()),
        (Leaf::I64, toml::Value::Integer(n)) => Ok(*n),
        (Leaf::I32, toml::Value::Integer(n)) => {
            i32::try_from(*n).map(i64::from).map_err(|_| out_of_range())
        }
        (Leaf::U32, toml::Value::Integer(n)) => {
            u32::try_from(*n).map(i64::from).map_err(|_| out_of_range())
        }
        (Leaf::Bool, toml::Value::Boolean(b)) => Ok(i64::from(*b)),
        _ => Err(format!("{v} is not a valid {leaf:?} leaf")),
    }
}

fn flatten<'a>(v: &'a toml::Value, out: &mut Vec<&'a toml::Value>) {
    match v {
        toml::Value::Array(items) => items.iter().for_each(|i| flatten(i, out)),
        other => out.push(other),
    }
}

/// Parses a hand-written argument: a leaf, or a (possibly nested) array of leaves in the
/// flattened column-major order of the type.
pub fn parse_value(ty: &Ty, v: &toml::Value) -> Result<Value, String> {
    let leaves = ty.leaves();
    let mut flat = Vec::new();
    flatten(v, &mut flat);
    if flat.len() != leaves.len() {
        return Err(format!(
            "`{ty}` needs {} leaves, got {}",
            leaves.len(),
            flat.len()
        ));
    }
    let parsed: Result<Vec<i64>, String> = leaves
        .iter()
        .zip(flat)
        .map(|(l, v)| parse_leaf(*l, v))
        .collect();
    Ok(Value::new(ty.clone(), parsed?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_hand_written_values() {
        let v: toml::Value = toml::from_str("v = [1.5, \"raw:-0x10\", 2]").unwrap();
        let value = parse_value(&Ty::Vec3, &v["v"]).unwrap();
        assert_eq!(value.leaves, vec![3 << 31, -16, 2 << 32]);
        let v: toml::Value = toml::from_str("v = [[1, 0], [0, 1]]").unwrap();
        assert_eq!(parse_value(&Ty::Mat2, &v["v"]).unwrap().leaves.len(), 4);
        assert!(parse_value(&Ty::Vec2, &v["v"]).is_err());
        let v: toml::Value = toml::from_str("v = \"raw:0x7fffffffffffffff\"").unwrap();
        assert_eq!(
            parse_value(&Ty::Fixed, &v["v"]).unwrap().leaves,
            vec![i64::MAX]
        );
        let v: toml::Value = toml::from_str("v = \"raw:-9223372036854775808\"").unwrap();
        assert_eq!(
            parse_value(&Ty::Fixed, &v["v"]).unwrap().leaves,
            vec![i64::MIN]
        );
    }
}
