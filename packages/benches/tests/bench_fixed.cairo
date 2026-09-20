//! Benchmarks of `fixed::fixed`: one `X__base` / `X__op` pair per public function, plus the
//! losing alternatives of `benches::alt::fixed` (`alt_*`).
use benches::alt::fixed as alt;
use benches::harness::{bb, sink};
use fixed::{Fixed, FixedTrait};

#[test]
fn add__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn add__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(a + b);
}

#[test]
fn sub__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn sub__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(a - b);
}

#[test]
fn mul__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn mul__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(a * b);
}

#[test]
fn div__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn div__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(a / b);
}

#[test]
fn rem__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn rem__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(a % b);
}

#[test]
fn neg__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn neg__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(-a);
}

#[test]
fn add_assign__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn add_assign__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink({
        let mut x = a;
        x += b;
        x
    });
}

#[test]
fn sub_assign__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn sub_assign__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink({
        let mut x = a;
        x -= b;
        x
    });
}

#[test]
fn mul_assign__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn mul_assign__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink({
        let mut x = a;
        x *= b;
        x
    });
}

#[test]
fn div_assign__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn div_assign__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink({
        let mut x = a;
        x /= b;
        x
    });
}

#[test]
fn rem_assign__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn rem_assign__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink({
        let mut x = a;
        x %= b;
        x
    });
}

#[test]
fn eq__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(true));
}

#[test]
fn eq__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(true);
    sink(a == b);
}

#[test]
fn lt__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(true));
}

#[test]
fn lt__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(true);
    sink(a < b);
}

#[test]
fn le__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(true));
}

#[test]
fn le__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(true);
    sink(a <= b);
}

#[test]
fn gt__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(true));
}

#[test]
fn gt__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(true);
    sink(a > b);
}

#[test]
fn ge__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(true));
}

#[test]
fn ge__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(true);
    sink(a >= b);
}

#[test]
fn from_int__base() {
    let _i = bb(-7_i32);
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn from_int__op() {
    let i = bb(-7_i32);
    let _r = bb(Fixed { raw: 1 });
    sink(FixedTrait::from_int(i));
}

#[test]
fn from_ratio__base() {
    let _i = bb(-1_i64);
    let _j = bb(3_i64);
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn from_ratio__op() {
    let i = bb(-1_i64);
    let j = bb(3_i64);
    let _r = bb(Fixed { raw: 1 });
    sink(FixedTrait::from_ratio(i, j));
}

#[test]
fn into_i16__base() {
    let _i = bb(-7_i16);
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn into_i16__op() {
    let i = bb(-7_i16);
    let _r = bb(Fixed { raw: 1 });
    sink({
        let x: Fixed = i.into();
        x
    });
}

#[test]
fn into_u16__base() {
    let _i = bb(7_u16);
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn into_u16__op() {
    let i = bb(7_u16);
    let _r = bb(Fixed { raw: 1 });
    sink({
        let x: Fixed = i.into();
        x
    });
}

#[test]
fn try_into_u32__base() {
    let _i = bb(7_u32);
    sink(bb(Option::Some(Fixed { raw: 1 })));
}

#[test]
fn try_into_u32__op() {
    let i = bb(7_u32);
    let _r = bb(Option::Some(Fixed { raw: 1 }));
    sink({
        let x: Option<Fixed> = i.try_into();
        x
    });
}

#[test]
fn to_int__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(1_i32));
}

#[test]
fn to_int__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(1_i32);
    sink(b.to_int());
}

#[test]
fn to_int_trunc__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(1_i32));
}

#[test]
fn to_int_trunc__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(1_i32);
    sink(b.to_int_trunc());
}

#[test]
fn to_int_round__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(1_i32));
}

#[test]
fn to_int_round__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(1_i32);
    sink(b.to_int_round());
}

#[test]
fn abs__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn abs__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(b.abs());
}

#[test]
fn signum__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn signum__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(b.signum());
}

#[test]
fn copysign__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn copysign__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.copysign(b));
}

#[test]
fn is_negative__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(true));
}

#[test]
fn is_negative__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(true);
    sink(b.is_negative());
}

#[test]
fn is_positive__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(true));
}

#[test]
fn is_positive__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(true);
    sink(b.is_positive());
}

#[test]
fn is_sign_negative__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(true));
}

#[test]
fn is_sign_negative__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(true);
    sink(b.is_sign_negative());
}

#[test]
fn is_sign_positive__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(true));
}

#[test]
fn is_sign_positive__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(true);
    sink(b.is_sign_positive());
}

#[test]
fn min__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn min__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.min(b));
}

#[test]
fn max__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn max__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.max(b));
}

#[test]
fn clamp__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn clamp__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.clamp(b, c));
}

#[test]
fn floor__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn floor__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(b.floor());
}

#[test]
fn ceil__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn ceil__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(b.ceil());
}

#[test]
fn round__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn round__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(b.round());
}

#[test]
fn trunc__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn trunc__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(b.trunc());
}

#[test]
fn fract__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn fract__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(b.fract());
}

