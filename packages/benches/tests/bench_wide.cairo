//! Benchmarks of `fixed::wide`: one `X__base` / `X__op` pair per public function (inlined, i.e.
//! the marginal cost inside a caller's kernel), the glam kernel shapes written against the
//! accumulator API behind a call boundary (`composite_*`: what a user of `glam` pays, and the
//! reference formulations for the porters), and the losing alternatives (`alt_*`).
use benches::alt::{fixed as alt_fixed, wide as alt_wide};
use benches::harness::{bb, sink};
use fixed::Fixed;
use fixed::wide::{
    NormTrait, RecipTrait, WideAdd, WideLift, WideMul, WideNarrow, WideNeg, WideSqrt, WideSub, det3,
    distance2, distance2_squared, distance3, distance3_squared, distance4, distance4_squared, dot2,
    dot2_add, dot3, dot3_add, dot4, mul_add, mul_sub, norm2, norm2_squared, norm2_wide, norm3,
    norm3_squared, norm3_wide, norm4, norm4_squared, norm4_wide, normalize2, normalize3, normalize4,
    wide_from, wide_mul,
};

#[derive(Copy, Drop)]
struct V3 {
    x: Fixed,
    y: Fixed,
    z: Fixed,
}

#[derive(Copy, Drop)]
struct V4 {
    x: Fixed,
    y: Fixed,
    z: Fixed,
    w: Fixed,
}

/// Column-major, like glam.
#[derive(Copy, Drop)]
struct M3 {
    x_axis: V3,
    y_axis: V3,
    z_axis: V3,
}

/// Column-major, like glam.
#[derive(Copy, Drop)]
struct M4 {
    x_axis: V4,
    y_axis: V4,
    z_axis: V4,
    w_axis: V4,
}

fn v3(x: i64, y: i64, z: i64) -> V3 {
    V3 { x: Fixed { raw: x }, y: Fixed { raw: y }, z: Fixed { raw: z } }
}

fn v4(x: i64, y: i64, z: i64, w: i64) -> V4 {
    V4 { x: Fixed { raw: x }, y: Fixed { raw: y }, z: Fixed { raw: z }, w: Fixed { raw: w } }
}

fn m3a() -> M3 {
    M3 {
        x_axis: v3(3865470566, -429496730, 1717986918),
        y_axis: v3(858993459, 4724464025, -1288490189),
        z_axis: v3(-2147483648, 2576980377, 3435973836),
    }
}

fn m3b() -> M3 {
    M3 {
        x_axis: v3(6442450944, 1073741824, -3221225472),
        y_axis: v3(-5368709120, 2147483648, 8589934592),
        z_axis: v3(429496729, -858993460, 1288490188),
    }
}

fn m4a() -> M4 {
    M4 {
        x_axis: v4(3865470566, -429496730, 1717986918, 0),
        y_axis: v4(858993459, 4724464025, -1288490189, 0),
        z_axis: v4(-2147483648, 2576980377, 3435973836, 0),
        w_axis: v4(4294967296, 8589934592, 12884901888, 4294967296),
    }
}

fn m4b() -> M4 {
    M4 {
        x_axis: v4(6442450944, 1073741824, -3221225472, 0),
        y_axis: v4(-5368709120, 2147483648, 8589934592, 0),
        z_axis: v4(429496729, -858993460, 1288490188, 0),
        w_axis: v4(-17179869184, 21474836480, 25769803776, 4294967296),
    }
}

#[inline(never)]
fn composite_dot3(a: V3, b: V3) -> Fixed {
    dot3(a.x, b.x, a.y, b.y, a.z, b.z)
}

#[inline(never)]
fn composite_length3(a: V3) -> Fixed {
    norm3(a.x, a.y, a.z)
}

#[inline(never)]
fn composite_distance3(a: V3, b: V3) -> Fixed {
    distance3(a.x, a.y, a.z, b.x, b.y, b.z)
}

#[inline(never)]
fn composite_normalize3(a: V3) -> V3 {
    let (x, y, z) = normalize3(a.x, a.y, a.z);
    V3 { x, y, z }
}

