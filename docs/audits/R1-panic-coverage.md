# R1 panic coverage: item -> `should_panic` test manifest

Audit date: 2026-09-22. Follows the "Panic messages and tests" section of
[`R1-deviations.md`](R1-deviations.md): the 61 distinct messages all had a test, but nothing tied a
documented panic of an **item** to a test that exercises it **on that item**.

## The checker

`python3 scripts/panic_coverage.py [--check]` (dependency-free, about 1 s; in `scripts/check.sh`
and the CI `fmt-lint` job). It reuses the doc-template parser of `scripts/deviations.py`.

- **Requirements.** Every public item with a `#### Panics` section other than `Never`: one
  requirement per quoted message of each bullet. Messages joined by `/` (`'i64_add Overflow'` /
  `'i64_add Underflow'`) are the two directions of one branch: either one covers it. A bullet
  with no quoted message that refers to another item (`As [`QuatTrait::slerp`]`) is an
  `(inherited)` requirement. Items inside inline modules are qualified by the module
  (`camera::rh::proj::vulkan::perspective`).
- **Attribution** of every `#[should_panic(expected: ...)]` test of
  `packages/{fixed,glam,glamx}/tests`, in this order: (a) a marker comment
  `// panics: <Owner>::<item>` above the test (for the generated `golden_*` files, which cannot
  carry one, the `MARKERS` table of the script); (b) the test name `test_<item>_<reason>` /
  `golden_<module>_<item>_<reason>`: the longest public item of the module under test that
  prefixes the name, preferring the items whose doc lists the message (operator impls answer to
  their operator: `Vec3Add` to `add`); (c) otherwise unattributed.
- **`--check` fails** on a requirement without a test, an unattributed test, a marker that names
  no item, a test whose message the doc of its item does not list (a wrong marker or a wrong doc),
  and a stale allowlist entry. Without `--check` it prints, per package, the table
  item / message / tests (or the allowlist reason, or **MISSING**), then the totals.

## Before / after

Both rows are measured with the final script (the "before" row on `8fe8b3b`, the base of the
branch, with the same allowlist).

| | requirements | covered by a test | allowlisted | missing | panic tests | attributed by marker / name | unattributed |
|---|---|---|---|---|---|---|---|
| before | 808 | 369 | 67 | 372 | 638 | 5 / 548 | 82 |
| after | 817 | 750 | 67 | **0** | 962 | 225 / 734 | **0** |

The 9 new requirements are the `'<T>: index out of bounds'` panics of the nine vector `IndexView`
impls, which now carry the doc template (`tools/codegen/fvec.py`, `intvec.py`).

324 tests were added (fixed 1, glam 296, glamx 27; 127 of them carry a marker), 93 existing
tests got a marker, none was weakened or removed. A test named after the wrong item is now
marked with the item it really calls (`test_recip_mul_*` -> `Recip::mul`,
`test_from_rotated_diagonal_overflow` -> `SdpMatrix3::from_rotated_diagonal_mat3`).

## Allowlist

67 requirements: 21 inherited `As X` docs (the panic is exercised on `X`), 21 quat requirements
deferred while the quat pull request is in flight (`packages/glam/src/quat.cairo` and
`tests/test_quat.cairo` were not edited), and 25 escalations (below). Plus 3 helper self-tests,
7 tests whose message the doc does not list (escalated), and 5 script-side markers of generated
golden tests.

