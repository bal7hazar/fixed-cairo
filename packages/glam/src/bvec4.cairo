//! Port of glam-rs `bool/bvec4.rs` @ 0.33.8: a 4-dimensional `bool` vector mask.
//!
//! Every formulation below is the cheapest of the candidates measured in `gas/bvec4.snap`; the
//! losing candidates live in `benches::alt::bvec4`. The logical operators work on `bool` with
//! the `bool_*_impl` libfuncs: no bitwise builtin cell is consumed.

use core::traits::{BitAnd, BitOr, BitXor};

/// A 4-dimensional `bool` vector mask.
///
/// Mirrors `glam::BVec4`.
/// #### Deviations
/// * `Debug` is the derived Cairo formatting, not glam's `BVec4(0xffffffff, 0x0, ..)`.
/// * `Display` is not implemented.
/// * The by-reference operator overloads (`&a & &b`, ...) and the `*Assign` operators
///   (`&=`, `|=`, `^=`) do not exist in Cairo: use `a = a & b`.
#[derive(Copy, Drop, Serde, PartialEq, Debug, Default, Hash)]
pub struct BVec4 {
    pub x: bool,
    pub y: bool,
    pub z: bool,
    pub w: bool,
}

/// Creates a 4-dimensional `bool` vector mask.
///
/// Mirrors `glam::bvec4`.
/// #### Panics
/// * Never.
/// #### Deviations
/// * None.
#[inline(always)]
pub fn bvec4(x: bool, y: bool, z: bool, w: bool) -> BVec4 {
    BVec4 { x, y, z, w }
}

pub trait BVec4Trait {
    /// All false.
    ///
    /// Mirrors `glam::BVec4::FALSE`.
    const FALSE: BVec4;
    /// All true.
    ///
    /// Mirrors `glam::BVec4::TRUE`.
    const TRUE: BVec4;
    /// Creates a new vector mask.
    ///
    /// Mirrors `glam::BVec4::new`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn new(x: bool, y: bool, z: bool, w: bool) -> BVec4;
    /// Creates a vector mask with all elements set to `v`.
    ///
    /// Mirrors `glam::BVec4::splat`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn splat(v: bool) -> BVec4;
    /// Creates a new vector mask from a bool array.
    ///
    /// Mirrors `glam::BVec4::from_array`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn from_array(a: [bool; 4]) -> BVec4;
    /// Returns a bitmask with the lowest 4 bits set from the elements of `self`.
    ///
    /// A true element results in a `1` bit and a false element in a `0` bit. Element `x` goes
    /// into the first lowest bit, element `y` into the second, etc.
    ///
    /// Mirrors `glam::BVec4::bitmask`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn bitmask(self: BVec4) -> u32;
    /// Returns true if any of the elements are true, false otherwise.
    ///
    /// Mirrors `glam::BVec4::any`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn any(self: BVec4) -> bool;
    /// Returns true if all the elements are true, false otherwise.
    ///
    /// Mirrors `glam::BVec4::all`.
    /// #### Panics
    /// * Never.
    /// #### Deviations
    /// * None.
    fn all(self: BVec4) -> bool;
    /// Tests the value at `index`.
    ///
    /// Mirrors `glam::BVec4::test`.
    /// #### Panics
    /// * `'BVec4: index out of bounds'` if `index` is greater than 3.
    /// #### Deviations
    /// * None.
    fn test(self: BVec4, index: usize) -> bool;
    /// Sets the element at `index`.
    ///
    /// Mirrors `glam::BVec4::set`.
    /// #### Panics
    /// * `'BVec4: index out of bounds'` if `index` is greater than 3.
    /// #### Deviations
    /// * None.
    fn set(ref self: BVec4, index: usize, value: bool);
}

pub impl BVec4Impl of BVec4Trait {
    const FALSE: BVec4 = BVec4 { x: false, y: false, z: false, w: false };
    const TRUE: BVec4 = BVec4 { x: true, y: true, z: true, w: true };

    #[inline(always)]
    fn new(x: bool, y: bool, z: bool, w: bool) -> BVec4 {
        BVec4 { x, y, z, w }
    }

    #[inline(always)]
    fn splat(v: bool) -> BVec4 {
        BVec4 { x: v, y: v, z: v, w: v }
    }

