//! Typed values exchanged between the generator and the oracle closures.
//!
//! A [`Value`] is a type plus its flattened `i64` leaves (`Fixed` -> raw Q32.32, integers ->
//! value, `bool` -> 0/1). Oracles read their arguments through the accessors (`f`, `raw`,
//! `i64`, `bool`, `elems`, ...) and return anything that converts into an [`Out`] (`f64`,
//! `bool`, integers, tuples, `Option<_>`, [`Out::raw`] for bit-exact integer oracles, [`skip`]).

use crate::types::Ty;

/// Number of fractional bits of `fixed::Fixed`.
pub const FRAC_BITS: u32 = 32;
/// `2^32` as `f64`.
pub const ONE_F64: f64 = 4_294_967_296.0;
/// Raw representation of `1.0`.
pub const ONE_RAW: i64 = 1 << FRAC_BITS;
/// Largest raw magnitude that converts to `f64` exactly.
pub const MAX_EXACT_RAW: i64 = 1 << 53;

/// Why a case is dropped instead of emitted.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Skip {
    /// The oracle result is outside the Q32.32 range (the Cairo side panics).
    Overflow,
    /// NaN / infinity: a documented panic path on the Cairo side.
    NotFinite,
    /// The inputs are outside the domain of the function (precondition, panic path).
    Domain(&'static str),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Value {
    pub ty: Ty,
    pub leaves: Vec<i64>,
}

/// Quantizes an `f64` to the nearest raw Q32.32 value (ties away from zero).
pub fn quantize(x: f64) -> Result<i64, Skip> {
    if !x.is_finite() {
        return Err(Skip::NotFinite);
    }
    // Scaling by a power of two is exact; `round` is an exact IEEE operation.
    let scaled = (x * ONE_F64).round();
    if (-9_223_372_036_854_775_808.0..9_223_372_036_854_775_808.0).contains(&scaled) {
        Ok(scaled as i64)
    } else {
        Err(Skip::Overflow)
    }
}

/// Converts a raw Q32.32 value to `f64`. Exact: panics if `|raw| > 2^53`.
pub fn raw_to_f64(raw: i64) -> f64 {
    assert!(
        raw.unsigned_abs() <= MAX_EXACT_RAW as u64,
        "raw {raw} does not convert to f64 exactly: keep f64-oracle inputs below 2^21, or use \
         `raw()` and an integer oracle"
    );
    raw as f64 / ONE_F64
}

impl Value {
    pub fn new(ty: Ty, leaves: Vec<i64>) -> Value {
        assert_eq!(
            ty.leaves().len(),
            leaves.len(),
            "leaf count mismatch for {ty}"
        );
        Value { ty, leaves }
    }

    pub fn fixed_raw(raw: i64) -> Value {
        Value::new(Ty::Fixed, vec![raw])
    }

    fn expect(&self, ty: Ty) {
        assert_eq!(
            self.ty, ty,
            "oracle read a `{}` argument as `{ty}`",
            self.ty
        );
    }

    /// Raw Q32.32 representation of a `Fixed` argument (for bit-exact integer oracles).
    pub fn raw(&self) -> i64 {
        self.expect(Ty::Fixed);
        self.leaves[0]
    }

    /// A `Fixed` argument as `f64` (exact).
    pub fn f(&self) -> f64 {
        raw_to_f64(self.raw())
    }

    pub fn i64(&self) -> i64 {
        self.expect(Ty::I64);
        self.leaves[0]
    }

    pub fn i32(&self) -> i32 {
        self.expect(Ty::I32);
        self.leaves[0] as i32
    }

    pub fn u32(&self) -> u32 {
        self.expect(Ty::U32);
        self.leaves[0] as u32
    }

    pub fn bool(&self) -> bool {
        self.expect(Ty::Bool);
        self.leaves[0] != 0
    }

    /// The elements of a tuple argument.
    pub fn elems(&self) -> Vec<Value> {
        let Ty::Tuple(tys) = &self.ty else {
            panic!("oracle read a `{}` as a tuple", self.ty)
        };
        let mut rest = self.leaves.as_slice();
        tys.iter()
            .map(|t| {
                let (head, tail) = rest.split_at(t.leaves().len());
                rest = tail;
                Value::new(t.clone(), head.to_vec())
            })
            .collect()
    }
}

/// The result of an oracle: a value or a reason to skip the case.
#[derive(Clone, Debug)]
pub struct Out {
    pub res: Result<Value, Skip>,
    /// True when every `Fixed` leaf was computed with exact integer arithmetic: the f64
    /// resolution guard (`max_abs`) does not apply.
    pub exact: bool,
}

/// Drops the case: the inputs hit a documented panic path or a precondition.
pub fn skip(reason: &'static str) -> Out {
    Out {
        res: Err(Skip::Domain(reason)),
        exact: true,
    }
}

