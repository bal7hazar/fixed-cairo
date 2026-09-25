//! Alternative implementations (math / bitwise / loop / table variants) kept for gas comparison.
//! The winner lives in the library; the losers stay here with their benches.

pub mod exp;
pub mod fixed;
pub mod trig;
pub mod wide;
