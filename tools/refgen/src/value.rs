//! Typed values exchanged between the generator and the oracle closures.
//!
//! A [`Value`] is a type plus its flattened `i64` leaves (`Fixed` -> raw Q32.32, integers ->
//! value, `bool` -> 0/1). Oracles read their arguments through the accessors (`f`, `dvec3`,
//! `dquat`, ...) and return anything that converts into an [`Out`] (`f64`, `DVec3`, `bool`,
//! tuples, `Option<_>`, [`Out::raw`] for bit-exact integer oracles, [`skip`]).

use glam::{
    BVec2, BVec3, BVec4, DAffine2, DAffine3, DMat2, DMat3, DMat4, DQuat, DVec2, DVec3, DVec4,
    IVec2, IVec3, IVec4, UVec2, UVec3, UVec4,
};

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

    fn floats<const N: usize>(&self, ty: Ty) -> [f64; N] {
        self.expect(ty);
        let mut out = [0.0; N];
        for (o, raw) in out.iter_mut().zip(&self.leaves) {
            *o = raw_to_f64(*raw);
        }
        out
    }

    /// Raw Q32.32 representation of a `Fixed` argument (for bit-exact integer oracles).
    pub fn raw(&self) -> i64 {
        self.expect(Ty::Fixed);
        self.leaves[0]
    }

    /// A `Fixed` argument as `f64` (exact).
    pub fn f(&self) -> f64 {
        self.floats::<1>(Ty::Fixed)[0]
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

    pub fn dvec2(&self) -> DVec2 {
        DVec2::from_array(self.floats(Ty::Vec2))
    }

    pub fn dvec3(&self) -> DVec3 {
        DVec3::from_array(self.floats(Ty::Vec3))
    }

    pub fn dvec4(&self) -> DVec4 {
        DVec4::from_array(self.floats(Ty::Vec4))
    }

    pub fn dquat(&self) -> DQuat {
        DQuat::from_array(self.floats(Ty::Quat))
    }

    pub fn dmat2(&self) -> DMat2 {
        DMat2::from_cols_array(&self.floats(Ty::Mat2))
    }

    pub fn dmat3(&self) -> DMat3 {
        DMat3::from_cols_array(&self.floats(Ty::Mat3))
    }

    pub fn dmat4(&self) -> DMat4 {
        DMat4::from_cols_array(&self.floats(Ty::Mat4))
    }

    pub fn daffine2(&self) -> DAffine2 {
        DAffine2::from_cols_array(&self.floats(Ty::Affine2))
    }

    pub fn daffine3(&self) -> DAffine3 {
        DAffine3::from_cols_array(&self.floats(Ty::Affine3))
    }

    fn bools(&self, ty: Ty) -> Vec<bool> {
        self.expect(ty);
        self.leaves.iter().map(|l| *l != 0).collect()
    }

    pub fn bvec2(&self) -> BVec2 {
        let b = self.bools(Ty::BVec2);
        BVec2::new(b[0], b[1])
    }

    pub fn bvec3(&self) -> BVec3 {
        let b = self.bools(Ty::BVec3);
        BVec3::new(b[0], b[1], b[2])
    }

    pub fn bvec4(&self) -> BVec4 {
        let b = self.bools(Ty::BVec4);
        BVec4::new(b[0], b[1], b[2], b[3])
    }

    fn i32s<const N: usize>(&self, ty: Ty) -> [i32; N] {
        self.expect(ty);
        let mut out = [0; N];
        for (o, l) in out.iter_mut().zip(&self.leaves) {
            *o = *l as i32;
        }
        out
    }

    fn u32s<const N: usize>(&self, ty: Ty) -> [u32; N] {
        self.expect(ty);
        let mut out = [0; N];
        for (o, l) in out.iter_mut().zip(&self.leaves) {
            *o = *l as u32;
        }
        out
    }

    pub fn ivec2(&self) -> IVec2 {
        IVec2::from_array(self.i32s(Ty::IVec2))
    }

    pub fn ivec3(&self) -> IVec3 {
        IVec3::from_array(self.i32s(Ty::IVec3))
    }

    pub fn ivec4(&self) -> IVec4 {
        IVec4::from_array(self.i32s(Ty::IVec4))
    }

    pub fn uvec2(&self) -> UVec2 {
        UVec2::from_array(self.u32s(Ty::UVec2))
    }

    pub fn uvec3(&self) -> UVec3 {
        UVec3::from_array(self.u32s(Ty::UVec3))
    }

    pub fn uvec4(&self) -> UVec4 {
        UVec4::from_array(self.u32s(Ty::UVec4))
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

    fn floats(ty: Ty, xs: &[f64]) -> Out {
        let leaves: Result<Vec<i64>, Skip> = xs.iter().map(|x| quantize(*x)).collect();
        Out {
            res: leaves.map(|l| Value::new(ty, l)),
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
        Out::floats(Ty::Fixed, &[x])
    }
}

macro_rules! out_from_floats {
    ($($src:ty => $ty:expr, $conv:expr;)*) => {$(
        impl From<$src> for Out {
            fn from(v: $src) -> Out {
                #[allow(clippy::redundant_closure_call)]
                Out::floats($ty, &($conv)(v))
            }
        }
    )*};
}

out_from_floats! {
    DVec2 => Ty::Vec2, |v: DVec2| v.to_array();
    DVec3 => Ty::Vec3, |v: DVec3| v.to_array();
    DVec4 => Ty::Vec4, |v: DVec4| v.to_array();
    DQuat => Ty::Quat, |v: DQuat| v.to_array();
    DMat2 => Ty::Mat2, |v: DMat2| v.to_cols_array();
    DMat3 => Ty::Mat3, |v: DMat3| v.to_cols_array();
    DMat4 => Ty::Mat4, |v: DMat4| v.to_cols_array();
    DAffine2 => Ty::Affine2, |v: DAffine2| v.to_cols_array();
    DAffine3 => Ty::Affine3, |v: DAffine3| v.to_cols_array();
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

fn bits(mask: u32, n: usize) -> Vec<i64> {
    (0..n).map(|i| i64::from((mask >> i) & 1)).collect()
}

out_from_ints! {
    bool => Ty::Bool, |v: bool| vec![i64::from(v)];
    i64 => Ty::I64, |v: i64| vec![v];
    i32 => Ty::I32, |v: i32| vec![i64::from(v)];
    u32 => Ty::U32, |v: u32| vec![i64::from(v)];
    BVec2 => Ty::BVec2, |v: BVec2| bits(v.bitmask(), 2);
    BVec3 => Ty::BVec3, |v: BVec3| bits(v.bitmask(), 3);
    BVec4 => Ty::BVec4, |v: BVec4| bits(v.bitmask(), 4);
    IVec2 => Ty::IVec2, |v: IVec2| v.to_array().iter().map(|c| i64::from(*c)).collect();
    IVec3 => Ty::IVec3, |v: IVec3| v.to_array().iter().map(|c| i64::from(*c)).collect();
    IVec4 => Ty::IVec4, |v: IVec4| v.to_array().iter().map(|c| i64::from(*c)).collect();
    UVec2 => Ty::UVec2, |v: UVec2| v.to_array().iter().map(|c| i64::from(*c)).collect();
    UVec3 => Ty::UVec3, |v: UVec3| v.to_array().iter().map(|c| i64::from(*c)).collect();
    UVec4 => Ty::UVec4, |v: UVec4| v.to_array().iter().map(|c| i64::from(*c)).collect();
}

impl From<Value> for Out {
    fn from(v: Value) -> Out {
        Out {
            res: Ok(v),
            exact: true,
        }
    }
}

/// `None` skips the case (e.g. `try_normalize` of a zero vector is a separate spec entry).
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
    fn tuple_and_glam_conversions() {
        let out: Out = (DVec3::new(1.0, 2.0, 3.0), 0.5).into();
        let v = out.res.unwrap();
        assert_eq!(v.ty, Ty::Tuple(vec![Ty::Vec3, Ty::Fixed]));
        assert_eq!(
            v.leaves,
            vec![ONE_RAW, 2 * ONE_RAW, 3 * ONE_RAW, ONE_RAW / 2]
        );
        assert!(!out.exact);
        let parts = v.elems();
        assert_eq!(parts[0].dvec3(), DVec3::new(1.0, 2.0, 3.0));
        assert_eq!(parts[1].f(), 0.5);
        let m: Out = BVec3::new(true, false, true).into();
        assert_eq!(m.res.unwrap().leaves, vec![1, 0, 1]);
    }
}
