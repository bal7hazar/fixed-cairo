//! Port of glam-rs `bool/bvec3.rs` @ 0.33.8: a 3-dimensional `bool` vector mask.
//!
//! Every formulation below is the cheapest of the candidates measured in `gas/bvec3.snap`; the
//! losing candidates live in `benches::alt::bvec3`. The logical operators work on `bool` with
//! the `bool_*_impl` libfuncs: no bitwise builtin cell is consumed.

use core::traits::{BitAnd, BitOr, BitXor};

/// A 3-dimensional `bool` vector mask.
///
/// Mirrors `glam::BVec3`.
/// #### Deviations
/// * `Debug` is the derived Cairo formatting, not glam's `BVec3(0xffffffff, 0x0, ..)`.
/// * `Display` is not implemented.
/// * The by-reference operator overloads (`&a & &b`, ...) and the `*Assign` operators
///   (`&=`, `|=`, `^=`) do not exist in Cairo: use `a = a & b`.
#[derive(Copy, Drop, Serde, PartialEq, Debug, Default, Hash)]
pub struct BVec3 {
    pub x: bool,
    pub y: bool,
    pub z: bool,
}

/// Creates a 3-dimensional `bool` vector mask.
///
/// Mirrors `glam::bvec3`.
/// #### Panics
/// * Never.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn bvec3(x: bool, y: bool, z: bool) -> BVec3 {
    BVec3 { x, y, z }
}

pub trait BVec3Trait {
    /// All false.
    ///
    /// Mirrors `glam::BVec3::FALSE`.
    const FALSE: BVec3;
    /// All true.
    ///
    /// Mirrors `glam::BVec3::TRUE`.
    const TRUE: BVec3;
    /// Creates a new vector mask.
    ///
    /// Mirrors `glam::BVec3::new`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn new(x: bool, y: bool, z: bool) -> BVec3;
    /// Creates a vector mask with all elements set to `v`.
    ///
    /// Mirrors `glam::BVec3::splat`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn splat(v: bool) -> BVec3;
    /// Creates a new vector mask from a bool array.
    ///
    /// Mirrors `glam::BVec3::from_array`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_array(a: [bool; 3]) -> BVec3;
    /// Returns a bitmask with the lowest 3 bits set from the elements of `self`.
    ///
    /// A true element results in a `1` bit and a false element in a `0` bit. Element `x` goes
    /// into the first lowest bit, element `y` into the second, etc.
    ///
    /// Mirrors `glam::BVec3::bitmask`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn bitmask(self: BVec3) -> u32;
    /// Returns true if any of the elements are true, false otherwise.
    ///
    /// Mirrors `glam::BVec3::any`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn any(self: BVec3) -> bool;
    /// Returns true if all the elements are true, false otherwise.
    ///
    /// Mirrors `glam::BVec3::all`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn all(self: BVec3) -> bool;
    /// Tests the value at `index`.
    ///
    /// Mirrors `glam::BVec3::test`.
    /// #### Panics
    /// * `'BVec3: index out of bounds'` if `index` is greater than 2.
    /// #### Deviations
    /// * None.
    fn test(self: BVec3, index: usize) -> bool;
    /// Sets the element at `index`.
    ///
    /// Mirrors `glam::BVec3::set`.
    /// #### Panics
    /// * `'BVec3: index out of bounds'` if `index` is greater than 2.
    /// #### Deviations
    /// * None.
    fn set(ref self: BVec3, index: usize, value: bool);
}

pub impl BVec3Impl of BVec3Trait {
    const FALSE: BVec3 = BVec3 { x: false, y: false, z: false };
    const TRUE: BVec3 = BVec3 { x: true, y: true, z: true };

    #[inline(always)]
    fn new(x: bool, y: bool, z: bool) -> BVec3 {
        BVec3 { x, y, z }
    }

    #[inline(always)]
    fn splat(v: bool) -> BVec3 {
        BVec3 { x: v, y: v, z: v }
    }

