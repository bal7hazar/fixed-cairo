# 02 - Architecture and Best Practices Benchmark

Benchmark of two reference repositories to define how `glam.cairo` (a pure-Cairo port of
`glam-rs`, base of a provable game physics engine) should be structured, tested, released
and driven by AI agents.

| Reference | Commit read | Used as reference for |
|---|---|---|
| `keep-starknet-strange/alexandria` | `6d2cfcc` (workspace `0.10.0`, Cairo `2.16.0`) | Workspace architecture, numeric Cairo idioms, CI, gas tracking, publishing |
| `keep-starknet-strange/starknet-agentic` | `c7e1c9e` | Repo hygiene, agent-driven workflow (AGENTS.md / CLAUDE.md / skills), CI hardening, Cairo optimization rules |

Everything below marked **(verified)** was executed locally with `scarb 2.19.4` +
`snforge 0.61.0` in a scratch workspace, not just read.

---

## 1. Alexandria

### 1.1 Workspace layout

```
alexandria/
├── .tool-versions            # scarb 2.16.0 / starknet-foundry 0.56.0
├── Scarb.toml                # workspace root (no root package)
├── Scarb.lock                # committed
├── gas_report.json           # committed gas baseline (1427 lines)
├── scripts/                  # generate_gas_report.sh, generate_doc.sh, update_registry.sh
├── docs/                     # CONTRIBUTING, SECURITY, CODE_OF_CONDUCT, book.toml, intro.md
├── .github/                  # CODEOWNERS, PR template, issue templates, labels, 6 workflows
└── packages/
    ├── math/  numeric/  linalg/  data_structures/  sorting/  searching/ ...
    │   ├── Scarb.toml
    │   ├── snfoundry.toml
    │   ├── README.md
    │   ├── src/lib.cairo + one file per algorithm
    │   └── tests/<module>_test.cairo
    ├── macros/               # Rust proc-macro crate ([cairo-plugin]), Cargo.toml + Scarb.toml
    └── macros_tests/         # dummy package only used to test macros
```

Root `Scarb.toml` (verbatim):

```toml
[workspace]
members = [
  "packages/data_structures",
  "packages/encoding",
  "packages/linalg",
  "packages/macros",
  "packages/macros_tests",
  "packages/math",
  "packages/merkle_tree",
  "packages/numeric",
  "packages/json",
  "packages/searching",
  "packages/sorting",
  "packages/storage",
  "packages/ascii",
  "packages/bytes",
  "packages/utils",
  "packages/evm",
  "packages/btc",
]
name = "alexandria"
version = "0.8.0"

description = "Community maintained Cairo and Starknet libraries"
homepage = "https://github.com/keep-starknet-strange/alexandria/"
cairo-version = "2.16.0"

[workspace.dependencies]
starknet = "2.16.0"
cairo_test = "2.16.0"
snforge_std = "0.56.0"

[workspace.tool.fmt]
sort-module-level-items = true

[workspace.package]
version = "0.10.0"

[profile.coverage]
sierra = true

[scripts]
all = "scarb build && snforge test"
```

Per-package manifest (`packages/linalg/Scarb.toml`, verbatim):

```toml
[package]
name = "alexandria_linalg"
version.workspace = true
description = "A set of linear algebra libraries and algorithms"
homepage = "https://github.com/keep-starknet-strange/alexandria/tree/main/packages/linalg"
edition = "2023_11"
cairo-version = "2.16.0"

[tool]
fmt.workspace = true

[dependencies]
alexandria_math = { path = "../math", version ="0.10.0" }

[dev-dependencies]
snforge_std.workspace = true
```

Observations:

- **No root package**: the root is a pure virtual workspace; every deliverable lives in
  `packages/<short_name>` and is named `alexandria_<short_name>`. The prefix makes registry
  names unambiguous and lets the gas script take short names (`-p alexandria_$1`).
- **Only `version` is inherited** through `[workspace.package]`. `edition` (`2023_11`
  everywhere except `macros` on `2024_07`) and `cairo-version` are repeated in each package,
  and the root `[workspace]` table carries stale keys (`name`, `version = "0.8.0"`,
  `cairo-version`) that are not valid workspace keys. **Do not copy this**: inherit
  `version`, `edition`, `cairo-version`, `license`, `repository` from `[workspace.package]`
  (verified to work on 2.19.4).
- **Intra-workspace deps are `path` + `version`** (`{ path = "../math", version = "0.10.0" }`).
  The `version` is required for `scarb publish` (path is stripped at packaging time), but it
  is duplicated in every dependent manifest and must be bumped by hand. Better: declare them
  once in `[workspace.dependencies]` and use `dep.workspace = true` (verified).
- **Shared tool config** via `[workspace.tool.fmt]` + `[tool] fmt.workspace = true`.
- **`Scarb.lock` is committed**, `.tool-versions` pins scarb and starknet-foundry for asdf.
- `snfoundry.toml` per package only sets `sierra = true` / `casm = true` under
  `[snforge.default]` (legacy; not needed for a pure library).
- A dependency-free package (`math`, `data_structures`) has **no `starknet` dependency** at
  all: pure Cairo libs compile as `lib` targets. Only `storage`/`evm`-style packages pull
  `starknet`. `glam.cairo` should likewise never depend on `starknet`.

### 1.2 Tool versions

| Tool | Alexandria | Notes |
|---|---|---|
| scarb / cairo | 2.16.0 | from `.tool-versions`; CI `setup-scarb` reads that file |
| starknet-foundry | 0.56.0 | duplicated: `.tool-versions` **and** hardcoded in `test.yml` (drift risk) |
| test runner | `snforge test` | `cairo_test` only used by the `macros` package |
| edition | `2023_11` (libs), `2024_07` (macros) | new code should be `2024_07` |

### 1.3 Test layout

- **All tests are integration tests in `packages/<pkg>/tests/`**, one file per source
  module: `tests/i257_test.cairo`, `tests/dot_test.cairo`, ... There is no `tests/lib.cairo`,
  so snforge compiles each file as a module of `<pkg>_integrationtest`
  (test IDs look like `alexandria_math_integrationtest::i257_test::i257_test_add`).
- Inline `#[cfg(test)]` is essentially unused (3 occurrences in the whole repo). Consequence:
  tests can only reach the **public API**, which is a healthy constraint for a library, but
  it forces internal helpers to be `pub` to be tested.
- Every package still has an orphan `src/tests.cairo` (a `mod xxx_test;` list) that is
  **not referenced from `lib.cairo`**: dead leftover of a previous `src/tests/` layout.
  Lesson: when a layout changes, delete the old one; agents will otherwise keep maintaining it.
- Naming is inconsistent (`i257_test_add`, `dot_product_test`, `test_stress_test`,
  file names `*_test.cairo`, `*_tests.cairo`, `test_*.cairo`). Pick one convention and lint it.
- Panics are asserted with the exact message:
  `#[should_panic(expected: ('Arrays must have the same len',))]`.
- No fuzz tests (`#[fuzzer]`) and no `#[available_gas]` anywhere.

### 1.4 Naming, trait and impl patterns

Patterns seen in `math`, `numeric`, `linalg`, `data_structures`:

1. **Free generic functions with anonymous impl bounds** for algorithms:
   ```cairo
   pub fn dot<T, +Mul<T>, +AddAssign<T, T>, +Zero<T>, +Copy<T>, +Drop<T>>(
       mut xs: Span<T>, mut ys: Span<T>,
   ) -> T
   ```
   Numeric literals in generic code are produced with `+Into<u8, T>` (`2_u8.into()`), zero
   with `core::num::traits::Zero`.
