//! Oracles of `glamx::pose2`. Spec: `specs/pose2.toml`.

use crate::prelude::*;
use glam::DVec2;
use glamx::{DPose2, DRot2};

const MAX_T: i64 = 500 * ONE_RAW;

fn pose(rng: &mut Rng) -> DPose2 {
    let angle = raw_to_f64(rng.range_i64(-26986075409, 26986075409));
    let mut leaf = || raw_to_f64(rng.range_i64(-MAX_T, MAX_T));
    DPose2::from_parts(DVec2::new(leaf(), leaf()), DRot2::new(angle))
}

pub fn register(r: &mut Registry) {
    r.generator("pose", |rng| value_of(pose(rng)));
    r.generator("rigid", |rng| value_of(pose(rng).to_mat3()));

    r.add("mul", |a| a[0].dpose2() * a[1].dpose2());
    r.add("inv_mul", |a| a[0].dpose2().inv_mul(&a[1].dpose2()));
    r.add("inverse", |a| a[0].dpose2().inverse());
    r.add("transform_point", |a| a[0].dpose2().transform_point(a[1].dvec2()));
    r.add("transform_vector", |a| a[0].dpose2().transform_vector(a[1].dvec2()));
    r.add("inverse_transform_point", |a| {
        a[0].dpose2().inverse_transform_point(a[1].dvec2())
    });
    r.add("inverse_transform_vector", |a| {
        a[0].dpose2().inverse_transform_vector(a[1].dvec2())
    });
    r.add("mul_vec2", |a| a[0].dpose2() * a[1].dvec2());
    r.add("prepend_translation", |a| a[0].dpose2().prepend_translation(a[1].dvec2()));
    r.add("append_translation", |a| a[0].dpose2().append_translation(a[1].dvec2()));
    r.add("mul_rot2", |a| a[0].dpose2() * a[1].dpose2().rotation);
    r.add("mul_pose2", |a| a[0].dpose2().rotation * a[1].dpose2());
    r.add("new", |a| DPose2::new(a[0].dvec2(), a[1].f()));
    r.add("rotation", |a| DPose2::rotation(a[0].f()));
    r.add("lerp", |a| a[0].dpose2().lerp(&a[1].dpose2(), a[2].f()));
    r.add("to_mat3", |a| a[0].dpose2().to_mat3());
    r.add("from_mat3", |a| DPose2::from_mat3(a[0].dmat3()));
}
