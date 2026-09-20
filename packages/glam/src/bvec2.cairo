//! Port of glam-rs `bool/bvec2.rs` @ 0.33.8: a 2-dimensional `bool` vector mask.
//!
//! Every formulation below is the cheapest of the candidates measured in `gas/bvec2.snap`; the
//! losing candidates live in `benches::alt::bvec2`. The logical operators work on `bool` with
//! the `bool_*_impl` libfuncs: no bitwise builtin cell is consumed.

use core::traits::{BitAnd, BitOr, BitXor};

/// A 2-dimensional `bool` vector mask.
///
/// Mirrors `glam::BVec2`.
/// #### Deviations
/// * `Debug` is the derived Cairo formatting, not glam's `BVec2(0xffffffff, 0x0, ..)`.
/// * `Display` is not implemented.
/// * The by-reference operator overloads (`&a & &b`, ...) and the `*Assign` operators
///   (`&=`, `|=`, `^=`) do not exist in Cairo: use `a = a & b`.
#[derive(Copy, Drop, Serde, PartialEq, Debug, Default, Hash)]
pub struct BVec2 {
    pub x: bool,
    pub y: bool,
}

/// Creates a 2-dimensional `bool` vector mask.
///
/// Mirrors `glam::bvec2`.
/// #### Panics
/// * Never.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn bvec2(x: bool, y: bool) -> BVec2 {
    BVec2 { x, y }
}

pub trait BVec2Trait {
    /// All false.
    ///
    /// Mirrors `glam::BVec2::FALSE`.
    const FALSE: BVec2;
    /// All true.
    ///
    /// Mirrors `glam::BVec2::TRUE`.
    const TRUE: BVec2;
    /// Creates a new vector mask.
    ///
    /// Mirrors `glam::BVec2::new`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn new(x: bool, y: bool) -> BVec2;
    /// Creates a vector mask with all elements set to `v`.
    ///
    /// Mirrors `glam::BVec2::splat`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn splat(v: bool) -> BVec2;
    /// Creates a new vector mask from a bool array.
    ///
    /// Mirrors `glam::BVec2::from_array`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_array(a: [bool; 2]) -> BVec2;
    /// Returns a bitmask with the lowest 2 bits set from the elements of `self`.
    ///
    /// A true element results in a `1` bit and a false element in a `0` bit. Element `x` goes
    /// into the first lowest bit, element `y` into the second, etc.
    ///
    /// Mirrors `glam::BVec2::bitmask`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn bitmask(self: BVec2) -> u32;
    /// Returns true if any of the elements are true, false otherwise.
    ///
    /// Mirrors `glam::BVec2::any`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn any(self: BVec2) -> bool;
    /// Returns true if all the elements are true, false otherwise.
    ///
    /// Mirrors `glam::BVec2::all`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn all(self: BVec2) -> bool;
    /// Tests the value at `index`.
    ///
    /// Mirrors `glam::BVec2::test`.
    /// #### Panics
    /// * `'BVec2: index out of bounds'` if `index` is greater than 1.
    /// #### Deviations
    /// * None.
    fn test(self: BVec2, index: usize) -> bool;
    /// Sets the element at `index`.
    ///
    /// Mirrors `glam::BVec2::set`.
    /// #### Panics
    /// * `'BVec2: index out of bounds'` if `index` is greater than 1.
    /// #### Deviations
    /// * None.
    fn set(ref self: BVec2, index: usize, value: bool);
}

pub impl BVec2Impl of BVec2Trait {
    const FALSE: BVec2 = BVec2 { x: false, y: false };
    const TRUE: BVec2 = BVec2 { x: true, y: true };

    #[inline(always)]
    fn new(x: bool, y: bool) -> BVec2 {
        BVec2 { x, y }
    }

    #[inline(always)]
    fn splat(v: bool) -> BVec2 {
        BVec2 { x: v, y: v }
    }