2. **`#[generate_trait]` for inherent-style methods** on a concrete type:
   `pub impl I257Impl of I257Trait { fn new(...) ... }`, `pub impl DecimalImpl of DecimalTrait`.
   Naming: type `Foo` -> trait `FooTrait` -> impl `FooImpl`.
3. **Explicit trait + one impl per primitive** when behaviour differs per width:
   `pub trait BitShift<T>` with `U8BitShift`, `U16BitShift`, ... `U256BitShift`;
   `pub trait OptWrapping<T>` with `U128OptWrappingImpl`, etc. Impl naming: `<Type><Trait>`
   or `<Type><Trait>Impl`.
4. **Blanket generic impl** when one body fits all:
   `pub impl WrappingMathImpl<T, +WrappingAdd<T>, +WrappingSub<T>, +WrappingMul<T>> of WrappingMath<T>`.
5. **Two-parameter container traits**: `pub trait StackTrait<S, T>` / `VecTrait<V, T>` with
   impls `Felt252StackImpl<T, ...> of StackTrait<Felt252Stack<T>, T>` and
   `NullableStackImpl<...>` - one API, several backing stores. Relevant for glam if one API
   (`Vec3Trait<V, S>`) must serve several scalar types.
6. **Operator overloading through core traits**, one impl per operator on the concrete type
   (`i257.cairo`): `Add`, `Sub`, `Mul`, `Div`, `Rem`, `Neg`, `PartialEq`, `PartialOrd`,
   `core::ops::{AddAssign, SubAssign, MulAssign, DivAssign, RemAssign}`,
   `core::num::traits::Zero`, `Default`, `Into<u256, i257>`, `core::fmt::Display`.
   The `*Assign` impls are always `#[inline(always)]` one-liners delegating to the binary op:
   ```cairo
   impl i257AddEq of AddAssign<i257, i257> {
       #[inline(always)]
       fn add_assign(ref self: i257, rhs: i257) { self = Add::add(self, rhs); }
   }
   ```
7. **Derive macros for component-wise operators** (`packages/macros`, a Rust `cairo-plugin`):
   `#[derive(Add, Sub, Mul, Div, AddAssign, SubAssign, MulAssign, DivAssign, Zero)]` generate
   member-wise impls on any struct, including generic ones. This is exactly the shape of
   `Vec2/Vec3/Vec4` operators. Trade-off: a proc-macro dependency means consumers need either
   a prebuilt plugin from the registry or a Rust toolchain; for a base library with ~10 types
   hand-written impls are cheaper than that supply-chain cost. Also `macro pow_inline` shows
   the declarative inline-macro feature (`experimental-features = ["user_defined_inline_macros"]`).
8. **`#[derive]` usage**: value types use `#[derive(Copy, Drop, Serde, PartialEq)]` (+ `Debug`,
   `Hash`, `Default` when useful); containers use `Drop`/`Destruct`. For glam: every math type
   should be `Copy, Drop, Serde, PartialEq, Debug, Default` (verified to compile on 2.19.4).
9. **`#[inline]` usage**: 189 x `#[inline(always)]`, 52 x `#[inline]`. Applied to thin
   wrappers, conversions, `*Assign`, modular helpers (`add_mod`, `mult_mod`), and the whole
   `opt_math.cairo` file. Non-trivial bodies (`i257` `Add`, `Mul`, `Div`) are *not* inlined.
10. **Constants**: `pub(crate) const WAD: u256 = 1_000_000_000_000_000_000;`, digit
    separators, SCREAMING_SNAKE_CASE, and **const fixed-size arrays as lookup tables**:
    `const sin_table: [u64; 10] = [...]` read through `*sin_table.span()[i]`;
    `pow2()` holds a `[u128; 128]` table rather than computing powers.
11. **Visibility**: `pub` on everything exported, `pub(crate)` for shared internals (9 uses),
    struct fields private by default with accessor methods (`i257.abs()`), `pub` fields for
    plain data (`Decimal`).
12. **Re-exports** in `lib.cairo`: `pub use core::num::traits::{Bounded, WideMul, ...};`.

### 1.5 Numeric idioms and efficiency tricks worth reusing

| Trick | Where | Relevance to glam.cairo |
|---|---|---|
| `WideMul::wide_mul` then take `.low` / mask, instead of checked mul + `%` | `opt_math.cairo`, `lib.cairo` (`BitShift`) | Fixed-point `mul` = `wide_mul` + single `DivRem` by `ONE` |
| `u512_safe_div_rem_by_u256(wide_mul(a, b), nz)` for mul-mod without overflow | `mod_arithmetics.cairo` | Same shape as high-precision fixed-point `mul_div` |
| `NonZero<T>` parameters for divisors (`mod_non_zero: NonZero<u256>`) | `mod_arithmetics.cairo` | Make scale constants `NonZero` consts: no runtime zero check |
| `DivRem::div_rem` once instead of `/` + `%` | `lib.cairo` `BitRotate` | Rounding, floor/fract, splitting int/frac parts |
| `overflowing_*` / `wrapping_*` from `core::num::traits` rather than hand-rolled | `u512_arithmetics.cairo` | Saturating/wrapping variants of glam |
| Lookup tables as const arrays | `const_pow.cairo`, `trigonometry.cairo` | `sin/cos/atan` tables, powers of two for shifts |
| Newton-Raphson with caller-provided iteration count | `fast_root.cairo` | `sqrt`/`rsqrt` with bounded, deterministic cost |
| Round-half-up: `(a * b + HALF) / ONE`, `(a * ONE + b / 2) / b` | `wad_ray_math.cairo` | Decide **one** rounding mode for the scalar and document it |
| `span.pop_front()` / `for x in span` loops instead of indexing | `dot.cairo`, `norm.cairo` | Any slice-based API (`dot` over spans, batch transforms) |
| Short-string (`felt252`) panic messages with `assert(cond, 'msg')` in hot paths, `assert!` with `ByteArray` elsewhere | everywhere | Short strings are much cheaper than formatted `ByteArray` panics |

Counter-examples (do **not** copy):

- **Sign-magnitude structs** (`i257 { abs, is_negative }`, `Decimal { int_part, frac_part,
  is_negative }`): every op branches on sign and re-asserts "no negative zero"
  (`i257_assert_no_negative_zero` is called 2x per `add`/`mul`/`eq`). `Decimal::add` rebuilds
  `int * SCALE + frac` on every call, `mul` goes through `u256`. This is the most expensive
  possible representation for a physics scalar; a single-limb representation is preferable
  (see the scalar research document).
- `i257_div` rounds by multiplying by 10 and inspecting the last digit; `i257_rem` is defined
  as `lhs - rhs * (lhs / rhs)` on top of that rounded division, so `rem` can be negative or
  inconsistent with `div_rem` expectations. Rounding semantics must be specified and
  property-tested, not improvised.
- `trigonometry.cairo` `fast_cos`: for `x < 0` it sets `a = -x` and loses the `+90 deg`
  offset (`cos(-x)` is computed as `sin(x)`). A table-driven trig needs symmetry property
  tests (`cos(-x) == cos(x)`, `sin(-x) == -sin(x)`, `sin^2 + cos^2 ~= 1`).
