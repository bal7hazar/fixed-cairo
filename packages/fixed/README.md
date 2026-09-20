# fixed

Signed Q32.32 fixed-point scalar for provable game math: `Fixed { raw: i64 }`, fused kernels that
rescale once per output (`wide`), and loop-free transcendental functions (`trig`).
Shared by the Cairo ports of glam, nalgebra and rapier. No dependencies.

Design, rounding and overflow policy: [`docs/DESIGN.md`](../../docs/DESIGN.md).
Compatible with Cairo 2.19.4.
