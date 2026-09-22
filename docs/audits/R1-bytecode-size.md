# R1i - bytecode size of a consumer contract

Toolchain: scarb 2.19.4 / Cairo 2.19.4, starknet-foundry 0.61.0 (`.tool-versions`). Every number
below is reproducible with `scripts/bytecode_size.py` (fixtures and attribution); the gas numbers of
section 4 come from `gas/*.snap` or from the scratch harness described in section 4.1.
Fixture sizes and the attribution table are re-measured on top of #32 / #34 (`main` at `7484b4b`).
Only `KitchenSink` (+298 CASM felts) and `SymmetricEigen3::new` (+298 felts for the first use)
changed. The eigen3 rewrite accounts for both.

## Summary

* The heaviest fixture, `KitchenSink` (22 entry points: every `fixed` family, a 2D and a 3D
  integrator step, contact frames, `Mat3` / `Mat4` inverse, `slerp`, Euler angles, a camera
  projection, `SymmetricEigen3`), compiles to **50,705 CASM felts: 61.9 % of the 81,920-felt
  limit**. Sierra length (23,120 felts, 28 %) and class object size (1.43 MB, 35 %) are not the
  binding limits: **CASM bytecode is**.
* Non-inlined items are paid once (8 to 65 felts per further call site). The inlined ones are paid
  at every call site: from 51 felts (`Fixed` `mul`) to 900 (`Mat4::mul_mat4`) and 1,118 (camera
  `perspective`). One class fits ~90 call sites of `mul_mat4` or ~1,600 of `Fixed * Fixed`.
* A non-inlined call to a mid-size kernel costs +15 % to +42 % gas. The compiler's
  `inlining-strategy` can cut the class size by up to 27 %, but it roughly **doubles the gas** of
  every item. **Recommendation: keep the library's inlining as it is, keep the compiler default,
  and document consumer-side outlining (`#[inline(never)]` wrapper) for call sites that are
  bytecode-bound.** A rapier-scale engine should plan to split into several classes from the start.

## 1. Limits

| quantity | limit | enforced by |
|---|--:|---|
| Sierra program length | 81,920 felts | gateway, `stateless_transaction_validator.rs` (`sierra_program.len() > max_contract_bytecode_size`) |
| CASM bytecode length | 81,920 felts | Sierra -> CASM compilation (`apollo_sierra_compilation_config`, `DEFAULT_MAX_BYTECODE_SIZE = 80 * 1024`) |
| Sierra class object | 4,089,446 bytes | gateway (`serde_json::to_string(&contract_class).len() > max_contract_class_object_size`) |
| compiled (CASM) class object | 4,089,446 bytes | class manager (`max_compiled_contract_class_object_size`) |

Sources: <https://docs.starknet.io/learn/cheatsheets/chain-info> (Mainnet Starknet v0.14.2,
Sepolia v0.14.3, read 2026-09-21; "Max contract bytecode size 81,920 felts", "Max contract class
size 4,089,446 bytes") and the sequencer that enforces them,
<https://github.com/starkware-libs/sequencer> at `1c4fa0261847f403fa0e2da81d412a30d56481d9` (files
named above). The documentation warns that the limits are revised regularly: they are parameters of
`scripts/bytecode_size.py` (`LIMITS`). Note that the 81,920-felt bytecode limit applies to **both**
the Sierra program (gateway) and the CASM bytecode (compiler); the class byte sizes are measured
as the compact JSON the sequencer serializes (the script re-serializes the declared fields, without
the Sierra debug info).

## 2. Fixtures (`packages/consumer`, release profile, `gas/bytecode.size`)

| contract | Sierra felts | CASM felts | CASM / limit | Sierra class bytes | CASM class bytes | bytes / limit |
|---|--:|--:|--:|--:|--:|--:|
| `Particles2d` | 2,233 | 6,233 | 7.6 % | 109,729 | 168,940 | 4.1 % |
| `Rigid3d` | 6,510 | 14,301 | 17.5 % | 318,633 | 390,190 | 9.5 % |
| `Scalar` | 9,138 | 14,946 | 18.2 % | 362,294 | 436,984 | 10.7 % |
| `KitchenSink` | 23,120 | 50,705 | 61.9 % | 1,223,140 | 1,427,321 | 34.9 % |