/// `try_normalize` written against `Norm`: one square root, no panic path for a zero vector.
#[inline(never)]
fn composite_try_normalize3(a: V3) -> Option<V3> {
    match norm3_wide(a.x, a.y, a.z).try_recip() {
        Some(r) => Some(V3 { x: r.mul(a.x), y: r.mul(a.y), z: r.mul(a.z) }),
        None => None,
    }
}

#[inline(never)]
fn composite_cross(a: V3, b: V3) -> V3 {
    V3 {
        x: mul_sub(a.y, b.z, b.y, a.z),
        y: mul_sub(a.z, b.x, b.z, a.x),
        z: mul_sub(a.x, b.y, b.x, a.y),
    }
}

#[inline(always)]
fn m3_mul_v3(m: M3, v: V3) -> V3 {
    V3 {
        x: dot3(m.x_axis.x, v.x, m.y_axis.x, v.y, m.z_axis.x, v.z),
        y: dot3(m.x_axis.y, v.x, m.y_axis.y, v.y, m.z_axis.y, v.z),
        z: dot3(m.x_axis.z, v.x, m.y_axis.z, v.y, m.z_axis.z, v.z),
    }
}

#[inline(never)]
fn composite_mat3_mul_vec3(m: M3, v: V3) -> V3 {
    m3_mul_v3(m, v)
}

#[inline(never)]
fn composite_mat3_mul_mat3(a: M3, b: M3) -> M3 {
    M3 {
        x_axis: m3_mul_v3(a, b.x_axis),
        y_axis: m3_mul_v3(a, b.y_axis),
        z_axis: m3_mul_v3(a, b.z_axis),
    }
}

#[inline(always)]
fn m4_mul_v4(m: M4, v: V4) -> V4 {
    V4 {
        x: dot4(m.x_axis.x, v.x, m.y_axis.x, v.y, m.z_axis.x, v.z, m.w_axis.x, v.w),
        y: dot4(m.x_axis.y, v.x, m.y_axis.y, v.y, m.z_axis.y, v.z, m.w_axis.y, v.w),
        z: dot4(m.x_axis.z, v.x, m.y_axis.z, v.y, m.z_axis.z, v.z, m.w_axis.z, v.w),
        w: dot4(m.x_axis.w, v.x, m.y_axis.w, v.y, m.z_axis.w, v.z, m.w_axis.w, v.w),
    }
}

#[inline(never)]
fn composite_mat4_mul_mat4(a: M4, b: M4) -> M4 {
    M4 {
        x_axis: m4_mul_v4(a, b.x_axis),
        y_axis: m4_mul_v4(a, b.y_axis),
        z_axis: m4_mul_v4(a, b.z_axis),
        w_axis: m4_mul_v4(a, b.w_axis),
    }
}

#[inline(never)]
fn composite_mat3_determinant(m: M3) -> Fixed {
    det3(
        m.x_axis.x,
        m.x_axis.y,
        m.x_axis.z,
        m.y_axis.x,
        m.y_axis.y,
        m.y_axis.z,
        m.z_axis.x,
        m.z_axis.y,
        m.z_axis.z,
    )
}

/// glam `Mat3::inverse`: adjugate (9 fused `mul_sub`), exact determinant (`det3`), then ONE
/// division (`Recip`) and 9 fused multiplications.
#[inline(never)]
fn composite_mat3_inverse(m: M3) -> M3 {
    let (a, b, c) = (m.x_axis, m.y_axis, m.z_axis);
    let r = RecipTrait::new(det3(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z));
    // tmp0 = b x c, tmp1 = c x a, tmp2 = a x b; inverse = transpose(tmp0, tmp1, tmp2) / det
    let t0 = composite_cross_inline(b, c);
    let t1 = composite_cross_inline(c, a);
    let t2 = composite_cross_inline(a, b);
    M3 {
        x_axis: V3 { x: r.mul(t0.x), y: r.mul(t1.x), z: r.mul(t2.x) },
        y_axis: V3 { x: r.mul(t0.y), y: r.mul(t1.y), z: r.mul(t2.y) },
        z_axis: V3 { x: r.mul(t0.z), y: r.mul(t1.z), z: r.mul(t2.z) },
    }
}

