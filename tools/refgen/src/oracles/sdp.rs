//! Oracles of `glamx::sdp` (parry `SdpMatrix2/3`, rapier `AngularInertiaOps`, the world-inertia
//! kernel). Spec: `specs/sdp.toml`.
//!
//! There is no f64 `SdpMatrix` type in glam or glamx: a symmetric matrix travels as a full `Mat2`
//! / `Mat3` whose upper triangle is read (`from_sdp_matrix`) and is emitted symmetric
//! (`into_matrix`). Two kinds of oracles:
//!
//! * integer oracles (tolerance 0): every function of the module is an exactly defined
//!   integer computation (fused sums rescaled by `floor`, one `Recip` rounded to nearest), redone
//!   here in `i128` with checked operations; an intermediate that leaves the 128-bit range means
//!   the Cairo result does not fit `i64` either and the case is skipped;
//! * f64 oracles on `DMat2` / `DMat3` (the literal parry formulas in double precision), with the
//!   error bound of the fixed-point formulation as tolerance.

use crate::prelude::*;

// ------------------------------------------------------------------------------------------------
// Integer helpers.

/// The 6 unique raw components `[m11, m12, m13, m22, m23, m33]` of the `Mat3` argument `v`, read
/// as `from_sdp_matrix` does (upper triangle, column-major leaves).
fn sdp3(v: &Value) -> [i128; 6] {
    let l = &v.leaves;
    [l[0], l[3], l[6], l[4], l[7], l[8]].map(i128::from)
}

/// The 3 unique raw components `[m11, m12, m22]` of the `Mat2` argument `v`.
fn sdp2(v: &Value) -> [i128; 3] {
    let l = &v.leaves;
    [l[0], l[2], l[3]].map(i128::from)
}

fn leaves(v: &Value) -> Vec<i128> {
    v.leaves.iter().map(|x| i128::from(*x)).collect()
}

fn to_i64(v: Option<i128>) -> Option<i64> {
    v.and_then(|v| i64::try_from(v).ok())
}

/// `into_matrix` of the 6 unique components, as a `Mat3` value; overflow skips the case.
fn out3(s: [Option<i128>; 6]) -> Out {
    let s: Option<Vec<i64>> = s.iter().map(|x| to_i64(*x)).collect();
    match s {
        Some(s) => {
            Value::new(Ty::Mat3, vec![s[0], s[1], s[2], s[1], s[3], s[4], s[2], s[4], s[5]]).into()
        }
        None => Out::raw_checked(None),
    }
}

/// `into_matrix` of the 3 unique components, as a `Mat2` value; overflow skips the case.
fn out2(s: [Option<i128>; 3]) -> Out {
    let s: Option<Vec<i64>> = s.iter().map(|x| to_i64(*x)).collect();
    match s {
        Some(s) => Value::new(Ty::Mat2, vec![s[0], s[1], s[1], s[2]]).into(),
        None => Out::raw_checked(None),
    }
}

fn out_vec(ty: Ty, xs: Vec<Option<i128>>) -> Out {
    let xs: Option<Vec<i64>> = xs.iter().map(|x| to_i64(*x)).collect();
    match xs {
        Some(xs) => Value::new(ty, xs).into(),
        None => Out::raw_checked(None),
    }
}

/// `floor(a * b / 2^32)`: `Fixed * Fixed`.
fn mul(a: i128, b: i128) -> Option<i128> {
    Some(a.checked_mul(b)? >> FRAC_BITS)
}

/// The exact Q64.64 sum `sum_i a_i b_i`.
fn wide_dot(pairs: &[(i128, i128)]) -> Option<i128> {
    pairs.iter().try_fold(0i128, |acc, (a, b)| acc.checked_add(a.checked_mul(*b)?))
}

/// `floor(sum_i a_i b_i / 2^32)`: one fused `dot` kernel.
fn dot(pairs: &[(i128, i128)]) -> Option<i128> {
    Some(wide_dot(pairs)? >> FRAC_BITS)
}

/// `floor(sum_i w_i c_i / 2^64)` for exact Q64.64 terms `w_i`: one fused triple-product kernel.
fn triple(terms: &[(Option<i128>, i128)]) -> Option<i128> {
    let sum = terms.iter().try_fold(0i128, |acc, (w, c)| acc.checked_add(w.as_ref()?.checked_mul(*c)?))?;
    Some(sum >> (2 * FRAC_BITS))
}

