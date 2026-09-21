//! Alternative implementations benchmarked against `glamx::eigen3` (the `alt_*` rows of
//! `gas/eigen3.snap`).
//!
//! [`symmetric_eigen_closed_form`] is the algorithm of glamx 0.3.1 (`eigen3.rs`, after Eberly's
//! "A Robust Eigensolver for 3 x 3 Symmetric Matrices"): the trigonometric roots of the
//! characteristic cubic (`acos`, two `cos`), then the eigenvectors by cross products. It is the
//! loser of the accuracy study of `scripts/gen_eigen3.py study`, which mirrors it bit for bit:
//! a double root of a cubic is only resolved to the square root of the precision of its
//! coefficients, so in Q32.32 the eigenvalues of a matrix with two close eigenvalues are off by
//! up to `6.8e4 ULP * |A|` (against `0.62` for the Jacobi iteration of the library), and the
//! middle eigenvalue, computed from the trace, can come out of order. The library's module
//! documentation carries the comparison table.
//!
//! What "careful" means here, beyond the glamx source:
//!
//! * the matrix is scaled by a power of two so that its largest magnitude lies in `[2^8, 2^12)`:
//!   the squares of the closed form cannot overflow and small matrices keep 40 to 44
//!   significant bits (the input is scaled **down**, i.e. loses low bits, from `2^12` on);
//! * the first eigenvector is the one of the most isolated eigenvalue (Eberly: the largest one
//!   if `det(B) >= 0`, else the smallest; glamx always starts from the smallest);
//! * multiplicity 3: a cross product shorter than `2^13` raw (scaled domain) is noise, because
//!   the 1 ULP rounding of the eigenvalue already moves it by `|A| * 1 ULP <= 2^12` raw
//!   (glamx: `d_max < 1e-20`, which is below one squared Q32.32 ULP).

use fixed::fixed::{FRAC_PI_3, Fixed, FixedTrait, HALF, ONE, ZERO};
use fixed::trig::TrigTrait;
use fixed::wide::{
    RecipTrait, WideAdd, WideMul, WideNarrow, WideSqrt, WideSub, dot3, mul_add, mul_sub, norm3,
    wide_from, wide_mul,
};
use glam::mat3::{Mat3, Mat3Trait};
use glam::vec3::{Vec3, Vec3Trait};
use glamx::eigen3::SymmetricEigen3;

const THREE: Fixed = Fixed { raw: 0x300000000 };
const SIX: Fixed = Fixed { raw: 0x600000000 };
/// `2 pi / 3`, as twice the raw value of `FRAC_PI_3`.
const FRAC_2_PI_3: Fixed = Fixed { raw: 8995358470 };
/// The shortest cross product (raw length, scaled domain) that is not rounding noise.
const CROSS_MIN: Fixed = Fixed { raw: 0x2000 };

/// The 6 unique entries of a symmetric matrix (row, column indices from 1).
#[derive(Copy, Drop)]
struct Sym {
    a11: Fixed,
    a12: Fixed,
    a13: Fixed,
    a22: Fixed,
    a23: Fixed,
    a33: Fixed,
}

/// A power-of-two scale: `x * up * up / 2^64` scales up, `(y + half) * down * down / 2^64` back.
#[derive(Copy, Drop)]
struct Scale {
    up: Fixed,
    down: Fixed,
    half: Fixed,
}

#[inline(always)]
fn scale(up: i64, down: i64, half: i64) -> Scale {
    Scale { up: Fixed { raw: up }, down: Fixed { raw: down }, half: Fixed { raw: half } }
}

// GENERATED-BEGIN eigen3
/// The power-of-two scale `2^e` that brings a largest raw magnitude `m > 0` into
/// `[2^40, 2^44)`: `e` is even, from `42` down to `-14` in steps of 4, then `-20` for
/// `m >= 2^58` (scaled into `[2^38, 2^43]`). An unrolled binary search on constant
/// thresholds (4 comparisons, no loop, no bitwise operation). `up = 2^(32 + e/2)`,
/// `down = 2^(32 - e/2)`, `half = 2^(e - 1)` (`0` if `e <= 0`), as raw values.
#[allow(collapsible_if_else)]
fn scale_of(m: i64) -> Scale {
    if m < 0x40000000 {
        if m < 0x4000 {
            if m < 0x40 {
                if m < 0x4 {
                    scale(0x20000000000000, 0x800, 0x20000000000)
                } else {
                    scale(0x8000000000000, 0x2000, 0x2000000000)
                }
            } else {
                if m < 0x400 {
                    scale(0x2000000000000, 0x8000, 0x200000000)
                } else {
                    scale(0x800000000000, 0x20000, 0x20000000)
                }
            }
        } else {
            if m < 0x400000 {
                if m < 0x40000 {
                    scale(0x200000000000, 0x80000, 0x2000000)
                } else {
                    scale(0x80000000000, 0x200000, 0x200000)
                }
            } else {
                if m < 0x4000000 {
                    scale(0x20000000000, 0x800000, 0x20000)
                } else {
                    scale(0x8000000000, 0x2000000, 0x2000)
                }
            }
        }
    } else {
        if m < 0x400000000000 {
            if m < 0x4000000000 {
                if m < 0x400000000 {
                    scale(0x2000000000, 0x8000000, 0x200)
                } else {
                    scale(0x800000000, 0x20000000, 0x20)
                }
            } else {
                if m < 0x40000000000 {
                    scale(0x200000000, 0x80000000, 0x2)
                } else {
                    scale(0x80000000, 0x200000000, 0x0)
                }
            }
        } else {
            if m < 0x40000000000000 {
                if m < 0x4000000000000 {
                    scale(0x20000000, 0x800000000, 0x0)
                } else {
                    scale(0x8000000, 0x2000000000, 0x0)
                }
            } else {
                if m < 0x400000000000000 {
                    scale(0x2000000, 0x8000000000, 0x0)
                } else {
                    scale(0x400000, 0x40000000000, 0x0)
                }
            }
        }
    }
}
// GENERATED-END eigen3

