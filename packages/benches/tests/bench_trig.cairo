//! Benchmarks of `fixed::trig`: one `X__base` / `X__op` pair per public function, with several
//! inputs per function because the cost depends on the branch taken (the octant of the
//! reduction, the sign, which half of `atan` is used, which quadrant `atan2` lands in). The
//! losing variants of `benches::alt::trig` are the `alt_*` rows.
//!
//! Note on the absolute numbers: they are ~2x the ones of the prototype of
//! `docs/research/05-gas-benchmarks.md` section 4, whose bench harness fed the functions
//! **constant** inputs (`let a: FMag = mk(10737418240);`, no black box); the same functions
//! measured that way here cost 10 430 (`sin`), 20 710 (`sin_cos`), 12 750 (`atan2`) and 22 660
//! (`acos`). Every row below goes through `bb`, as `AGENTS.md` requires.
use benches::alt::trig as alt;
use benches::harness::{bb, sink};
use fixed::{Fixed, TrigTrait};

#[test]
fn sin__small__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn sin__small__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(a.sin());
}

#[test]
fn sin__quadrant2__base() {
    let _a = bb(Fixed { raw: 0x280000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn sin__quadrant2__op() {
    let a = bb(Fixed { raw: 0x280000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.sin());
}

#[test]
fn sin__negative__base() {
    let _a = bb(Fixed { raw: -0x280000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn sin__negative__op() {
    let a = bb(Fixed { raw: -0x280000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.sin());
}

#[test]
fn sin__beyond_one_turn__base() {
    let _a = bb(Fixed { raw: 0x188b2f704a68 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn sin__beyond_one_turn__op() {
    let a = bb(Fixed { raw: 0x188b2f704a68 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.sin());
}

#[test]
fn cos__small__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn cos__small__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(a.cos());
}

#[test]
fn cos__quadrant2__base() {
    let _a = bb(Fixed { raw: 0x280000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn cos__quadrant2__op() {
    let a = bb(Fixed { raw: 0x280000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.cos());
}

#[test]
fn sin_cos__small__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn sin_cos__small__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(a.sin_cos());
}

#[test]
fn sin_cos__quadrant3__base() {
    let _a = bb(Fixed { raw: 0x480000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn sin_cos__quadrant3__op() {
    let a = bb(Fixed { raw: 0x480000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.sin_cos());
}

#[test]
fn tan__small__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn tan__small__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(a.tan());
}

#[test]
fn tan__quadrant2__base() {
    let _a = bb(Fixed { raw: 0x280000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn tan__quadrant2__op() {
    let a = bb(Fixed { raw: 0x280000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.tan());
}

#[test]
fn asin__small__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn asin__small__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(a.asin());
}

#[test]
fn asin__negative__base() {
    let _a = bb(Fixed { raw: -0xb3333333 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn asin__negative__op() {
    let a = bb(Fixed { raw: -0xb3333333 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.asin());
}

#[test]
fn acos__small__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn acos__small__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(a.acos());
}

#[test]
fn acos__negative__base() {
    let _a = bb(Fixed { raw: -0xb3333333 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn acos__negative__op() {
    let a = bb(Fixed { raw: -0xb3333333 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.acos());
}

#[test]
fn asin_clamped__inside__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn asin_clamped__inside__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(a.asin_clamped());
}

#[test]
fn acos_clamped__outside__base() {
    let _a = bb(Fixed { raw: 0x180000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn acos_clamped__outside__op() {
    let a = bb(Fixed { raw: 0x180000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.acos_clamped());
}

#[test]
fn atan__small__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn atan__small__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(a.atan());
}

#[test]
fn atan__large__base() {
    let _a = bb(Fixed { raw: 0xa00000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn atan__large__op() {
    let a = bb(Fixed { raw: 0xa00000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.atan());
}

#[test]
fn atan2__quadrant1__base() {
    let _a = bb(Fixed { raw: 0x4ccccccc });
    let _b = bb(Fixed { raw: 0xb3333333 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn atan2__quadrant1__op() {
    let a = bb(Fixed { raw: 0x4ccccccc });
    let b = bb(Fixed { raw: 0xb3333333 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.atan2(b));
}

#[test]
fn atan2__quadrant2__base() {
    let _a = bb(Fixed { raw: 0xb3333333 });
    let _b = bb(Fixed { raw: -0x4ccccccc });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn atan2__quadrant2__op() {
    let a = bb(Fixed { raw: 0xb3333333 });
    let b = bb(Fixed { raw: -0x4ccccccc });
    let _r = bb(Fixed { raw: 1 });
    sink(a.atan2(b));
}

#[test]
fn atan2__quadrant3__base() {
    let _a = bb(Fixed { raw: -0xb3333333 });
    let _b = bb(Fixed { raw: -0x4ccccccc });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn atan2__quadrant3__op() {
    let a = bb(Fixed { raw: -0xb3333333 });
    let b = bb(Fixed { raw: -0x4ccccccc });
    let _r = bb(Fixed { raw: 1 });
    sink(a.atan2(b));
}

#[test]
fn atan2__quadrant4__base() {
    let _a = bb(Fixed { raw: -0x4ccccccc });
    let _b = bb(Fixed { raw: 0xb3333333 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn atan2__quadrant4__op() {
    let a = bb(Fixed { raw: -0x4ccccccc });
    let b = bb(Fixed { raw: 0xb3333333 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.atan2(b));
}

#[test]
fn atan2__axis__base() {
    let _a = bb(Fixed { raw: 0x100000000 });
    let _b = bb(Fixed { raw: 0x0 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn atan2__axis__op() {
    let a = bb(Fixed { raw: 0x100000000 });
    let b = bb(Fixed { raw: 0x0 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.atan2(b));
}

#[test]
fn to_radians__base() {
    let _a = bb(Fixed { raw: 0x2d00000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn to_radians__op() {
    let a = bb(Fixed { raw: 0x2d00000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.to_radians());
}

#[test]
fn to_degrees__base() {
    let _a = bb(Fixed { raw: 0xc90fd991 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn to_degrees__op() {
    let a = bb(Fixed { raw: 0xc90fd991 });
    let _r = bb(Fixed { raw: 1 });
    sink(a.to_degrees());
}

#[test]
fn alt_sin_no_cody_waite_tail__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_sin_no_cody_waite_tail__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::sin_no_tail(a));
}

#[test]
fn alt_sin_quadrant_reduction__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_sin_quadrant_reduction__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::sin_q(a));
}

#[test]
fn alt_sin_quadrant_reduction_q2__base() {
    let _a = bb(Fixed { raw: 0x280000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_sin_quadrant_reduction_q2__op() {
    let a = bb(Fixed { raw: 0x280000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::sin_q(a));
}

#[test]
fn alt_sin_cos_quadrant_reduction__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_sin_cos_quadrant_reduction__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::sin_cos_q(a));
}

#[test]
fn alt_sin_lut__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_sin_lut__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::sin_lut(a));
}

#[test]
fn alt_sin_lut_quadrant2__base() {
    let _a = bb(Fixed { raw: 0x280000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_sin_lut_quadrant2__op() {
    let a = bb(Fixed { raw: 0x280000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::sin_lut(a));
}

#[test]
fn alt_cos_lut__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_cos_lut__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::cos_lut(a));
}

#[test]
fn alt_atan_single_poly__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_atan_single_poly__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::atan_single(a));
}

#[test]
fn alt_atan_single_poly_reduced__base() {
    let _a = bb(Fixed { raw: 0xb3333333 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_atan_single_poly_reduced__op() {
    let a = bb(Fixed { raw: 0xb3333333 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::atan_single(a));
}

#[test]
fn alt_atan2_single_poly__base() {
    let _a = bb(Fixed { raw: 0x4ccccccc });
    let _b = bb(Fixed { raw: 0xb3333333 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_atan2_single_poly__op() {
    let a = bb(Fixed { raw: 0x4ccccccc });
    let b = bb(Fixed { raw: 0xb3333333 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::atan2_single(a, b));
}

#[test]
fn alt_acos_atan2__base() {
    let _a = bb(Fixed { raw: 0x4ccccccd });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_acos_atan2__op() {
    let a = bb(Fixed { raw: 0x4ccccccd });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::acos_atan2(a));
}

#[test]
fn alt_to_radians_mul__base() {
    let _a = bb(Fixed { raw: 0x2d00000000 });
    sink(bb(Fixed { raw: 1 }));
}

#[test]
fn alt_to_radians_mul__op() {
    let a = bb(Fixed { raw: 0x2d00000000 });
    let _r = bb(Fixed { raw: 1 });
    sink(alt::to_radians_mul(a));
}