Reading:

* `Scalar` is almost as large as `Rigid3d`: the transcendental polynomials and their tables
  dominate, not the linear algebra. `ln` (7.5k) and `powf` (9.3k, which shares `exp`/`ln` code)
  alone are ~11k felts.
* The 3D step itself is cheap in bytecode (`Rigid3d`: 14.3k for step, contact frame and inertia
  basis). `KitchenSink` adds ~30k for `Mat4::inverse`, `slerp` + Euler, a camera and
  `SymmetricEigen3` on top of the three smaller contracts.
* Headroom of `KitchenSink`: 31,215 CASM felts. A contract that holds a full rapier-style step
  (broad phase, narrow phase for several shape pairs, a solver with several joint types) on top of
  this will most likely cross the limit: the consumer architecture (several classes and
  `library_call_syscall`, or one class per subsystem) is the lever, not the library.

## 3. Attribution: CASM felts per call site

`scripts/bytecode_size.py attribution` (default `inlining-strategy`). One probe contract per item
and per number of call sites (0, 1, 2 calls in two entry points of the same signature); `1st use =
v1 - v0`, `each further use = v2 - v1`. Sorted by the cost of a further use.

| item | 1st use | each further use | `inline(always)` today | further sites in one class (81,920 / cost) | further sites in the `KitchenSink` headroom |
|---|--:|--:|:-:|--:|--:|
| `rh::proj::opengl::perspective` | 2,180 | 1,118 | yes | 73 | 27 |
| `Mat4::mul_mat4` | 905 | 900 | yes | 91 | 34 |
| `Mat3::from_quat` | 627 | 612 | yes | 133 | 51 |
| `Pose3::inv_mul` | 564 | 549 | yes | 149 | 56 |
| `Mat3::mul_mat3` | 502 | 497 | yes | 164 | 62 |
| `Pose3 * Pose3` | 438 | 433 | yes | 189 | 72 |
| `Pose2::inv_mul` | 328 | 313 | yes | 261 | 99 |
| `Quat::normalize` | 290 | 280 | yes | 292 | 111 |
| `Quat::mul_quat` | 248 | 243 | yes | 337 | 128 |
| `Vec3::normalize` | 251 | 236 | yes | 347 | 132 |
| `Pose3::transform_point` | 224 | 219 | yes | 374 | 142 |
| `Fixed / Fixed` | 221 | 211 | yes | 388 | 147 |
| `Quat::mul_vec3` | 206 | 201 | yes | 407 | 155 |
| `Vec3::cross` | 180 | 175 | yes | 468 | 178 |
| `Vec3::dot` (`dot3`) | 61 | 56 | yes | 1,462 | 557 |
| `Fixed::sqrt` | 62 | 52 | yes | 1,575 | 600 |
| `Fixed * Fixed` | 56 | 51 | yes | 1,606 | 612 |
| `Fixed::ln` | 7,477 | 65 | no | - | - |
| `Quat::to_euler` (YXZ) | 3,628 | 35 | no | - | - |
| `Mat4::inverse` | 2,628 | 25 | no | - | - |
| `Quat::slerp` | 3,655 | 24 | no | - | - |
| `Fixed::powf` | 9,298 | 14 | no | - | - |
| `Fixed::atan2` | 2,607 | 14 | no | - | - |
| `SdpMatrix3::from_rotated_diagonal` | 977 | 14 | no | - | - |
| `Fixed::exp` | 1,635 | 13 | no | - | - |
| `Mat3::inverse` | 1,033 | 13 | no | - | - |
| `Rot2::from_angle` | 1,050 | 13 | yes (wraps the non-inlined `sin_cos`) | - | - |
| `Fixed::sin_cos` | 1,048 | 11 | no | - | - |
| `Quat::from_scaled_axis` | 1,511 | 11 | no | - | - |
| `Quat::from_euler` (YXZ) | 1,450 | 11 | no | - | - |
| `SymmetricEigen3::new` | 5,659 | 8 | no | - | - |

Reading:

* The split already follows DESIGN rule 4.3: every item above ~1k felts is a call (paid once),
  every inlined item is <= 1.1k felts per site. The one-time cost of the non-inlined items is what
  sizes `Scalar` and `KitchenSink`; it does not grow with the number of call sites.