| Owner::item | Message | Reason |
|---|---|---|
| `Fixed::move_towards` | `'i64_add Overflow'` | escalated: unreachable, `self + d` runs only when `rhs - self > d`, so `self + d < rhs`; `self - d` only when `self - d > rhs` (the away branches panic with 'i64_add Underflow' / 'i64_sub Overflow') |
| `Fixed::to_radians` | `'Fixed: overflow'` | escalated: unreachable, `\|self * PI / 180\| < \|self\|` |
| `camera::lh::view::look_at_mat3` | `'i64_neg Underflow'` | escalated: unreachable, the negations act on `normalize(center - eye)`, components in [-1, 1] |
| `camera::rh::view::look_at_mat3` | `'i64_neg Underflow'` | escalated: unreachable, the negations act on `normalize(center - eye)`, components in [-1, 1] |
| `Mat4::to_scale_rotation_translation` | `'i64_neg Underflow'` | escalated: unreachable, the only negation is `-length(x_axis)`, never `MIN` |
| `Vec2::normalize` | `'Fixed: overflow'` | escalated: unreachable, `norm2_wide` cannot overflow and `\|x\| * recip(len) <= 2^96`: every component is in [-1, 1] |
| `Vec2::try_normalize` | `'Fixed: overflow'` | escalated: unreachable, `norm2_wide` cannot overflow and `\|x\| * recip(len) <= 2^96`: every component is in [-1, 1] |
| `Vec2::normalize_or` | `'Fixed: overflow'` | escalated: unreachable, `norm2_wide` cannot overflow and `\|x\| * recip(len) <= 2^96`: every component is in [-1, 1] |
| `Vec2::normalize_or_zero` | `'Fixed: overflow'` | escalated: unreachable, `norm2_wide` cannot overflow and `\|x\| * recip(len) <= 2^96`: every component is in [-1, 1] |
| `Vec3::normalize` | `'Fixed: overflow'` | escalated: unreachable, `norm3_wide` cannot overflow and `\|x\| * recip(len) <= 2^96`: every component is in [-1, 1] |
| `Vec3::try_normalize` | `'Fixed: overflow'` | escalated: unreachable, `norm3_wide` cannot overflow and `\|x\| * recip(len) <= 2^96`: every component is in [-1, 1] |
| `Vec3::normalize_or` | `'Fixed: overflow'` | escalated: unreachable, `norm3_wide` cannot overflow and `\|x\| * recip(len) <= 2^96`: every component is in [-1, 1] |
| `Vec3::normalize_or_zero` | `'Fixed: overflow'` | escalated: unreachable, `norm3_wide` cannot overflow and `\|x\| * recip(len) <= 2^96`: every component is in [-1, 1] |
| `Vec2::midpoint` | `'Fixed: overflow'` | escalated: unreachable, the floored exact midpoint lies between the two inputs |
| `Vec3::midpoint` | `'Fixed: overflow'` | escalated: unreachable, the floored exact midpoint lies between the two inputs |
| `Vec4::midpoint` | `'Fixed: overflow'` | escalated: unreachable, the floored exact midpoint lies between the two inputs |
| `Vec3::rotate_towards` | `'i64_sub Overflow'` | escalated: unreachable, the only `i64` subtraction is `angle_between - PI`, with `angle_between` in [0, PI] |
| `Pose2::abs_diff_eq` | `'i64_sub Overflow'` | escalated: unreachable, built on `Fixed::abs_diff_eq`, an `i128` difference that never panics |
| `Pose3::abs_diff_eq` | `'i64_sub Overflow'` | escalated: unreachable, built on `Fixed::abs_diff_eq`, an `i128` difference that never panics |
| `SdpMatrix2::add_diagonal` | `'Fixed: overflow'` | escalated: wrong message, a plain `Fixed` sum panics with 'i64_add Overflow' (tested) |
| `SdpMatrix3::add_diagonal` | `'Fixed: overflow'` | escalated: wrong message, a plain `Fixed` sum panics with 'i64_add Overflow' (tested) |
| `SdpMatrix::SdpMatrix2Add` | `'Fixed: overflow'` | escalated: wrong message, a plain `Fixed` sum panics with 'i64_add Overflow' (tested) |
| `SdpMatrix::SdpMatrix3Add` | `'Fixed: overflow'` | escalated: wrong message, a plain `Fixed` sum panics with 'i64_add Overflow' (tested) |
| `SdpMatrix::SdpMatrix2Sub` | `'Fixed: overflow'` | escalated: wrong message, a plain `Fixed` sum panics with 'i64_sub Overflow' / 'i64_sub Underflow' (tested) |
| `SdpMatrix::SdpMatrix3Sub` | `'Fixed: overflow'` | escalated: wrong message, a plain `Fixed` sum panics with 'i64_sub Overflow' / 'i64_sub Underflow' (tested) |
| `Affine3::from_quat` | (inherited) | inherited: panics as `Mat3Trait::from_quat`, exercised there |
| `Affine3::from_axis_angle` | (inherited) | inherited: panics as `Mat3Trait::from_axis_angle`, exercised there |
| `Affine3::from_scale_rotation_translation` | (inherited) | inherited: panics as `Mat4Trait::from_scale_rotation_translation`, exercised there |
| `Affine3::from_rotation_translation` | (inherited) | inherited: panics as `Mat3Trait::from_quat`, exercised there |
| `Affine3::look_to_lh` | (inherited) | inherited: panics as `look_to_rh`, exercised there |
| `Affine3::quat_from_affine3` | (inherited) | inherited: panics as `QuatTrait::from_rotation_axes`, exercised there |
| `camera::lh::view::look_at_affine3` | (inherited) | inherited: panics as `look_at_mat4`, exercised there |
| `camera::lh::view::look_to_affine3` | (inherited) | inherited: panics as `look_to_mat4`, exercised there |
| `camera::lh::view::look_at_quat` | (inherited) | inherited: panics as `look_at_mat3` and `QuatTrait::from_mat3`, exercised there |
| `camera::rh::view::look_to_affine3` | (inherited) | inherited: panics as `look_to_mat4`, exercised there |
| `camera::rh::view::look_at_quat` | (inherited) | inherited: panics as `look_at_mat3` and `QuatTrait::from_mat3`, exercised there |
| `camera::rh::view::look_to_quat` | (inherited) | inherited: panics as `look_to_mat3` and `QuatTrait::from_mat3`, exercised there |
| `Quat::from_axis_angle` | `'Fixed: overflow'` | deferred: quat PR in flight |
| `Quat::from_rotation_axes` | `'i64_add Overflow'` | deferred: quat PR in flight |
| `Quat::from_rotation_axes` | `'Fixed: overflow'` | deferred: quat PR in flight |
| `Quat::from_mat3` | (inherited) | deferred: quat PR in flight |
| `Quat::from_mat4` | (inherited) | deferred: quat PR in flight |
| `Quat::from_affine3` | (inherited) | deferred: quat PR in flight |
| `Quat::look_to_lh` | (inherited) | deferred: quat PR in flight |
| `Quat::look_to_rh` | `'Vec3: normalize zero'` | deferred: quat PR in flight |
| `Quat::look_at_lh` | `'Vec3: normalize zero'` | deferred: quat PR in flight |
| `Quat::look_at_rh` | `'Vec3: normalize zero'` | deferred: quat PR in flight |
| `Quat::from_rotation_arc` | `'Fixed: overflow'` | deferred: quat PR in flight |
| `Quat::from_rotation_arc_colinear` | `'i64_neg Underflow'` | deferred: quat PR in flight |
| `Quat::from_rotation_arc_2d` | `'Fixed: overflow'` | deferred: quat PR in flight |
| `Quat::to_scaled_axis` | (inherited) | deferred: quat PR in flight |
| `Quat::inverse` | (inherited) | deferred: quat PR in flight |
| `Quat::length_recip` | `'Fixed: overflow'` | deferred: quat PR in flight |
| `Quat::rotate_towards` | (inherited) | deferred: quat PR in flight |
| `Quat::lerp` | `'Fixed: overflow'` | deferred: quat PR in flight |
| `Quat::slerp` | `'Fixed: overflow'` | deferred: quat PR in flight |
| `Quat::div_scalar` | `'Fixed: overflow'` | deferred: quat PR in flight |
| `Quat::QuatMul` | `'Fixed: overflow'` | deferred: quat PR in flight |
| `Pose2::lerp` | (inherited) | inherited: panics as `Rot2Trait::slerp` and `Vec2Trait::lerp`, exercised there |
| `Pose2::mul_vec2` | (inherited) | inherited: panics as `Pose2Trait::transform_point`, exercised there |
| `Pose3::new` | (inherited) | inherited: panics as `QuatTrait::from_scaled_axis`, exercised there |
| `Pose3::rotation` | (inherited) | inherited: panics as `QuatTrait::from_scaled_axis`, exercised there |
| `Pose3::lerp` | (inherited) | inherited: panics as `QuatTrait::slerp` and `Vec3Trait::lerp`, exercised there |
| `Pose3::from_mat4` | (inherited) | inherited: panics as `QuatTrait::from_mat4`, exercised there |
| `Pose3::mul_vec3` | (inherited) | inherited: panics as `Pose3Trait::transform_point`, exercised there |
| `Rot2::normalize_mut` | (inherited) | inherited: panics as `Rot2Trait::normalize`, exercised there |
| `Rot2::Rot2MulAssign` | (inherited) | inherited: panics as `Rot2Mul`, exercised there |

