use benches::harness::{bb, sink};
use fixed::Fixed;

#[test]
fn add__base() {
    let a = bb(Fixed { raw: 0x500000000 });
    let _b = bb(Fixed { raw: -0x280000000 });
    sink(a);
}

#[test]
fn add__op() {
    let a = bb(Fixed { raw: 0x500000000 });
    let b = bb(Fixed { raw: -0x280000000 });
    sink(a + b);
}
