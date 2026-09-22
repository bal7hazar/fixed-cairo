//! Alternative implementations benchmarked against `glam::quat` (the `alt_*` rows of
//! `gas/quat.snap`). The library ships the formulation it documents; the others stay here so
//! that the comparison is reproducible across compiler upgrades.

use fixed::fixed::{Fixed, FixedTrait};
use fixed::trig::TrigTrait;
use fixed::wide::{NormTrait, RecipTrait, WideAdd, WideNarrow, mul_add, norm3_wide, wide_mul};
use glam::quat::{Quat, QuatTrait};
use glam::vec3::{Vec3, Vec3Trait};

/// Alternative to `Quat::mul_quat`. The literal glam-rs `w0 x1 + x0 w1 + y0 z1 - z0 y1`, ...:
/// four rounded products per component instead of one exact sum rescaled once: 37 080 gas
/// against the 10 040 of the fused form.
#[inline(always)]
pub fn mul_quat_unfused(lhs: Quat, rhs: Quat) -> Quat {
    Quat {
        x: lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
        y: lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
        z: lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
        w: lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z,
    }
}

/// Alternative to `Quat::mul_vec3`. The `t = 2 b x v; v + w t + b x t` formulation (b = the
/// vector part): 15 multiplications become 12, but the two cross products and the sum each
/// rescale, so the result rounds three times instead of once and costs 22 580 gas against the
/// 9 360 of the triple-product form.
#[inline(always)]
pub fn mul_vec3_two_cross(lhs: Quat, rhs: Vec3) -> Vec3 {
    let b = Vec3 { x: lhs.x, y: lhs.y, z: lhs.z };
    let c = b.cross(rhs);
    let t = Vec3 { x: c.x + c.x, y: c.y + c.y, z: c.z + c.z };
    let ct = b.cross(t);
    Vec3 {
        x: mul_add(lhs.w, t.x, rhs.x) + ct.x,
        y: mul_add(lhs.w, t.y, rhs.y) + ct.y,
        z: mul_add(lhs.w, t.z, rhs.z) + ct.z,
    }
}

/// Alternative to `Quat::from_scaled_axis`. The sine folded into the shared division
/// (`v * (sin(angle / 2) / length)`): one `Recip` multiplication instead of three. 4 470 gas
/// cheaper (44 350 vs 48 820), at the price of the exactness of the axis-aligned inputs, which
/// is why the library keeps the literal form.
#[inline(always)]
pub fn from_scaled_axis_fused(v: Vec3) -> Quat {
    let n = norm3_wide(v.x, v.y, v.z);
    match n.try_recip() {
        Some(r) => {
            let (s, c) = (n.to_fixed() * F_HALF).sin_cos();
            let k = r.mul(s);
            Quat { x: v.x * k, y: v.y * k, z: v.z * k, w: c }
        },
        None => QuatTrait::IDENTITY,
    }
}

/// Alternative to `Quat::to_scaled_axis`. The angle folded into the shared division
/// (`xyz * (angle / length)`), same trade-off as [`from_scaled_axis_fused`]: 6 670 gas cheaper
/// (40 500 vs 47 170), not exact on the axis-aligned inputs.
#[inline(always)]
pub fn to_scaled_axis_fused(lhs: Quat) -> Vec3 {
    let n = norm3_wide(lhs.x, lhs.y, lhs.z);
    let len = n.to_fixed();
    if len >= AXIS_EPS {
        let a = len.atan2(lhs.w);
        let k = n.recip().mul(a + a);
        Vec3 { x: lhs.x * k, y: lhs.y * k, z: lhs.z * k }
    } else {
        Vec3Trait::ZERO
    }
}

/// Alternative to `Quat::from_axis_angle`. Two reductions (`sin` then `cos`) instead of the
/// shared one of `sin_cos`: 52 300 gas against 40 350.
#[inline(always)]
pub fn from_axis_angle_two_calls(axis: Vec3, angle: Fixed) -> Quat {
    let h = angle * F_HALF;
    let s = h.sin();
    Quat { x: axis.x * s, y: axis.y * s, z: axis.z * s, w: h.cos() }
}

/// Alternative to the `s / sin(theta)` of `Quat::slerp`. A truncated `Fixed` reciprocal followed
/// by four multiplications, as glam-rs spells it, instead of the shared wide `Recip`:
/// 130 750 gas against 122 180, and up to 1 ULP further from the exact quotient.
#[inline(always)]
pub fn slerp_fixed_recip(lhs: Quat, end: Quat, s: Fixed) -> Quat {
    let d0 = QuatTrait::dot(lhs, end);
    let neg = d0.is_negative();
    let d = if neg {
        -d0
    } else {
        d0
    };
    if d > NEAR_ONE {
        QuatTrait::lerp(lhs, end, s)
    } else {
        let theta = d.acos();
        let scale1 = (theta * (F_ONE - s)).sin();
        let sin2 = (theta * s).sin();
        let scale2 = if neg {
            -sin2
        } else {
            sin2
        };
        let r = theta.sin().recip();
        Quat {
            x: (lhs.x * scale1 + end.x * scale2) * r,
            y: (lhs.y * scale1 + end.y * scale2) * r,
            z: (lhs.z * scale1 + end.z * scale2) * r,
            w: (lhs.w * scale1 + end.w * scale2) * r,
        }
    }
}