#[inline(always)]
fn composite_cross_inline(a: V3, b: V3) -> V3 {
    V3 {
        x: mul_sub(a.y, b.z, b.y, a.z),
        y: mul_sub(a.z, b.x, b.z, a.x),
        z: mul_sub(a.x, b.y, b.x, a.y),
    }
}

/// glam `Quat::mul_quat`: four sums of four products, signs through `sub` (free) rather than
/// by negating the operands.
#[inline(never)]
fn composite_quat_mul(a: V4, b: V4) -> V4 {
    V4 {
        x: wide_mul(a.w, b.x)
            .add(wide_mul(a.x, b.w))
            .add(wide_mul(a.y, b.z))
            .sub(wide_mul(a.z, b.y))
            .narrow(),
        y: wide_mul(a.w, b.y)
            .sub(wide_mul(a.x, b.z))
            .add(wide_mul(a.y, b.w))
            .add(wide_mul(a.z, b.x))
            .narrow(),
        z: wide_mul(a.w, b.z)
            .add(wide_mul(a.x, b.y))
            .sub(wide_mul(a.y, b.x))
            .add(wide_mul(a.z, b.w))
            .narrow(),
        w: wide_mul(a.w, b.w)
            .sub(wide_mul(a.x, b.x))
            .sub(wide_mul(a.y, b.y))
            .sub(wide_mul(a.z, b.z))
            .narrow(),
    }
}

/// glam `Quat::mul_vec3`: `v * (w^2 - b.b) + b * 2 (v.b) + (b x v) * 2 w` with b = (x, y, z).
/// Every term is a triple product: the three sums stay exact at the Q96.96 scale (`T14`) and
/// each output component is rescaled once.
#[inline(never)]
fn composite_quat_rotate(q: V4, v: V3) -> V3 {
    let s1 = wide_mul(q.w, q.w)
        .sub(wide_mul(q.x, q.x))
        .sub(wide_mul(q.y, q.y))
        .sub(wide_mul(q.z, q.z)); // W4: w^2 - b.b
    let d = wide_mul(v.x, q.x).add(wide_mul(v.y, q.y)).add(wide_mul(v.z, q.z)); // W3: v.b
    let s2 = d.add(d); // W6: 2 (v.b)
    let cx = wide_mul(q.y, v.z).sub(wide_mul(v.y, q.z)); // W2: (b x v).x
    let cy = wide_mul(q.z, v.x).sub(wide_mul(v.z, q.x));
    let cz = wide_mul(q.x, v.y).sub(wide_mul(v.x, q.y));
    V3 {
        x: s1.mul(v.x).add(s2.mul(q.x)).add(cx.add(cx).mul(q.w)).narrow(), // T4 + T6 + T4
        y: s1.mul(v.y).add(s2.mul(q.y)).add(cy.add(cy).mul(q.w)).narrow(),
        z: s1.mul(v.z).add(s2.mul(q.z)).add(cz.add(cz).mul(q.w)).narrow(),
    }
}

#[test]
fn wide_mul_narrow__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn wide_mul_narrow__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(wide_mul(a, b).narrow());
}

#[test]
fn wide_from__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn wide_from__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(Fixed { raw: 1 });
    sink(wide_mul(a, b).add(wide_from(c)).narrow());
}

#[test]
fn wide_add__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn wide_add__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(wide_mul(a, b).add(wide_mul(c, d)).narrow());
}

#[test]
fn wide_sub__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn wide_sub__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(wide_mul(a, b).sub(wide_mul(c, d)).narrow());
}

#[test]
fn wide_neg__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn wide_neg__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(wide_mul(a, b).neg().narrow());
}

#[test]
fn wide_mul_fixed__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn wide_mul_fixed__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(Fixed { raw: 1 });
    sink(wide_mul(a, b).mul(c).narrow());
}