    #[inline(always)]
    fn from_array(a: [bool; 4]) -> BVec4 {
        let [x, y, z, w] = a;
        BVec4 { x, y, z, w }
    }

    // A `felt252` weighted sum (`bool -> felt252` is free) converted back to `u32`: with 16 leaves
    // the decision tree that wins on `BVec2` / `BVec3` is 30 % more expensive than this.
    #[inline(always)]
    fn bitmask(self: BVec4) -> u32 {
        let mask: felt252 = self.x.into()
            + self.y.into() * 2
            + self.z.into() * 4
            + self.w.into() * 8;
        mask.try_into().unwrap()
    }

    // Short-circuit `||`: never more expensive than the eager `|` chain.
    #[inline(always)]
    fn any(self: BVec4) -> bool {
        self.x || self.y || self.z || self.w
    }

    // Eager `&` (a field multiplication): cheaper than the branches of `&&`.
    #[inline(always)]
    fn all(self: BVec4) -> bool {
        self.x & self.y & self.z & self.w
    }

    #[inline(always)]
    fn test(self: BVec4, index: usize) -> bool {
        match index {
            0 => self.x,
            1 => self.y,
            2 => self.z,
            3 => self.w,
            _ => core::panic_with_felt252('BVec4: index out of bounds'),
        }
    }

    #[inline(always)]
    fn set(ref self: BVec4, index: usize, value: bool) {
        match index {
            0 => self.x = value,
            1 => self.y = value,
            2 => self.z = value,
            3 => self.w = value,
            _ => core::panic_with_felt252('BVec4: index out of bounds'),
        }
    }
}

/// Component-wise logical AND.
///
/// Mirrors `impl BitAnd for glam::BVec4`.
pub impl BVec4BitAnd of BitAnd<BVec4> {
    #[inline(always)]
    fn bitand(lhs: BVec4, rhs: BVec4) -> BVec4 {
        BVec4 { x: lhs.x & rhs.x, y: lhs.y & rhs.y, z: lhs.z & rhs.z, w: lhs.w & rhs.w }
    }
}

/// Component-wise logical OR.
///
/// Mirrors `impl BitOr for glam::BVec4`.
pub impl BVec4BitOr of BitOr<BVec4> {
    #[inline(always)]
    fn bitor(lhs: BVec4, rhs: BVec4) -> BVec4 {
        BVec4 { x: lhs.x | rhs.x, y: lhs.y | rhs.y, z: lhs.z | rhs.z, w: lhs.w | rhs.w }
    }
}

/// Component-wise logical XOR.
///
/// Mirrors `impl BitXor for glam::BVec4`.
pub impl BVec4BitXor of BitXor<BVec4> {
    #[inline(always)]
    fn bitxor(lhs: BVec4, rhs: BVec4) -> BVec4 {
        BVec4 { x: lhs.x ^ rhs.x, y: lhs.y ^ rhs.y, z: lhs.z ^ rhs.z, w: lhs.w ^ rhs.w }
    }
}

/// Component-wise logical NOT.
///
/// Mirrors `impl Not for glam::BVec4`.
pub impl BVec4Not of Not<BVec4> {
    #[inline(always)]
    fn not(a: BVec4) -> BVec4 {
        BVec4 { x: !a.x, y: !a.y, z: !a.z, w: !a.w }
    }
}

/// Mirrors `impl From<[bool; 4]> for glam::BVec4`.
pub impl BoolArrayIntoBVec4 of Into<[bool; 4], BVec4> {
    #[inline(always)]
    fn into(self: [bool; 4]) -> BVec4 {
        BVec4Trait::from_array(self)
    }
}

/// Mirrors `impl From<glam::BVec4> for [bool; 4]`.
pub impl BVec4IntoBoolArray of Into<BVec4, [bool; 4]> {
    #[inline(always)]
    fn into(self: BVec4) -> [bool; 4] {
        [self.x, self.y, self.z, self.w]
    }
}

/// Mirrors `impl From<glam::BVec4> for [u32; 4]`: `true` maps to `0xffffffff`, `false` to `0`.
pub impl BVec4IntoU32Array of Into<BVec4, [u32; 4]> {
    #[inline(always)]
    fn into(self: BVec4) -> [u32; 4] {
        [mask(self.x), mask(self.y), mask(self.z), mask(self.w)]
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