/// Alternative organization of `slerp` / `slerp_long`: the pre-#R1d non-inlined shared helper.
/// It saves bytecode when both entry points are linked, at the cost of a second call boundary:
/// 125 260 gas / 944 steps against 122 180 / 923 for the shipped inlined template.
#[inline(never)]
pub fn slerp_shared_call(lhs: Quat, end: Quat, s: Fixed) -> Quat {
    slerp_shared_impl(lhs, end, s, true)
}

#[inline(never)]
fn slerp_shared_impl(a: Quat, b: Quat, s: Fixed, shortest: bool) -> Quat {
    let d0 = QuatTrait::dot(a, b);
    let flip = shortest && d0.is_negative();
    let d = if flip {
        -d0
    } else {
        d0
    };
    let near = if shortest {
        d > NEAR_ONE
    } else {
        d.abs() > NEAR_ONE
    };
    if near {
        alt_lerp_impl(a, b, s, if flip {
            -s
        } else {
            s
        })
    } else {
        alt_slerp_weights(a, b, s, d.acos(), flip)
    }
}

/// Alternative organization with the `shortest` match hoisted around the specialized bodies.
/// The helper remains non-inlined, so this tests whether removing its internal boolean branches
/// offsets the call boundary: 123 580 gas / 938 steps, still slower than the inlined template.
#[inline(never)]
pub fn slerp_hoisted_match(lhs: Quat, end: Quat, s: Fixed) -> Quat {
    slerp_match_impl(lhs, end, s, true)
}

#[inline(never)]
fn slerp_match_impl(a: Quat, b: Quat, s: Fixed, shortest: bool) -> Quat {
    match shortest {
        true => alt_slerp_short_body(a, b, s),
        false => alt_slerp_long_body(a, b, s),
    }
}

/// Alternative organization with a duplicated, specialized `slerp` body. This has one call
/// boundary like the shipped inlined-template form and ties it at 122 180 gas / 923 steps, but
/// requires maintaining two large bodies.
#[inline(never)]
pub fn slerp_duplicated_body(lhs: Quat, end: Quat, s: Fixed) -> Quat {
    alt_slerp_short_body(lhs, end, s)
}

#[inline(always)]
fn alt_slerp_short_body(a: Quat, b: Quat, s: Fixed) -> Quat {
    let d0 = QuatTrait::dot(a, b);
    let flip = d0.is_negative();
    let d = if flip {
        -d0
    } else {
        d0
    };
    if d > NEAR_ONE {
        alt_lerp_impl(a, b, s, if flip {
            -s
        } else {
            s
        })
    } else {
        alt_slerp_weights(a, b, s, d.acos(), flip)
    }
}

#[inline(always)]
fn alt_slerp_long_body(a: Quat, b: Quat, s: Fixed) -> Quat {
    let d = QuatTrait::dot(a, b);
    if d.abs() > NEAR_ONE {
        alt_lerp_impl(a, b, s, s)
    } else {
        alt_slerp_weights(a, b, s, d.acos(), false)
    }
}

#[inline(always)]
fn alt_slerp_weights(a: Quat, b: Quat, s: Fixed, theta: Fixed, flip: bool) -> Quat {
    let scale1 = (theta * (F_ONE - s)).sin();
    let sin2 = (theta * s).sin();
    let scale2 = if flip {
        -sin2
    } else {
        sin2
    };
    let r = RecipTrait::new(theta.sin());
    Quat {
        x: r.mul(wide_mul(a.x, scale1).add(wide_mul(b.x, scale2)).narrow()),
        y: r.mul(wide_mul(a.y, scale1).add(wide_mul(b.y, scale2)).narrow()),
        z: r.mul(wide_mul(a.z, scale1).add(wide_mul(b.z, scale2)).narrow()),
        w: r.mul(wide_mul(a.w, scale1).add(wide_mul(b.w, scale2)).narrow()),
    }
}

#[inline(always)]
fn alt_lerp_impl(a: Quat, b: Quat, s: Fixed, t: Fixed) -> Quat {
    let u = F_ONE - s;
    QuatTrait::normalize(
        Quat {
            x: wide_mul(a.x, u).add(wide_mul(b.x, t)).narrow(),
            y: wide_mul(a.y, u).add(wide_mul(b.y, t)).narrow(),
            z: wide_mul(a.z, u).add(wide_mul(b.z, t)).narrow(),
            w: wide_mul(a.w, u).add(wide_mul(b.w, t)).narrow(),
        },
    )
}

