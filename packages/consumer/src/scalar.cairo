//! One entry point per `fixed` family.

#[starknet::contract]
pub mod Scalar {
    use fixed::{ExpTrait, Fixed, FixedTrait, TrigTrait};

    #[storage]
    struct Storage {}

    #[external(v0)]
    fn mul(self: @ContractState, a: Fixed, b: Fixed) -> Fixed {
        a * b
    }

    #[external(v0)]
    fn div(self: @ContractState, a: Fixed, b: Fixed) -> Fixed {
        a / b
    }

    #[external(v0)]
    fn sqrt(self: @ContractState, a: Fixed) -> Fixed {
        a.sqrt()
    }

    #[external(v0)]
    fn sin_cos(self: @ContractState, a: Fixed) -> (Fixed, Fixed) {
        a.sin_cos()
    }

    #[external(v0)]
    fn atan2(self: @ContractState, y: Fixed, x: Fixed) -> Fixed {
        y.atan2(x)
    }

    #[external(v0)]
    fn exp(self: @ContractState, a: Fixed) -> Fixed {
        a.exp()
    }

    #[external(v0)]
    fn ln(self: @ContractState, a: Fixed) -> Fixed {
        a.ln()
    }

    #[external(v0)]
    fn powf(self: @ContractState, a: Fixed, n: Fixed) -> Fixed {
        a.powf(n)
    }
}