| Test | Reason |
|---|---|
| `packages/glam/tests/test_swizzles.cairo` `fixed_vec::checker_detects_mismatch` | self-test of the ck2 test helper, not a library panic |
| `packages/glam/tests/test_swizzles.cairo` `ivec::checker_detects_mismatch` | self-test of the ck2 test helper, not a library panic |
| `packages/glam/tests/test_swizzles.cairo` `uvec::checker_detects_mismatch` | self-test of the ck2 test helper, not a library panic |

| Test | Reason |
|---|---|
| `packages/glamx/tests/test_sdp.cairo` `test_add_overflow` | escalated: the doc of the item lists 'Fixed: overflow', the plain `Fixed` sum panics with the i64 message |
| `packages/glamx/tests/test_sdp.cairo` `test_sub_underflow` | escalated: the doc of the item lists 'Fixed: overflow', the plain `Fixed` sum panics with the i64 message |
| `packages/glamx/tests/test_sdp.cairo` `test_add_diagonal_overflow` | escalated: the doc of the item lists 'Fixed: overflow', the plain `Fixed` sum panics with the i64 message |
| `packages/glamx/tests/test_sdp.cairo` `test_add_diagonal2_overflow` | escalated: the doc of the item lists 'Fixed: overflow', the plain `Fixed` sum panics with the i64 message |
| `packages/glamx/tests/test_sdp.cairo` `test_add2_overflow` | escalated: the doc of the item lists 'Fixed: overflow', the plain `Fixed` sum panics with the i64 message |
| `packages/glamx/tests/test_sdp.cairo` `test_sub3_underflow` | escalated: the doc of the item lists 'Fixed: overflow', the plain `Fixed` sum panics with the i64 message |
| `packages/fixed/tests/golden_fixed.cairo` `golden_fixed_move_towards_panics_away_underflow` | escalated: the doc lists 'i64_add Overflow' / 'i64_sub Underflow' for `self +- d`, the away-underflow branch panics with 'i64_add Underflow' |

