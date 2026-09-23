//! Port of glam-rs `camera` @ 0.33.8 on the Q32.32 scalar: view and projection matrix
//! constructors.
//!
//! The module tree is the one of glam-rs: `camera::{rh, lh}::view` (`look_at_*`, `look_to_*`) and
//! `camera::{rh, lh}::proj::{opengl, vulkan, directx}` (`perspective`, `perspective_infinite`,
//! `perspective_infinite_reverse`, `orthographic`, `frustum`). Pick `lh` or `rh` from the
//! handedness of the world; the projection functions expect the Y-up view space of the view
//! functions of the same handedness.
//!
//! | module | NDC Z | NDC Y |
//! |---|---|---|
//! | `opengl` | [-1, 1] | Up |
//! | `directx` | [0, 1] | Up |
//! | `vulkan` | [0, 1] | Down |
//!
//! glam-rs builds every function from one const-generic kernel (`RH`, `ZO`, `YFLIP`); Cairo has
//! no const generics (and `#[inline(always)]` is rejected on generic functions, E2143), so each
//! public function assembles its matrix from the small `#[inline(always)]` helpers of
//! `camera_impl` (the shared scalars: `cot(fov / 2)`, `far / (far - near)`, ...): every variant is
//! branch free. The public constructors are `#[inline(always)]` themselves: measured about 4k gas
//! (2k for the `Mat3` views, 5k for `look_at_mat4`) cheaper than a call (`gas/camera.snap`,
//! `alt_*_call` and `alt_*_delegate`), and the `Mat4` view constructors are bit-identical to
//! `Mat4::look_*` with the call removed.
//!
//! #### Numerics
//! * `cot(fov / 2)` is one `sin_cos` and one division (`fixed::trig`, accurate to about 1 ULP).
//! * The depth terms share **one** division: with `q = far / (far - near)` (rounded), the
//!   `[0, 1]` matrices use `zz = +-q` and `tz = -near * q`; the `[-1, 1]` ones use
//!   `zz = +-(2 q - 1)` and `tz = -2 near q`. The product `near * q` is one fused wide product with
//!   a single floor rescale, so `near * far` is never formed as a `Fixed` (it would overflow for
//!   `near * far >= 2^31`). The usable range of every function is in its `#### Panics` section.
//! * `orthographic` and `frustum` divide by `right - left` and `top - bottom` through one shared
//!   `fixed::wide::Recip` per axis (two quotients each, rounded to nearest).
//!
//! #### Deviations (module wide)
//! * The deprecated `Mat4::perspective_*`, `orthographic_*` and `frustum_*` methods are not ported
//!   (glam-rs 0.33.1 moved them here); `Mat4::look_*` exist in `glam::mat4`.
//! * `Mat3A` / `Affine3A` collapse into `Mat3` / `Affine3` (docs/DESIGN.md section 1): there is
//!   no `look_*_mat3a` / `look_*_affine3a`.
//! * glam-rs quirks that are kept bit for bit: the Vulkan `orthographic` negates `yy` but not the
//!   Y translation, and the left-handed `frustum` keeps the sign of the off-axis terms `zx`, `zy`
//!   of the right-handed one (documented on the items).
//! * The `glam_assert!` preconditions that keep the result meaningful are checked and panic:
//!   `near > 0`, `far > 0` (glam-rs, `perspective*` and `frustum`), a vertical field of view in
//!   `(0, PI)` and a non-zero aspect ratio. The normalization of `dir` and `up` of the view
//!   functions is not checked (docs/DESIGN.md section 3).
//! * NaN and infinity do not exist: a degenerate box (`left == right`, `near == far`) panics with
//!   `'Fixed: division by zero'` instead of producing infinities.

mod camera_impl;
pub mod lh;
pub mod rh;
