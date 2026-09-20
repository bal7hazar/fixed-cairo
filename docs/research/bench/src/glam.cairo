//! Minimal glam-like composite workloads, generic over the scalar representation.
//! Every composite is `#[inline(never)]` (it is what a library user would call) and is written flat
//! against the `Fused` kernels, so the only thing that changes between representations is the
//! scalar arithmetic.
use crate::fixed::{Fused, Real};

#[derive(Copy, Drop)]
pub struct Vec3<T> {
    pub x: T,
    pub y: T,
    pub z: T,
}
#[derive(Copy, Drop)]
pub struct Quat<T> {
    pub x: T,
    pub y: T,
    pub z: T,
    pub w: T,
}
/// Column-major, like glam.
#[derive(Copy, Drop)]
pub struct Mat3<T> {
    pub x_axis: Vec3<T>,
    pub y_axis: Vec3<T>,
    pub z_axis: Vec3<T>,
}
#[derive(Copy, Drop)]
pub struct Vec4<T> {
    pub x: T,
    pub y: T,
    pub z: T,
    pub w: T,
}
#[derive(Copy, Drop)]
pub struct Mat4<T> {
    pub x_axis: Vec4<T>,
    pub y_axis: Vec4<T>,
    pub z_axis: Vec4<T>,
    pub w_axis: Vec4<T>,
}

#[inline(never)]
pub fn vec3_add<T, +Add<T>, +Drop<T>>(a: Vec3<T>, b: Vec3<T>) -> Vec3<T> {
    Vec3 { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z }
}

#[inline(never)]
pub fn vec3_scale<T, +Mul<T>, +Copy<T>, +Drop<T>>(a: Vec3<T>, s: T) -> Vec3<T> {
    Vec3 { x: a.x * s, y: a.y * s, z: a.z * s }
}

#[inline(never)]
pub fn dot<T, +Fused<T>, +Drop<T>>(a: Vec3<T>, b: Vec3<T>) -> T {
    Fused::dot3(a.x, b.x, a.y, b.y, a.z, b.z)
}

#[inline(never)]
pub fn cross<T, +Fused<T>, +Copy<T>, +Drop<T>>(a: Vec3<T>, b: Vec3<T>) -> Vec3<T> {
    Vec3 {
        x: Fused::mul_sub(a.y, b.z, b.y, a.z),
        y: Fused::mul_sub(a.z, b.x, b.z, a.x),
        z: Fused::mul_sub(a.x, b.y, b.x, a.y),
    }
}

#[inline(never)]
pub fn length<T, +Fused<T>, +Drop<T>>(a: Vec3<T>) -> T {
    Fused::norm3(a.x, a.y, a.z)
}

/// glam: `self * self.length_recip()` -> 1 sqrt, 1 div, 3 mul.
#[inline(never)]
pub fn normalize<T, +Fused<T>, +Real<T>, +Mul<T>, +Div<T>, +Copy<T>, +Drop<T>>(a: Vec3<T>) -> Vec3<T> {
    let inv = Real::from_int(1) / Fused::norm3(a.x, a.y, a.z);
    Vec3 { x: a.x * inv, y: a.y * inv, z: a.z * inv }
}

#[inline(never)]
pub fn mat3_mul_vec3<T, +Fused<T>, +Copy<T>, +Drop<T>>(m: Mat3<T>, v: Vec3<T>) -> Vec3<T> {
    Vec3 {
        x: Fused::dot3(m.x_axis.x, v.x, m.y_axis.x, v.y, m.z_axis.x, v.z),
        y: Fused::dot3(m.x_axis.y, v.x, m.y_axis.y, v.y, m.z_axis.y, v.z),
        z: Fused::dot3(m.x_axis.z, v.x, m.y_axis.z, v.y, m.z_axis.z, v.z),
    }
}

/// Flat expansion (9 dot3): `#[inline(always)]` is rejected on functions with impl generic
/// parameters (E2143), so helper functions cannot be force-inlined in generic code.
#[inline(never)]
pub fn mat3_mul_mat3<T, +Fused<T>, +Copy<T>, +Drop<T>>(a: Mat3<T>, b: Mat3<T>) -> Mat3<T> {
    Mat3 {
        x_axis: Vec3 {
            x: Fused::dot3(a.x_axis.x, b.x_axis.x, a.y_axis.x, b.x_axis.y, a.z_axis.x, b.x_axis.z),
            y: Fused::dot3(a.x_axis.y, b.x_axis.x, a.y_axis.y, b.x_axis.y, a.z_axis.y, b.x_axis.z),
            z: Fused::dot3(a.x_axis.z, b.x_axis.x, a.y_axis.z, b.x_axis.y, a.z_axis.z, b.x_axis.z),
        },
        y_axis: Vec3 {
            x: Fused::dot3(a.x_axis.x, b.y_axis.x, a.y_axis.x, b.y_axis.y, a.z_axis.x, b.y_axis.z),
            y: Fused::dot3(a.x_axis.y, b.y_axis.x, a.y_axis.y, b.y_axis.y, a.z_axis.y, b.y_axis.z),
            z: Fused::dot3(a.x_axis.z, b.y_axis.x, a.y_axis.z, b.y_axis.y, a.z_axis.z, b.y_axis.z),
        },
        z_axis: Vec3 {
            x: Fused::dot3(a.x_axis.x, b.z_axis.x, a.y_axis.x, b.z_axis.y, a.z_axis.x, b.z_axis.z),
            y: Fused::dot3(a.x_axis.y, b.z_axis.x, a.y_axis.y, b.z_axis.y, a.z_axis.y, b.z_axis.z),
            z: Fused::dot3(a.x_axis.z, b.z_axis.x, a.y_axis.z, b.z_axis.y, a.z_axis.z, b.z_axis.z),
        },
    }
}