#[inline(always)]
fn scale_up(x: Fixed, s: Scale) -> Fixed {
    wide_mul(x, s.up).mul(s.up).narrow()
}

#[inline(always)]
fn scale_down(y: Fixed, s: Scale) -> Fixed {
    wide_mul(y + s.half, s.down).mul(s.down).narrow()
}

/// The scale of `mat` and its scaled upper triangle, or `None` for the zero matrix.
fn scaled(mat: Mat3) -> Option<(Sym, Scale)> {
    let (a11, a12, a13) = (mat.x_axis.x, mat.y_axis.x, mat.z_axis.x);
    let (a22, a23, a33) = (mat.y_axis.y, mat.z_axis.y, mat.z_axis.z);
    let m = a11.abs().max(a12.abs()).max(a13.abs());
    let m = m.max(a22.abs()).max(a23.abs()).max(a33.abs());
    if m.raw == 0 {
        return None;
    }
    let s = scale_of(m.raw);
    Some(
        (
            Sym {
                a11: scale_up(a11, s),
                a12: scale_up(a12, s),
                a13: scale_up(a13, s),
                a22: scale_up(a22, s),
                a23: scale_up(a23, s),
                a33: scale_up(a33, s),
            },
            s,
        ),
    )
}

/// Ascending 3-element sorting network.
fn sort3(a: Fixed, b: Fixed, c: Fixed) -> (Fixed, Fixed, Fixed) {
    let (a, b) = if a > b {
        (b, a)
    } else {
        (a, b)
    };
    let (b, c) = if b > c {
        (c, b)
    } else {
        (b, c)
    };
    let (a, b) = if a > b {
        (b, a)
    } else {
        (a, b)
    };
    (a, b, c)
}

/// `glamx::SymmetricEigen3::eigenvalues` on the scaled matrix: the eigenvalues (ascending up to
/// the rounding of the middle one) and `r = det(B) / 2`, whose sign tells which end of the
/// spectrum is isolated.
fn eigenvalues_scaled(a: Sym) -> (Fixed, Fixed, Fixed, Fixed) {
    if a.a12.raw == 0 && a.a13.raw == 0 && a.a23.raw == 0 {
        let (l0, l1, l2) = sort3(a.a11, a.a22, a.a33);
        return (l0, l1, l2, ONE);
    }
    let trace = a.a11 + a.a22 + a.a33;
    let q = trace / THREE;
    let (d1, d2, d3) = (a.a11 - q, a.a22 - q, a.a33 - q);
    let off = wide_mul(a.a12, a.a12).add(wide_mul(a.a13, a.a13)).add(wide_mul(a.a23, a.a23));
    let p2 = wide_mul(d1, d1)
        .add(wide_mul(d2, d2))
        .add(wide_mul(d3, d3))
        .add(off.add(off))
        .narrow();
    let p = (p2 / SIX).sqrt();
    let r = if p.raw != 0 {
        let inv = RecipTrait::new(p);
        let (b11, b12, b13) = (inv.mul(d1), inv.mul(a.a12), inv.mul(a.a13));
        let (b22, b23, b33) = (inv.mul(d2), inv.mul(a.a23), inv.mul(d3));
        let det = wide_mul(b22, b33)
            .sub(wide_mul(b23, b23))
            .mul(b11)
            .add(wide_mul(b23, b13).sub(wide_mul(b33, b12)).mul(b12))
            .add(wide_mul(b12, b23).sub(wide_mul(b13, b22)).mul(b13))
            .narrow();
        det * HALF
    } else {
        ONE
    };
    let phi = if r <= -ONE {
        FRAC_PI_3
    } else if r >= ONE {
        ZERO
    } else {
        r.acos() / THREE
    };
    let two_p = p + p;
    let e1 = mul_add(two_p, phi.cos(), q);
    let e3 = mul_add(two_p, (phi + FRAC_2_PI_3).cos(), q);
    (e3, trace - e1 - e3, e1, r)
}

