use fixed::{Fixed, FixedTrait, ONE, ONE_RAW, ZERO};

#[test]
fn test_fixed_add_sub_neg() {
    let a = FixedTrait::from_raw(3 * ONE_RAW);
    let b = FixedTrait::from_raw(-ONE_RAW / 2);
    assert_eq!(a + b, Fixed { raw: 0x280000000 });
    assert_eq!(a - b, Fixed { raw: 0x380000000 });
    assert_eq!(-ONE + ONE, ZERO);
}

#[test]
#[should_panic(expected: 'i64_add Overflow')]
fn test_fixed_add_overflow_panics() {
    let max = FixedTrait::from_raw(0x7fffffffffffffff);
    let _ = max + ONE;
}