- Generic recursion for `pow` with `+Div +Rem +Into<u8,T>` bounds: elegant but each generic
  instantiation is monomorphized and each step pays a `%` and a `/`.
- Duplicate implementations across packages (`bit_array`/`byte_reader` exist in both
  `bytes` and `data_structures`): one owner per concept.

### 1.6 Documentation conventions

- `//!` crate/module header in every `lib.cairo` (`//! # Alexandria Math` + summary). Note
  that in several files the `//!` block sits *below* the `use` lines (an artefact of
  `sort-module-level-items` with older formatters). **(verified)** `scarb fmt` 2.19.4 keeps
  `//!` headers on top.
- `///` on every public item with a fixed template:
  ```cairo
  /// Compute the dot product for 2 given arrays.
  /// #### Arguments
  /// * `xs` - The first sequence of len L.
  /// #### Returns
  /// * `sum` - The dot product.
  /// #### Panics
  /// * If ...
  ```
  plus time complexity in the summary line when relevant (`/// O(log n) time complexity.`).
- One `README.md` per package listing each module with a link to its source and a paragraph
  of explanation; root README lists packages, the compatible Cairo version and the
  `scarb add alexandria_math@0.10.0` lines.
- API docs are generated by `scripts/generate_doc.sh`: `scarb doc --workspace --exclude ...
  --remote-base-url <repo>` then mdBook (`docs/book.toml`, custom `docs/intro.md`), deployed
  to GitHub Pages by a manual (`workflow_dispatch`) `mdbook.yml`.

### 1.7 Formatting and linting

- Formatting: only `[workspace.tool.fmt] sort-module-level-items = true`; CI runs
  `scarb fmt --check`.
- **Linting: none.** No `scarb lint` / cairo-lint step or config anywhere. This is a gap, not
  a pattern to follow. **(verified)** `scarb lint --workspace --test --deny-warnings` works
  on 2.19.4 and is cheap to add.

### 1.8 CI workflows

| Workflow | Trigger | Jobs |
|---|---|---|
| `test.yml` | `push`, `pull_request` | `build` (`scarb build`) -> `test` (`snforge test`) and `check-format` (`scarb fmt --check`) -> `gas-report` (`./scripts/generate_gas_report.sh`) |
| `macros.yml` | paths `packages/macros/**` | `cargo build --release`, `cargo fmt --check`, `cargo clippy` with `RUSTFLAGS=-Dwarnings`, `scarb fmt --check` |
| `mdbook.yml` | manual | `scarb doc` + mdBook -> GitHub Pages |
| `labels.yml`, `lock.yml`, `stale.yml` | housekeeping | label sync, lock closed threads, stale bot |

Details: `actions/checkout@v3`, `software-mansion/setup-scarb@v1.3.2` (version taken from
`.tool-versions`, built-in cache), `foundry-rs/setup-snfoundry@v3` with
`starknet-foundry-version: '0.56.0'`. No matrix, no explicit cache step, no `permissions:`
block, actions pinned by mutable tag, jobs chained with `needs:` (each job re-installs the
toolchain and rebuilds from scratch, so the chain mostly adds latency).

### 1.9 Gas tracking

`scripts/generate_gas_report.sh` greps `snforge test` output for
`[PASS] <name> (l1_gas: ~A, l1_data_gas: ~B, l2_gas: ~C)`, writes `gas_report.json`
(test -> l2_gas, sorted by cost), compares against the committed file and writes
`gas_report_diff.json` (git-ignored). The idea is right; the implementation has problems we
should not inherit:

- It **always exits 0**, so CI never fails or even warns on a regression, and the refreshed
  report is not committed back or uploaded - the CI job is informational noise.
- The generated `gas_report.json` has a **trailing comma and is not valid JSON**
  (confirmed with `json.load`); it is parsed back with bash string slicing.
- `sed -i ''` is macOS-only; fuzz tests (different output shape) are silently ignored.
- Many entries sit at `13840` gas: that is the *empty test baseline*. **(verified on
  2.19.4 / 0.61.0)** an empty test costs `13620` sierra gas (58 steps), and a test whose
  inputs are compile-time constants folds down to that baseline, i.e. measures nothing.
  Benchmarks must use inputs the compiler cannot fold (loop-varying values, fuzz args) and
  should subtract/know the baseline.

### 1.10 Release, publishing, contribution conventions

- Registry: packages are published to **scarbs.xyz** with `scripts/update_registry.sh`, a
  manual loop of `scarb publish --package <name>` in dependency order (no CI job, no tag
  trigger). All packages share one version (`[workspace.package] version`), bumped together
  with the Cairo version ("0.10.0 compatible with Cairo 2.16.0" in the README).
- **No `CHANGELOG.md`**, no git tags in the clone; history is squash-merged PR titles
  (`Documentation update (#433)`).
- `CONTRIBUTING.md` asks for an issue first, `feat/<name>` branches and conventional commit
  messages (`feat: add amazing_feature`); the "dev environment setup" section is still a TODO.
- PR template: type-of-change checkboxes, current/new behaviour, breaking-change yes/no.
- `CODEOWNERS`: `* @LucasLvy`. Issue templates: bug / feature / codebase improvement.
  `.all-contributorsrc` for the contributors table.

### 1.11 Alexandria scorecard

| Adopt | Avoid / improve |
|---|---|
| Virtual workspace, `packages/*`, prefixed package names | Stale root keys, per-package repetition of edition/cairo-version |
| `.tool-versions` + committed `Scarb.lock` | Tool version duplicated in CI yaml |
| One test file per source module, exact panic messages | Orphan `src/tests.cairo`, inconsistent test names, no fuzzing |
| Core-trait operator overloading, `#[generate_trait]`, `FooTrait`/`FooImpl` naming | Sign-magnitude numeric structs, improvised rounding |
| `///` template (Arguments / Returns / Panics), README per package, `scarb doc` + mdBook | No lint step |
| Committed gas baseline diffed in CI | Non-failing, invalid-JSON, macOS-only gas script |
| scarbs.xyz publishing in dependency order | Manual publishing, no changelog, no tags |

---

## 2. starknet-agentic

A pnpm + Cairo monorepo (contracts, TS packages, installable agent skills). Its Cairo code
is contract-oriented, but its **repo hygiene and agent workflow** are the most mature public
example in the ecosystem.

### 2.1 Instruction files: one canonical source

