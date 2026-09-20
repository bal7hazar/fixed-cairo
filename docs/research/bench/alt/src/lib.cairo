#[inline(never)]
fn bb<T>(x: T) -> T {
    x
}
#[inline(never)]
fn sink<T, +Drop<T>>(x: T) {}

#[executable]
fn exe_base(a: u64, b: u64) {
    let _a = bb(a);
    let _b = bb(b);
    let r = bb(1_u64);
    sink(r);
}
#[executable]
fn exe_op(a: u64, b: u64) {
    let a = bb(a);
    let b = bb(b);
    let _r = bb(1_u64);
    sink(a / b);
}

#[cfg(test)]
mod tests {
    use super::{bb, sink};
    #[test]
    fn t_base() {
        let _a = bb(0x123456789_u64);
        let _b = bb(0x54321_u64);
        let r = bb(1_u64);
        sink(r);
    }
    #[test]
    fn t_op() {
        let a = bb(0x123456789_u64);
        let b = bb(0x54321_u64);
        let _r = bb(1_u64);
        sink(a / b);
    }
}
