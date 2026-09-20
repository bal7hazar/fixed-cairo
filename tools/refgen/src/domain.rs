//! Input generation: raw Q32.32 integers drawn directly from the integer PRNG, inside
//! engine-representative ranges, plus whole-value constraints (unit vectors, rotations, ...).
//!
//! Only exact or correctly-rounded IEEE operations (`+ - * / sqrt`) are used here, never a
//! transcendental: the generated inputs are identical on every platform.

use glam::{DMat2, DMat3, DMat4, DQuat, DVec2, DVec3, DVec4};

use crate::registry::Registry;
use crate::rng::Rng;
use crate::spec::{ArgFull, ArgSpec};
use crate::types::{Leaf, Ty};
use crate::value::{quantize, raw_to_f64, Out, Value, ONE_RAW};

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
    Leaves {
        fixed: LeafDomain,
        int: (i64, i64),
    },
    Normalized,
    NonZero {
        fixed: LeafDomain,
        min_len: f64,
    },
    Invertible {
        fixed: LeafDomain,
        min_det: f64,
    },
    Rotation {
        fixed: LeafDomain,
    },
    Trs {
        fixed: LeafDomain,
        scale: LeafDomain,
    },
    Tuple(Vec<ArgGen<'a>>),
    Custom(&'a dyn Fn(&mut Rng) -> Value),
}

fn quantized(ty: &Ty, xs: &[f64]) -> Value {
    Value::new(
        ty.clone(),
        xs.iter().map(|x| quantize(*x).expect("in range")).collect(),
    )
}

fn unit_floats<const N: usize>(rng: &mut Rng) -> [f64; N] {
    let unit = LeafDomain {
        lo: -ONE_RAW,
        hi: ONE_RAW,
        nonzero: false,
        min_abs: 0,
    };
    loop {
        let mut v = [0.0; N];
        for c in &mut v {
            *c = raw_to_f64(unit.sample(rng));
        }
        let len = v.iter().map(|c| c * c).sum::<f64>().sqrt();
        if len >= 0.1 {
            return v.map(|c| c / len);
        }
    }
}

fn unit_quat(rng: &mut Rng) -> DQuat {
    DQuat::from_array(unit_floats::<4>(rng))
}

/// 2D rotation matrix without trigonometry: a unit vector `(c, s)`.
fn rotation2(rng: &mut Rng) -> DMat2 {
    let [c, s] = unit_floats::<2>(rng);
    DMat2::from_cols(DVec2::new(c, s), DVec2::new(-s, c))
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
        let is_vec = matches!(ty, Ty::Vec2 | Ty::Vec3 | Ty::Vec4 | Ty::Quat);
        let is_mat = matches!(
            ty,
            Ty::Mat2 | Ty::Mat3 | Ty::Mat4 | Ty::Affine2 | Ty::Affine3
        );
        let kind = match arg.constraint.as_deref() {
            None => {
                let int = match ty {
                    Ty::I64 => int_bounds(&arg, (-1000, 1000), (i64::MIN, i64::MAX))?,
                    Ty::I32 | Ty::IVec2 | Ty::IVec3 | Ty::IVec4 => int_bounds(
                        &arg,
                        (-1000, 1000),
                        (i64::from(i32::MIN), i64::from(i32::MAX)),
                    )?,
                    Ty::U32 | Ty::UVec2 | Ty::UVec3 | Ty::UVec4 => {
                        int_bounds(&arg, (0, 1000), (0, i64::from(u32::MAX)))?
                    }
                    _ => (0, 1),
                };
                Kind::Leaves { fixed, int }
            }
            Some("normalized") if is_vec => Kind::Normalized,
            Some("nonzero") if is_vec => Kind::NonZero {
                fixed,
                min_len: arg.min_len.unwrap_or(0.001),
            },
            Some("invertible") if is_mat => Kind::Invertible {
                fixed,
                min_det: arg.min_det.unwrap_or(0.01),
            },
            Some("rotation") if is_mat => Kind::Rotation { fixed },
            Some("trs") if matches!(ty, Ty::Mat3 | Ty::Mat4 | Ty::Affine2 | Ty::Affine3) => {
                let scale = LeafDomain {
                    lo: to_raw(arg.scale_min.unwrap_or(0.25), "scale_min")?,
                    hi: to_raw(arg.scale_max.unwrap_or(4.0), "scale_max")?,
                    nonzero: true,
                    min_abs: 0,
                };
                if scale.lo > scale.hi {
                    return Err("scale_min > scale_max".into());
                }
                Kind::Trs { fixed, scale }
            }
            Some(other) => {
                return Err(format!("constraint {other:?} is not supported for `{ty}`"));
            }
        };
        Ok(ArgGen { ty, kind })
    }

    pub fn ty(&self) -> &Ty {
        &self.ty
    }

    fn floats(&self, fixed: &LeafDomain, n: usize, rng: &mut Rng) -> Vec<f64> {
        (0..n).map(|_| raw_to_f64(fixed.sample(rng))).collect()
    }

    pub fn sample(&self, rng: &mut Rng) -> Value {
        let ty = &self.ty;
        let n = ty.leaves().len();
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
            Kind::Normalized => match n {
                2 => quantized(ty, &unit_floats::<2>(rng)),
                3 => quantized(ty, &unit_floats::<3>(rng)),
                _ => quantized(ty, &unit_floats::<4>(rng)),
            },
            Kind::NonZero { fixed, min_len } => loop {
                let v = self.floats(fixed, n, rng);
                if v.iter().map(|c| c * c).sum::<f64>().sqrt() >= *min_len {
                    return quantized(ty, &v);
                }
            },
            Kind::Invertible { fixed, min_det } => loop {
                let v = self.floats(fixed, n, rng);
                let det = match ty {
                    Ty::Mat2 | Ty::Affine2 => DMat2::from_cols_slice(&v[..4]).determinant(),
                    Ty::Mat3 | Ty::Affine3 => DMat3::from_cols_slice(&v[..9]).determinant(),
                    _ => DMat4::from_cols_slice(&v).determinant(),
                };
                if det.abs() >= *min_det {
                    return quantized(ty, &v);
                }
            },
            Kind::Rotation { fixed } => {
                let mut v: Vec<f64> = match ty {
                    Ty::Mat2 | Ty::Affine2 => rotation2(rng).to_cols_array().to_vec(),
                    Ty::Mat3 | Ty::Affine3 => {
                        DMat3::from_quat(unit_quat(rng)).to_cols_array().to_vec()
                    }
                    _ => DMat4::from_quat(unit_quat(rng)).to_cols_array().to_vec(),
                };
                let translation = self.floats(fixed, n - v.len(), rng);
                v.extend(translation);
                quantized(ty, &v)
            }
            Kind::Trs { fixed, scale } => {
                let v: Vec<f64> = match ty {
                    // 2D transforms: scale, rotation, translation.
                    Ty::Mat3 | Ty::Affine2 => {
                        let s = self.floats(scale, 2, rng);
                        let r = rotation2(rng);
                        let t = self.floats(fixed, 2, rng);
                        let m = DMat2::from_cols(r.x_axis * s[0], r.y_axis * s[1]);
                        if *ty == Ty::Affine2 {
                            [m.to_cols_array().as_slice(), &t].concat()
                        } else {
                            let cols = [
                                m.x_axis.extend(0.0),
                                m.y_axis.extend(0.0),
                                DVec3::new(t[0], t[1], 1.0),
                            ];
                            DMat3::from_cols(cols[0], cols[1], cols[2])
                                .to_cols_array()
                                .to_vec()
                        }
                    }
                    _ => {
                        let s = self.floats(scale, 3, rng);
                        let r = DMat3::from_quat(unit_quat(rng));
                        let t = self.floats(fixed, 3, rng);
                        let m = DMat3::from_cols(r.x_axis * s[0], r.y_axis * s[1], r.z_axis * s[2]);
                        if *ty == Ty::Affine3 {
                            [m.to_cols_array().as_slice(), &t].concat()
                        } else {
                            DMat4::from_cols(
                                m.x_axis.extend(0.0),
                                m.y_axis.extend(0.0),
                                m.z_axis.extend(0.0),
                                DVec4::new(t[0], t[1], t[2], 1.0),
                            )
                            .to_cols_array()
                            .to_vec()
                        }
                    }
                };
                quantized(ty, &v)
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

    #[test]
    fn normalized_is_unit_within_quantization() {
        let registry = Registry::default();
        let spec = ArgSpec::Full(Box::new(ArgFull {
            ty: "Quat".into(),
            constraint: Some("normalized".into()),
            ..ArgFull::default()
        }));
        let gen = ArgGen::new(&spec, &registry).unwrap();
        let mut rng = Rng::from_label("quat");
        for _ in 0..100 {
            let q = gen.sample(&mut rng).dquat();
            assert!((q.length() - 1.0).abs() < 1e-9);
        }
    }
}
