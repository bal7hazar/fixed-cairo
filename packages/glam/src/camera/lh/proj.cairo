//! Projection matrix constructors.
//!
//! Expects left-handed Y-up view space input.
//!
//! Each sub-module targets a specific graphics API convention:
//!
//! * [`opengl`] - NDC Z range **[-1, 1]**, Y-up
//! * [`directx`] - NDC Z range **[0, 1]**, Y-up
//! * [`vulkan`] - NDC Z range **[0, 1]**, Y-down

pub mod opengl {
    //! OpenGL NDC convention: Z range **[-1, 1]**, Y-up.
    //!
    //! Expects a left-handed Y-up view space input.

    use fixed::fixed::{Fixed, ONE, TWO};
    use crate::camera::camera_impl;
    use crate::mat4::Mat4;

    /// Creates a perspective projection matrix for use with OpenGL.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [-1, 1] and Y-up.
    ///
    /// This is the OpenGL `gluPerspective` equivalent.
    ///
    /// Implementation notes:
    /// * `#[inline(always)]`: measured about 4k gas cheaper than a call (`alt_perspective_call` in
    ///   `gas/camera.snap`).
    ///
    /// Mirrors `glam::camera::lh::proj::opengl::perspective`.
    /// #### Panics
    /// * `'camera: fov out of range'` if `vertical_fov` is not in `(0, PI)` (glam-rs does not check
    ///   it).
    /// * `'camera: aspect zero'` if `aspect_ratio` is zero.
    /// * `'camera: near not positive'` if `near <= 0` (the `glam_assert!` of glam-rs, checked
    ///   here).
    /// * `'camera: far not positive'` if `far <= 0` (the `glam_assert!` of glam-rs, checked here).
    /// * `'Fixed: division by zero'` if `vertical_fov` is one raw ULP (the half angle floors to
    ///   zero) or if `near == far`.
    /// * `'Fixed: overflow'` if `cot(vertical_fov / 2)` (`vertical_fov` below about `1e-9`), `xx`
    ///   or a depth term does not fit the scalar range. The depth terms fit while `far / (far -
    ///   near)` and `near * far / (far - near)` are below `2^30`, e.g. for `far >= 2 * near` and
    ///   `far < 2^29`. `near * far` itself is never formed as a `Fixed`.
    /// #### Deviations
    /// * `cot(vertical_fov / 2)` is one `sin_cos` (`fixed::trig`, 1.02 ULP) and one truncated
    ///   division: `yy` is within `4 (1 + yy)^2` ULP of the exact value (the floored half angle,
    ///   the two `sin_cos` errors and the division), `xx = yy / aspect_ratio` within that over
    ///   `|aspect_ratio|` plus 1 ULP.
    /// * One division `q = far / (far - near)` (truncated) for both depth terms: `zz = +-(2 q - 1)`
    ///   is within 2 ULP of the exact value and `tz = -2 near q` (one fused product, one floor
    ///   rescale) within `2 near + 1` ULP.
    /// * `near > far` (a reversed depth range) is accepted, as in glam-rs.
    #[inline(always)]
    pub fn perspective(vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed, far: Fixed) -> Mat4 {
        let (xx, h) = camera_impl::fov_scales(vertical_fov, aspect_ratio);
        let q = camera_impl::depth_q(near, far);
        camera_impl::persp(xx, h, q + q - ONE, ONE, camera_impl::depth_tz2(near, q))
    }