* The costs are not additive between items that share code (`powf` reuses `exp2` / `log2`
  bodies; two entry points that call the same `sim` function pay it once).
* Sierra felts per further use are much smaller (8 for `mul`, 421 for `mul_mat4`, full table in
  the script output): Sierra is not the binding limit for this library.

## 4. What changing the inlining would cost

### 4.1 Non-inlined call of an inlined item (consumer-side `#[inline(never)]` wrapper)

Measured in a scratch snforge package (not committed) outside the workspace, with the
`benches::harness` protocol: `X__base` (inputs through `bb`, `sink`), `X__inline` (the library call
as it is), `X__call` (the same call inside a local `#[inline(never)] fn twin_X(..) { .. }`). The
`inline` column agrees with `gas/*.snap` within a few percent (`mul_mat4` 35,800 here vs 36,480 in
`gas/mat4.snap`, `Vec3::normalize` 8,720 in both). `camera` is taken from `gas/camera.snap`
(`rh_opengl_perspective` vs `alt_perspective_call`).

| item | inlined gas | called gas | call overhead | felts saved per further site |
|---|--:|--:|--:|--:|
| `rh::proj::opengl::perspective` | 50,060 | 52,620 | +2,560 (+5.1 %) | ~1,100 |
| `Mat4::mul_mat4` | 35,800 | 42,330 | +6,530 (+18.2 %) | ~890 |
| `Mat3::from_quat` | 20,660 | 22,770 | +2,110 (+10.2 %) | ~600 |
| `Pose3::inv_mul` | 20,000 | 22,910 | +2,910 (+14.6 %) | ~535 |
| `Mat3::mul_mat3` | 18,740 | 22,250 | +3,510 (+18.7 %) | ~485 |
| `Pose3 * Pose3` | 18,680 | 21,590 | +2,910 (+15.6 %) | ~420 |
| `Pose2::inv_mul` | 9,520 | 11,530 | +2,010 (+21.1 %) | ~300 |
| `Quat::normalize` | 10,500 | 12,110 | +1,610 (+15.3 %) | ~265 |
| `Quat::mul_quat` | 9,640 | 11,650 | +2,010 (+20.9 %) | ~230 |
| `Vec3::normalize` | 8,720 | 10,130 | +1,410 (+16.2 %) | ~225 |
| `Pose3::transform_point` | 9,560 | 11,670 | +2,110 (+22.1 %) | ~205 |
| `Fixed / Fixed` | 3,340 | 4,730 | +1,390 (+41.6 %) | ~200 |
| `Quat::mul_vec3` | 8,960 | 10,770 | +1,810 (+20.2 %) | ~190 |
| `Vec3::cross` | 6,260 | 7,970 | +1,710 (+27.3 %) | ~165 |

A call costs ~1.4k-3.5k gas of argument passing and return (6.5k for the 32 scalars of two `Mat4`),
i.e. +15 % to +42 % on the mid-size kernels. The felts saved per site are the further-use cost
of section 3 minus the call sequence (~10-15 felts).

### 4.2 Compiler `inlining-strategy` of the consumer

Scarb 2.19.4 accepts `default`, `avoid` or a number (`unknown inlining strategy: ... use one of:
default, avoid or a number`), set as `[profile.release.cairo] inlining-strategy` (or `[cairo]`) in
the consumer's manifest. It applies to every crate compiled into the class, the library and the
corelib included. `#[inline(always)]` is honoured under every setting: the further-use cost of the
inlined items stays of the same order (`mul_mat4` 900 -> 576 felts at `8`, `Fixed * Fixed` 51 -> 53).

Bytecode (`scripts/bytecode_size.py attribution --strategy S`, CASM felts):

| strategy | `Particles2d` | `Rigid3d` | `Scalar` | `KitchenSink` | vs default |
|---|--:|--:|--:|--:|--:|
| `default` | 6,233 | 14,301 | 14,946 | 50,705 | - |
| `avoid` | 6,180 | 15,313 | 16,185 | 49,692 | -2.0 % |
| `8` | 5,060 | 11,563 | 11,134 | 38,745 | -23.6 % |
| `16` | 5,032 | 11,450 | 11,139 | 38,570 | -23.9 % |
| `24` | 4,617 | 10,243 | 11,030 | 36,981 | -27.1 % |
| `64` | 6,048 | 14,441 | 14,965 | 50,836 | +0.3 % |