| Test | Marker |
|---|---|
| `packages/fixed/tests/golden_fixed.cairo` `golden_fixed_euclid_panics_division_by_zero` | `Fixed::div_euclid` |
| `packages/fixed/tests/golden_fixed.cairo` `golden_fixed_euclid_panics_overflow` | `Fixed::div_euclid` |
| `packages/glam/tests/golden_quat.cairo` `golden_quat_mul_div_scalar_panics_div_scalar_zero` | `Quat::div_scalar` |
| `packages/fixed/tests/golden_wide.cairo` `golden_wide_recip_mul_panics_overflow` | `Recip::mul` |
| `packages/glamx/tests/golden_sdp.cairo` `golden_sdp_inverse_unchecked2_panics_singular` | `SdpMatrix2::inverse_unchecked` |

## Escalations

No `src/` change was made (brief). Each item below needs a doc fix by its owner; the allowlist
entry becomes stale (and `--check` fails) once the doc changes, so it must be removed with the fix.

**Unreachable documented panics** (drop the bullet, or say `Never`):

- `Vec2` / `Vec3` `normalize`, `try_normalize`, `normalize_or`, `normalize_or_zero`,
  `'Fixed: overflow'`: `norm{2,3}_wide` cannot overflow, `len = floor(sqrt(sum x^2)) >= |x|`, the
  reciprocal is `floor(2^96 / len)` and `|x| * r <= 2^96`: every component is in `[-1, 1]`. (The
  `Vec4` ones are reachable, four `MIN` components overflow `norm4_wide`, and are tested.)
- `Vec2` / `Vec3` / `Vec4::midpoint`, `'Fixed: overflow'`: each component is
  `floor(a + (b - a) / 2)`, computed exactly, which lies between `a` and `b`.
- `Vec3::rotate_towards`, `'i64_sub ...'`: the only `i64` subtraction is `angle_between - PI` with
  `angle_between` in `[0, PI]`.
- `Mat4::to_scale_rotation_translation`, `'i64_neg Underflow'`: the only negation is
  `-length(x_axis)`, never `MIN`.
- `camera::{lh,rh}::view::look_at_mat3`, `'i64_neg Underflow'`: the negations act on
  `normalize(center - eye)`, whose components are in `[-1, 1]` (the `look_at_mat4` one, on
  `dot(eye, s)`, is reachable and tested).
- `Fixed::to_radians`, `'Fixed: overflow'`: `|self * PI / 180| < |self|`.
- `Pose2` / `Pose3::abs_diff_eq`, `'i64_sub ...'`: built on `Fixed::abs_diff_eq`, an `i128`
  difference documented `Never`.

**Wrong message in the doc** (the real message is tested):