impl Out {
    /// A `Fixed` result given by its exact raw representation.
    pub fn raw(raw: i64) -> Out {
        Out {
            res: Ok(Value::fixed_raw(raw)),
            exact: true,
        }
    }

    /// Exact raw result of a checked integer operation; `None` (overflow) skips the case.
    pub fn raw_checked(raw: Option<i64>) -> Out {
        match raw {
            Some(raw) => Out::raw(raw),
            None => Out {
                res: Err(Skip::Overflow),
                exact: true,
            },
        }
    }

    /// Exact raw result computed in `i128`; skipped when it does not fit an `i64`.
    pub fn raw_wide(raw: i128) -> Out {
        Out::raw_checked(i64::try_from(raw).ok())
    }

    fn float(x: f64) -> Out {
        Out {
            res: quantize(x).map(Value::fixed_raw),
            exact: false,
        }
    }

    fn ints(ty: Ty, leaves: Vec<i64>) -> Out {
        Out {
            res: Ok(Value::new(ty, leaves)),
            exact: true,
        }
    }

    fn tuple(parts: Vec<Out>) -> Out {
        let exact = parts.iter().all(|p| p.exact);
        let mut tys = Vec::new();
        let mut leaves = Vec::new();
        for p in parts {
            match p.res {
                Ok(v) => {
                    tys.push(v.ty);
                    leaves.extend(v.leaves);
                }
                Err(e) => return Out { res: Err(e), exact },
            }
        }
        Out {
            res: Ok(Value::new(Ty::Tuple(tys), leaves)),
            exact,
        }
    }
}

impl From<f64> for Out {
    fn from(x: f64) -> Out {
        Out::float(x)
    }
}

macro_rules! out_from_ints {
    ($($src:ty => $ty:expr, $conv:expr;)*) => {$(
        impl From<$src> for Out {
            fn from(v: $src) -> Out {
                #[allow(clippy::redundant_closure_call)]
                Out::ints($ty, ($conv)(v))
            }
        }
    )*};
}

out_from_ints! {
    bool => Ty::Bool, |v: bool| vec![i64::from(v)];
    i64 => Ty::I64, |v: i64| vec![v];
    i32 => Ty::I32, |v: i32| vec![i64::from(v)];
    u32 => Ty::U32, |v: u32| vec![i64::from(v)];
}

impl From<Value> for Out {
    fn from(v: Value) -> Out {
        Out {
            res: Ok(v),
            exact: true,
        }
    }
}

/// `None` skips the case.
impl<T: Into<Out>> From<Option<T>> for Out {
    fn from(v: Option<T>) -> Out {
        v.map_or_else(|| skip("oracle returned None"), Into::into)
    }
}

impl<A: Into<Out>, B: Into<Out>> From<(A, B)> for Out {
    fn from((a, b): (A, B)) -> Out {
        Out::tuple(vec![a.into(), b.into()])
    }
}

impl<A: Into<Out>, B: Into<Out>, C: Into<Out>> From<(A, B, C)> for Out {
    fn from((a, b, c): (A, B, C)) -> Out {
        Out::tuple(vec![a.into(), b.into(), c.into()])
    }
}

impl<A: Into<Out>, B: Into<Out>, C: Into<Out>, D: Into<Out>> From<(A, B, C, D)> for Out {
    fn from((a, b, c, d): (A, B, C, D)) -> Out {
        Out::tuple(vec![a.into(), b.into(), c.into(), d.into()])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quantize_rounds_to_nearest_and_detects_overflow() {
        assert_eq!(quantize(1.0), Ok(ONE_RAW));
        assert_eq!(quantize(-0.5), Ok(-(ONE_RAW / 2)));
        assert_eq!(quantize(0.6 / ONE_F64), Ok(1));
        assert_eq!(quantize(-0.5 / ONE_F64), Ok(-1));
        assert_eq!(quantize(-2_147_483_648.0), Ok(i64::MIN));
        assert_eq!(quantize(2_147_483_648.0), Err(Skip::Overflow));
        assert_eq!(quantize(f64::NAN), Err(Skip::NotFinite));
        assert_eq!(quantize(f64::INFINITY), Err(Skip::NotFinite));
    }

    #[test]
    fn tuple_conversions() {
        let out: Out = (2.0, 0.5, 7_i64).into();
        let v = out.res.unwrap();
        assert_eq!(v.ty, Ty::Tuple(vec![Ty::Fixed, Ty::Fixed, Ty::I64]));
        assert_eq!(v.leaves, vec![2 * ONE_RAW, ONE_RAW / 2, 7]);
        assert!(!out.exact);
        let parts = v.elems();
        assert_eq!(parts[0].f(), 2.0);
        assert_eq!(parts[2].i64(), 7);
        let m: Out = (true, Out::raw(3)).into();
        assert!(m.exact);
        assert_eq!(m.res.unwrap().leaves, vec![1, 3]);
    }
}