    /// Creates an orthographic projection matrix for use with OpenGL.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [-1, 1] and Y-up.
    ///
    /// This is the OpenGL `glOrtho` equivalent.
    ///
    /// Implementation notes:
    /// * `#[inline(always)]`: measured about 4k gas cheaper than a call (`alt_orthographic_call` in
    ///   `gas/camera.snap`).
    ///
    /// Mirrors `glam::camera::lh::proj::opengl::orthographic`.
    /// #### Panics
    /// * `'Fixed: division by zero'` if `left == right`, `bottom == top` or `near == far`.
    /// * `'Fixed: overflow'` if an element (a rounded quotient) does not fit the scalar range.
    /// #### Deviations
    /// * A difference or a sum of the box (`right - left`, `top - bottom`, `far - near`,
    ///   `left + right`, `bottom + top`, `far + near`) that leaves the scalar range panics with
    ///   a plain `i64` message (`'i64_sub Overflow'` / `'i64_sub Underflow'` / `'i64_add
    ///   Overflow'` / `'i64_add Underflow'`), not `'Fixed: overflow'` (R1 panic-coverage audit,
    ///   escalation 2).
    /// * Every quotient is rounded to nearest (one shared `Recip` per axis, and one for the depth)
    ///   where glam-rs multiplies by a rounded reciprocal: each element is within 1 ULP of the
    ///   exact value.
    #[inline(always)]
    pub fn orthographic(
        left: Fixed, right: Fixed, bottom: Fixed, top: Fixed, near: Fixed, far: Fixed,
    ) -> Mat4 {
        let (xx, tx) = camera_impl::ortho_axis(left, right, TWO);
        let (yy, ty) = camera_impl::ortho_axis(bottom, top, TWO);
        let (zz, tz) = camera_impl::ortho_depth_gl(near, far, TWO);
        camera_impl::ortho(xx, yy, zz, tx, ty, tz)
    }

    /// Creates a perspective projection matrix from a frustum for use with OpenGL.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [-1, 1] and Y-up.
    ///
    /// This is the OpenGL `glFrustum` equivalent.
    ///
    /// Implementation notes:
    /// * As in glam-rs, the off-axis terms are `zx = (right + left) / (right - left)` and `zy =
    ///   (top + bottom) / (top - bottom)` in the left-handed matrices too (same sign as the
    ///   right-handed ones, with `w = +z`): an off-center left-handed frustum is mirrored, and the
    ///   box maps to the NDC cube only when `right = -left` and `top = -bottom`.
    /// * `#[inline(always)]`: as `orthographic` (about 4k gas cheaper than a call).
    ///
    /// Mirrors `glam::camera::lh::proj::opengl::frustum`.
    /// #### Panics
    /// * `'camera: near not positive'` if `near <= 0` (the `glam_assert!` of glam-rs, checked
    ///   here).
    /// * `'camera: far not positive'` if `far <= 0` (the `glam_assert!` of glam-rs, checked here).
    /// * `'Fixed: division by zero'` if `left == right`, `bottom == top` or `near == far`.
    /// * `'Fixed: overflow'` if a quotient or a depth term does not fit the scalar range. The
    ///   depth terms fit while `far / (far - near)` and `near * far / (far - near)` are below
    ///   `2^30`, as in `perspective`.
    /// #### Deviations
    /// * `2 * near`, or a difference or a sum of the box (`right - left`, `right + left`,
    ///   `top - bottom`, `top + bottom`), that leaves the scalar range panics with a plain
    ///   `i64` message (`'i64_add Overflow'` / `'i64_add Underflow'` / `'i64_sub Overflow'` /
    ///   `'i64_sub Underflow'`), not `'Fixed: overflow'` (R1 panic-coverage audit, escalation 2).
    /// * `xx`, `yy`, `zx` and `zy` are quotients rounded to nearest (one shared `Recip` per axis):
    ///   each is within 1 ULP of the exact value.
    /// * The depth terms are those of `perspective`: one truncated division and one fused product.
    ///   `zz` is within 2 ULP and `tz` within `2 near + 1` ULP.
    /// * `near > far` is accepted, as in glam-rs.
    #[inline(always)]
    pub fn frustum(
        left: Fixed, right: Fixed, bottom: Fixed, top: Fixed, near: Fixed, far: Fixed,
    ) -> Mat4 {
        let q = camera_impl::depth_q(near, far);
        let two_near = near + near;
        let (xx, zx) = camera_impl::frustum_axis(left, right, two_near);
        let (yy, zy) = camera_impl::frustum_axis(bottom, top, two_near);
        camera_impl::frust(xx, yy, zx, zy, q + q - ONE, ONE, camera_impl::depth_tz2(near, q))
    }
}