/// The pre-#R1d `rotate_towards`: `angle_between` and `slerp` each compute their own dot and
/// inverse cosine. It costs 160 840 gas / 1 259 steps against 129 100 / 1 007 when those values
/// are shared. (The committed pre-R1d row was 162 720 / 1 268 before `slerp` was inlined.)
#[inline(never)]
pub fn rotate_towards_recompute(lhs: Quat, rhs: Quat, max_angle: Fixed) -> Quat {
    let angle = QuatTrait::angle_between(lhs, rhs);
    if angle <= ROTATE_TOWARDS_EPS {
        rhs
    } else {
        QuatTrait::slerp(lhs, rhs, (max_angle / angle).clamp(F_NEG_ONE, F_ONE))
    }
}

/// Alternative to `Quat::lerp`. The literal glam-rs `self * (1 - s) + end * s` (two rounded
/// products per component) before the shared normalization, with `end` negated on the long
/// path: 31 140 gas against 24 120.
#[inline(always)]
pub fn lerp_glam(lhs: Quat, end: Quat, s: Fixed) -> Quat {
    let b = if QuatTrait::dot(lhs, end).is_negative() {
        Quat { x: -end.x, y: -end.y, z: -end.z, w: -end.w }
    } else {
        end
    };
    let u = F_ONE - s;
    QuatTrait::normalize(
        Quat {
            x: lhs.x * u + b.x * s,
            y: lhs.y * u + b.y * s,
            z: lhs.z * u + b.z * s,
            w: lhs.w * u + b.w * s,
        },
    )
}

/// Alternative to `Quat::is_near_identity`. The literal angle test
/// `2 acos(|w|) < 2 acos(1 - 1e-6)`, i.e. one `acos` (32 070 gas) instead of one comparison
/// (1 770).
#[inline(always)]
pub fn is_near_identity_angle(lhs: Quat) -> bool {
    let a = lhs.w.abs().acos_clamped();
    a + a < NEAR_IDENTITY_ANGLE
}

/// Alternative to `Quat::from_rotation_axes`. The literal glam-rs `0.5 / sqrt(four_csq)` as a
/// truncated `Fixed` division followed by four multiplications, instead of the shared wide
/// `Recip` of `2 sqrt(four_csq)`: two roundings per component instead of one.
#[inline(never)]
pub fn from_rotation_axes_fixed_recip(x_axis: Vec3, y_axis: Vec3, z_axis: Vec3) -> Quat {
    if !z_axis.z.is_positive() {
        let dif10 = y_axis.y - x_axis.x;
        let omm22 = F_ONE - z_axis.z;
        if !dif10.is_positive() {
            let four_xsq = omm22 - dif10;
            let inv = F_HALF / four_xsq.sqrt();
            Quat {
                x: four_xsq * inv,
                y: (x_axis.y + y_axis.x) * inv,
                z: (x_axis.z + z_axis.x) * inv,
                w: (y_axis.z - z_axis.y) * inv,
            }
        } else {
            let four_ysq = omm22 + dif10;
            let inv = F_HALF / four_ysq.sqrt();
            Quat {
                x: (x_axis.y + y_axis.x) * inv,
                y: four_ysq * inv,
                z: (y_axis.z + z_axis.y) * inv,
                w: (z_axis.x - x_axis.z) * inv,
            }
        }
    } else {
        let sum10 = y_axis.y + x_axis.x;
        let opm22 = F_ONE + z_axis.z;
        if !sum10.is_positive() {
            let four_zsq = opm22 - sum10;
            let inv = F_HALF / four_zsq.sqrt();
            Quat {
                x: (x_axis.z + z_axis.x) * inv,
                y: (y_axis.z + z_axis.y) * inv,
                z: four_zsq * inv,
                w: (x_axis.y - y_axis.x) * inv,
            }
        } else {
            let four_wsq = opm22 + sum10;
            let inv = F_HALF / four_wsq.sqrt();
            Quat {
                x: (y_axis.z - z_axis.y) * inv,
                y: (z_axis.x - x_axis.z) * inv,
                z: (x_axis.y - y_axis.x) * inv,
                w: four_wsq * inv,
            }
        }
    }
}

/// `1`.
const F_ONE: Fixed = Fixed { raw: 0x100000000 };

/// `-1`.
const F_NEG_ONE: Fixed = Fixed { raw: -0x100000000 };

/// `1 / 2`.
const F_HALF: Fixed = Fixed { raw: 0x80000000 };

/// `1 - 2^-20`: `glam::quat::NEAR_ONE`.
const NEAR_ONE: Fixed = Fixed { raw: 0xfffff000 };

/// `2^-16`: `glam::quat::AXIS_EPS`.
const AXIS_EPS: Fixed = Fixed { raw: 0x10000 };

/// `2 acos(1 - 1e-6) = 2.83e-3` rad, as `fixed::trig::acos` computes it.
const NEAR_IDENTITY_ANGLE: Fixed = Fixed { raw: 12148048 };

/// `1e-4` rad quantized, the `rotate_towards` direct-target threshold.
const ROTATE_TOWARDS_EPS: Fixed = Fixed { raw: 429497 };