/// `x / d` rounded to nearest, ties toward +infinity, through the truncated 96-bit reciprocal:
/// what `RecipTrait::new(d).mul(x)` returns.
fn recip_mul(d: i128, x: i128) -> Option<i128> {
    let recip = (1i128 << 96) / d;
    Some((x.checked_mul(recip)?.checked_add(1 << 63)?) >> 64)
}

/// `m^T s m` with `s * m` exact and one rescale per output (`quadform`).
fn quadform(s: [i128; 6], m: &[i128]) -> [Option<i128>; 6] {
    let [m11, m12, m13, m22, m23, m33] = s;
    let rows = [[m11, m12, m13], [m12, m22, m23], [m13, m23, m33]];
    let col = |j: usize| [m[3 * j], m[3 * j + 1], m[3 * j + 2]];
    // sm[k][j] = row k of s . column j of m, exact.
    let sm = |k: usize, j: usize| {
        let c = col(j);
        wide_dot(&[(rows[k][0], c[0]), (rows[k][1], c[1]), (rows[k][2], c[2])])
    };
    let q = |i: usize, j: usize| {
        let c = col(i);
        triple(&[(sm(0, j), c[0]), (sm(1, j), c[1]), (sm(2, j), c[2])])
    };
    [q(0, 0), q(0, 1), q(0, 2), q(1, 1), q(1, 2), q(2, 2)]
}

/// `r diag(d) r^T`, one rescale per output (`from_rotated_diagonal_mat3`); `r` column-major.
fn rotated_diagonal(r: &[Option<i128>], d: &[i128]) -> [Option<i128>; 6] {
    // r_ik = column k, row i.
    let rr = |i: usize, k: usize| r[3 * k + i];
    let q = |i: usize, j: usize| -> Option<i128> {
        let terms: Option<Vec<(Option<i128>, i128)>> = (0..3)
            .map(|k| Some((rr(i, k)?.checked_mul(d[k]), rr(j, k)?)))
            .collect();
        triple(&terms?)
    };
    [q(0, 0), q(0, 1), q(0, 2), q(1, 1), q(1, 2), q(2, 2)]
}

/// `Mat3::from_quat` of glam.cairo: one fused floor rescale per element, from `x2 = x + x`...
fn from_quat(q: &[i128]) -> Vec<Option<i128>> {
    let (x, y, z, w) = (q[0], q[1], q[2], q[3]);
    let (x2, y2, z2) = (x + x, y + y, z + z);
    let one = 1i128 << (2 * FRAC_BITS);
    let f = |s: i128| Some(s >> FRAC_BITS);
    vec![
        f(one - y * y2 - z * z2),
        f(x * y2 + w * z2),
        f(x * z2 - w * y2),
        f(x * y2 - w * z2),
        f(one - x * x2 - z * z2),
        f(y * z2 + w * x2),
        f(x * z2 + w * y2),
        f(y * z2 - w * x2),
        f(one - x * x2 - y * y2),
    ]
}

/// `inverse_unchecked` of a symmetric 3x3 matrix; `None` when the floored determinant is zero.
fn inverse3(s: [i128; 6]) -> Option<[Option<i128>; 6]> {
    let [m11, m12, m13, m22, m23, m33] = s;
    let a = (m22 * m33).checked_sub(m23 * m23)?;
    let b = (m12 * m33).checked_sub(m13 * m23)?;
    let c = (m12 * m23).checked_sub(m13 * m22)?;
    let det = a
        .checked_mul(m11)?
        .checked_sub(b.checked_mul(m12)?)?
        .checked_add(c.checked_mul(m13)?)?
        >> (2 * FRAC_BITS);
    if det == 0 {
        return None;
    }
    let cof = [
        a >> FRAC_BITS,
        (-b) >> FRAC_BITS,
        c >> FRAC_BITS,
        (m11 * m33 - m13 * m13) >> FRAC_BITS,
        (m13 * m12 - m23 * m11) >> FRAC_BITS,
        (m11 * m22 - m12 * m12) >> FRAC_BITS,
    ];
    Some(cof.map(|x| recip_mul(det, x)))
}