pub mod vulkan {
    //! Vulkan NDC convention: Z range **[0, 1]**, Y-down.
    //!
    //! Expects a left-handed Y-up view space input.
    //!
    //! Includes standard, infinite-far, and reverse-depth variants.

    use fixed::fixed::{Fixed, ONE, TWO, ZERO};
    use crate::camera::camera_impl::{self, NEG_TWO};
    use crate::mat4::Mat4;

    /// Creates a perspective projection matrix for use with Vulkan.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [0, 1] and Y-down.
    ///
    /// Implementation notes:
    /// * `#[inline(always)]`: measured about 4k gas cheaper than a call (`alt_perspective_call` in
    ///   `gas/camera.snap`).
    ///
    /// Mirrors `glam::camera::lh::proj::vulkan::perspective`.
    /// #### Panics
    /// * `'camera: fov out of range'` if `vertical_fov` is not in `(0, PI)` (glam-rs does not check
    ///   it).
    /// * `'camera: aspect zero'` if `aspect_ratio` is zero.
    /// * `'camera: near not positive'` if `near <= 0` (the `glam_assert!` of glam-rs, checked
    ///   here).
    /// * `'camera: far not positive'` if `far <= 0` (the `glam_assert!` of glam-rs, checked here).
    /// * `'Fixed: division by zero'` if `vertical_fov` is one raw ULP (the half angle floors to
    ///   zero) or if `near == far`.
    /// * `'Fixed: overflow'` if `cot(vertical_fov / 2)` (`vertical_fov` below about `1e-9`), `xx`
    ///   or a depth term does not fit the scalar range. The depth terms fit while `far / (far -
    ///   near)` and `near * far / (far - near)` are below `2^31`, e.g. for `far >= 2 * near` and
    ///   `far < 2^31`. `near * far` itself is never formed as a `Fixed`.
    /// #### Deviations
    /// * `cot(vertical_fov / 2)` is one `sin_cos` (`fixed::trig`, 1.02 ULP) and one truncated
    ///   division: `yy` is within `4 (1 + yy)^2` ULP of the exact value (the floored half angle,
    ///   the two `sin_cos` errors and the division), `xx = yy / aspect_ratio` within that over
    ///   `|aspect_ratio|` plus 1 ULP.
    /// * One division `q = far / (far - near)` (truncated) for both depth terms: `zz = +-q` is
    ///   within 1 ULP of the exact value and `tz = -near * q` (one fused product, one floor
    ///   rescale) within `near + 1` ULP.
    /// * `near > far` (a reversed depth range) is accepted, as in glam-rs.
    #[inline(always)]
    pub fn perspective(vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed, far: Fixed) -> Mat4 {
        let (xx, h) = camera_impl::fov_scales(vertical_fov, aspect_ratio);
        let q = camera_impl::depth_q(near, far);
        camera_impl::persp(xx, -h, q, ONE, camera_impl::depth_tz(near, q))
    }