#[test]
fn fract_gl__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn fract_gl__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(b.fract_gl());
}

#[test]
fn recip__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn recip__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(b.recip());
}

#[test]
fn sqrt__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn sqrt__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.sqrt());
}

#[test]
fn div_euclid__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn div_euclid__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(b.div_euclid(a));
}

#[test]
fn rem_euclid__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn rem_euclid__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(b.rem_euclid(a));
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
    sink(a.mul_add(b, c));
}

#[test]
fn powi_2__base() {
    let _b = bb(Fixed { raw: -0x280000001 });
    let _n = bb(2_i32);
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn powi_2__op() {
    let b = bb(Fixed { raw: -0x280000001 });
    let n = bb(2_i32);
    let _r = bb(Fixed { raw: 1 });
    sink(b.powi(n));
}

#[test]
fn powi_5__base() {
    let _b = bb(Fixed { raw: -0x280000001 });
    let _n = bb(5_i32);
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn powi_5__op() {
    let b = bb(Fixed { raw: -0x280000001 });
    let n = bb(5_i32);
    let _r = bb(Fixed { raw: 1 });
    sink(b.powi(n));
}

#[test]
fn powi_neg3__base() {
    let _b = bb(Fixed { raw: -0x280000001 });
    let _n = bb(-3_i32);
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn powi_neg3__op() {
    let b = bb(Fixed { raw: -0x280000001 });
    let n = bb(-3_i32);
    let _r = bb(Fixed { raw: 1 });
    sink(b.powi(n));
}

#[test]
fn lerp__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn lerp__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.lerp(b, c));
}

#[test]
fn inverse_lerp__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn inverse_lerp__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(Fixed { raw: 1 });
    sink(FixedTrait::inverse_lerp(a, b, c));
}

#[test]
fn remap__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    let _d = bb(Fixed { raw: 0x3243f6a88 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn remap__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let d = bb(Fixed { raw: 0x3243f6a88 });
    let _r = bb(Fixed { raw: 1 });
    sink(c.remap(a, b, b, d));
}

#[test]
fn step__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn step__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.step(b));
}

#[test]
fn saturate__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn saturate__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(b.saturate());
}

#[test]
fn smoothstep__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn smoothstep__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(Fixed { raw: 1 });
    sink(c.smoothstep(b, a));
}

#[test]
fn move_towards__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn move_towards__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.move_towards(b, c));
}

#[test]
fn abs_diff_eq__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    let _c = bb(Fixed { raw: 0x16a09e667 });
    sink(bb(true));
}

#[test]
fn abs_diff_eq__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let c = bb(Fixed { raw: 0x16a09e667 });
    let _r = bb(true);
    sink(a.abs_diff_eq(b, c));
}

#[test]
fn zero_is_zero__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    sink(bb(true));
}

#[test]
fn zero_is_zero__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let _r = bb(true);
    sink(core::num::traits::Zero::is_zero(@a));
}

#[test]
fn one_is_one__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    sink(bb(true));
}

#[test]
fn one_is_one__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let _r = bb(true);
    sink(core::num::traits::One::is_one(@a));
}

#[test]
fn alt_mul_stable__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_mul_stable__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::mul_stable(a, b));
}

#[test]
fn alt_mul_stable_i128__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_mul_stable_i128__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::mul_stable_i128(a, b));
}

#[test]
fn alt_mul_bias_downcast__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_mul_bias_downcast__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::mul_bias_downcast(a, b));
}

#[test]
fn alt_div_stable__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_div_stable__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::div_stable(a, b));
}

#[test]
fn alt_div_floor__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_div_floor__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::div_floor(a, b));
}

#[test]
fn alt_div_trunc_flat__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_div_trunc_flat__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::div_trunc_flat(a, b));
}

#[test]
fn alt_recip_floor__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_recip_floor__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::recip_floor(b));
}

#[test]
fn alt_rem_native__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_rem_native__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::rem_native(a, b));
}

#[test]
fn alt_abs_downcast__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_abs_downcast__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::abs_downcast(b));
}

#[test]
fn alt_round_downcast__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000001 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_round_downcast__op() {
    let _a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000001 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::round_downcast(b));
}

#[test]
fn alt_sqrt_constrain__base() {
    let _a = bb(Fixed { raw: 0x500000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_sqrt_constrain__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::sqrt_constrain(a));
}

#[test]
fn alt_powi_loop_2__base() {
    let _b = bb(Fixed { raw: -0x280000001 });
    let _n = bb(2_i32);
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_powi_loop_2__op() {
    let b = bb(Fixed { raw: -0x280000001 });
    let n = bb(2_i32);
    let _r = bb(Fixed { raw: 1 });
    sink(alt::powi_loop(b, n));
}

#[test]
fn alt_powi_loop_5__base() {
    let _b = bb(Fixed { raw: -0x280000001 });
    let _n = bb(5_i32);
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_powi_loop_5__op() {
    let b = bb(Fixed { raw: -0x280000001 });
    let n = bb(5_i32);
    let _r = bb(Fixed { raw: 1 });
    sink(alt::powi_loop(b, n));
}