#[inline(never)]
pub fn mat4_mul_mat4<T, +Fused<T>, +Copy<T>, +Drop<T>>(a: Mat4<T>, b: Mat4<T>) -> Mat4<T> {
    Mat4 {
        x_axis: Vec4 {
            x: Fused::dot4(
                a.x_axis.x, b.x_axis.x, a.y_axis.x, b.x_axis.y, a.z_axis.x, b.x_axis.z, a.w_axis.x, b.x_axis.w,
            ),
            y: Fused::dot4(
                a.x_axis.y, b.x_axis.x, a.y_axis.y, b.x_axis.y, a.z_axis.y, b.x_axis.z, a.w_axis.y, b.x_axis.w,
            ),
            z: Fused::dot4(
                a.x_axis.z, b.x_axis.x, a.y_axis.z, b.x_axis.y, a.z_axis.z, b.x_axis.z, a.w_axis.z, b.x_axis.w,
            ),
            w: Fused::dot4(
                a.x_axis.w, b.x_axis.x, a.y_axis.w, b.x_axis.y, a.z_axis.w, b.x_axis.z, a.w_axis.w, b.x_axis.w,
            ),
        },
        y_axis: Vec4 {
            x: Fused::dot4(
                a.x_axis.x, b.y_axis.x, a.y_axis.x, b.y_axis.y, a.z_axis.x, b.y_axis.z, a.w_axis.x, b.y_axis.w,
            ),
            y: Fused::dot4(
                a.x_axis.y, b.y_axis.x, a.y_axis.y, b.y_axis.y, a.z_axis.y, b.y_axis.z, a.w_axis.y, b.y_axis.w,
            ),
            z: Fused::dot4(
                a.x_axis.z, b.y_axis.x, a.y_axis.z, b.y_axis.y, a.z_axis.z, b.y_axis.z, a.w_axis.z, b.y_axis.w,
            ),
            w: Fused::dot4(
                a.x_axis.w, b.y_axis.x, a.y_axis.w, b.y_axis.y, a.z_axis.w, b.y_axis.z, a.w_axis.w, b.y_axis.w,
            ),
        },
        z_axis: Vec4 {
            x: Fused::dot4(
                a.x_axis.x, b.z_axis.x, a.y_axis.x, b.z_axis.y, a.z_axis.x, b.z_axis.z, a.w_axis.x, b.z_axis.w,
            ),
            y: Fused::dot4(
                a.x_axis.y, b.z_axis.x, a.y_axis.y, b.z_axis.y, a.z_axis.y, b.z_axis.z, a.w_axis.y, b.z_axis.w,
            ),
            z: Fused::dot4(
                a.x_axis.z, b.z_axis.x, a.y_axis.z, b.z_axis.y, a.z_axis.z, b.z_axis.z, a.w_axis.z, b.z_axis.w,
            ),
            w: Fused::dot4(
                a.x_axis.w, b.z_axis.x, a.y_axis.w, b.z_axis.y, a.z_axis.w, b.z_axis.z, a.w_axis.w, b.z_axis.w,
            ),
        },
        w_axis: Vec4 {
            x: Fused::dot4(
                a.x_axis.x, b.w_axis.x, a.y_axis.x, b.w_axis.y, a.z_axis.x, b.w_axis.z, a.w_axis.x, b.w_axis.w,
            ),
            y: Fused::dot4(
                a.x_axis.y, b.w_axis.x, a.y_axis.y, b.w_axis.y, a.z_axis.y, b.w_axis.z, a.w_axis.y, b.w_axis.w,
            ),
            z: Fused::dot4(
                a.x_axis.z, b.w_axis.x, a.y_axis.z, b.w_axis.y, a.z_axis.z, b.w_axis.z, a.w_axis.z, b.w_axis.w,
            ),
            w: Fused::dot4(
                a.x_axis.w, b.w_axis.x, a.y_axis.w, b.w_axis.y, a.z_axis.w, b.w_axis.z, a.w_axis.w, b.w_axis.w,
            ),
        },
    }
}