    /// Creates an infinite perspective projection matrix for use with Vulkan.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [0, 1] and Y-down.
    ///
    /// Like `perspective`, but with an infinite value for `far`. Points at distance `near` map to
    /// depth `0`; as distance approaches infinity, depth approaches `1`.
    ///
    /// Implementation notes:
    /// * `#[inline(always)]`: measured about 4k gas cheaper than a call (`alt_perspective_call` in
    ///   `gas/camera.snap`).
    ///
    /// Mirrors `glam::camera::lh::proj::vulkan::perspective_infinite`.
    /// #### Panics
    /// * `'camera: fov out of range'` if `vertical_fov` is not in `(0, PI)` (glam-rs does not check
    ///   it).
    /// * `'camera: aspect zero'` if `aspect_ratio` is zero.
    /// * `'camera: near not positive'` if `near <= 0` (the `glam_assert!` of glam-rs, checked
    ///   here).
    /// * `'Fixed: division by zero'` if `vertical_fov` is one raw ULP (the half angle floors to
    ///   zero).
    /// * `'Fixed: overflow'` if `cot(vertical_fov / 2)` (`vertical_fov` below about `1e-9`), `xx`
    ///   or `near` does not fit the scalar range.
    /// #### Deviations
    /// * `cot(vertical_fov / 2)` is one `sin_cos` (`fixed::trig`, 1.02 ULP) and one truncated
    ///   division: `yy` is within `4 (1 + yy)^2` ULP of the exact value (the floored half angle,
    ///   the two `sin_cos` errors and the division), `xx = yy / aspect_ratio` within that over
    ///   `|aspect_ratio|` plus 1 ULP.
    /// * Every other element is exact.
    #[inline(always)]
    pub fn perspective_infinite(vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed) -> Mat4 {
        let (xx, h) = camera_impl::fov_scales(vertical_fov, aspect_ratio);
        camera_impl::check_near(near);
        camera_impl::persp(xx, -h, ONE, ONE, -near)
    }

    /// Creates an infinite perspective projection matrix with reversed depth for use with Vulkan.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [0, 1] and Y-down.
    ///
    /// Maps `near` to depth `1` and infinity to depth `0`.
    ///
    /// Reversed Z improves depth precision when used with a floating-point depth buffer.
    ///
    /// Implementation notes:
    /// * `#[inline(always)]`: measured about 4k gas cheaper than a call (`alt_perspective_call` in
    ///   `gas/camera.snap`).
    ///
    /// Mirrors `glam::camera::lh::proj::vulkan::perspective_infinite_reverse`.
    /// #### Panics
    /// * `'camera: fov out of range'` if `vertical_fov` is not in `(0, PI)` (glam-rs does not check
    ///   it).
    /// * `'camera: aspect zero'` if `aspect_ratio` is zero.
    /// * `'camera: near not positive'` if `near <= 0` (the `glam_assert!` of glam-rs, checked
    ///   here).
    /// * `'Fixed: division by zero'` if `vertical_fov` is one raw ULP (the half angle floors to
    ///   zero).
    /// * `'Fixed: overflow'` if `cot(vertical_fov / 2)` (`vertical_fov` below about `1e-9`), `xx`
    ///   or `near` does not fit the scalar range.
    /// #### Deviations
    /// * `cot(vertical_fov / 2)` is one `sin_cos` (`fixed::trig`, 1.02 ULP) and one truncated
    ///   division: `yy` is within `4 (1 + yy)^2` ULP of the exact value (the floored half angle,
    ///   the two `sin_cos` errors and the division), `xx = yy / aspect_ratio` within that over
    ///   `|aspect_ratio|` plus 1 ULP.
    /// * Every other element is exact.
    #[inline(always)]
    pub fn perspective_infinite_reverse(
        vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed,
    ) -> Mat4 {
        let (xx, h) = camera_impl::fov_scales(vertical_fov, aspect_ratio);
        camera_impl::check_near(near);
        camera_impl::persp(xx, -h, ZERO, ONE, near)
    }