#[test]
fn wide_lift__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn wide_lift__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(wide_mul(a, b).mul(c).add(wide_mul(d, a).lift()).narrow());
}

#[test]
fn wide_sqrt__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn wide_sqrt__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(wide_mul(a, a).sub(wide_mul(c, d)).sqrt());
}

#[test]
fn wide_sum16__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn wide_sum16__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(
        {
            let p = wide_mul(a, b).add(wide_mul(c, d));
            let q = p.add(p);
            let r = q.add(q);
            r.add(r).narrow()
        },
    );
}

#[test]
fn triple_sum16__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn triple_sum16__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(
        {
            let p = wide_mul(a, b).add(wide_mul(c, d)).mul(c);
            let q = p.add(p);
            let r = q.add(q);
            r.add(r).narrow()
        },
    );
}

#[test]
fn dot2__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn dot2__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(dot2(a, b, c, d));
}

#[test]
fn dot3__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn dot3__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(dot3(a, b, c, d, a, c));
}

#[test]
fn dot4__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn dot4__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(dot4(a, b, c, d, a, c, b, d));
}

#[test]
fn dot2_add__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn dot2_add__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(dot2_add(a, b, c, d, a));
}

#[test]
fn dot3_add__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn dot3_add__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(dot3_add(a, b, c, d, a, c, b));
}

#[test]
fn mul_add__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn mul_add__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(Fixed { raw: 1 });
    sink(mul_add(a, b, c));
}

#[test]
fn mul_sub__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn mul_sub__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(mul_sub(a, b, c, d));
}

#[test]
fn det3__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn det3__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(det3(a, b, c, d, a, c, b, d, a));
}

#[test]
fn norm2_squared__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn norm2_squared__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(norm2_squared(a, b));
}

#[test]
fn norm3_squared__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn norm3_squared__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(Fixed { raw: 1 });
    sink(norm3_squared(a, b, c));
}

#[test]
fn norm4_squared__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn norm4_squared__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(norm4_squared(a, b, c, d));
}

#[test]
fn norm2__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn norm2__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(norm2(a, b));
}

#[test]
fn norm3__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn norm3__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(Fixed { raw: 1 });
    sink(norm3(a, b, c));
}

#[test]
fn norm4__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn norm4__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(norm4(a, b, c, d));
}

#[test]
fn norm2_wide__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn norm2_wide__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(norm2_wide(a, b).to_fixed());
}

#[test]
fn norm3_wide__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn norm3_wide__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(Fixed { raw: 1 });
    sink(norm3_wide(a, b, c).to_fixed());
}

#[test]
fn norm4_wide__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn norm4_wide__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(norm4_wide(a, b, c, d).to_fixed());
}

#[test]
fn norm_is_zero__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(true));
}

#[test]
fn norm_is_zero__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(true);
    sink(norm3_wide(a, b, c).is_zero());
}

#[test]
fn distance2__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn distance2__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(distance2(a, b, c, d));
}

#[test]
fn distance3__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn distance3__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(distance3(a, b, c, d, a, c));
}

#[test]
fn distance4__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn distance4__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(distance4(a, b, c, d, a, c, b, d));
}

#[test]
fn distance2_squared__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn distance2_squared__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(distance2_squared(a, b, c, d));
}

#[test]
fn distance3_squared__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn distance3_squared__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(distance3_squared(a, b, c, d, a, c));
}

#[test]
fn distance4_squared__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn distance4_squared__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(distance4_squared(a, b, c, d, a, c, b, d));
}

#[test]
fn recip_new__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn recip_new__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(RecipTrait::new(a).mul(a));
}

#[test]
fn recip_mul__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn recip_mul__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink({
        let r = RecipTrait::new(a);
        r.mul(a) + r.mul(b)
    });
}

#[test]
fn normalize2__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb((Fixed { raw: 1 }, Fixed { raw: 1 })));
}

#[test]
fn normalize2__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb((Fixed { raw: 1 }, Fixed { raw: 1 }));
    sink(normalize2(a, b));
}

