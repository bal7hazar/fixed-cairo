//! Vendored from influenceth/cubit `src/f64/math/trig.cairo` (MIT), adapted to the local `FMag`
//! type (same layout and same arithmetic as cubit's `Fixed`). Logic is unchanged.
use crate::cubit_lut as lut;
use crate::fixed::Real;
use crate::fixed::mag::{FMag, ONE};

const TWO_PI: u64 = 26986075409;
const PI: u64 = 13493037705;
const HALF_PI: u64 = 6746518852;

fn new(mag: u64, sign: bool) -> FMag {
    FMag { mag, sign }
}
fn one() -> FMag {
    FMag { mag: ONE, sign: false }
}

pub fn acos(a: FMag) -> FMag {
    let asin_arg = (one() - a * a).sqrt();
    let asin_res = asin(asin_arg);
    if a.sign {
        new(PI, false) - asin_res
    } else {
        asin_res
    }
}

pub fn acos_fast(a: FMag) -> FMag {
    let asin_arg = (one() - a * a).sqrt();
    let asin_res = asin_fast(asin_arg);
    if a.sign {
        new(PI, false) - asin_res
    } else {
        asin_res
    }
}

pub fn asin(a: FMag) -> FMag {
    if a.mag == ONE {
        return new(HALF_PI, a.sign);
    }
    let div = (one() - a * a).sqrt();
    atan(a / div)
}

pub fn asin_fast(a: FMag) -> FMag {
    if a.mag == ONE {
        return new(HALF_PI, a.sign);
    }
    let div = (one() - a * a).sqrt();
    atan_fast(a / div)
}

pub fn atan(a: FMag) -> FMag {
    let mut at = a.abs();
    let mut shift = false;
    let mut invert = false;
    if at.mag > ONE {
        at = one() / at;
        invert = true;
    }
    if at.mag > 3006477107 {
        let sqrt3_3 = new(2479700525, false);
        at = (at - sqrt3_3) / (one() + at * sqrt3_3);
        shift = true;
    }
    let r10 = new(7866091, true) * at;
    let r9 = (r10 + new(200950905, true)) * at;
    let r8 = (r9 + new(834081193, false)) * at;
    let r7 = (r8 + new(1125283850, true)) * at;
    let r6 = (r7 + new(187746747, false)) * at;
    let r5 = (r6 + new(816293925, false)) * at;
    let r4 = (r5 + new(5897657, false)) * at;
    let r3 = (r4 + new(1432117161, true)) * at;
    let r2 = (r3 + new(17657, false)) * at;
    let mut res = (r2 + new(4294967059, false)) * at;
    if shift {
        res = res + new(2248839617, false);
    }
    if invert {
        res = res - new(HALF_PI, false);
    }
    new(res.mag, a.sign)
}

pub fn atan_fast(a: FMag) -> FMag {
    let mut at = a.abs();
    let mut shift = false;
    let mut invert = false;
    if at.mag > ONE {
        at = one() / at;
        invert = true;
    }
    if at.mag > 3006477107 {
        let sqrt3_3 = new(2479700525, false);
        at = (at - sqrt3_3) / (one() + at * sqrt3_3);
        shift = true;
    }
    let (start, low, high) = lut::atan(at.mag);
    let partial_step = new(at.mag - start, false) / new(30064771, false);
    let mut res = partial_step * new(high - low, false) + new(low, false);
    if shift {
        res = res + new(2248839617, false);
    }
    if invert {
        res = res - new(HALF_PI, false);
    }
    new(res.mag, a.sign)
}

pub fn cos(a: FMag) -> FMag {
    sin(new(HALF_PI, false) - a)
}

pub fn cos_fast(a: FMag) -> FMag {
    sin_fast(new(HALF_PI, false) - a)
}

pub fn sin(a: FMag) -> FMag {
    let a1 = a.mag % TWO_PI;
    let (whole_rem, partial_rem) = DivRem::div_rem(a1, PI.try_into().unwrap());
    let a2 = new(partial_rem, false);
    let partial_sign = whole_rem == 1;
    let loop_res = a2 * _sin_loop(a2, 7, one());
    new(loop_res.mag, a.sign ^ partial_sign && loop_res.mag != 0)
}

pub fn sin_fast(a: FMag) -> FMag {
    let a1 = a.mag % TWO_PI;
    let (whole_rem, mut partial_rem) = DivRem::div_rem(a1, PI.try_into().unwrap());
    let partial_sign = whole_rem == 1;
    if partial_rem >= HALF_PI {
        partial_rem = PI - partial_rem;
    }
    let (start, low, high) = lut::sin(partial_rem);
    let partial_step = (new(partial_rem, false) - new(start, false)) / new(26353589, false);
    let res = partial_step * (new(high, false) - new(low, false)) + new(low, false);
    new(res.mag, a.sign ^ partial_sign && res.mag != 0)
}

fn _sin_loop(a: FMag, i: u64, acc: FMag) -> FMag {
    let div = (2 * i + 2) * (2 * i + 3);
    let term = a * a * acc / new(div * ONE, false);
    let new_acc = one() - term;
    if i == 0 {
        return new_acc;
    }
    _sin_loop(a, i - 1, new_acc)
}