    /// Creates an orthographic projection matrix for use with Vulkan.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [0, 1] and Y-down.
    ///
    /// Implementation notes:
    /// * As in glam-rs, `YFLIP` negates `yy` only: the Y translation `-(top + bottom) / (top -
    ///   bottom)` is not flipped, so the box maps to the NDC cube when `bottom = -top`.
    /// * `#[inline(always)]`: measured about 4k gas cheaper than a call (`alt_orthographic_call` in
    ///   `gas/camera.snap`).
    ///
    /// Mirrors `glam::camera::lh::proj::vulkan::orthographic`.
    /// #### Panics
    /// * `'Fixed: division by zero'` if `left == right`, `bottom == top` or `near == far`.
    /// * `'Fixed: overflow'` if an element (a rounded quotient) does not fit the scalar range.
    /// #### Deviations
    /// * A difference or a sum of the box (`right - left`, `top - bottom`, `far - near`,
    ///   `left + right`, `bottom + top`, `near`) that leaves the scalar range panics with a
    ///   plain `i64` message (`'i64_sub Overflow'` / `'i64_sub Underflow'` / `'i64_add
    ///   Overflow'` / `'i64_add Underflow'`), not `'Fixed: overflow'` (R1 panic-coverage audit,
    ///   escalation 2).
    /// * Every quotient is rounded to nearest (one shared `Recip` per axis, and one for the depth)
    ///   where glam-rs multiplies by a rounded reciprocal: each element is within 1 ULP of the
    ///   exact value.
    #[inline(always)]
    pub fn orthographic(
        left: Fixed, right: Fixed, bottom: Fixed, top: Fixed, near: Fixed, far: Fixed,
    ) -> Mat4 {
        let (xx, tx) = camera_impl::ortho_axis(left, right, TWO);
        let (yy, ty) = camera_impl::ortho_axis(bottom, top, NEG_TWO);
        let (zz, tz) = camera_impl::ortho_depth_zo(near, far, ONE);
        camera_impl::ortho(xx, yy, zz, tx, ty, tz)
    }

    /// Creates a perspective projection matrix from a frustum for use with Vulkan.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [0, 1] and Y-down.
    ///
    /// Implementation notes:
    /// * As in glam-rs, the off-axis terms are `zx = (right + left) / (right - left)` and `zy =
    ///   (top + bottom) / (top - bottom)` in the left-handed matrices too (same sign as the
    ///   right-handed ones, with `w = +z`): an off-center left-handed frustum is mirrored, and the
    ///   box maps to the NDC cube only when `right = -left` and `top = -bottom`.
    /// * `#[inline(always)]`: as `orthographic` (about 4k gas cheaper than a call).
    ///
    /// Mirrors `glam::camera::lh::proj::vulkan::frustum`.
    /// #### Panics
    /// * `'camera: near not positive'` if `near <= 0` (the `glam_assert!` of glam-rs, checked
    ///   here).
    /// * `'camera: far not positive'` if `far <= 0` (the `glam_assert!` of glam-rs, checked here).
    /// * `'Fixed: division by zero'` if `left == right`, `bottom == top` or `near == far`.
    /// * `'Fixed: overflow'` if a quotient or a depth term does not fit the scalar range. The
    ///   depth terms fit while `far / (far - near)` and `near * far / (far - near)` are below
    ///   `2^31`, as in `perspective`.
    /// #### Deviations
    /// * `2 * near`, or a difference or a sum of the box (`right - left`, `right + left`,
    ///   `top - bottom`, `top + bottom`), that leaves the scalar range panics with a plain
    ///   `i64` message (`'i64_add Overflow'` / `'i64_add Underflow'` / `'i64_sub Overflow'` /
    ///   `'i64_sub Underflow'`), not `'Fixed: overflow'` (R1 panic-coverage audit, escalation 2).
    /// * `xx`, `yy`, `zx` and `zy` are quotients rounded to nearest (one shared `Recip` per axis):
    ///   each is within 1 ULP of the exact value.
    /// * The depth terms are those of `perspective`: one truncated division and one fused product.
    ///   `zz` is within 1 ULP and `tz` within `near + 1` ULP.
    /// * `near > far` is accepted, as in glam-rs.
    #[inline(always)]
    pub fn frustum(
        left: Fixed, right: Fixed, bottom: Fixed, top: Fixed, near: Fixed, far: Fixed,
    ) -> Mat4 {
        let q = camera_impl::depth_q(near, far);
        let two_near = near + near;
        let (xx, zx) = camera_impl::frustum_axis(left, right, two_near);
        let (yy, zy) = camera_impl::frustum_axis_flip(bottom, top, two_near);
        camera_impl::frust(xx, yy, zx, zy, q, ONE, camera_impl::depth_tz(near, q))
    }
}