#[test]
fn normalize3__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb((Fixed { raw: 1 }, Fixed { raw: 1 }, Fixed { raw: 1 })));
}

#[test]
fn normalize3__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb((Fixed { raw: 1 }, Fixed { raw: 1 }, Fixed { raw: 1 }));
    sink(normalize3(a, b, c));
}

#[test]
fn normalize4__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb((Fixed { raw: 1 }, Fixed { raw: 1 }, Fixed { raw: 1 }, Fixed { raw: 1 })));
}

#[test]
fn normalize4__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb((Fixed { raw: 1 }, Fixed { raw: 1 }, Fixed { raw: 1 }, Fixed { raw: 1 }));
    sink(normalize4(a, b, c, d));
}

#[test]
fn composite_dot3__base() {
    let _u = bb(v3(5368709120, -10737418240, 16106127360));
    let _v = bb(v3(-3006477108, 18038862643, 1503238553));
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn composite_dot3__op() {
    let u = bb(v3(5368709120, -10737418240, 16106127360));
    let v = bb(v3(-3006477108, 18038862643, 1503238553));
    let _r = bb(Fixed { raw: 1 });
    sink(composite_dot3(u, v));
}

#[test]
fn composite_length3__base() {
    let _u = bb(v3(5368709120, -10737418240, 16106127360));
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn composite_length3__op() {
    let u = bb(v3(5368709120, -10737418240, 16106127360));
    let _r = bb(Fixed { raw: 1 });
    sink(composite_length3(u));
}

#[test]
fn composite_distance3__base() {
    let _u = bb(v3(5368709120, -10737418240, 16106127360));
    let _v = bb(v3(-3006477108, 18038862643, 1503238553));
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn composite_distance3__op() {
    let u = bb(v3(5368709120, -10737418240, 16106127360));
    let v = bb(v3(-3006477108, 18038862643, 1503238553));
    let _r = bb(Fixed { raw: 1 });
    sink(composite_distance3(u, v));
}

#[test]
fn composite_normalize3__base() {
    let _u = bb(v3(5368709120, -10737418240, 16106127360));
    sink(bb(v3(1, 1, 1)));
}

#[test]
fn composite_normalize3__op() {
    let u = bb(v3(5368709120, -10737418240, 16106127360));
    let _r = bb(v3(1, 1, 1));
    sink(composite_normalize3(u));
}

#[test]
fn composite_try_normalize3__base() {
    let _u = bb(v3(5368709120, -10737418240, 16106127360));
    sink(bb(Option::Some(v3(1, 1, 1))));
}

#[test]
fn composite_try_normalize3__op() {
    let u = bb(v3(5368709120, -10737418240, 16106127360));
    let _r = bb(Option::Some(v3(1, 1, 1)));
    sink(composite_try_normalize3(u));
}

#[test]
fn composite_cross__base() {
    let _u = bb(v3(5368709120, -10737418240, 16106127360));
    let _v = bb(v3(-3006477108, 18038862643, 1503238553));
    sink(bb(v3(1, 1, 1)));
}

#[test]
fn composite_cross__op() {
    let u = bb(v3(5368709120, -10737418240, 16106127360));
    let v = bb(v3(-3006477108, 18038862643, 1503238553));
    let _r = bb(v3(1, 1, 1));
    sink(composite_cross(u, v));
}

#[test]
fn composite_mat3_mul_vec3__base() {
    let _m = bb(m3a());
    let _v = bb(v3(5368709120, -10737418240, 16106127360));
    sink(bb(v3(1, 1, 1)));
}

#[test]
fn composite_mat3_mul_vec3__op() {
    let m = bb(m3a());
    let v = bb(v3(5368709120, -10737418240, 16106127360));
    let _r = bb(v3(1, 1, 1));
    sink(composite_mat3_mul_vec3(m, v));
}

#[test]
fn composite_mat3_mul_mat3__base() {
    let _m = bb(m3a());
    let _n = bb(m3b());
    sink(bb(m3a()));
}

#[test]
fn composite_mat3_mul_mat3__op() {
    let m = bb(m3a());
    let n = bb(m3b());
    let _r = bb(m3a());
    sink(composite_mat3_mul_mat3(m, n));
}

#[test]
fn composite_mat4_mul_mat4__base() {
    let _m = bb(m4a());
    let _n = bb(m4b());
    sink(bb(m4a()));
}

#[test]
fn composite_mat4_mul_mat4__op() {
    let m = bb(m4a());
    let n = bb(m4b());
    let _r = bb(m4a());
    sink(composite_mat4_mul_mat4(m, n));
}

#[test]
fn composite_mat3_determinant__base() {
    let _m = bb(m3a());
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn composite_mat3_determinant__op() {
    let m = bb(m3a());
    let _r = bb(Fixed { raw: 1 });
    sink(composite_mat3_determinant(m));
}

#[test]
fn composite_mat3_inverse__base() {
    let _m = bb(m3a());
    sink(bb(m3a()));
}

#[test]
fn composite_mat3_inverse__op() {
    let m = bb(m3a());
    let _r = bb(m3a());
    sink(composite_mat3_inverse(m));
}

#[test]
fn composite_quat_mul__base() {
    let _p = bb(v4(784150175, 1568300307, 2352450482, 3136600614));
    let _q = bb(v4(-2147483648, 2147483648, -2147483648, 2147483648));
    sink(bb(v4(1, 1, 1, 1)));
}

#[test]
fn composite_quat_mul__op() {
    let p = bb(v4(784150175, 1568300307, 2352450482, 3136600614));
    let q = bb(v4(-2147483648, 2147483648, -2147483648, 2147483648));
    let _r = bb(v4(1, 1, 1, 1));
    sink(composite_quat_mul(p, q));
}

#[test]
fn composite_quat_rotate__base() {
    let _q = bb(v4(784150175, 1568300307, 2352450482, 3136600614));
    let _v = bb(v3(5368709120, -10737418240, 16106127360));
    sink(bb(v3(1, 1, 1)));
}

#[test]
fn composite_quat_rotate__op() {
    let q = bb(v4(784150175, 1568300307, 2352450482, 3136600614));
    let v = bb(v3(5368709120, -10737418240, 16106127360));
    let _r = bb(v3(1, 1, 1));
    sink(composite_quat_rotate(q, v));
}

#[test]
fn alt_triple_single_downcast__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_triple_single_downcast__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt_fixed::triple_single_downcast(a, b, c, d, a));
}

#[test]
fn alt_triple_two_stage__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_triple_two_stage__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt_fixed::triple_two_stage(a, b, c, d, a));
}

