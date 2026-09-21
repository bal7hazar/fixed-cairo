//! Port of Dimforge glamx 0.3.1 (https://github.com/dimforge/glamx) on top of `glam` and the
//! `fixed` Q32.32 scalar: the rigid-body math used by parry and rapier.
//!
//! Scope and priorities: `docs/research/06-glamx-scope.md`.

pub mod eigen3;
pub mod pose2;
pub mod pose3;
pub mod rot2;
pub mod rot3;
pub mod sdp;

pub use eigen3::{Mat3ExtTrait, SymmetricEigen3, SymmetricEigen3Trait};
pub use pose2::{Pose2, Pose2Trait, Rot2Pose2Trait};
pub use pose3::{Pose3, Pose3Trait, Rot3Pose3Trait};
pub use rot2::{Rot2, Rot2Trait};
pub use rot3::Rot3;
pub use sdp::{SdpMatrix2, SdpMatrix2Trait, SdpMatrix3, SdpMatrix3Trait};