pub mod directx {
    //! DirectX and WebGPU NDC convention: Z range **[0, 1]**, Y-up.
    //!
    //! Expects a left-handed Y-up view space input.
    //!
    //! Includes standard, infinite-far, and reverse-depth variants.

    use fixed::fixed::{Fixed, ONE, TWO, ZERO};
    use crate::camera::camera_impl;
    use crate::mat4::Mat4;

    /// Creates a perspective projection matrix for use with DirectX and WebGPU.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [0, 1] and Y-up.
    ///
    /// Implementation notes:
    /// * `#[inline(always)]`: measured about 4k gas cheaper than a call (`alt_perspective_call` in
    ///   `gas/camera.snap`).
    ///
    /// Mirrors `glam::camera::lh::proj::directx::perspective`.
    /// #### Panics
    /// * `'camera: fov out of range'` if `vertical_fov` is not in `(0, PI)` (glam-rs does not check
    ///   it).
    /// * `'camera: aspect zero'` if `aspect_ratio` is zero.
    /// * `'camera: near not positive'` if `near <= 0` (the `glam_assert!` of glam-rs, checked
    ///   here).
    /// * `'camera: far not positive'` if `far <= 0` (the `glam_assert!` of glam-rs, checked here).
    /// * `'Fixed: division by zero'` if `vertical_fov` is one raw ULP (the half angle floors to
    ///   zero) or if `near == far`.
    /// * `'Fixed: overflow'` if `cot(vertical_fov / 2)` (`vertical_fov` below about `1e-9`), `xx`
    ///   or a depth term does not fit the scalar range. The depth terms fit while `far / (far -
    ///   near)` and `near * far / (far - near)` are below `2^31`, e.g. for `far >= 2 * near` and
    ///   `far < 2^31`. `near * far` itself is never formed as a `Fixed`.
    /// #### Deviations
    /// * `cot(vertical_fov / 2)` is one `sin_cos` (`fixed::trig`, 1.02 ULP) and one truncated
    ///   division: `yy` is within `4 (1 + yy)^2` ULP of the exact value (the floored half angle,
    ///   the two `sin_cos` errors and the division), `xx = yy / aspect_ratio` within that over
    ///   `|aspect_ratio|` plus 1 ULP.
    /// * One division `q = far / (far - near)` (truncated) for both depth terms: `zz = +-q` is
    ///   within 1 ULP of the exact value and `tz = -near * q` (one fused product, one floor
    ///   rescale) within `near + 1` ULP.
    /// * `near > far` (a reversed depth range) is accepted, as in glam-rs.
    #[inline(always)]
    pub fn perspective(vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed, far: Fixed) -> Mat4 {
        let (xx, h) = camera_impl::fov_scales(vertical_fov, aspect_ratio);
        let q = camera_impl::depth_q(near, far);
        camera_impl::persp(xx, h, q, ONE, camera_impl::depth_tz(near, q))
    }