    #[inline(always)]
    fn from_array(a: [bool; 3]) -> BVec3 {
        let [x, y, z] = a;
        BVec3 { x, y, z }
    }

    // A decision tree returning constants: no arithmetic, no range check. It beats the `felt252`
    // weighted sum here, but not on `BVec4` (16 leaves).
    #[inline(always)]
    fn bitmask(self: BVec3) -> u32 {
        if self.z {
            if self.y {
                if self.x {
                    7
                } else {
                    6
                }
            } else if self.x {
                5
            } else {
                4
            }
        } else if self.y {
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
    fn any(self: BVec3) -> bool {
        self.x || self.y || self.z
    }

    // Eager `&` (a field multiplication): cheaper than the branches of `&&`.
    #[inline(always)]
    fn all(self: BVec3) -> bool {
        self.x & self.y & self.z
    }

    #[inline(always)]
    fn test(self: BVec3, index: usize) -> bool {
        match index {
            0 => self.x,
            1 => self.y,
            2 => self.z,
            _ => core::panic_with_felt252('BVec3: index out of bounds'),
        }
    }

    #[inline(always)]
    fn set(ref self: BVec3, index: usize, value: bool) {
        match index {
            0 => self.x = value,
            1 => self.y = value,
            2 => self.z = value,
            _ => core::panic_with_felt252('BVec3: index out of bounds'),
        }
    }
}

/// Component-wise logical AND.
///
/// Mirrors `impl BitAnd for glam::BVec3`.
pub impl BVec3BitAnd of BitAnd<BVec3> {
    #[inline(always)]
    fn bitand(lhs: BVec3, rhs: BVec3) -> BVec3 {
        BVec3 { x: lhs.x & rhs.x, y: lhs.y & rhs.y, z: lhs.z & rhs.z }
    }
}

/// Component-wise logical OR.
///
/// Mirrors `impl BitOr for glam::BVec3`.
pub impl BVec3BitOr of BitOr<BVec3> {
    #[inline(always)]
    fn bitor(lhs: BVec3, rhs: BVec3) -> BVec3 {
        BVec3 { x: lhs.x | rhs.x, y: lhs.y | rhs.y, z: lhs.z | rhs.z }
    }
}

/// Component-wise logical XOR.
///
/// Mirrors `impl BitXor for glam::BVec3`.
pub impl BVec3BitXor of BitXor<BVec3> {
    #[inline(always)]
    fn bitxor(lhs: BVec3, rhs: BVec3) -> BVec3 {
        BVec3 { x: lhs.x ^ rhs.x, y: lhs.y ^ rhs.y, z: lhs.z ^ rhs.z }
    }
}

/// Component-wise logical NOT.
///
/// Mirrors `impl Not for glam::BVec3`.
pub impl BVec3Not of Not<BVec3> {
    #[inline(always)]
    fn not(a: BVec3) -> BVec3 {
        BVec3 { x: !a.x, y: !a.y, z: !a.z }
    }
}

/// Mirrors `impl From<[bool; 3]> for glam::BVec3`.
pub impl BoolArrayIntoBVec3 of Into<[bool; 3], BVec3> {
    #[inline(always)]
    fn into(self: [bool; 3]) -> BVec3 {
        BVec3Trait::from_array(self)
    }
}

/// Mirrors `impl From<glam::BVec3> for [bool; 3]`.
pub impl BVec3IntoBoolArray of Into<BVec3, [bool; 3]> {
    #[inline(always)]
    fn into(self: BVec3) -> [bool; 3] {
        [self.x, self.y, self.z]
    }
}

/// Mirrors `impl From<glam::BVec3> for [u32; 3]`: `true` maps to `0xffffffff`, `false` to `0`.
pub impl BVec3IntoU32Array of Into<BVec3, [u32; 3]> {
    #[inline(always)]
    fn into(self: BVec3) -> [u32; 3] {
        [mask(self.x), mask(self.y), mask(self.z)]
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
