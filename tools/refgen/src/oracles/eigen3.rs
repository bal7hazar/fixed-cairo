//! Oracles of `glamx::eigen3` (symmetric 3x3 eigen-decomposition). Spec: `specs/eigen3.toml`.
//!
//! Only eigenvalues are golden: the sign of an eigenvector and the basis of a repeated
//! eigenspace are arbitrary, so eigenvectors are checked through their invariants (`A v =
//! lambda v`, orthonormality, handedness, reconstruction) in `tests/test_eigen3.cairo`.
//!
//! Two eigenvalue oracles, both on the symmetric matrix read from the **upper triangle** of the
//! `Mat3` argument, as the Cairo module does:
//!
//! * `glamx::DSymmetricEigen3::eigenvalues` (the f64 closed form of glamx 0.3.1), the parity
//!   oracle. A closed form resolves a double root of the characteristic cubic to the square root
//!   of its precision only (`1e-8` relative in f64, i.e. tens of raw ULPs): the cases whose
//!   smallest gap is below 1 % of the spectrum width are skipped, which keeps the oracle itself
//!   within `0.01` ULP for `|a_ij| <= 16`.
//! * a cyclic Jacobi iteration in f64, accurate to a few `2^-53 |A|` whatever the gaps: the oracle
//!   of the degenerate cases (repeated eigenvalues, rank-deficient matrices).

use crate::prelude::*;
use glamx::DSymmetricEigen3;

/// The symmetric matrix whose upper triangle is the one of `m`.
fn symmetric(m: DMat3) -> DMat3 {
    let (a12, a13, a23) = (m.y_axis.x, m.z_axis.x, m.z_axis.y);
    DMat3::from_cols(
        DVec3::new(m.x_axis.x, a12, a13),
        DVec3::new(a12, m.y_axis.y, a23),
        DVec3::new(a13, a23, m.z_axis.z),
    )
}

/// Ascending eigenvalues by cyclic Jacobi rotations in f64 (Rutishauser's update formulas).
fn jacobi(m: DMat3) -> DVec3 {
    let s = symmetric(m);
    let mut a = [
        [s.x_axis.x, s.y_axis.x, s.z_axis.x],
        [s.y_axis.x, s.y_axis.y, s.z_axis.y],
        [s.z_axis.x, s.z_axis.y, s.z_axis.z],
    ];
    for _ in 0..32 {
        if a[0][1] == 0.0 && a[0][2] == 0.0 && a[1][2] == 0.0 {
            break;
        }
        for (p, q) in [(0, 1), (0, 2), (1, 2)] {
            let apq = a[p][q];
            if apq == 0.0 {
                continue;
            }
            let d = a[q][q] - a[p][p];
            let r = (d * d + 4.0 * apq * apq).sqrt();
            let t = 2.0 * apq / (d + if d < 0.0 { -r } else { r });
            let c = 1.0 / (1.0 + t * t).sqrt();
            let sn = t * c;
            let k = 3 - p - q;
            let (akp, akq) = (a[k][p], a[k][q]);
            a[p][p] -= t * apq;
            a[q][q] += t * apq;
            a[p][q] = 0.0;
            a[q][p] = 0.0;
            a[k][p] = c * akp - sn * akq;
            a[p][k] = a[k][p];
            a[k][q] = sn * akp + c * akq;
            a[q][k] = a[k][q];
        }
    }
    let mut l = [a[0][0], a[1][1], a[2][2]];
    l.sort_by(f64::total_cmp);
    DVec3::from_array(l)
}

/// glamx's closed form, skipped when two eigenvalues are closer than 1 % of the spectrum width.
fn closed_form(m: DMat3) -> Out {
    let l = DSymmetricEigen3::eigenvalues(symmetric(m));
    let width = l.z - l.x;
    if !(l.y - l.x >= 0.01 * width && l.z - l.y >= 0.01 * width) || width == 0.0 {
        return skip("eigenvalues too close for the f64 closed form");
    }
    l.into()
}

pub fn register(r: &mut Registry) {
    r.add("eigenvalues_glamx", |a| closed_form(a[0].dmat3()));
    r.add("eigenvalues_jacobi", |a| jacobi(a[0].dmat3()));
}