    #[inline(always)]
    fn from_array(a: [bool; 2]) -> BVec2 {
        let [x, y] = a;
        BVec2 { x, y }
    }

    // A decision tree returning constants: no arithmetic, no range check. It beats the `felt252`
    // weighted sum here, but not on `BVec4` (16 leaves).
    #[inline(always)]
    fn bitmask(self: BVec2) -> u32 {
        if self.y {
            if self.x {
                3
            } else {
                2
            }
        } else if self.x {
            1
        } else {
            0
        }
    }

    // Short-circuit `||`: never more expensive than the eager `|` chain.
    #[inline(always)]
    fn any(self: BVec2) -> bool {
        self.x || self.y
    }

    // Eager `&` (a field multiplication): cheaper than the branches of `&&`.
    #[inline(always)]
    fn all(self: BVec2) -> bool {
        self.x & self.y
    }

    #[inline(always)]
    fn test(self: BVec2, index: usize) -> bool {
        match index {
            0 => self.x,
            1 => self.y,
            _ => core::panic_with_felt252('BVec2: index out of bounds'),
        }
    }

    #[inline(always)]
    fn set(ref self: BVec2, index: usize, value: bool) {
        match index {
            0 => self.x = value,
            1 => self.y = value,
            _ => core::panic_with_felt252('BVec2: index out of bounds'),
        }
    }
}

/// Component-wise logical AND.
///
/// Mirrors `impl BitAnd for glam::BVec2`.
pub impl BVec2BitAnd of BitAnd<BVec2> {
    #[inline(always)]
    fn bitand(lhs: BVec2, rhs: BVec2) -> BVec2 {
        BVec2 { x: lhs.x & rhs.x, y: lhs.y & rhs.y }
    }
}

/// Component-wise logical OR.
///
/// Mirrors `impl BitOr for glam::BVec2`.
pub impl BVec2BitOr of BitOr<BVec2> {
    #[inline(always)]
    fn bitor(lhs: BVec2, rhs: BVec2) -> BVec2 {
        BVec2 { x: lhs.x | rhs.x, y: lhs.y | rhs.y }
    }
}

/// Component-wise logical XOR.
///
/// Mirrors `impl BitXor for glam::BVec2`.
pub impl BVec2BitXor of BitXor<BVec2> {
    #[inline(always)]
    fn bitxor(lhs: BVec2, rhs: BVec2) -> BVec2 {
        BVec2 { x: lhs.x ^ rhs.x, y: lhs.y ^ rhs.y }
    }
}

/// Component-wise logical NOT.
///
/// Mirrors `impl Not for glam::BVec2`.
pub impl BVec2Not of Not<BVec2> {
    #[inline(always)]
    fn not(a: BVec2) -> BVec2 {
        BVec2 { x: !a.x, y: !a.y }
    }
}

/// Mirrors `impl From<[bool; 2]> for glam::BVec2`.
pub impl BoolArrayIntoBVec2 of Into<[bool; 2], BVec2> {
    #[inline(always)]
    fn into(self: [bool; 2]) -> BVec2 {
        BVec2Trait::from_array(self)
    }
}

/// Mirrors `impl From<glam::BVec2> for [bool; 2]`.
pub impl BVec2IntoBoolArray of Into<BVec2, [bool; 2]> {
    #[inline(always)]
    fn into(self: BVec2) -> [bool; 2] {
        [self.x, self.y]
    }
}

/// Mirrors `impl From<glam::BVec2> for [u32; 2]`: `true` maps to `0xffffffff`, `false` to `0`.
pub impl BVec2IntoU32Array of Into<BVec2, [u32; 2]> {
    #[inline(always)]
    fn into(self: BVec2) -> [u32; 2] {
        [mask(self.x), mask(self.y)]
    }
}

#[inline(always)]
fn mask(v: bool) -> u32 {
    if v {
        0xffffffff
    } else {
        0
    }
}