Gas (same scratch harness, `X__inline - X__base`, the package's `[cairo] inlining-strategy`
set to each value):

This table was measured before #32 / #34 were merged. The `SymmetricEigen3::new` row is stale: #34
rewrote the solver, and `gas/eigen3.snap` now gives `new_generic` 535,850 gas on its own input. The
other rows use code that #32 / #34 did not change.

| item | default | avoid | 8 | 24 | 64 |
|---|--:|--:|--:|--:|--:|
| `Fixed * Fixed` | 1,580 | 4,420 (+180 %) | 3,320 (+110 %) | 3,320 (+110 %) | 2,500 (+58 %) |
| `Fixed / Fixed` | 3,340 | 3,020 (-10 %) | 3,020 (-10 %) | 2,420 (-28 %) | 3,340 (+0 %) |
| `Fixed::sqrt` | 2,020 | 3,520 (+74 %) | 3,520 (+74 %) | 2,020 (+0 %) | 2,940 (+46 %) |
| `Fixed::sin_cos` | 31,300 | 83,090 (+165 %) | 63,100 (+102 %) | 57,900 (+85 %) | 31,300 (+0 %) |
| `Fixed::atan2` | 28,020 | 68,350 (+144 %) | 51,310 (+83 %) | 41,820 (+49 %) | 28,020 (+0 %) |
| `Fixed::exp` | 20,840 | 263,170 (+1163 %) | 41,590 (+100 %) | 37,290 (+79 %) | 20,840 (+0 %) |
| `Fixed::ln` | 19,520 | 60,190 (+208 %) | 38,450 (+97 %) | 33,640 (+72 %) | 21,350 (+9 %) |
| `Fixed::powf` | 47,530 | 345,390 (+627 %) | 88,510 (+86 %) | 77,600 (+63 %) | 47,530 (+0 %) |
| `Vec3::cross` | 6,260 | 13,860 (+121 %) | 10,560 (+69 %) | 10,560 (+69 %) | 6,260 (+0 %) |
| `Vec3::normalize` | 8,720 | 18,960 (+117 %) | 15,860 (+82 %) | 14,760 (+69 %) | 8,720 (+0 %) |
| `Quat::mul_quat` | 9,640 | 20,080 (+108 %) | 15,680 (+63 %) | 15,680 (+63 %) | 9,640 (+0 %) |
| `Quat::mul_vec3` | 8,960 | 15,660 (+75 %) | 13,260 (+48 %) | 13,260 (+48 %) | 8,960 (+0 %) |
| `Quat::normalize` | 10,500 | 23,280 (+122 %) | 19,380 (+85 %) | 18,280 (+74 %) | 10,500 (+0 %) |
| `Quat::from_scaled_axis` | 48,820 | 122,790 (+152 %) | 94,640 (+94 %) | 88,340 (+81 %) | 49,740 (+2 %) |
| `Quat::slerp` | 142,940 | 372,090 (+160 %) | 276,620 (+94 %) | 255,130 (+78 %) | 142,020 (-1 %) |
| `Mat3::mul_mat3` | 18,740 | 43,380 (+131 %) | 33,480 (+79 %) | 33,480 (+79 %) | 17,820 (-5 %) |
| `Mat3::from_quat` | 20,660 | 52,890 (+156 %) | 40,890 (+98 %) | 40,890 (+98 %) | 20,660 (+0 %) |
| `Mat3::inverse` | 39,530 | 92,550 (+134 %) | 72,590 (+84 %) | 71,590 (+81 %) | 40,450 (+2 %) |
| `Mat4::mul_mat4` | 35,800 | 80,320 (+124 %) | 62,720 (+75 %) | 62,720 (+75 %) | 34,880 (-3 %) |
| `Mat4::inverse` | 102,610 | 249,290 (+143 %) | 195,130 (+90 %) | 194,130 (+89 %) | 106,390 (+4 %) |
| `Pose2::inv_mul` | 9,520 | 25,020 (+163 %) | 19,220 (+102 %) | 19,220 (+102 %) | 9,520 (+0 %) |
| `Pose3 * Pose3` | 18,680 | 36,740 (+97 %) | 29,940 (+60 %) | 29,940 (+60 %) | 17,760 (-5 %) |
| `Pose3::inv_mul` | 20,000 | 45,650 (+128 %) | 36,750 (+84 %) | 36,750 (+84 %) | 19,080 (-5 %) |
| `Pose3::transform_point` | 9,560 | 16,260 (+70 %) | 13,860 (+45 %) | 13,860 (+45 %) | 8,640 (-10 %) |
| `SdpMatrix3::from_rotated_diagonal` | 35,150 | 83,200 (+137 %) | 65,740 (+87 %) | 65,740 (+87 %) | 35,150 (+0 %) |
| `SymmetricEigen3::new` | 466,180 | 1,092,000 (+134 %) | 845,820 (+81 %) | 793,900 (+70 %) | 467,100 (+0 %) |
| **total of the 26 items** | 1,166,420 | 3,235,170 (+177 %) | 2,154,960 (+85 %) | 2,034,240 (+74 %) | 1,171,110 (+0.4 %) |