/// glam `Quat::mul_quat`.
#[inline(never)]
pub fn quat_mul<T, +Fused<T>, +Neg<T>, +Copy<T>, +Drop<T>>(a: Quat<T>, b: Quat<T>) -> Quat<T> {
    Quat {
        x: Fused::dot4(a.w, b.x, a.x, b.w, a.y, b.z, -a.z, b.y),
        y: Fused::dot4(a.w, b.y, -a.x, b.z, a.y, b.w, a.z, b.x),
        z: Fused::dot4(a.w, b.z, a.x, b.y, -a.y, b.x, a.z, b.w),
        w: Fused::dot4(a.w, b.w, -a.x, b.x, -a.y, b.y, -a.z, b.z),
    }
}

/// glam `Quat::mul_vec3`:
/// `rhs * (w*w - b.b) + b * (2 * rhs.b) + (b x rhs) * (2 * w)` with b = (x, y, z).
#[inline(never)]
pub fn quat_rotate<T, +Fused<T>, +Add<T>, +Neg<T>, +Copy<T>, +Drop<T>>(q: Quat<T>, v: Vec3<T>) -> Vec3<T> {
    let s1 = Fused::dot4(q.w, q.w, -q.x, q.x, -q.y, q.y, -q.z, q.z);
    let d = Fused::dot3(v.x, q.x, v.y, q.y, v.z, q.z);
    let s2 = d + d;
    let s3 = q.w + q.w;
    let cx = Fused::mul_sub(q.y, v.z, v.y, q.z);
    let cy = Fused::mul_sub(q.z, v.x, v.z, q.x);
    let cz = Fused::mul_sub(q.x, v.y, v.x, q.y);
    Vec3 {
        x: Fused::dot3(v.x, s1, q.x, s2, cx, s3),
        y: Fused::dot3(v.y, s1, q.y, s2, cy, s3),
        z: Fused::dot3(v.z, s1, q.z, s2, cz, s3),
    }
}

// ------------------------------------------------------------------ bench constructors
#[inline(never)]
pub fn mk<T, +Real<T>>(raw: i64) -> T {
    Real::from_raw(raw)
}
#[inline(never)]
pub fn mk_vec3<T, +Real<T>, +Drop<T>>(x: i64, y: i64, z: i64) -> Vec3<T> {
    Vec3 { x: Real::from_raw(x), y: Real::from_raw(y), z: Real::from_raw(z) }
}
#[inline(never)]
pub fn mk_quat<T, +Real<T>, +Drop<T>>(x: i64, y: i64, z: i64, w: i64) -> Quat<T> {
    Quat { x: Real::from_raw(x), y: Real::from_raw(y), z: Real::from_raw(z), w: Real::from_raw(w) }
}
#[inline(never)]
pub fn mk_mat3<T, +Real<T>, +Drop<T>>(s: Span<i64>) -> Mat3<T> {
    Mat3 {
        x_axis: mk_vec3(*s[0], *s[1], *s[2]), y_axis: mk_vec3(*s[3], *s[4], *s[5]),
        z_axis: mk_vec3(*s[6], *s[7], *s[8]),
    }
}
#[inline(never)]
pub fn mk_vec4<T, +Real<T>, +Drop<T>>(x: i64, y: i64, z: i64, w: i64) -> Vec4<T> {
    Vec4 { x: Real::from_raw(x), y: Real::from_raw(y), z: Real::from_raw(z), w: Real::from_raw(w) }
}
#[inline(never)]
pub fn mk_mat4<T, +Real<T>, +Drop<T>>(s: Span<i64>) -> Mat4<T> {
    Mat4 {
        x_axis: mk_vec4(*s[0], *s[1], *s[2], *s[3]), y_axis: mk_vec4(*s[4], *s[5], *s[6], *s[7]),
        z_axis: mk_vec4(*s[8], *s[9], *s[10], *s[11]), w_axis: mk_vec4(*s[12], *s[13], *s[14], *s[15]),
    }
}

// ------------------------------------------------------------------ array/loop based proxy
/// Tensor-style (orion-like) 3x3 product: row-major `Span` storage, triple loop, per-product
/// rescale. Proxy for "generic N-d array code" vs the unrolled struct code above.
#[inline(never)]
pub fn mat3_mul_mat3_span_loop<T, +Add<T>, +Mul<T>, +Copy<T>, +Drop<T>, +Real<T>>(
    a: Span<T>, b: Span<T>,
) -> Array<T> {
    let mut out: Array<T> = array![];
    let mut i: u32 = 0;
    while i != 3 {
        let mut j: u32 = 0;
        while j != 3 {
            let mut acc: T = Real::from_int(0);
            let mut k: u32 = 0;
            while k != 3 {
                acc = acc + *a[i * 3 + k] * *b[k * 3 + j];
                k += 1;
            }
            out.append(acc);
            j += 1;
        }
        i += 1;
    }
    out
}

#[inline(never)]
pub fn mk_span9<T, +Real<T>, +Drop<T>>(s: Span<i64>) -> Span<T> {
    let mut out: Array<T> = array![];
    for v in s {
        out.append(Real::from_raw(*v));
    }
    out.span()
}
