//! Starknet contract fixture that links `fixed` into a deployable class, so that the size of a
//! consumer can be tracked against the network limits.
//!
//! Measurement fixture, not a product: `scripts/bytecode_size.py` builds this package in the
//! release profile and reports the Sierra and CASM sizes of every contract
//! (`gas/bytecode.size`). Every input comes from calldata, so that nothing is constant-folded.
//!
//! `Scalar` has one entry point per `fixed` family. The heavier fixtures (`Particles2d`,
//! `Rigid3d`, `KitchenSink`) link `glam` / `glamx` and live in their repositories.

pub mod scalar;