/// `glamx::SymmetricEigen3::eigenvector1`: the longest cross product of two rows of
/// `A - lambda I`.
fn eigenvector1(a: Sym, lambda: Fixed) -> Vec3 {
    let c0 = Vec3 { x: a.a11 - lambda, y: a.a12, z: a.a13 };
    let c1 = Vec3 { x: a.a12, y: a.a22 - lambda, z: a.a23 };
    let c2 = Vec3 { x: a.a13, y: a.a23, z: a.a33 - lambda };
    let x01 = c0.cross(c1);
    let x02 = c0.cross(c2);
    let x12 = c1.cross(c2);
    let mut best = x01;
    let mut d_max = norm3(x01.x, x01.y, x01.z);
    let d1 = norm3(x02.x, x02.y, x02.z);
    if d1 > d_max {
        d_max = d1;
        best = x02;
    }
    let d2 = norm3(x12.x, x12.y, x12.z);
    if d2 > d_max {
        d_max = d2;
        best = x12;
    }
    if d_max < CROSS_MIN {
        return Vec3Trait::X;
    }
    best.normalize()
}

/// `(1, small / big)` normalised.
fn unit(big: Fixed, small: Fixed) -> (Fixed, Fixed) {
    let ratio = small / big;
    let inv = RecipTrait::new(wide_mul(ratio, ratio).add(wide_from(ONE)).sqrt());
    (inv.mul(ONE), inv.mul(ratio))
}

/// `cu * u - cv * v`.
fn comb(cu: Fixed, u: Vec3, cv: Fixed, v: Vec3) -> Vec3 {
    Vec3 {
        x: mul_sub(cu, u.x, cv, v.x), y: mul_sub(cu, u.y, cv, v.y), z: mul_sub(cu, u.z, cv, v.z),
    }
}

fn mul_vec(a: Sym, x: Vec3) -> Vec3 {
    Vec3 {
        x: dot3(a.a11, x.x, a.a12, x.y, a.a13, x.z),
        y: dot3(a.a12, x.x, a.a22, x.y, a.a23, x.z),
        z: dot3(a.a13, x.x, a.a23, x.y, a.a33, x.z),
    }
}

/// `glamx::SymmetricEigen3::eigenvector2`: the kernel of the 2x2 projection of `A - lambda I`
/// on the plane orthogonal to `w`.
fn eigenvector2(a: Sym, w: Vec3, lambda: Fixed) -> Vec3 {
    let (u, v) = w.any_orthonormal_pair();
    let au = mul_vec(a, u);
    let av = mul_vec(a, v);
    let m00 = u.dot(au) - lambda;
    let m01 = u.dot(av);
    let m11 = v.dot(av) - lambda;
    let (abs00, abs01, abs11) = (m00.abs(), m01.abs(), m11.abs());
    if abs00 >= abs11 {
        if abs00.max(abs01).raw > 0 {
            if abs00 >= abs01 {
                let (n00, n01) = unit(m00, m01);
                return comb(n01, u, n00, v);
            }
            let (n01, n00) = unit(m01, m00);
            return comb(n01, u, n00, v);
        }
    } else if abs11.max(abs01).raw > 0 {
        if abs11 >= abs01 {
            let (n11, n01) = unit(m11, m01);
            return comb(n11, u, n01, v);
        }
        let (n01, n11) = unit(m01, m11);
        return comb(n11, u, n01, v);
    }
    u
}

/// Alternative to `SymmetricEigen3Trait::eigenvalues`: the closed form of glamx (no
/// eigenvector). The middle eigenvalue can come out of order by a few ULPs.
pub fn symmetric_eigenvalues_closed_form(mat: Mat3) -> Vec3 {
    match scaled(mat) {
        Some((
            a, s,
        )) => {
            let (l0, l1, l2, _) = eigenvalues_scaled(a);
            Vec3 { x: scale_down(l0, s), y: scale_down(l1, s), z: scale_down(l2, s) }
        },
        None => Vec3Trait::ZERO,
    }
}

/// Alternative to `SymmetricEigen3Trait::new`: the closed form of glamx with Eberly's ordering
/// (module documentation). Reads the upper triangle, like the library.
pub fn symmetric_eigen_closed_form(mat: Mat3) -> SymmetricEigen3 {
    match scaled(mat) {
        Some((
            a, s,
        )) => {
            let (l0, l1, l2, r) = eigenvalues_scaled(a);
            let (w0, w1, w2) = if r.raw >= 0 {
                let w2 = eigenvector1(a, l2);
                let w1 = eigenvector2(a, w2, l1);
                (w1.cross(w2), w1, w2)
            } else {
                let w0 = eigenvector1(a, l0);
                let w1 = eigenvector2(a, w0, l1);
                (w0, w1, w0.cross(w1))
            };
            SymmetricEigen3 {
                eigenvalues: Vec3 {
                    x: scale_down(l0, s), y: scale_down(l1, s), z: scale_down(l2, s),
                },
                eigenvectors: Mat3 { x_axis: w0, y_axis: w1, z_axis: w2 },
            }
        },
        None => SymmetricEigen3 { eigenvalues: Vec3Trait::ZERO, eigenvectors: Mat3Trait::IDENTITY },
    }
}