- **`AGENTS.md` is the single canonical, tool-agnostic instruction file** ("Keep behavior and
  workflow directives here"). It states a compatibility policy: any tool-specific file
  (`CLAUDE.md`) "must be a thin adapter or reference layer, not a conflicting instruction
  source". The changelog records the clean-up: "Canonicalized agent instructions to root
  `AGENTS.md` and removed legacy duplicate root instruction files".
- **`CLAUDE.md` = repository context, not behaviour.** XML-tagged sections:
  `<identity>`, `<stack>` (versions table), `<structure>` (annotated tree with status),
  `<commands>` (task / command / working directory table), `<conventions>`, `<workflows>`
  (step lists for "adding a new X"), `<boundaries>`, `<references>` (path + "use when"),
  `<implementation_status>`, `<troubleshooting>` (problem / solution table).
- Weakness observed: `CLAUDE.md` hard-codes counts and statuses ("110 tests", "9 tools",
  line counts, "Cairo 2.14.0") that drift; `SKILL.md` files reference
  `../references/skill-handoff.md`, which does not exist in the tree. **Anything written in
  an instruction file must be either stable or machine-checked.**

`AGENTS.md` sections worth reusing almost as-is:

| Section | Content |
|---|---|
| Mission / Scope | 3 lines: what the repo builds, which directories matter |
| Core operating principles | single source of truth; small testable changes; security-first on high-risk paths; reproducibility (pinned refs, deterministic scripts); explicit handoffs |
| Roles and boundaries | table `Role / Owns / Does not own`: Coordinator (scope, plan, sequencing, `STATUS.md` accuracy - *not* large implementation), Executors per area, Reviewer (correctness, security regressions, release gates - *not* initial implementation) |
| Task lifecycle | `todo -> inprogress -> inreview -> done`, `blocked` reachable from any state |
| Work protocol | 1) Investigation (coordinator): touched files/interfaces, risk class, **acceptance checks defined before implementation**, parallelizable vs serialized; 2) Execution: only approved scope, focused and reversible, surface blockers immediately; 3) Review: run checks, verify interface compatibility, confirm acceptance criteria |
| Parallelization rules | explicit "safe to parallelize" vs "must serialize" lists (shared interface changes, `scripts/**`, CI workflows, same directory) + 4-step conflict resolution (detect overlap early, pause dependents, land interface change first with tests, rebase and re-verify) |
| Required validation by change type | exact commands per kind of change (contracts: `scarb build` + `snforge test` in impacted packages) |
| Escalation rules + format | when to escalate (public interface change, security-sensitive behaviour, credentials needed, contradictory requirements) and a fixed template: `Blocker / Options / Recommendation` |
| Canonical references | paths to specs the agent must consult |

`CLAUDE.md` `<boundaries>` is a three-tier permission model worth copying:
**DO NOT modify** (`.env*`, `Scarb.lock`, submodules) / **Require human review** (interface
changes, dependency bumps in `Scarb.toml`, security-sensitive code) / **Safe for agents**
(reading anything, editing source/tests/docs, running builds and tests).

### 2.2 Skills structure

```
skills/<skill-name>/
├── SKILL.md            # YAML frontmatter + orchestration
├── README.md
├── workflows/default.md   # phase-by-phase checklist
├── references/            # long-form rules, loaded on demand
│   ├── legacy-full.md
│   └── anti-pattern-pairs.md
├── scripts/               # deterministic CLIs (profile.py, bounded_int_calc.py)
└── agents/                # sub-agent prompts (cairo-auditor: vector-scan.md, adversarial.md)
```

- Root `SKILL.md` is a **router**: intent -> smallest focused skill, "load one child skill
  first, then add a second only when the task crosses a real boundary", plus a recommended
  flow `authoring -> testing -> optimization -> auditor`.
- Frontmatter: `name`, `description` (with trigger words), `license`, `metadata` (author,
  version, upstream commit + sync date for vendored content), `keywords`, `allowed-tools`,
  `user-invocable`.
- Body template shared by all skills: *When to use / When NOT to use / Quick start /
  **Rationalizations to reject** / Mode selection / Orchestration in turns
  (Understand|Baseline -> **Plan, max 30 lines, wait for confirmation** -> Implement ->
  Verify) / Error codes and recovery table / **Security-critical (non-negotiable) rules** /
  References / Workflow*.
- **Progressive disclosure**: `SKILL.md` stays < 200 lines; a table maps "request involves X"
  to the reference file to load.
- **Deterministic tooling over model arithmetic**: "Always use
  `bounded_int_calc.py` to compute bounds - never calculate manually"; "always use the
  `profile.py` CLI, do NOT run snforge/cairo-profiler/pprof manually" with documented exit
  codes and the action to take for each.
- Distribution: canonical content in `skills/`, `.agents/skills/*` are symlinks for Codex,
  `.claude-plugin/{plugin,marketplace}.json` for Claude Code, `skills/manifest.json`
  generated and checked by `scripts/skills_manifest.py --check`. Validation scripts
  (`scripts/quality/validate_skills.py` ...) run in CI.
- **Evals**: `evals/cases/*.jsonl` + scorecards; rule "when rules in a skill change, update
  at least one eval case"; optimization claims are encoded as deterministic regex rules with
  paired good/bad fixtures.

### 2.3 Cairo optimization rules (from `skills/cairo-optimization`)

Directly applicable to a math library (source: feltroidprime/cairo-skills, vendored):

| # | Rule |
|---|---|
| 1 | `DivRem::div_rem(x, m)` - never separate `/` and `%` |
| 2 | `while i != n` instead of `while i < n` for exact-trip loops only |
| 3 | Never compute `2^k` with `pow()` - lookup table |
| 4 | Iterate with `pop_front` / `for` / `multi_pop_front::<N>()`, never `*data.at(i)` |
| 5 | Cache `.len()` outside loop conditions |
| 6 | `span.slice()` instead of manual copy loops |
| 7 | Parity/halving with `DivRem::div_rem(x, 2)` - bitwise ops are *more* expensive in Cairo |
| 8 | Smallest integer type that fits the range (`u128` over `u256`) |
| 10 | **`BoundedInt<MIN, MAX>`** for limb splitting/assembly and modular arithmetic: bounds are tracked at compile time, removing runtime overflow checks (reported 28,340 -> 13,840 gas for a 4 x u32 -> u128 assembly) |
| 12 | `u128s_from_felt252` + `upcast` (2 steps) instead of `downcast`/`try_into` (4 steps); **never `try_into().unwrap()` in hot/unrolled code** (panic path drops all live vars -> quadratic Sierra bloat) |

BoundedInt architecture rule, important for the scalar design: *"Use BoundedInt types as
function inputs AND outputs"* - `downcast` at each call adds a range check that outweighs the
savings; `upcast` to a superset range is free; downcast only at system boundaries
(deserialization). Other pitfalls listed: subtraction bounds are `[a_lo - b_hi, a_hi - b_lo]`;
`bounded_int_div_rem` does not accept negative lower bounds (use the SHIFT pattern: add a
multiple of the modulus first); bounds are capped at 2^128; always annotate intermediate
types. Dependency: `corelib_imports = "0.1.2"`.

Process rules: optimize only after tests pass and behaviour is locked; **one optimization
class per commit**; re-profile after every change; record before/after step deltas in the PR;
"reject changes that reduce readability without measurable gains". Profiling pipeline:
`snforge test --save-trace-data` -> `cairo-profiler` -> `pprof`, metrics `steps`, `rc`
(range checks), `sierra-gas`, `l2-gas`.

### 2.4 Testing approach for Cairo

From `skills/cairo-testing` and the contract packages:

- Layout: `src/` + `tests/` **with `tests/lib.cairo`** declaring `mod test_xxx;` (a single
  integration-test crate = one compilation unit, faster than one crate per file) and files
  named `tests/test_<area>.cairo`. `edition = "2024_07"`, dev-deps `snforge_std` +
  `assert_macros`, `[tool.scarb] allow-prebuilt-plugins = ["snforge_std"]` (avoids compiling
  the snforge plugin with cargo), `[scripts] test = "snforge test"`.
- Test names: `test_<function>_<scenario>`.
- `#[should_panic(expected: '...')]` always with the message, never bare.
- Fuzz tests with a **fixed seed**: `#[fuzzer(runs: 256, seed: 12345)]`; constrain inputs
  with bounded types rather than discarding invalid inputs.
- A plan-first protocol: list functions, positive/negative paths, edge cases (zero, max,
  duplicates), fuzz targets; then implement; then a coverage walk-through.
- Regression rule: every accepted finding = patch + regression test.

