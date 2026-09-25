//! The value types understood by the generator and their Cairo layout.
//!
//! Every value is flattened to a list of `i64` leaves (Fixed -> raw, integers -> value,
//! bool -> 0/1); a tuple is the concatenation of its elements.

use std::fmt;

/// Scalar leaf kinds.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Leaf {
    Fixed,
    I64,
    I32,
    U32,
    Bool,
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Ty {
    Fixed,
    I64,
    I32,
    U32,
    Bool,
    Tuple(Vec<Ty>),
}

impl Ty {
    pub fn parse(s: &str) -> Result<Ty, String> {
        let s = s.trim();
        if let Some(inner) = s.strip_prefix('(').and_then(|r| r.strip_suffix(')')) {
            let elems: Result<Vec<Ty>, String> = inner
                .split(',')
                .filter(|p| !p.trim().is_empty())
                .map(Ty::parse)
                .collect();
            let elems = elems?;
            if elems.len() < 2 {
                return Err(format!("tuple type `{s}` needs at least two elements"));
            }
            if elems.iter().any(|t| matches!(t, Ty::Tuple(_))) {
                return Err(format!("nested tuple type `{s}` is not supported"));
            }
            return Ok(Ty::Tuple(elems));
        }
        Ok(match s {
            "Fixed" => Ty::Fixed,
            "i64" => Ty::I64,
            "i32" => Ty::I32,
            "u32" => Ty::U32,
            "bool" => Ty::Bool,
            other => return Err(format!("unknown type `{other}`")),
        })
    }

    /// The Cairo type name (also the name used in specs).
    pub fn cairo(&self) -> String {
        match self {
            Ty::Fixed => "Fixed".into(),
            Ty::I64 => "i64".into(),
            Ty::I32 => "i32".into(),
            Ty::U32 => "u32".into(),
            Ty::Bool => "bool".into(),
            Ty::Tuple(elems) => {
                let inner: Vec<String> = elems.iter().map(Ty::cairo).collect();
                format!("({})", inner.join(", "))
            }
        }
    }

    /// Suffix of the generated `next_*` / `check_*` helpers.
    pub fn snake(&self) -> String {
        self.cairo().to_lowercase()
    }

    pub fn leaf(&self) -> Option<Leaf> {
        Some(match self {
            Ty::Fixed => Leaf::Fixed,
            Ty::I64 => Leaf::I64,
            Ty::I32 => Leaf::I32,
            Ty::U32 => Leaf::U32,
            Ty::Bool => Leaf::Bool,
            Ty::Tuple(_) => return None,
        })
    }

    /// Import path of the type; `None` for primitives and tuples.
    pub fn path(&self) -> Option<String> {
        match self {
            Ty::Fixed => Some("fixed::Fixed".into()),
            Ty::I64 | Ty::I32 | Ty::U32 | Ty::Bool | Ty::Tuple(_) => None,
        }
    }

    /// The flattened leaves of the type, in order.
    pub fn leaves(&self) -> Vec<Leaf> {
        match (self, self.leaf()) {
            (Ty::Tuple(elems), _) => elems.iter().flat_map(Ty::leaves).collect(),
            (_, leaf) => vec![leaf.expect("every non-tuple type is a leaf")],
        }
    }

    pub fn has_fixed_leaf(&self) -> bool {
        self.leaves().contains(&Leaf::Fixed)
    }
}

impl fmt::Display for Ty {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.cairo())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_and_flatten() {
        assert_eq!(Ty::parse("i32").unwrap(), Ty::I32);
        assert_eq!(
            Ty::parse("(Fixed, bool)").unwrap(),
            Ty::Tuple(vec![Ty::Fixed, Ty::Bool])
        );
        assert_eq!(Ty::parse("(Fixed, Fixed, i64)").unwrap().leaves().len(), 3);
        assert!(Ty::parse("((Fixed, Fixed), Fixed)").is_err());
        assert!(Ty::parse("Vec3").is_err());
        assert!(!Ty::parse("(bool, u32)").unwrap().has_fixed_leaf());
    }
}