- `Fixed::move_towards`: the doc lists `'i64_add Overflow'` / `'i64_sub Underflow'` for
  `self +- d`, which is unreachable (`self + d` runs only when `self + d < rhs`, `self - d` only
  when `self - d > rhs`); the away branches (negative `d`) panic with `'i64_add Underflow'`
  (golden test) and `'i64_sub Overflow'` (`test_move_towards_away_overflow_panics`).
- `SdpMatrix2` / `SdpMatrix3::add_diagonal`, `SdpMatrix2Add`, `SdpMatrix3Add`, `SdpMatrix2Sub`,
  `SdpMatrix3Sub`: documented `'Fixed: overflow'`, but the plain `Fixed` `+` / `-` panic with
  `'i64_add Overflow'` / `'i64_sub Underflow'` (tests in `test_sdp.cairo`, allowlisted in
  `ALLOWED_UNDOCUMENTED` until the doc is fixed).
- Not blocking (the requirement is covered by another path): the `orthographic` / `frustum` docs
  of the camera say that a box difference or sum leaving the scalar range panics with
  `'Fixed: overflow'`; the plain `Fixed` `+` / `-` panic with the `i64_add` / `i64_sub` messages.

**Compile budget.** One `should_panic` test per (item, message) cannot be table-driven (one panic
per test), and no new test file was allowed. Six files end above the 1 200-line guideline:
`test_camera.cairo` 1 719 (882 before), `test_vec2.cairo` 1 469 (1 287), `test_vec3.cairo`
1 575 (1 333), `test_vec4.cairo` 1 326 (1 120), `test_ivec3.cairo` 1 221 (1 209),
`test_ivec4.cairo` 1 299 (1 287). Every added test is a one-line `let _ = <call>;` body. Options:
accept the panic sections above the guideline (they add one call site per test), or split the
panic tests into `test_<m>_panics.cairo` files (a `tests/lib.cairo` change, orchestrator-owned).

**Inventory.** The nine `IndexView` doc blocks add nine items to the `scripts/deviations.py`
inventory; the appendix of `R1-deviations.md` was already stale on the base commit
(`deviations.py --check` fails there too) and is left to the deviation-doc task.

## Follow-up (#R1m)

Branch `test/panic-followup`, follow-up of the panic coverage above: the 21 `deferred: quat PR in
flight` entries (the quat pull request #36 is merged), the "unreachable documented panics"
escalation, and the "wrong message in the doc" escalation. `deviations.py`'s doc-comment parser is
unaffected: none of the edits below touch anything outside a `#### Panics` / `#### Deviations`
bullet.

**The 21 quat entries.** `is_normalized` and `is_near_identity` already document `Never` (fixed by
#36, nothing to do). Of the other 20, each got a `#[should_panic(expected: ...)]` test in
`test_quat.cairo` with a `// panics: Quat::<item>` marker: `from_axis_angle`, `from_rotation_axes`
(`'i64_add Overflow'`), `from_mat3`, `from_mat4`, `from_affine3`, `look_to_lh`, `look_to_rh`,
`look_at_lh`, `look_at_rh`, `from_rotation_arc`, `from_rotation_arc_colinear`,
`from_rotation_arc_2d`, `to_scaled_axis`, `inverse`, `length_recip`, `rotate_towards`, `lerp`,
`slerp`, `div_scalar`, `QuatMul`. The 21st, `from_rotation_axes` / `'Fixed: overflow'`, turned out
unreachable on inspection: the doc already noted "whichever branch is taken, the value under the
root is `1 - m22 -+ (m11 -+ m00) >= 1`" (an algebraic identity of the branch-selection
inequalities alone, true of any input, not just a real rotation matrix), which bounds the shared
reciprocal `r` to at most `1/2`; every component it scales is itself a plain `i64` sum or
difference that already fits the scalar range (else the `'i64_add'` / `'i64_sub'` bullet would
have fired first), so `r.mul(component)` is at most half of an already-valid scalar and cannot
overflow. Verified two ways: algebraically (above) and by a 2 000 000-case randomized brute force
of the raw Q32.32 arithmetic in Python, `check_rotaxes.py` (scratch, not committed), which found no
overflow. The doc bullet and the allowlist entry were removed instead of adding an unreachable
test.

**Unreachable documented panics (escalation 1).** Verified by reading the code (the branch-
selection or construction that makes the panic unreachable) and, for the vector items, confirmed
against the existing golden/fuzz tests; no test was reachable to add, so the bullet was dropped (or
the whole item set to `Never`) and the allowlist entry removed:

- `Vec2` / `Vec3::normalize` / `try_normalize` / `normalize_or` / `normalize_or_zero`: the `OVF`
  bullet is conditional on the vector's dimension in `tools/codegen/fvec.py` now (`t.n == 4`
  only); `Vec4` keeps it (reachable, already tested).