### 2.5 CI setup and security practices

`ci.yml` (one of 16 workflows) shows the patterns to copy:

- `permissions: contents: read` at workflow level; extra permissions per job only.
- **Every action pinned to a full commit SHA with the version in a comment**, kept fresh by
  Dependabot (`package-ecosystem: github-actions`, weekly):
  `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`,
  `software-mansion/setup-scarb@2a96b748888e3329ee44ac9ac073d930e692b3cd # v1.6.2`,
  `foundry-rs/setup-snfoundry@16e23ddd0e2845f38727c92f4b913a7b728cda9e # v6.0.0`.
- `detect-changes` job with `dorny/paths-filter` so each Cairo package is only built/tested
  when its path (or the CI file itself) changes.
- A final **`all-checks` aggregator job** (`if: always()`, `needs: [...]`, fails on any
  `failure`/`cancelled`) used as the single required status check for branch protection.
- `secret-scan` job (gitleaks, working tree, merge-blocking) + optional local pre-commit hook
  installed by `scripts/setup_githooks.sh` (`.githooks/pre-commit`).
- Also present: CodeQL, OpenSSF Scorecard, dependency-review, Dependabot auto-merge.
- AI reviewers are configured *in-repo* with path-specific instructions:
  `.coderabbit.yaml` (`path_instructions`, `request_changes_workflow: true`),
  `.greptile/rules.md`, `.pr_agent.toml`. Notable rules: "Workflows must pin action versions
  to full SHA", "Flag any `unwrap()` equivalent or panic-path in production code",
  "Prefer correctness and production safety over style".

### 2.6 Contribution, versioning, release

- `CONTRIBUTING.md`: "Contributions should be small, reviewable, and come with an acceptance
  test". PR checklist: linked issue or rationale; **includes acceptance test**; build passes;
  tests pass (or scoped target documented); **no unrelated refactors**. Conventional commits
  (`feat`, `fix`, `docs`, `chore`, `test`, `refactor`, `ci`). "Keep PRs small (one logical
  change)".
- Security guardrail worth generalizing: *"Do not ship stubbed success"* - unimplemented
  behaviour must panic explicitly, never silently return a default. For glam: an unported
  function must not exist, or must `panic!`, never return zero.
- `VERSIONING.md`: SemVer with an explicit **pre-1.0 policy** (PATCH = fixes, internal
  refactors, docs/CI; MINOR = any externally visible behaviour change or breaking change),
  1.0 readiness criteria, and a 6-step release process (update `CHANGELOG.md` `Unreleased`
  -> choose version -> move notes under dated heading -> annotated tag `v0.y.z` -> push tag
  -> GitHub Release from changelog).
- `CHANGELOG.md` in Keep a Changelog format, entries reference PR numbers.
- `CODEOWNERS` per area; `SECURITY.md`; `llms.txt` at the root as an LLM-oriented index.

---

## 3. Recommendation for glam.cairo

### 3.1 Workspace vs single package

**Use a virtual workspace from day one**, even with few packages:

- Sibling repos (`nalgebra.cairo`, `rapier.cairo`) need **two** artefacts: the math types and
  the fixed-point scalar. The scalar must be a standalone package so `nalgebra.cairo` can
  depend on it without pulling `glam`.
- A git dependency on a workspace repo resolves a member **by package name**, so siblings can
  consume both packages from one repo and one tag:
  ```toml
  # nalgebra.cairo/Scarb.toml
  [workspace.dependencies]
  glam        = { git = "https://github.com/bal7hazar/glam.cairo", tag = "v0.1.0" }
  glam_scalar = { git = "https://github.com/bal7hazar/glam.cairo", tag = "v0.1.0" }
  ```
  then `version = "0.1.0"` from scarbs.xyz once published. Always pin `tag`/`rev`, never a
  branch: two repos resolving different commits of the scalar would produce incompatible
  types.
- Give the scalar a **repo-independent package name** (placeholder here: `glam_scalar`; pick
  the final name before the first publish). If it later moves to its own repository, registry
  consumers are unaffected.
- Keep benchmarks out of the published library in a non-published member
  (`packages/benches` with `publish = false` in its `[package]` table, accepted by scarb
  2.19.4 - verified) so bench-only helpers never leak into the API.

```
glam.cairo/
├── .tool-versions
├── Scarb.toml                 # virtual workspace
├── Scarb.lock                 # committed
├── AGENTS.md                  # canonical agent instructions
├── CLAUDE.md                  # thin adapter: imports AGENTS.md + Claude-specific notes
├── CHANGELOG.md  VERSIONING.md  CONTRIBUTING.md  LICENSE  README.md
├── gas_snapshot.json          # committed, generated by scripts/gas_snapshot.py
├── scripts/
│   ├── gas_snapshot.py
│   └── check.sh               # fmt + lint + build + test + snapshot check (the DoD command)
├── docs/
│   ├── research/              # this document and siblings
│   ├── specs/                 # one task spec per porting unit (see 3.6)
│   ├── PORTING_STATUS.md      # generated/checked table: glam-rs item -> status
│   └── DESIGN.md              # scalar format, rounding, overflow policy, deviations from glam-rs
├── .claude/
│   ├── agents/                # sub-agent definitions (porter, reviewer, optimizer)
│   └── skills/                # port-module, gas-bench (SKILL.md + workflows/ + references/)
├── .github/
│   ├── workflows/ci.yml  release.yml
│   ├── dependabot.yml  CODEOWNERS  PULL_REQUEST_TEMPLATE.md
└── packages/
    ├── scalar/                # fixed-point scalar (name TBD), zero dependencies
    │   ├── Scarb.toml  README.md
    │   ├── src/lib.cairo ...
    │   └── tests/lib.cairo + test_*.cairo
    ├── glam/                  # Vec2/3/4, Mat2/3/4, Quat, Affine - mirrors glam-rs modules
    │   ├── Scarb.toml  README.md
    │   ├── src/lib.cairo, vec2.cairo, vec3.cairo, ..., mat4.cairo, quat.cairo
    │   └── tests/lib.cairo + test_vec2.cairo ...
    └── benches/               # unpublished; bench_*.cairo feeding gas_snapshot.json
```

Mirror glam-rs file/module names one-to-one (`vec3.cairo` <-> `vec3.rs`) so that a sub-agent
task is "port `src/f32/vec3.rs` to `packages/glam/src/vec3.cairo`" with no mapping ambiguity.

### 3.2 Scarb.toml templates (verified on scarb 2.19.4 / snforge 0.61.0)

`.tool-versions`:

```
scarb 2.19.4
starknet-foundry 0.61.0
```

Root `Scarb.toml`:

```toml
[workspace]
members = ["packages/*"]

[workspace.package]
version = "0.1.0"
edition = "2024_07"
cairo-version = "2.19.4"
license = "MIT"
repository = "https://github.com/bal7hazar/glam.cairo"

[workspace.dependencies]
glam = { path = "packages/glam", version = "0.1.0" }          # used by packages/benches
glam_scalar = { path = "packages/scalar", version = "0.1.0" }
snforge_std = "0.61.0"
assert_macros = "2.19.4"

[workspace.tool.fmt]
sort-module-level-items = true
max-line-length = 100

[workspace.tool.scarb]
allow-prebuilt-plugins = ["snforge_std"]
```

`packages/glam/Scarb.toml`:

