//! Alternative implementations benchmarked against `glam::euler` (the `alt_*` rows of
//! `gas/euler.snap`). The library ships the formulation it documents; the others stay here so
//! that the comparison is reproducible across compiler upgrades.
//!
//! The 24 orders decode to the same arithmetic with a different axis permutation, so the
//! variants below are specialized to `EulerRot::YXZ` (the default order: permutation
//! `(i, j, k) = (1, 0, 2)`, odd parity, no repeated axis, intrinsic frame). What is measured is
//! the shape of the arithmetic, not the `match` that selects it, which is common to all of them.

use fixed::fixed::Fixed;
use fixed::trig::TrigTrait;
use glam::mat3::Mat3;
use glam::quat::{Quat, QuatTrait};
use glam::vec3::Vec3;

/// Alternative to `Mat3::from_euler`. The literal glam-rs formulation: the four intermediate
/// products `cc = ci * ch`, `cs`, `sc`, `ss` are rounded first and combined with `cj` / `sj`
/// afterwards, i.e. two rescales per entry instead of one, for a strictly larger error.
pub fn mat3_from_euler_glam(a: Fixed, b: Fixed, c: Fixed) -> Mat3 {
    let (si, ci) = a.sin_cos();
    let (sj, cj) = b.sin_cos();
    let (sh, ch) = c.sin_cos();
    let cc = ci * ch;
    let cs = ci * sh;
    let sc = si * ch;
    let ss = si * sh;
    let (ii, ij, ik) = (cj * ch, sj * sc - cs, sj * cc + ss);
    let (ji, jj, jk) = (cj * sh, sj * ss + cc, sj * cs - sc);
    let (ki, kj, kk) = (-sj, cj * si, cj * ci);
    Mat3 {
        x_axis: Vec3 { x: jj, y: ji, z: jk },
        y_axis: Vec3 { x: ij, y: ii, z: ik },
        z_axis: Vec3 { x: kj, y: ki, z: kk },
    }
}

/// Alternative to `Quat::from_euler`. The literal glam-rs formulation, with the same four
/// rounded intermediates.
pub fn quat_from_euler_glam(a: Fixed, b: Fixed, c: Fixed) -> Quat {
    let half = Fixed { raw: 0x80000000 };
    let (si, ci) = (a * half).sin_cos();
    let (sj, cj) = (b * half).sin_cos();
    let (sh, ch) = (c * half).sin_cos();
    let cc = ci * ch;
    let cs = ci * sh;
    let sc = si * ch;
    let ss = si * sh;
    let ai = cj * sc - sj * cs;
    let aj = cj * ss + sj * cc;
    let ak = cj * cs - sj * sc;
    let w = cj * cc + sj * ss;
    Quat { x: aj, y: ai, z: ak, w }
}

/// Alternative to `Quat::from_euler`: the composition of the three elemental quaternions, which
/// is how the identity is stated but not how glam-rs computes it. Three `sin_cos` plus two
/// Hamilton products, and the product rounds twice more.
pub fn quat_from_euler_compose(a: Fixed, b: Fixed, c: Fixed) -> Quat {
    QuatTrait::from_rotation_y(a) * QuatTrait::from_rotation_x(b) * QuatTrait::from_rotation_z(c)
}
