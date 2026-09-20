//! Case generation: hand-picked edges first, then seeded random inputs, each run through the
//! oracle; cases the oracle skips (overflow, panic path, precondition) are redrawn.

use crate::domain::ArgGen;
use crate::registry::Registry;
use crate::rng::Rng;
use crate::spec::{parse_value, FunctionSpec, Spec};
use crate::types::{Leaf, Ty};
use crate::value::{Value, ONE_F64};

/// Default f64 resolution guard: below `2^20` a double resolves `2^-33`, half a raw ULP.
pub const DEFAULT_MAX_ABS: f64 = 1_048_576.0;

pub struct Case {
    pub args: Vec<Value>,
    pub expected: Value,
}

pub struct PanicCase {
    pub name: String,
    pub args: Vec<Value>,
    pub expected: String,
}

pub struct FunctionCases {
    pub arg_tys: Vec<Ty>,
    pub ret: Ty,
    pub cases: Vec<Case>,
    pub panics: Vec<PanicCase>,
}

fn parse_args(tys: &[Ty], raw: &[toml::Value], what: &str) -> Result<Vec<Value>, String> {
    if raw.len() != tys.len() {
        return Err(format!(
            "{what}: expected {} arguments, got {}",
            tys.len(),
            raw.len()
        ));
    }
    tys.iter()
        .zip(raw)
        .enumerate()
        .map(|(i, (ty, v))| parse_value(ty, v).map_err(|e| format!("{what}: arg {i}: {e}")))
        .collect()
}

pub fn generate(
    spec: &Spec,
    f: &FunctionSpec,
    registry: &Registry,
) -> Result<FunctionCases, String> {
    let oracle_name = f.oracle.as_deref().unwrap_or(&f.name);
    let oracle = registry.oracles.get(oracle_name).ok_or_else(|| {
        format!(
            "no oracle {oracle_name:?} in tools/refgen/src/oracles/{}.rs",
            spec.module
        )
    })?;
    let gens: Result<Vec<ArgGen>, String> = f
        .args
        .iter()
        .enumerate()
        .map(|(i, a)| ArgGen::new(a, registry).map_err(|e| format!("arg {i}: {e}")))
        .collect();
    let gens = gens?;
    let arg_tys: Vec<Ty> = gens.iter().map(|g| g.ty().clone()).collect();
    let ret = Ty::parse(&f.ret)?;
    let max_abs = f.max_abs.unwrap_or(DEFAULT_MAX_ABS);
    if !(max_abs > 0.0 && max_abs <= 2_147_483_648.0) {
        return Err(format!("max_abs = {max_abs} must be in (0, 2^31]"));
    }
    let max_raw = max_abs * ONE_F64;

    // Runs the oracle; Ok(None) = skipped.
    let run = |args: &[Value]| -> Result<Option<Value>, String> {
        let out = oracle(args);
        let Ok(value) = out.res else { return Ok(None) };
        if value.ty != ret {
            return Err(format!(
                "the oracle returned `{}` but the spec says `{ret}`",
                value.ty
            ));
        }
        let too_large =
            |(leaf, raw): (&Leaf, &i64)| *leaf == Leaf::Fixed && (*raw as f64).abs() >= max_raw;
        if !out.exact && ret.leaves().iter().zip(&value.leaves).any(too_large) {
            return Ok(None);
        }
        Ok(Some(value))
    };

    let mut cases = Vec::new();
    for (i, edge) in f.edges.iter().enumerate() {
        let args = parse_args(&arg_tys, edge, &format!("edge {i}"))?;
        let expected = run(&args)?.ok_or_else(|| {
            format!(
                "edge {i} is skipped by the oracle (overflow or panic path): move it to `panics`"
            )
        })?;
        cases.push(Case { args, expected });
    }

    let wanted = if gens.is_empty() {
        usize::from(f.edges.is_empty()).min(f.cases)
    } else {
        f.cases
    };
    let mut rng = Rng::from_label(&format!("{}::{}", spec.module, f.name));
    let mut attempts = 0usize;
    let mut produced = 0usize;
    while produced < wanted {
        attempts += 1;
        if attempts > 1000 + wanted * 200 {
            return Err(format!(
                "only {produced}/{wanted} valid cases after {attempts} draws: the oracle skips \
                 almost everything, tighten the input domains"
            ));
        }
        let args: Vec<Value> = gens.iter().map(|g| g.sample(&mut rng)).collect();
        if let Some(expected) = run(&args)? {
            cases.push(Case { args, expected });
            produced += 1;
        }
    }

    let mut panics = Vec::new();
    for p in &f.panics {
        let args = parse_args(&arg_tys, &p.args, &format!("panic {:?}", p.name))?;
        panics.push(PanicCase {
            name: p.name.clone(),
            args,
            expected: p.expected.clone(),
        });
    }
    Ok(FunctionCases {
        arg_tys,
        ret,
        cases,
        panics,
    })
}