#[test]
fn alt_dot3_unfused__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_dot3_unfused__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt_wide::dot3_unfused(a, b, c, d, a, c));
}

#[test]
fn alt_mul_sub_unfused__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_mul_sub_unfused__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt_wide::mul_sub_unfused(a, b, c, d));
}

#[test]
fn alt_det3_cross_dot__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_det3_cross_dot__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt_wide::det3_cross_dot(a, b, c, d, a, c, b, d, a));
}

#[test]
fn alt_norm3_via_squared__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_norm3_via_squared__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt_wide::norm3_via_squared(a, b, c));
}

#[test]
fn alt_normalize3_recip_mul__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb((Fixed { raw: 1 }, Fixed { raw: 1 }, Fixed { raw: 1 })));
}

#[test]
fn alt_normalize3_recip_mul__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb((Fixed { raw: 1 }, Fixed { raw: 1 }, Fixed { raw: 1 }));
    sink(alt_wide::normalize3_recip_mul(a, b, c));
}

#[test]
fn alt_normalize3_div__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb((Fixed { raw: 1 }, Fixed { raw: 1 }, Fixed { raw: 1 })));
}

#[test]
fn alt_normalize3_div__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb((Fixed { raw: 1 }, Fixed { raw: 1 }, Fixed { raw: 1 }));
    sink(alt_wide::normalize3_div(a, b, c));
}