```toml
[package]
name = "glam"
description = "Port of glam-rs: fixed-point vector, matrix and quaternion math for provable games"
version.workspace = true
edition.workspace = true
cairo-version.workspace = true
license.workspace = true
repository.workspace = true
readme = "README.md"

[dependencies]
glam_scalar.workspace = true

[dev-dependencies]
snforge_std.workspace = true
assert_macros.workspace = true

[tool]
fmt.workspace = true
scarb.workspace = true

[scripts]
test = "snforge test"
```

Verified: `scarb fmt --check --workspace`, `scarb build --workspace`,
`scarb doc --workspace --disable-remote-linking`,
`scarb lint --workspace --test --deny-warnings`,
`snforge test --workspace` (unit tests in `src/`, integration tests in `tests/`, a seeded
`#[fuzzer]` test), `scarb package -p glam` (only warning: missing readme, hence the `readme`
key above). No `starknet` dependency, no `[[target.starknet-contract]]`, no `snfoundry.toml`.

Notes:

- `cairo-version` is a *minimum requirement check*; pin it to the toolchain in
  `.tool-versions` and bump both together in a dedicated PR ("require human review").
- Before 1.0 follow Alexandria's practice of stating "version X compatible with Cairo Y" in
  the README, because compiler bumps change gas numbers and sometimes semantics.

### 3.3 Test and benchmark conventions

- **Integration tests** in `packages/<pkg>/tests/` with a `tests/lib.cairo` (`mod test_vec2;`),
  files `test_<module>.cairo`, functions `test_<fn>_<scenario>`
  (`test_vec3_normalize_zero_panics`). They exercise the public API exactly like a consumer.
- **Inline `#[cfg(test)] mod tests`** only for private helpers that must not become `pub`.
- **Golden vectors from glam-rs**: expected values are produced by running the Rust crate
  (f64) and quantizing to the scalar format; record the generator script and tolerance
  (`assert_approx_eq(actual, expected, EPS)` helper in a shared `tests/utils.cairo`). Exact
  equality only for operations that are exact in fixed point (add, sub, neg, component
  selects, integer scaling).