/// `inverse_unchecked` of a symmetric 2x2 matrix; `None` when the floored determinant is zero.
fn inverse2(s: [i128; 3]) -> Option<[Option<i128>; 3]> {
    let [m11, m12, m22] = s;
    let det = (m11 * m22 - m12 * m12) >> FRAC_BITS;
    if det == 0 {
        return None;
    }
    Some([recip_mul(det, m22), recip_mul(det, -m12), recip_mul(det, m11)])
}

// ------------------------------------------------------------------------------------------------
// f64 helpers.

/// The symmetric `DMat3` whose upper triangle is the one of the argument.
fn dsym3(v: &Value) -> DMat3 {
    let m = v.dmat3();
    DMat3::from_cols(
        DVec3::new(m.x_axis.x, m.y_axis.x, m.z_axis.x),
        DVec3::new(m.y_axis.x, m.y_axis.y, m.z_axis.y),
        DVec3::new(m.z_axis.x, m.z_axis.y, m.z_axis.z),
    )
}

/// The symmetric `DMat2` whose upper triangle is the one of the argument.
fn dsym2(v: &Value) -> DMat2 {
    let m = v.dmat2();
    DMat2::from_cols(DVec2::new(m.x_axis.x, m.y_axis.x), DVec2::new(m.y_axis.x, m.y_axis.y))
}

/// A random symmetric positive-definite matrix `R diag(e) R^T` with eigenvalues `e` in `[1, 4]`,
/// quantized: its determinant stays near `e1 e2 e3 >= 1` and its cofactors below `16`.
fn spd3(rng: &mut Rng) -> Value {
    let mut leaf = |lo: i64, hi: i64| raw_to_f64(rng.range_i64(lo, hi));
    let axis = DVec3::new(leaf(-ONE_RAW, ONE_RAW), leaf(-ONE_RAW, ONE_RAW), leaf(-ONE_RAW, ONE_RAW));
    let axis = if axis.length() < 0.1 { DVec3::Z } else { axis.normalize() };
    let angle = leaf(-4 * ONE_RAW, 4 * ONE_RAW);
    let e = DVec3::new(leaf(ONE_RAW, 4 * ONE_RAW), leaf(ONE_RAW, 4 * ONE_RAW), leaf(ONE_RAW, 4 * ONE_RAW));
    let r = DMat3::from_axis_angle(axis, angle);
    value_of(r * DMat3::from_diagonal(e) * r.transpose())
}

/// A random symmetric positive-definite 2x2 matrix with eigenvalues in `[1, 4]`, quantized.
fn spd2(rng: &mut Rng) -> Value {
    let mut leaf = |lo: i64, hi: i64| raw_to_f64(rng.range_i64(lo, hi));
    let angle = leaf(-4 * ONE_RAW, 4 * ONE_RAW);
    let e = DVec2::new(leaf(ONE_RAW, 4 * ONE_RAW), leaf(ONE_RAW, 4 * ONE_RAW));
    let r = DMat2::from_angle(angle);
    value_of(r * DMat2::from_diagonal(e) * r.transpose())
}

