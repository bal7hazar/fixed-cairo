//! Input generation: raw Q32.32 integers drawn directly from the integer PRNG, inside
//! engine-representative ranges, tuples of those, or a custom generator of the module.
//!
//! Only exact or correctly-rounded IEEE operations (`+ - * / sqrt`) are used here, never a
//! transcendental: the generated inputs are identical on every platform.

use crate::registry::Registry;
use crate::rng::Rng;
use crate::spec::{ArgFull, ArgSpec};
use crate::types::{Leaf, Ty};
use crate::value::{quantize, Out, Value, ONE_RAW};

/// Inclusive raw bounds of a `Fixed` leaf.
#[derive(Clone, Copy, Debug)]
pub struct LeafDomain {
    pub lo: i64,
    pub hi: i64,
    pub nonzero: bool,
    pub min_abs: i64,
}

/// Named ranges, in value units. `full` is the whole `i64` range and is reserved to integer
/// oracles (`Value::raw`): an f64 oracle needs `|raw| <= 2^53`, i.e. `|x| <= 2^21`.
pub fn preset(name: &str) -> Result<(i64, i64), String> {
    let tau = quantize(std::f64::consts::TAU).expect("tau");
    Ok(match name {
        "position" => (-1000 * ONE_RAW, 1000 * ONE_RAW),
        "positive" => (1, 1000 * ONE_RAW),
        "unit" => (-ONE_RAW, ONE_RAW),
        "t" => (0, ONE_RAW),
        "small" => (-8 * ONE_RAW, 8 * ONE_RAW),
        "angle" => (-tau, tau),
        "scale" => (quantize(0.01).expect("0.01"), 100 * ONE_RAW),
        "wide" => (-(1 << 20) * ONE_RAW, (1 << 20) * ONE_RAW),
        "full" => (i64::MIN, i64::MAX),
        other => return Err(format!("unknown domain preset {other:?}")),
    })
}

fn to_raw(x: f64, what: &str) -> Result<i64, String> {
    quantize(x).map_err(|_| format!("{what} = {x} is outside the Q32.32 range"))
}

impl LeafDomain {
    pub fn from_spec(arg: &ArgFull) -> Result<LeafDomain, String> {
        let (mut lo, mut hi) = preset(arg.domain.as_deref().unwrap_or("position"))?;
        if let Some(min) = arg.min {
            lo = to_raw(min, "min")?;
        }
        if let Some(max) = arg.max {
            hi = to_raw(max, "max")?;
        }
        if lo > hi {
            return Err(format!("empty domain: min {lo} > max {hi} (raw)"));
        }
        let min_abs = arg.min_abs.map_or(Ok(0), |m| to_raw(m, "min_abs"))?;
        if lo.unsigned_abs().max(hi.unsigned_abs()) < min_abs.unsigned_abs() {
            return Err("min_abs excludes the whole domain".into());
        }
        if arg.nonzero && lo == 0 && hi == 0 {
            return Err("nonzero excludes the whole domain".into());
        }
        Ok(LeafDomain {
            lo,
            hi,
            nonzero: arg.nonzero,
            min_abs,
        })
    }

    fn accepts(&self, raw: i64) -> bool {
        (self.lo..=self.hi).contains(&raw)
            && !(self.nonzero && raw == 0)
            && raw.unsigned_abs() >= self.min_abs.unsigned_abs()
    }

    /// Draws a raw value. Half of the draws are uniform; the others exercise small magnitudes
    /// (right-shifted), integers and half-integers, which uniform sampling never produces.
    pub fn sample(&self, rng: &mut Rng) -> i64 {
        for _ in 0..1000 {
            let uniform = rng.range_i64(self.lo, self.hi);
            let candidate = match rng.below(8) {
                0..=3 => uniform,
                4 | 5 => uniform >> rng.below(41),
                6 => uniform - uniform.rem_euclid(ONE_RAW),
                _ => uniform - uniform.rem_euclid(ONE_RAW / 2),
            };
            if self.accepts(candidate) {
                return candidate;
            }
            if self.accepts(uniform) {
                return uniform;
            }
        }
        panic!("domain {self:?} rejects every sample");
    }
}

fn int_bounds(
    arg: &ArgFull,
    default: (i64, i64),
    limits: (i64, i64),
) -> Result<(i64, i64), String> {
    let lo = arg.min.map_or(default.0, |m| m as i64);
    let hi = arg.max.map_or(default.1, |m| m as i64);
    if lo > hi || lo < limits.0 || hi > limits.1 {
        return Err(format!("invalid integer bounds [{lo}, {hi}]"));
    }
    Ok((lo, hi))
}