Steps follow the same pattern (`8`: +19 % to +87 %, `avoid`: +47 % to +1373 %; `Fixed / Fixed` is
the only item that gets cheaper, -7 %).

Why: every helper of `fixed` is already `#[inline(always)]` (49/49 in `internal/bounded`, 579/579
in `internal/acc`, 36/36 in `wide`; the only non-inlined functions are the public transcendentals
and the large glam bodies). What a lower threshold stops inlining is the **corelib** (integer and
bounded-int trait impls, `DivRem`, span access), which the library cannot annotate. The numeric
thresholds are not monotonic (24 is smaller than 8 and 16; 64 is equivalent to `default`).

## 5. Recommendations (no library change in this task)

1. **Keep the compiler default `inlining-strategy`** and say so in the consumer documentation
   (README "Using the library in a contract"): lowering it saves at most 27 % of class size for
   +74 % to +85 % gas on the library as a whole, and `avoid` costs +177 % (`exp` x12.6).
2. **Keep `#[inline(always)]` on the scalar operators, vector / quaternion / pose kernels and
   `mul_mat3` / `mul_mat4`.** Their per-site cost is 51 to 900 felts, and turning them into calls
   costs +15 % to +42 % gas (table 4.1). `Fixed * Fixed`, `sqrt` and `dot3` fit > 1,400 times in
   one class: bytecode is not a concern for them at all.
3. **Do not add non-inlined twins to the library.** A consumer that is bytecode-bound at a given
   call site can outline it with a local `#[inline(never)]` wrapper at exactly the cost of table
   4.1 (that is how it was measured), while the opposite (inlining a non-inlined library function)
   is impossible for the consumer. The library's current choice (inline everything <= ~1k felts)
   is therefore the one that leaves the consumer every option. Suggested addition to
   `docs/DESIGN.md` rule 4.3 (orchestrator decision): "Consumers that hit the class size limit
   outline hot call sites of inlined kernels themselves (`#[inline(never)]` wrapper); see
   `docs/audits/R1-bytecode-size.md`."
4. **Optional, lowest priority: the camera projection constructors** (`perspective*`,
   `orthographic`, `frustum`, 1,100 felts per site) are the only items whose call overhead is
   small in relative terms (+2,560 gas, +5.1 %, `gas/camera.snap`) and which are typically called
   once per contract (camera setup). They could lose `#[inline(always)]` if a real consumer shows
   several call sites; with one call site the change is neutral in bytecode and +5 % in gas, so
   today it is not worth it.
5. **Architecture of `rapier.cairo`**: plan for a multi-class layout from the start. The fixtures
   show that the math of one 3D step is small (14k felts), but `KitchenSink` already uses 61.9 % of
   a class with 22 entry points, and the transcendental / decomposition bodies (`powf` 9.3k, `ln`
   7.5k, `SymmetricEigen3` 5.7k, `slerp` 3.7k, `to_euler` 3.6k) are each paid once per class that
   uses them. Group the rarely used heavy bodies in a separate class.
6. **Tracking**: `gas/bytecode.size` is checked by `scripts/check.sh` and CI (release build, ~8 s
   from a cold target locally). Extend `packages/consumer` when `nalgebra.cairo` / `rapier.cairo`
   exist, and refresh `LIMITS` when Starknet changes them.