pub fn register(r: &mut Registry) {
    r.generator("spd3", spd3);
    r.generator("spd2", spd2);

    // --- SdpMatrix3, exact ----------------------------------------------------------------------
    r.add("add", |a| {
        let (s, t) = (sdp3(&a[0]), sdp3(&a[1]));
        out3(std::array::from_fn(|i| Some(s[i] + t[i])))
    });
    r.add("sub", |a| {
        let (s, t) = (sdp3(&a[0]), sdp3(&a[1]));
        out3(std::array::from_fn(|i| Some(s[i] - t[i])))
    });
    r.add("mul_scalar", |a| {
        let (s, k) = (sdp3(&a[0]), i128::from(a[1].raw()));
        out3(s.map(|x| mul(x, k)))
    });
    r.add("add_diagonal", |a| {
        let (s, k) = (sdp3(&a[0]), i128::from(a[1].raw()));
        out3([Some(s[0] + k), Some(s[1]), Some(s[2]), Some(s[3] + k), Some(s[4]), Some(s[5] + k)])
    });
    r.add("mul_vec", |a| {
        let ([m11, m12, m13, m22, m23, m33], v) = (sdp3(&a[0]), leaves(&a[1]));
        out_vec(
            Ty::Vec3,
            vec![
                dot(&[(m11, v[0]), (m12, v[1]), (m13, v[2])]),
                dot(&[(m12, v[0]), (m22, v[1]), (m23, v[2])]),
                dot(&[(m13, v[0]), (m23, v[1]), (m33, v[2])]),
            ],
        )
    });
    r.add("mul_mat", |a| {
        let ([m11, m12, m13, m22, m23, m33], m) = (sdp3(&a[0]), leaves(&a[1]));
        let rows = [[m11, m12, m13], [m12, m22, m23], [m13, m23, m33]];
        let xs = (0..9)
            .map(|n| {
                let (j, i) = (n / 3, n % 3);
                dot(&[(rows[i][0], m[3 * j]), (rows[i][1], m[3 * j + 1]), (rows[i][2], m[3 * j + 2])])
            })
            .collect();
        out_vec(Ty::Mat3, xs)
    });
    r.add("quadform", |a| out3(quadform(sdp3(&a[0]), &leaves(&a[1]))));
    r.add("quadform_f64", |a| {
        let (s, m) = (dsym3(&a[0]), a[1].dmat3());
        m.transpose() * s * m
    });
    r.add("inverse", |a| -> Out {
        match inverse3(sdp3(&a[0])) {
            Some(inv) => out3(inv),
            None => skip("singular: covered by `inverse_singular` and the panic tests"),
        }
    });
    r.add("inverse_zero", |a| -> Out {
        match inverse3(sdp3(&a[0])) {
            Some(_) => skip("regular matrix"),
            None => out3([Some(0); 6]),
        }
    });
    r.add("inverse_f64", |a| dsym3(&a[0]).inverse());
    r.add("from_rotated_diagonal_mat3", |a| {
        let (m, d) = (leaves(&a[0]), leaves(&a[1]));
        let m: Vec<Option<i128>> = m.into_iter().map(Some).collect();
        out3(rotated_diagonal(&m, &d))
    });
    r.add("from_rotated_diagonal_mat3_f64", |a| {
        let (m, d) = (a[0].dmat3(), a[1].dvec3());
        m * DMat3::from_diagonal(d) * m.transpose()
    });
    r.add("from_rotated_diagonal", |a| {
        let (q, d) = (leaves(&a[0]), leaves(&a[1]));
        out3(rotated_diagonal(&from_quat(&q), &d))
    });
    r.add("from_rotated_diagonal_f64", |a| {
        let m = DMat3::from_quat(a[0].dquat());
        m * DMat3::from_diagonal(a[1].dvec3()) * m.transpose()
    });

    // --- SdpMatrix2, exact ----------------------------------------------------------------------
    r.add("add2", |a| {
        let (s, t) = (sdp2(&a[0]), sdp2(&a[1]));
        out2(std::array::from_fn(|i| Some(s[i] + t[i])))
    });
    r.add("sub2", |a| {
        let (s, t) = (sdp2(&a[0]), sdp2(&a[1]));
        out2(std::array::from_fn(|i| Some(s[i] - t[i])))
    });
    r.add("mul_scalar2", |a| {
        let (s, k) = (sdp2(&a[0]), i128::from(a[1].raw()));
        out2(s.map(|x| mul(x, k)))
    });
    r.add("add_diagonal2", |a| {
        let (s, k) = (sdp2(&a[0]), i128::from(a[1].raw()));
        out2([Some(s[0] + k), Some(s[1]), Some(s[2] + k)])
    });
    r.add("mul_vec2", |a| {
        let ([m11, m12, m22], v) = (sdp2(&a[0]), leaves(&a[1]));
        out_vec(Ty::Vec2, vec![dot(&[(m11, v[0]), (m12, v[1])]), dot(&[(m12, v[0]), (m22, v[1])])])
    });
    r.add("inverse_unchecked2", |a| -> Out {
        match inverse2(sdp2(&a[0])) {
            Some(inv) => out2(inv),
            None => skip("singular: covered by the panic tests"),
        }
    });
    r.add("inverse2_f64", |a| dsym2(&a[0]).inverse());
}