/// A compiled argument generator.
pub struct ArgGen<'a> {
    ty: Ty,
    kind: Kind<'a>,
}

enum Kind<'a> {
    Leaves { fixed: LeafDomain, int: (i64, i64) },
    Tuple(Vec<ArgGen<'a>>),
    Custom(&'a dyn Fn(&mut Rng) -> Value),
}

impl<'a> ArgGen<'a> {
    pub fn new(spec: &ArgSpec, registry: &'a Registry) -> Result<ArgGen<'a>, String> {
        let arg = spec.full();
        let ty = Ty::parse(&arg.ty)?;
        if let Some(name) = &arg.custom {
            let gen = registry
                .generators
                .get(name)
                .ok_or_else(|| format!("no generator {name:?} registered for this module"))?;
            return Ok(ArgGen {
                ty,
                kind: Kind::Custom(gen.as_ref()),
            });
        }
        if let Ty::Tuple(elems) = &ty {
            let specs: Vec<ArgSpec> = if arg.elems.is_empty() {
                elems.iter().map(|t| ArgSpec::Short(t.cairo())).collect()
            } else {
                arg.elems.clone()
            };
            let gens: Result<Vec<ArgGen>, String> =
                specs.iter().map(|s| ArgGen::new(s, registry)).collect();
            let gens = gens?;
            let got: Vec<Ty> = gens.iter().map(|g| g.ty.clone()).collect();
            if &got != elems {
                return Err(format!("`elems` types {got:?} do not match `{ty}`"));
            }
            return Ok(ArgGen {
                ty,
                kind: Kind::Tuple(gens),
            });
        }
        // `min` / `max` are integer bounds for integer types: no Fixed domain to build.
        let fixed = if ty.has_fixed_leaf() {
            LeafDomain::from_spec(&arg)?
        } else {
            LeafDomain {
                lo: 0,
                hi: 0,
                nonzero: false,
                min_abs: 0,
            }
        };
        let int = match ty {
            Ty::I64 => int_bounds(&arg, (-1000, 1000), (i64::MIN, i64::MAX))?,
            Ty::I32 => int_bounds(
                &arg,
                (-1000, 1000),
                (i64::from(i32::MIN), i64::from(i32::MAX)),
            )?,
            Ty::U32 => int_bounds(&arg, (0, 1000), (0, i64::from(u32::MAX)))?,
            _ => (0, 1),
        };
        Ok(ArgGen {
            ty,
            kind: Kind::Leaves { fixed, int },
        })
    }

    pub fn ty(&self) -> &Ty {
        &self.ty
    }

    pub fn sample(&self, rng: &mut Rng) -> Value {
        let ty = &self.ty;
        match &self.kind {
            Kind::Custom(gen) => {
                let v = gen(rng);
                assert_eq!(
                    &v.ty, ty,
                    "custom generator returned `{}` for a `{ty}`",
                    v.ty
                );
                v
            }
            Kind::Tuple(gens) => {
                let leaves = gens.iter().flat_map(|g| g.sample(rng).leaves).collect();
                Value::new(ty.clone(), leaves)
            }
            Kind::Leaves { fixed, int } => {
                let leaves = ty
                    .leaves()
                    .iter()
                    .map(|leaf| match leaf {
                        Leaf::Fixed => fixed.sample(rng),
                        Leaf::Bool => i64::from(rng.bool()),
                        Leaf::I64 | Leaf::I32 | Leaf::U32 => rng.range_i64(int.0, int.1),
                    })
                    .collect();
                Value::new(ty.clone(), leaves)
            }
        }
    }
}

/// Convenience for custom generators: wraps an oracle-style result, panicking on a skip.
pub fn value_of(out: impl Into<Out>) -> Value {
    out.into()
        .res
        .expect("custom generator produced an unrepresentable value")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn samples_respect_the_domain() {
        let arg = ArgFull {
            ty: "Fixed".into(),
            domain: Some("unit".into()),
            nonzero: true,
            min_abs: Some(0.25),
            ..ArgFull::default()
        };
        let dom = LeafDomain::from_spec(&arg).unwrap();
        let mut rng = Rng::from_label("domain");
        for _ in 0..2000 {
            let raw = dom.sample(&mut rng);
            assert!(raw.abs() >= ONE_RAW / 4 && raw.abs() <= ONE_RAW);
        }
    }
}