    /// Creates an infinite perspective projection matrix for use with DirectX and WebGPU.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [0, 1] and Y-up.
    ///
    /// Like `perspective`, but with an infinite value for `far`. Points at distance `near` map to
    /// depth `0`; as distance approaches infinity, depth approaches `1`.
    ///
    /// Implementation notes:
    /// * `#[inline(always)]`: measured about 4k gas cheaper than a call (`alt_perspective_call` in
    ///   `gas/camera.snap`).
    ///
    /// Mirrors `glam::camera::lh::proj::directx::perspective_infinite`.
    /// #### Panics
    /// * `'camera: fov out of range'` if `vertical_fov` is not in `(0, PI)` (glam-rs does not check
    ///   it).
    /// * `'camera: aspect zero'` if `aspect_ratio` is zero.
    /// * `'camera: near not positive'` if `near <= 0` (the `glam_assert!` of glam-rs, checked
    ///   here).
    /// * `'Fixed: division by zero'` if `vertical_fov` is one raw ULP (the half angle floors to
    ///   zero).
    /// * `'Fixed: overflow'` if `cot(vertical_fov / 2)` (`vertical_fov` below about `1e-9`), `xx`
    ///   or `near` does not fit the scalar range.
    /// #### Deviations
    /// * `cot(vertical_fov / 2)` is one `sin_cos` (`fixed::trig`, 1.02 ULP) and one truncated
    ///   division: `yy` is within `4 (1 + yy)^2` ULP of the exact value (the floored half angle,
    ///   the two `sin_cos` errors and the division), `xx = yy / aspect_ratio` within that over
    ///   `|aspect_ratio|` plus 1 ULP.
    /// * Every other element is exact.
    #[inline(always)]
    pub fn perspective_infinite(vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed) -> Mat4 {
        let (xx, h) = camera_impl::fov_scales(vertical_fov, aspect_ratio);
        camera_impl::check_near(near);
        camera_impl::persp(xx, h, ONE, ONE, -near)
    }

    /// Creates an infinite perspective projection matrix with reversed depth for use with DirectX
    /// and WebGPU.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [0, 1] and Y-up.
    ///
    /// Maps `near` to depth `1` and infinity to depth `0`.
    ///
    /// Reversed Z improves depth precision when used with a floating-point depth buffer.
    ///
    /// Implementation notes:
    /// * `#[inline(always)]`: measured about 4k gas cheaper than a call (`alt_perspective_call` in
    ///   `gas/camera.snap`).
    ///
    /// Mirrors `glam::camera::lh::proj::directx::perspective_infinite_reverse`.
    /// #### Panics
    /// * `'camera: fov out of range'` if `vertical_fov` is not in `(0, PI)` (glam-rs does not check
    ///   it).
    /// * `'camera: aspect zero'` if `aspect_ratio` is zero.
    /// * `'camera: near not positive'` if `near <= 0` (the `glam_assert!` of glam-rs, checked
    ///   here).
    /// * `'Fixed: division by zero'` if `vertical_fov` is one raw ULP (the half angle floors to
    ///   zero).
    /// * `'Fixed: overflow'` if `cot(vertical_fov / 2)` (`vertical_fov` below about `1e-9`), `xx`
    ///   or `near` does not fit the scalar range.
    /// #### Deviations
    /// * `cot(vertical_fov / 2)` is one `sin_cos` (`fixed::trig`, 1.02 ULP) and one truncated
    ///   division: `yy` is within `4 (1 + yy)^2` ULP of the exact value (the floored half angle,
    ///   the two `sin_cos` errors and the division), `xx = yy / aspect_ratio` within that over
    ///   `|aspect_ratio|` plus 1 ULP.
    /// * Every other element is exact.
    #[inline(always)]
    pub fn perspective_infinite_reverse(
        vertical_fov: Fixed, aspect_ratio: Fixed, near: Fixed,
    ) -> Mat4 {
        let (xx, h) = camera_impl::fov_scales(vertical_fov, aspect_ratio);
        camera_impl::check_near(near);
        camera_impl::persp(xx, h, ZERO, ONE, near)
    }