- `Vec2` / `Vec3` / `Vec4::midpoint`: `OVF` dropped unconditionally in `fvec.py` (unreachable at
  every dimension).
- `Vec3::rotate_towards`: the `SUB_P` bullet dropped in `fvec.py`; the `'Fixed: overflow'` bullet
  (reachable, tested) stays.
- `Mat4::to_scale_rotation_translation`: the `NEG_P` bullet dropped in `fmat.py`.
- `camera::{lh,rh}::view::look_at_mat3`: the `'i64_neg Underflow'` bullet dropped by hand (not
  generated); the `'Fixed: overflow'` and `'i64_sub ...'` bullets (reachable via `look_at_mat4`'s
  `dot(eye, s)` and the element differences) stay.
- `Fixed::to_radians`: the whole item is now `Never`.
- `Pose2` / `Pose3::abs_diff_eq`: the whole item is now `Never`.

**Wrong message in the doc (escalation 2).** The doc bullet now quotes the message the code
actually raises; the mechanism note (what the doc used to say, and why it was wrong) moved to
`#### Deviations` so it does not itself read as a second, untested requirement:

- `Fixed::move_towards`: the `self +- d` bullet now reads `'i64_add Underflow'` / `'i64_sub
  Overflow'` (the away branches; the towards branches are unreachable, noted inline), matching
  the existing `golden_fixed_move_towards_panics_away_underflow` and
  `test_move_towards_away_overflow_panics`.
- `SdpMatrix2` / `SdpMatrix3::add_diagonal`, `SdpMatrix{2,3}Add`, `SdpMatrix{2,3}Sub`: the bullet
  now reads `'i64_add Overflow'` / `'i64_add Underflow'` (`Add`, `add_diagonal`) or `'i64_sub
  Overflow'` / `'i64_sub Underflow'` (`Sub`), matching the existing `test_add_overflow`,
  `test_sub_underflow`, `test_add_diagonal_overflow`, `test_add_diagonal2_overflow`,
  `test_add2_overflow`, `test_sub3_underflow` of `test_sdp.cairo`.
- `orthographic` / `frustum` (all three graphics-API variants, both handedness files, 12 doc
  blocks): not blocking (the `'Fixed: overflow'` requirement was already covered by the genuine
  quotient/depth-term overflow, e.g. the `width_one_ulp` / `depth_overflow` tests), so fixed for
  accuracy without touching the checker-tracked message: the `'Fixed: overflow'` bullet now names
  only the rounded quotient / depth term, and a new `#### Deviations` bullet says the box
  difference/sum (and, for `frustum`, `2 * near`) is a plain `i64` operation instead, naming the
  real messages. No test file besides `test_quat.cairo` is in this task's allowlist, and none of
  `orthographic` / `frustum`'s existing tests needed to change.

**Before / after** (same script, same repository, before = the base commit of this branch):

| | requirements | covered | allowlisted | missing | panic tests | by marker / by name |
|---|---|---|---|---|---|---|
| before | 815 | 748 | 67 | 0 | 960 | 225 / 732 |
| after | 796 | 775 | 21 | **0** | 980 | 245 / 732 |

19 fewer requirements (the unreachable bullets dropped: 4 + 4 normalize family, 3 midpoint, 1
`rotate_towards`, 1 `to_scale_rotation_translation`, 2 `look_at_mat3`, 1 `to_radians`, 2
`abs_diff_eq`, 1 `from_rotation_axes`), 20 more panic tests (the quat tests, all marker-attributed),
46 fewer allowlist entries (21 quat + 19 now-absent unreachable requirements + 6 wrong-message
entries whose corrected message the existing test already satisfies without an allowlist entry).

**Line budget.** `test_quat.cairo` is 1138 lines after the 20 new tests: still under the 1200-line
guideline, no overage.

**Inventory (again).** No new item was added or removed from the `scripts/deviations.py`
inventory by this follow-up (doc-comment wording only); `R1-deviations.md`'s appendix is unchanged
from the base commit and is still left to the deviation-doc task (`deviations.py --check` is not
part of `scripts/check.sh`).