- **Property tests with fixed seeds** (`#[fuzzer(runs: 256, seed: 42)]`): commutativity,
  `a + (-a) == 0`, `dot(a, b) == dot(b, a)`, `|normalize(v)| ~= 1`, `q * q^-1 ~= identity`,
  `cos(-x) == cos(x)` (the class of bug found in Alexandria's `fast_cos`).
- `#[should_panic(expected: '...')]` always with the message; panic messages are short
  strings (`felt252`) namespaced per type: `'Vec3: normalize zero'`.
- **Benchmarks** live in `packages/benches/tests/bench_<module>.cairo`. **(verified)** a test
  with constant inputs folds to the empty-test baseline (13620 sierra gas / 58 steps), so
  every bench must (a) derive inputs from a loop counter or fuzz args, (b) run the operation
  N times (N = 100) to dominate the baseline. Example measured locally: 100 x `Vec2::dot` on
  `i64` = 455,410 sierra gas / 3,851 steps / 894 range checks.
- Track **two metrics**: sierra gas (default, what `[PASS]` lines print) for the committed
  snapshot, and Cairo steps + range checks
  (`snforge test --detailed-resources --tracked-resource cairo-steps`) when optimizing, since
  proving cost follows steps/builtins.

`scripts/gas_snapshot.py` (verified: regenerates, passes when unchanged, exits 1 with a
markdown diff table when stale):

```python
#!/usr/bin/env python3
"""Generate or check gas_snapshot.json from `snforge test` output.
  scripts/gas_snapshot.py            # regenerate
  scripts/gas_snapshot.py --check    # exit 1 if the committed snapshot is stale
"""
import json, re, subprocess, sys
from pathlib import Path

SNAPSHOT = Path(__file__).resolve().parent.parent / "gas_snapshot.json"
# Fuzz tests print a `(runs: N, ...)` block and are skipped on purpose (input dependent).
LINE = re.compile(r"^\[PASS\] (\S+) \(l1_gas: ~\d+, l1_data_gas: ~\d+, l2_gas: ~(\d+)\)")

def measure() -> dict:
    proc = subprocess.run(["snforge", "test", "--workspace"], capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
        sys.exit(proc.returncode)
    gas = {m.group(1): int(m.group(2)) for m in map(LINE.match, proc.stdout.splitlines()) if m}
    if not gas:
        sys.exit("error: no gas data parsed from snforge output")
    return dict(sorted(gas.items()))

def main() -> int:
    new = measure()
    if "--check" not in sys.argv:
        SNAPSHOT.write_text(json.dumps(new, indent=2) + "\n")
        print(f"wrote {len(new)} entries to {SNAPSHOT.name}")
        return 0
    old = json.loads(SNAPSHOT.read_text()) if SNAPSHOT.exists() else {}
    rows = []
    for name in sorted(set(old) | set(new)):
        a, b = old.get(name), new.get(name)
        if a != b:
            delta = "" if a is None or b is None else f"{b - a:+d} ({(b - a) * 100 / a:+.2f}%)"
            rows.append(f"| `{name}` | {a} | {b} | {delta} |")
    if rows:
        print("| test | committed | measured | delta |\n|---|---|---|---|")
        print("\n".join(rows))
        print("\nSnapshot is stale: run `scripts/gas_snapshot.py` and commit the result.")
        return 1
    print(f"gas snapshot up to date ({len(new)} entries)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

Policy (the `forge snapshot --check` model, fixing Alexandria's non-failing script): the
snapshot is **committed**; CI fails when it is stale; therefore every gas change shows up as a
reviewable diff of `gas_snapshot.json` in the PR, and the PR description must justify any
increase. Sorted keys + valid JSON keep diffs minimal and merge conflicts trivial.

### 3.4 CI workflow template

`.github/workflows/ci.yml` (action SHAs are the ones currently pinned by starknet-agentic;
both setup actions read `.tool-versions`, so versions are declared once):

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  fmt-lint:
    name: Format and lint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: software-mansion/setup-scarb@2a96b748888e3329ee44ac9ac073d930e692b3cd # v1.6.2
      - run: scarb fmt --check --workspace
      - run: scarb lint --workspace --test --deny-warnings

  test:
    name: Build, test, gas snapshot
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: software-mansion/setup-scarb@2a96b748888e3329ee44ac9ac073d930e692b3cd # v1.6.2
      - uses: foundry-rs/setup-snfoundry@16e23ddd0e2845f38727c92f4b913a7b728cda9e # v6.0.0
      - run: scarb build --workspace
      # Runs the whole test suite once; fails on test failure or stale snapshot.
      - name: Test and check gas snapshot
        run: |
          python3 scripts/gas_snapshot.py --check | tee gas_diff.md
          exit ${PIPESTATUS[0]}
      - name: Publish gas diff
        if: failure()
        run: cat gas_diff.md >> "$GITHUB_STEP_SUMMARY"

  docs:
    name: Docs build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: software-mansion/setup-scarb@2a96b748888e3329ee44ac9ac073d930e692b3cd # v1.6.2
      - run: scarb doc --workspace --disable-remote-linking

  all-checks:
    name: All checks passed
    if: always()
    needs: [fmt-lint, test, docs]
    runs-on: ubuntu-latest
    steps:
      - run: |
          if [[ "${{ contains(needs.*.result, 'failure') }}" == "true" ]] || \
             [[ "${{ contains(needs.*.result, 'cancelled') }}" == "true" ]]; then
            exit 1
          fi
```

- Jobs run in parallel (no `needs:` chain as in Alexandria); `all-checks` is the single
  required status for branch protection.
- Caching: `setup-scarb` caches the Scarb dependency cache keyed on `Scarb.lock`
  out of the box; nothing else is worth caching for a dependency-free library.
- The docs job only checks that documentation generates; `--disable-remote-linking` makes it
  independent of git metadata (without it `scarb doc` exits 1 when it cannot discover a
  usable git repository - observed locally). The published book should instead pass
  `--remote-base-url <repo>` as Alexandria does.
- No matrix initially. When supporting a second Cairo version becomes a goal, add
  `strategy.matrix.scarb: ["2.18.0", "2.19.4"]` with `scarb-version: ${{ matrix.scarb }}` on
  the build/test job only, and keep the gas snapshot check on the pinned version (gas differs
  per compiler).
- `dependabot.yml` with `package-ecosystem: github-actions` (weekly) keeps the SHAs current.
- `release.yml` (tag `v*`): verify the tag equals `[workspace.package] version`, run the
  checks, `scarb publish -p glam_scalar` then `scarb publish -p glam` (dependency order, as
  in Alexandria's `update_registry.sh`) with a `SCARB_REGISTRY_AUTH_TOKEN` secret, and create
  the GitHub Release from the `CHANGELOG.md` section.
- `scripts/check.sh` runs the same five commands locally; it is the one command an agent
  must run green before reporting "done".

### 3.5 Code, doc and naming conventions

Naming:

| Item | Convention | Example |
|---|---|---|
| Package | snake_case, no prefix for the flagship, prefix for satellites | `glam`, `glam_scalar` |
| Module / file | glam-rs name | `vec3.cairo`, `mat4.cairo`, `quat.cairo`, `affine3.cairo` |
| Type | glam-rs name | `Vec3`, `Mat4`, `Quat` |
| Method trait / impl | `<Type>Trait` / `<Type>Impl` | `pub impl Vec3Impl of Vec3Trait` |
| Operator impl | `<Type><CoreTrait>` | `Vec3Add`, `Vec3Neg`, `Vec3Mul`, `Vec3AddAssign`, `Vec3MulAssignScalar` |
| Conversion impl | `<From>Into<To>` | `Vec2IntoVec3` |
| Constants | glam-rs associated consts become trait consts or `pub const` | `Vec3Trait::ZERO` / `pub const VEC3_ZERO` |
| Method names | identical to glam-rs | `dot`, `cross`, `length_squared`, `normalize_or_zero`, `try_normalize` |
| Panic messages | `'<Type>: <reason>'`, <= 31 chars | `'Quat: not normalized'` |

Code rules (derived from sections 1.4, 1.5, 2.3):

1. All value types: `#[derive(Copy, Drop, Serde, PartialEq, Debug, Default)]`, `pub` fields
   (as in glam-rs). Methods take `self` by value (types are `Copy`), not by snapshot.
2. Explicit `pub trait Vec3Trait` + `pub impl Vec3Impl of Vec3Trait` rather than
   `#[generate_trait]` for the main API: the trait is the documentation surface, carries the
   doc comments, and is what `scarb doc` renders. `#[generate_trait]` is fine for private
   helper impls.
3. Operators through core traits only (`Add`, `Sub`, `Mul`, `Div`, `Neg`, `PartialEq`,
   `core::ops::*Assign`, `core::num::traits::Zero/One`), hand-written (no proc-macro
   dependency in a base library). Core `Add<T>` / `Mul<T>` / `Div<T>` are **homogeneous**
   (`fn mul(lhs: T, rhs: T) -> T`, checked in the corelib), so `Vec3 * Vec3` is an operator
   but `Vec3 * S` cannot be: expose it as a named method (`mul_scalar`, `div_scalar`). The
   `core::ops::MulAssign<Lhs, Rhs>` family *is* heterogeneous, so `v *= s` is possible.
   Record the choice once in `DESIGN.md`.
4. `#[inline(always)]` on constructors, accessors, conversions and `*Assign` delegations;
   plain `#[inline]` (or nothing) on component-wise ops; **never** on large bodies
   (`Mat4::inverse`, `Quat::slerp`). Every inlining decision on a hot path must be backed by
   a snapshot delta.
5. Arithmetic: one `DivRem::div_rem` instead of `/` + `%`; `WideMul` + single division for
   fixed-point products; `NonZero` consts for fixed divisors; lookup tables as
   `const [T; N]`; no `pow()` for powers of two; no `try_into().unwrap()` in hot paths;
   loops as `while i != n` / `for x in span`; prefer fully unrolled component code for fixed
   sizes 2/3/4 (no arrays, no loops).
6. No sign-magnitude structs, no `u256` intermediates unless proven necessary; evaluate
   `BoundedInt` for the scalar internals with bounds flowing through signatures
   (no downcast at each call).
7. One rounding mode and one overflow policy (panic vs wrap vs saturate) defined in
   `DESIGN.md`; every deviation from glam-rs semantics (no NaN/inf, no `f32::EPSILON`) is
   listed there and in the item's doc comment under `#### Deviations`.
8. No stubbed success: an unported function does not exist. No `todo`-style placeholders
   returning zero.
9. `lib.cairo` contains only `//!` docs, `pub mod` declarations and `pub use` re-exports
   (prelude-style: `pub use vec3::{Vec3, Vec3Trait};`).

Doc template (Alexandria's, extended):

```cairo
/// Computes the dot product of `self` and `rhs`.
///
/// Mirrors `glam::Vec3::dot`.
/// #### Arguments
/// * `rhs` - The other vector.
/// #### Returns
/// * `S` - The dot product, rounded toward zero.
/// #### Panics
/// * `'Fixed: overflow'` if an intermediate product exceeds the scalar range.
/// #### Deviations
/// * None.
fn dot(self: Vec3, rhs: Vec3) -> S;
```

Every file starts with a `//!` header naming the glam-rs source it mirrors
(`//! Port of glam-rs src/f32/vec3.rs @ <glam version>`). One README per package: purpose,
install line, module table with porting status, gas table of the headline operations.
Note: `scarb doc` on 2.19.4 exposes `--no-run` / `--show-run-output`, which suggests doc
examples can be executed; worth evaluating so that examples in `///` blocks are tested.

Commits and PRs: conventional commits with the package or module as scope
(`feat(vec3): add cross and dot`, `perf(scalar): single div_rem in mul`,
`test(quat): slerp golden vectors`), squash merge, PR title = commit title. One module (or
one optimization class) per PR. PR template = Alexandria's type checkboxes +
starknet-agentic's checklist (acceptance test included, checks green, no unrelated
refactors) + a **gas delta table** section + "breaking change: yes/no". `CHANGELOG.md`
(Keep a Changelog) updated in the same PR under `Unreleased`. `VERSIONING.md` with the
pre-1.0 policy: PATCH = fixes/perf without API or numeric-result change; MINOR = any API
change **or any change of numeric results** (rounding, precision), since downstream physics
determinism depends on bit-exact outputs.

### 3.6 Agent-driven workflow: AGENTS.md / CLAUDE.md outline

Principles taken from starknet-agentic: one canonical instruction file; context files
contain only stable or machine-checked facts; deterministic scripts instead of model
judgement for anything numeric; plan -> implement -> verify with explicit acceptance checks;
orchestrator coordinates and reviews, sub-agents implement.

`CLAUDE.md` (thin adapter, Claude Code reads it automatically and supports imports):

```markdown
# glam.cairo
@AGENTS.md

## Claude-specific
- Sub-agent definitions: `.claude/agents/`. Project skills: `.claude/skills/`.
- Work in the provided worktree only; never `cd` to the main checkout; never use bare `git stash`.
```

`AGENTS.md` draft outline:

```markdown
# AGENTS.md - canonical agent instructions

## Mission
Port glam-rs to pure Cairo as a deterministic, gas-efficient, provable math library.
Siblings nalgebra.cairo and rapier.cairo depend on `glam` and `glam_scalar`.

## Repository map
(annotated tree of 3.1 - directories only, no counts, no statuses)

## Toolchain and commands
| Task | Command |
| Full gate (run before reporting done) | `scripts/check.sh` |
| Format | `scarb fmt --workspace` |
| Lint | `scarb lint --workspace --test --deny-warnings` |
| Test one module | `snforge test -p glam test_vec3` |
| Steps / range checks | `snforge test <filter> --detailed-resources --tracked-resource cairo-steps` |
| Regenerate gas snapshot | `scripts/gas_snapshot.py` |
Versions live in `.tool-versions` only.

## Core principles
1. Single source of truth: behaviour rules here, design decisions in `docs/DESIGN.md`,
   progress in `docs/PORTING_STATUS.md`.
2. Small, testable changes: one module or one optimization class per task/PR.
3. Correctness first, then gas: never optimize untested code.
4. Determinism: bit-exact results are API. Changing a numeric result is a breaking change.
5. No stubbed success: unported = absent.
6. Measure, do not guess: every perf claim cites a `gas_snapshot.json` delta.

## Roles
| Role | Owns | Does not own |
| Orchestrator | task specs, sequencing, PORTING_STATUS, review, merges | large implementations |
| Porter (sub-agent) | one module: source + tests + docs + bench | public API of other modules, Scarb.toml, CI |
| Optimizer (sub-agent) | gas/steps reduction on a locked module | behaviour or API changes |
| Reviewer (sub-agent) | parity with glam-rs, edge cases, conventions, gas deltas | implementation |

## Task lifecycle and spec
`todo -> inprogress -> inreview -> done` (`blocked` from any state).
Every delegated task is a file `docs/specs/<id>-<slug>.md`:
- Goal (one sentence) and glam-rs source reference (file + version)
- Scope: files allowed to change / files forbidden
- API to deliver (signatures)
- Acceptance checks (exact commands + expected results, golden vectors, properties)
- Gas budget or baseline to beat (if any)
- Dependencies on other tasks; parallel-safe: yes/no
- Out of scope

## Work protocol
1. Investigate: read the spec, the glam-rs source, `docs/DESIGN.md`, neighbouring modules.
2. Plan: <= 30 lines (API, test list, open questions). Escalate open questions, do not guess.
3. Implement: source -> tests (golden, edge, property, panic) -> docs -> bench.
4. Verify: `scripts/check.sh` green; regenerate snapshot if benches changed.
5. Report using the handoff format.

## Definition of done (all mandatory)
- [ ] Every public item of the spec exists with glam-rs name and the doc template
- [ ] Tests: golden vectors, edge cases (zero, one, max, negative), seeded fuzz properties,
      `should_panic` with exact message for every panic path
- [ ] A bench with non-constant inputs for each hot operation; `gas_snapshot.json` updated
- [ ] `scripts/check.sh` passes (fmt, lint -D warnings, build, test, snapshot check)
- [ ] `docs/PORTING_STATUS.md`, package README and `CHANGELOG.md` updated
- [ ] Deviations from glam-rs documented in the item docs and `docs/DESIGN.md`
- [ ] No changes outside the spec's allowed files; no unrelated refactors

## Handoff / report format
Summary (3 lines) - Files changed - Commands run + result - Gas table (before/after) -
Deviations - Open questions / follow-ups.

## Parallelization rules
Safe in parallel: different modules with no shared file; docs vs code; benches vs tests.
Must serialize: scalar API changes, `lib.cairo` re-exports, `Scarb.toml`, `scripts/**`,
`.github/**`, `gas_snapshot.json` (regenerated by the orchestrator after merging parallel work).
Conflict protocol: detect overlap -> pause dependents -> land interface change first with
tests -> rebase and re-verify.

## Boundaries
DO NOT modify: `Scarb.lock` by hand, `.tool-versions`, `LICENSE`, `.github/**` (unless the task says so).
Require human review: scalar representation/rounding/overflow policy, public API renames,
toolchain or dependency bumps, release/publish, anything lowering test coverage.
Safe for agents: source, tests, benches, docs within the task scope; running any scarb/snforge command.

## Escalation
When: spec contradicts glam-rs or DESIGN.md; an API cannot be expressed in Cairo; gas budget
unreachable; a change to a serialized file is needed.
Format: `## Escalation: <title>` / Blocker / Options / Recommendation.

## Cairo rules (hard)
(the 9 code rules of 3.5 + the optimization table of 2.3, as a checklist)

## Rationalizations to reject
- "Constant inputs are fine for this bench."      - they fold to the 13620-gas baseline
- "It is obviously faster, no need to re-measure."
- "I'll add the panic/edge tests later."
- "A small refactor of the neighbouring module while I'm here."
- "Exact equality failed, I loosened the tolerance."  - explain the error bound instead

## References
`docs/DESIGN.md`, `docs/research/*`, `docs/PORTING_STATUS.md`, glam-rs docs (version pinned).
```

Project skills (`.claude/skills/`), following the starknet-agentic template (frontmatter,
when / when not, rationalizations to reject, turn-based orchestration, error table,
non-negotiable rules, `workflows/default.md`, `references/`):

- `port-module`: drives the work protocol above for one glam-rs module.
- `gas-bench`: baseline -> plan -> one optimization class per commit -> re-measure -> lock,
  with `references/optimization-rules.md` (section 2.3, attributed to
  feltroidprime/cairo-skills) and the snapshot script as the only accepted measurement tool.
- Optionally install the upstream `cairo-optimization` / `cairo-testing` skills from the
  starknet-agentic plugin marketplace rather than copying them; they are contract-oriented
  but the optimization references apply unchanged.

Keep instruction files honest: no test counts, line counts or statuses in `AGENTS.md` /
`CLAUDE.md`; status lives in `docs/PORTING_STATUS.md`, ideally checked by a script in
`scripts/check.sh` (every `pub fn` in a trait appears in the status table), mirroring
starknet-agentic's `validate_skills.py` / manifest `--check` approach.

### 3.7 Adoption checklist

1. Create the virtual workspace (3.1, 3.2), `.tool-versions`, commit `Scarb.lock`.
2. Add `scripts/gas_snapshot.py`, `scripts/check.sh`, empty `gas_snapshot.json`.
3. Add `ci.yml` (3.4), `dependabot.yml`, `CODEOWNERS`, PR template; protect `main` with
   `all-checks` required.
4. Write `AGENTS.md`, thin `CLAUDE.md`, `docs/DESIGN.md` skeleton, `docs/PORTING_STATUS.md`,
   `CONTRIBUTING.md`, `VERSIONING.md`, `CHANGELOG.md`.
5. Land the scalar package first (serialized, human-reviewed design), then fan out one
   sub-agent per glam module with a spec file each.
6. First tag `v0.1.0` only when siblings need a pin; publish to scarbs.xyz in dependency
   order (`glam_scalar`, then `glam`).
