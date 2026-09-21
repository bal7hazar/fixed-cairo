//! Oracles of `glam::camera`. Spec: `specs/camera.toml`. Every closure is the glam-rs 0.33.8 f64
//! function of the same name (`glam::dcamera::{lh, rh}::{view, proj::{opengl, vulkan, directx}}`).
//!
//! The `skip` guards of the view oracles drop the cases where the Cairo result is dominated by an
//! amplified error (a view matrix whose `dir` and `up` are nearly parallel, a `center - eye` of
//! length below 1): the same guards as the `Mat4::look_*` oracles of `oracles/mat4.rs`.

use crate::prelude::*;
use glam::dcamera::{lh, rh};

pub fn register(r: &mut Registry) {
    r.add("lh_opengl_perspective", |a| lh::proj::opengl::perspective(a[0].f(), a[1].f(), a[2].f(), a[3].f()));
    r.add("lh_opengl_orthographic", |a| lh::proj::opengl::orthographic(a[0].f(), a[1].f(), a[2].f(), a[3].f(), a[4].f(), a[5].f()));
    r.add("lh_opengl_frustum", |a| lh::proj::opengl::frustum(a[0].f(), a[1].f(), a[2].f(), a[3].f(), a[4].f(), a[5].f()));
    r.add("lh_vulkan_perspective", |a| lh::proj::vulkan::perspective(a[0].f(), a[1].f(), a[2].f(), a[3].f()));
    r.add("lh_vulkan_perspective_infinite", |a| lh::proj::vulkan::perspective_infinite(a[0].f(), a[1].f(), a[2].f()));
    r.add("lh_vulkan_perspective_infinite_reverse", |a| lh::proj::vulkan::perspective_infinite_reverse(a[0].f(), a[1].f(), a[2].f()));
    r.add("lh_vulkan_orthographic", |a| lh::proj::vulkan::orthographic(a[0].f(), a[1].f(), a[2].f(), a[3].f(), a[4].f(), a[5].f()));
    r.add("lh_vulkan_frustum", |a| lh::proj::vulkan::frustum(a[0].f(), a[1].f(), a[2].f(), a[3].f(), a[4].f(), a[5].f()));
    r.add("lh_directx_perspective", |a| lh::proj::directx::perspective(a[0].f(), a[1].f(), a[2].f(), a[3].f()));
    r.add("lh_directx_perspective_infinite", |a| lh::proj::directx::perspective_infinite(a[0].f(), a[1].f(), a[2].f()));
    r.add("lh_directx_perspective_infinite_reverse", |a| lh::proj::directx::perspective_infinite_reverse(a[0].f(), a[1].f(), a[2].f()));
    r.add("lh_directx_orthographic", |a| lh::proj::directx::orthographic(a[0].f(), a[1].f(), a[2].f(), a[3].f(), a[4].f(), a[5].f()));
    r.add("lh_directx_frustum", |a| lh::proj::directx::frustum(a[0].f(), a[1].f(), a[2].f(), a[3].f(), a[4].f(), a[5].f()));
    r.add("lh_view_look_to_mat4", |a| -> Out {
        let (eye, dir, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        if dir.cross(up).length() < 0.5 {
            return skip("lh look_to_mat4: dir and up are nearly parallel");
        }
        lh::view::look_to_mat4(eye, dir, up).into()
    });
    r.add("lh_view_look_at_mat4", |a| -> Out {
        let (eye, center, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        let d = center - eye;
        if d.length() < 1.0 {
            return skip("lh look_at_mat4: |center - eye| < 1 amplifies the error of `normalize`");
        }
        if d.normalize().cross(up).length() < 0.5 {
            return skip("lh look_at_mat4: the view direction and up are nearly parallel");
        }
        lh::view::look_at_mat4(eye, center, up).into()
    });
    r.add("lh_view_look_to_mat3", |a| -> Out {
        let (dir, up) = (a[0].dvec3(), a[1].dvec3());
        if dir.cross(up).length() < 0.5 {
            return skip("lh look_to_mat3: dir and up are nearly parallel");
        }
        lh::view::look_to_mat3(dir, up).into()
    });
    r.add("lh_view_look_at_mat3", |a| -> Out {
        let (eye, center, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        let d = center - eye;
        if d.length() < 1.0 {
            return skip("lh look_at_mat3: |center - eye| < 1 amplifies the error of `normalize`");
        }
        if d.normalize().cross(up).length() < 0.5 {
            return skip("lh look_at_mat3: the view direction and up are nearly parallel");
        }
        lh::view::look_at_mat3(eye, center, up).into()
    });
    r.add("rh_opengl_perspective", |a| rh::proj::opengl::perspective(a[0].f(), a[1].f(), a[2].f(), a[3].f()));
    r.add("rh_opengl_orthographic", |a| rh::proj::opengl::orthographic(a[0].f(), a[1].f(), a[2].f(), a[3].f(), a[4].f(), a[5].f()));
    r.add("rh_opengl_frustum", |a| rh::proj::opengl::frustum(a[0].f(), a[1].f(), a[2].f(), a[3].f(), a[4].f(), a[5].f()));
    r.add("rh_vulkan_perspective", |a| rh::proj::vulkan::perspective(a[0].f(), a[1].f(), a[2].f(), a[3].f()));
    r.add("rh_vulkan_perspective_infinite", |a| rh::proj::vulkan::perspective_infinite(a[0].f(), a[1].f(), a[2].f()));
    r.add("rh_vulkan_perspective_infinite_reverse", |a| rh::proj::vulkan::perspective_infinite_reverse(a[0].f(), a[1].f(), a[2].f()));
    r.add("rh_vulkan_orthographic", |a| rh::proj::vulkan::orthographic(a[0].f(), a[1].f(), a[2].f(), a[3].f(), a[4].f(), a[5].f()));
    r.add("rh_vulkan_frustum", |a| rh::proj::vulkan::frustum(a[0].f(), a[1].f(), a[2].f(), a[3].f(), a[4].f(), a[5].f()));
    r.add("rh_directx_perspective", |a| rh::proj::directx::perspective(a[0].f(), a[1].f(), a[2].f(), a[3].f()));
    r.add("rh_directx_perspective_infinite", |a| rh::proj::directx::perspective_infinite(a[0].f(), a[1].f(), a[2].f()));
    r.add("rh_directx_perspective_infinite_reverse", |a| rh::proj::directx::perspective_infinite_reverse(a[0].f(), a[1].f(), a[2].f()));
    r.add("rh_directx_orthographic", |a| rh::proj::directx::orthographic(a[0].f(), a[1].f(), a[2].f(), a[3].f(), a[4].f(), a[5].f()));
    r.add("rh_directx_frustum", |a| rh::proj::directx::frustum(a[0].f(), a[1].f(), a[2].f(), a[3].f(), a[4].f(), a[5].f()));
    r.add("rh_view_look_to_mat4", |a| -> Out {
        let (eye, dir, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        if dir.cross(up).length() < 0.5 {
            return skip("rh look_to_mat4: dir and up are nearly parallel");
        }
        rh::view::look_to_mat4(eye, dir, up).into()
    });
    r.add("rh_view_look_at_mat4", |a| -> Out {
        let (eye, center, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        let d = center - eye;
        if d.length() < 1.0 {
            return skip("rh look_at_mat4: |center - eye| < 1 amplifies the error of `normalize`");
        }
        if d.normalize().cross(up).length() < 0.5 {
            return skip("rh look_at_mat4: the view direction and up are nearly parallel");
        }
        rh::view::look_at_mat4(eye, center, up).into()
    });
    r.add("rh_view_look_to_mat3", |a| -> Out {
        let (dir, up) = (a[0].dvec3(), a[1].dvec3());
        if dir.cross(up).length() < 0.5 {
            return skip("rh look_to_mat3: dir and up are nearly parallel");
        }
        rh::view::look_to_mat3(dir, up).into()
    });
    r.add("rh_view_look_at_mat3", |a| -> Out {
        let (eye, center, up) = (a[0].dvec3(), a[1].dvec3(), a[2].dvec3());
        let d = center - eye;
        if d.length() < 1.0 {
            return skip("rh look_at_mat3: |center - eye| < 1 amplifies the error of `normalize`");
        }
        if d.normalize().cross(up).length() < 0.5 {
            return skip("rh look_at_mat3: the view direction and up are nearly parallel");
        }
        rh::view::look_at_mat3(eye, center, up).into()
    });
}
