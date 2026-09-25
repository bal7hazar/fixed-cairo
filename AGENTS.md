# AGENTS.md - canonical agent instructions

## Mission

Port [glam-rs](https://github.com/bitshifter/glam-rs) 0.33.8 to pure Cairo as a deterministic,
gas-efficient, provable math library: the base layer of a provable game physics engine.
`nalgebra-cairo` and `rapier-cairo` depend on the `fixed` and `glam` packages of this repository.

Read `docs/DESIGN.md` before writing any code. It is short and every rule in it is measured.

## Repository map

| path | content |
|---|---|
| `packages/fixed` | signed Q32.32 scalar `Fixed { raw: i64 }`, fused kernels (`wide`), transcendentals (`trig`) |
| `packages/glam` | the glam-rs port; one module per glam-rs type, same names |
| `packages/benches` | unpublished: `tests/bench_<module>.cairo`, `src/harness.cairo` (`bb`, `sink`), `src/alt/` (losing variants) |
| `gas/<module>.snap` | committed gas/step snapshots, one file per bench module |
| `scripts/check.sh` | the full gate; `scripts/bench.py` the bench runner |
| `docs/DESIGN.md`, `docs/PLAN.md`, `docs/PORTING_STATUS.md` | decisions, sequencing, progress |
| `docs/ORCHESTRATOR.md` | how the orchestrator session spawns and briefs sub-agents (CLIs, model choice, brief format) |
| `docs/HANDOFF.md` | where a new orchestrator session starts: reading order, machine setup, operating loop, what remains |
| `docs/briefs/` | every porter brief (`COMMON.md` + one file per task) |
| `docs/research/` | the five research reports and the benchmark prototype (`bench/`) they are based on |

## Commands

| task | command |
|---|---|
| Full gate (must be green before reporting done) | `scripts/check.sh` |
| Format | `scarb fmt --workspace` |
| Lint | `scarb lint --workspace --test --deny-warnings` |
| Test one module | `snforge test -p glam test_vec3` |
| Generate golden tests of one module (spec `tools/refgen/specs/<m>.toml` + oracles `tools/refgen/src/oracles/<m>.rs`, see `tools/refgen/README.md`) | `cargo run --manifest-path tools/refgen/Cargo.toml -- gen <module>` |
| Bench one module (net cost table) | `scripts/bench.py run bench_vec3` |
| Update the snapshot of one module | `scripts/bench.py snapshot bench_vec3` |
| Check all snapshots | `scripts/bench.py check` |

Toolchain versions live in `.tool-versions` only (asdf).

## Principles

1. Correctness first, then gas. Never optimize untested code.
2. Measure, do not guess. Every performance claim cites a `gas/*.snap` delta. Cost intuition in
   Cairo is unreliable; the default ordering is: field/add/mul < div/mod ~ bitwise < table lookup
   < loop iteration < non-inlined panicking call < 128-bit mul < u256.
3. When the cheapest formulation is ambiguous, implement the variants (math / bitwise / loop /
   table), bench them all, ship the winner, keep the losers and their benches in `benches::alt`.
4. Determinism: bit-exact results are API. Changing a numeric result is a breaking change.
5. Same names as glam-rs, always. Deviations are documented, never silent.
6. No stubbed success: an unported function does not exist.
7. Small scope: one module per task and per pull request. No drive-by refactors.

## Roles

| role | owns | does not own |
|---|---|---|
| Orchestrator | sequencing, briefs, review, merges, `Scarb.toml`, `lib.cairo` files, `scripts/**`, `.github/**`, `docs/DESIGN.md`, `docs/PLAN.md`, `docs/PORTING_STATUS.md`, `CHANGELOG.md`, releases | large implementations |
| Porter | one module: `src/<module>.cairo`, `tests/test_<module>.cairo`, `tests/golden_<module>.cairo` (generated), `tools/refgen/specs/<module>.toml`, `tools/refgen/src/oracles/<module>.rs`, `benches/tests/bench_<module>.cairo`, `benches/src/alt/<module>.cairo`, `gas/<module>.snap` | anything else |
| Optimizer | gas/step reduction of a merged module, same files as the porter | behaviour or API changes |
| Reviewer | parity with glam-rs, edge cases, conventions, gas deltas | implementation |

All stub files already exist and are already declared in the `lib.cairo` files: a porter never
needs to edit a shared file. If you believe you must, stop and escalate.

## Work protocol (porter)

1. Read the brief, `docs/DESIGN.md`, the glam-rs source you mirror, and the neighbouring modules.
2. Plan in <= 30 lines: API list, test list, which kernels of `fixed::wide` you use, open
   questions. Escalate open questions instead of guessing.
3. Implement: source -> tests -> docs -> benches -> snapshot.
4. Run `scripts/check.sh` until green.
5. Commit on your branch (conventional commits, scope = module: `feat(vec3): ...`), push, open a
   pull request with the template filled (gas table included). Do not merge.
6. Report using the handoff format.

## Definition of done

- [ ] Every public item of the brief exists with the glam-rs name and the doc template
      (`Mirrors`, `#### Panics`, `#### Deviations`)
- [ ] Tests: golden vectors (glam-rs as the oracle), edge cases (zero, one, negative, extreme
      magnitudes), seeded fuzz properties, `#[should_panic(expected: ...)]` with the exact message
      for every panic path
- [ ] A `X__base` / `X__op` bench with `bb`-wrapped inputs for every public function that does
      arithmetic; `gas/<module>.snap` regenerated and committed
- [ ] `scripts/check.sh` green
- [ ] Deviations from glam-rs documented on the item; anything that needs a `docs/DESIGN.md`
      change is escalated, not applied
- [ ] No change outside the allowed files

## Handoff format

Summary (3 lines) / Files changed / Commands run and their result / Gas table of the headline
operations / Deviations / Open questions and follow-ups / PR URL.

## Escalation

When: the brief contradicts glam-rs or `docs/DESIGN.md`; an API cannot be expressed in Cairo; a
shared file must change; the scalar API lacks a kernel you need (ask for it, do not emulate it with
chains of `Fixed * Fixed`).
Format: `## Escalation: <title>` / Blocker / Options / Recommendation.

## Cairo rules (hard) - summary of docs/DESIGN.md section 4

- `Copy` structs of named scalar fields, passed by value. No `Array` / `Span` / dict / loop in
  fixed-size math.
- Products through `fixed::wide` fused kernels: one rescale per output scalar.
- `#[inline(always)]` on scalar operators, constructors, accessors, kernel helpers; not on large
  bodies. No hot generic free functions (E2143 forbids forcing their inlining).
- No bitwise operators; `DivRem` by a constant power of two instead. Never `pow(2, n)` at runtime.
- Tables: `const [T; N]` + `.span()`. Dispatch: `match`. Never if-chains.
- Operands <= 64 bits; no `u128` multiplication, no `u256`, no felt -> int conversions in hot
  paths unless measured.
- Plain panicking operators (not `wrapping_*` / `checked_*` / `saturating_*`).
- One `DivRem::div_rem` instead of `/` plus `%`.
- Bench inputs through `bb`, results through `sink`: a bench that reports ~0 is constant-folded.

## Rationalizations to reject

- "Constant inputs are fine for this bench." They fold to the empty-test floor.
- "It is obviously cheaper, no need to measure."
- "I'll add the panic / edge tests later."
- "Exact equality failed, I loosened the tolerance." Explain the error bound in ULPs instead.
- "A small refactor of the neighbouring module while I'm here."
- "This shared file needs just one line." Escalate.
