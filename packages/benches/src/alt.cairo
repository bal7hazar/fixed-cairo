//! Alternative implementations (math / bitwise / loop / table variants) kept for gas comparison.
//! The winner lives in the library; the losers stay here with their benches.

pub mod affine2;
pub mod affine3;
pub mod bvec2;
pub mod bvec3;
pub mod bvec4;
pub mod camera;
pub mod euler;
pub mod fixed;
pub mod ivec2;
pub mod ivec3;
pub mod ivec4;
pub mod mat2;
pub mod mat3;
pub mod mat4;
pub mod quat;
pub mod swizzles;
pub mod trig;
pub mod uvec2;
pub mod uvec3;
pub mod uvec4;
pub mod vec2;
pub mod vec3;
pub mod vec4;
pub mod wide;
