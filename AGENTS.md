# AGENTS.md - canonical agent instructions

## Mission

Maintain `fixed`, the signed Q32.32 scalar shared by the Cairo ports of the Rust game-physics
stack (`glam-cairo`, `glamx-cairo`, `nalgebra-cairo`, `rapier-cairo`): deterministic,
gas-efficient, provable. Every consumer's results depend on its bits: a changed numeric result is
a breaking change for all of them.

Read `docs/DESIGN.md` before writing any code. It is short and every rule in it is measured.

The orchestrator of the split repositories lives in
[`glam-cairo`](https://github.com/bal7hazar/glam-cairo) (`docs/ORCHESTRATOR.md`,
`docs/HANDOFF.md`, `docs/briefs/`, the research reports and audits): tasks for this repository
are briefed and sequenced there.

## Repository map

| path | content |
|---|---|
| `packages/fixed` | signed Q32.32 scalar `Fixed { raw: i64 }`, fused kernels (`wide`), transcendentals (`trig`, `exp`), `internal` (generated `BoundedInt` plumbing) |
| `packages/benches` | unpublished: `tests/bench_<module>.cairo`, `src/harness.cairo` (`bb`, `sink`), `src/alt/` (losing variants) |
| `packages/consumer` | unpublished: the `Scalar` Starknet contract fixture measured by `scripts/bytecode_size.py` |
| `gas/<module>.snap`, `gas/bytecode.size` | committed gas/step snapshots (one file per bench module) and class sizes |
| `scripts/check.sh` | the full gate; `scripts/bench.py` the bench runner |
| `scripts/gen_bounded.py`, `gen_trig.py`, `gen_exp.py` | generators of `internal`, the trig / exp coefficients and their bit-exact Python mirrors |
| `scripts/panic_coverage.py`, `deviations.py`, `gas_tables.py`, `bytecode_size.py` | doc-template checks, README gas tables, class sizes |
| `tools/refgen` | golden-vector generator (specs + oracles of `fixed` and `wide`) |
| `docs/DESIGN.md`, `CHANGELOG.md` | decisions, changes |

## Commands

| task | command |
|---|---|
| Full gate (must be green before reporting done) | `scripts/check.sh` |
| Format | `scarb fmt --workspace` |
| Lint | `scarb lint --workspace --test --deny-warnings` |
| Test one module | `snforge test -p fixed test_trig` |
| Generate golden tests of one module (spec `tools/refgen/specs/<m>.toml` + oracles `tools/refgen/src/oracles/<m>.rs`, see `tools/refgen/README.md`) | `cargo run --manifest-path tools/refgen/Cargo.toml -- gen <module>` |
| Bench one module (net cost table) | `scripts/bench.py run bench_trig` |
| Update the snapshot of one module | `scripts/bench.py snapshot bench_trig` |
| Check all snapshots | `scripts/bench.py check` |
| README gas tables | `python3 scripts/gas_tables.py` |

Toolchain versions live in `.tool-versions` only (asdf).

## Principles

1. Correctness first, then gas. Never optimize untested code.
2. Measure, do not guess. Every performance claim cites a `gas/*.snap` delta. Cost intuition in
   Cairo is unreliable; the default ordering is: field/add/mul < div/mod ~ bitwise < table lookup
   < loop iteration < non-inlined panicking call < 128-bit mul < u256.
3. When the cheapest formulation is ambiguous, implement the variants (math / bitwise / loop /
   table), bench them all, ship the winner, keep the losers and their benches in `benches::alt`.
4. Determinism: bit-exact results are API. Changing a numeric result is a breaking change for
   every consuming repository.
5. Same names as Rust's `f32` / glam's `FloatExt`, always. Deviations are documented, never
   silent.
6. No stubbed success: an unimplemented function does not exist.
7. Small scope: one topic per task and per pull request. No drive-by refactors.

## Roles

| role | owns | does not own |
|---|---|---|
| Orchestrator (session in `glam-cairo`) | sequencing, briefs, review, merges, `Scarb.toml`, `lib.cairo` files, `scripts/**`, `.github/**`, `docs/DESIGN.md`, `CHANGELOG.md`, releases | large implementations |
| Implementer | one module: `src/<module>.cairo`, `tests/test_<module>.cairo`, `tests/golden_<module>.cairo` (generated), `tools/refgen/specs/<module>.toml`, `tools/refgen/src/oracles/<module>.rs`, `benches/tests/bench_<module>.cairo`, `benches/src/alt/<module>.cairo`, `gas/<module>.snap` | anything else |
| Optimizer | gas/step reduction of a merged module, same files as the implementer | behaviour or API changes |
| Reviewer | parity with the Rust float API, edge cases, conventions, gas deltas | implementation |

## Work protocol

1. Read the brief, `docs/DESIGN.md`, the Rust reference you mirror, and the neighbouring modules.
2. Plan in <= 30 lines: API list, test list, which kernels of `fixed::wide` you use, open
   questions. Escalate open questions instead of guessing.
3. Implement: source -> tests -> docs -> benches -> snapshot.
4. Run `scripts/check.sh` until green.
5. Commit on your branch (conventional commits, scope = module: `feat(trig): ...`), push, open a
   pull request with the template filled (gas table included). Do not merge.
6. Report using the handoff format.

## Definition of done

- [ ] Every public item exists with the reference name and the doc template (`Mirrors`,
      `#### Panics`, `#### Deviations`)
- [ ] Tests: golden vectors, edge cases (zero, one, negative, extreme magnitudes), seeded fuzz
      properties, `#[should_panic(expected: ...)]` with the exact message for every panic path
- [ ] A `X__base` / `X__op` bench with `bb`-wrapped inputs for every public function;
      `gas/<module>.snap` regenerated and committed
- [ ] `scripts/check.sh` green
- [ ] Deviations documented on the item; anything that needs a `docs/DESIGN.md` change is
      escalated, not applied
- [ ] No change outside the allowed files

## Handoff format

Summary (3 lines) / Files changed / Commands run and their result / Gas table of the headline
operations / Deviations / Open questions and follow-ups / PR URL.

## Escalation

When: the brief contradicts the Rust reference or `docs/DESIGN.md`; an API cannot be expressed in
Cairo; a shared file must change; a consumer needs a kernel that does not exist.
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
