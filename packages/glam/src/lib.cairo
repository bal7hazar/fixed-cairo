//! Port of glam-rs (https://github.com/bitshifter/glam-rs) on top of the `fixed` Q32.32 scalar.
//!
//! Module names mirror glam-rs one-to-one. See `docs/PORTING_STATUS.md` for progress.

pub mod affine2;
pub mod affine3;
pub mod bvec2;
pub mod bvec3;
pub mod bvec4;
pub mod camera;
pub mod euler;
pub mod ivec2;
pub mod ivec3;
pub mod ivec4;
pub mod mat2;
pub mod mat3;
pub mod mat4;
pub mod quat;
pub mod swizzles;
pub mod uvec2;
pub mod uvec3;
pub mod uvec4;
pub mod vec2;
pub mod vec3;
pub mod vec4;
pub use affine2::{Affine2, Affine2Trait};

pub use bvec2::{BVec2, BVec2Trait};
pub use bvec3::{BVec3, BVec3Trait};
pub use bvec4::{BVec4, BVec4Trait};
pub use ivec2::{IVec2, IVec2Trait};
pub use ivec3::{IVec3, IVec3Trait};
pub use ivec4::{IVec4, IVec4Trait};
pub use mat2::{Mat2, Mat2Trait};
pub use mat3::{Mat3, Mat3Trait};
pub use mat4::{Mat4, Mat4Trait};
pub use quat::{Quat, QuatTrait};
pub use swizzles::{
    IVec2Swizzles, IVec3Swizzles, IVec4Swizzles, UVec2Swizzles, UVec3Swizzles, UVec4Swizzles,
    Vec2Swizzles, Vec3Swizzles, Vec4Swizzles,
};
pub use uvec2::{UVec2, UVec2Trait};
pub use uvec3::{UVec3, UVec3Trait};
pub use uvec4::{UVec4, UVec4Trait};
pub use vec2::{Vec2, Vec2Trait};
pub use vec3::{Vec3, Vec3Trait};
pub use vec4::{Vec4, Vec4Trait};