    /// Creates an orthographic projection matrix for use with DirectX and WebGPU.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [0, 1] and Y-up.
    ///
    /// Implementation notes:
    /// * `#[inline(always)]`: measured about 4k gas cheaper than a call (`alt_orthographic_call` in
    ///   `gas/camera.snap`).
    ///
    /// Mirrors `glam::camera::lh::proj::directx::orthographic`.
    /// #### Panics
    /// * `'Fixed: division by zero'` if `left == right`, `bottom == top` or `near == far`.
    /// * `'Fixed: overflow'` if an element (a rounded quotient) does not fit the scalar range.
    /// #### Deviations
    /// * A difference or a sum of the box (`right - left`, `top - bottom`, `far - near`,
    ///   `left + right`, `bottom + top`, `near`) that leaves the scalar range panics with a
    ///   plain `i64` message (`'i64_sub Overflow'` / `'i64_sub Underflow'` / `'i64_add
    ///   Overflow'` / `'i64_add Underflow'`), not `'Fixed: overflow'` (R1 panic-coverage audit,
    ///   escalation 2).
    /// * Every quotient is rounded to nearest (one shared `Recip` per axis, and one for the depth)
    ///   where glam-rs multiplies by a rounded reciprocal: each element is within 1 ULP of the
    ///   exact value.
    #[inline(always)]
    pub fn orthographic(
        left: Fixed, right: Fixed, bottom: Fixed, top: Fixed, near: Fixed, far: Fixed,
    ) -> Mat4 {
        let (xx, tx) = camera_impl::ortho_axis(left, right, TWO);
        let (yy, ty) = camera_impl::ortho_axis(bottom, top, TWO);
        let (zz, tz) = camera_impl::ortho_depth_zo(near, far, ONE);
        camera_impl::ortho(xx, yy, zz, tx, ty, tz)
    }

    /// Creates a perspective projection matrix from a frustum for use with DirectX and WebGPU.
    ///
    /// Expects a left-handed Y-up view space input.
    /// Outputs NDC with Z in [0, 1] and Y-up.
    ///
    /// Implementation notes:
    /// * As in glam-rs, the off-axis terms are `zx = (right + left) / (right - left)` and `zy =
    ///   (top + bottom) / (top - bottom)` in the left-handed matrices too (same sign as the
    ///   right-handed ones, with `w = +z`): an off-center left-handed frustum is mirrored, and the
    ///   box maps to the NDC cube only when `right = -left` and `top = -bottom`.
    /// * `#[inline(always)]`: as `orthographic` (about 4k gas cheaper than a call).
    ///
    /// Mirrors `glam::camera::lh::proj::directx::frustum`.
    /// #### Panics
    /// * `'camera: near not positive'` if `near <= 0` (the `glam_assert!` of glam-rs, checked
    ///   here).
    /// * `'camera: far not positive'` if `far <= 0` (the `glam_assert!` of glam-rs, checked here).
    /// * `'Fixed: division by zero'` if `left == right`, `bottom == top` or `near == far`.
    /// * `'Fixed: overflow'` if a quotient or a depth term does not fit the scalar range. The
    ///   depth terms fit while `far / (far - near)` and `near * far / (far - near)` are below
    ///   `2^31`, as in `perspective`.
    /// #### Deviations
    /// * `2 * near`, or a difference or a sum of the box (`right - left`, `right + left`,
    ///   `top - bottom`, `top + bottom`), that leaves the scalar range panics with a plain
    ///   `i64` message (`'i64_add Overflow'` / `'i64_add Underflow'` / `'i64_sub Overflow'` /
    ///   `'i64_sub Underflow'`), not `'Fixed: overflow'` (R1 panic-coverage audit, escalation 2).
    /// * `xx`, `yy`, `zx` and `zy` are quotients rounded to nearest (one shared `Recip` per axis):
    ///   each is within 1 ULP of the exact value.
    /// * The depth terms are those of `perspective`: one truncated division and one fused product.
    ///   `zz` is within 1 ULP and `tz` within `near + 1` ULP.
    /// * `near > far` is accepted, as in glam-rs.
    #[inline(always)]
    pub fn frustum(
        left: Fixed, right: Fixed, bottom: Fixed, top: Fixed, near: Fixed, far: Fixed,
    ) -> Mat4 {
        let q = camera_impl::depth_q(near, far);
        let two_near = near + near;
        let (xx, zx) = camera_impl::frustum_axis(left, right, two_near);
        let (yy, zy) = camera_impl::frustum_axis(bottom, top, two_near);
        camera_impl::frust(xx, yy, zx, zy, q, ONE, camera_impl::depth_tz(near, q))
    }
}
