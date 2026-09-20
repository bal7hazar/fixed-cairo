# 05 - Gas / step micro-benchmarks

Empirical measurements backing the choice of the scalar representation and of the coding rules for
the Cairo port of `glam-rs`. Everything below was **measured**, not estimated, with:

- scarb 2.19.4 (cairo 2.19.4, sierra 1.9.3), starknet-foundry (snforge) 0.61.0, macOS arm64
- bench project (re-runnable, README inside):
  `/private/tmp/claude-501/-Users-bal7hazar-git-glam-cairo--claude-worktrees-physics-engine-cairo-benchmark-431dc7/d0f7aa2b-bc78-4594-9f73-c563863f8fab/scratchpad/bench`
- 496 benchmarks; raw snforge output kept in `results/raw/`, parsed tables in `results/results.{md,csv}`,
  accuracy sweeps in `results/trig_errors.md`, committed-style snapshot in `gas-snapshot`.

Cell format used in the wide tables: **`l2_gas / steps / range_checks`**.

---

## 0. TL;DR

1. **North-star metric: `l2_gas` (= Sierra gas)**, that is what users pay on Starknet today; report
   Cairo steps + builtins next to it (prover cost). In practice they are tightly coupled:
   `sierra gas ~= 100 x steps + 70 x range_check + 583 x bitwise`, plus a worst-branch premium.
2. **The owner's heuristic is confirmed, with numbers and two amendments** (section 2.9):
   add/sub/mul (~470-570 gas) < div/rem (~1 010-1 210) ~= bitwise and/or/xor (1 083) << one loop
   iteration (~1 200-1 400 gas of pure overhead, 3.6x slower than unrolled code). Amendments:
   (a) **range checks and non-inlined panicking calls** are the real hidden costs, not the arithmetic
   instruction itself; (b) a **const-array lookup (1 270) is cheaper than a `match` jump table
   (2 370)**, and both crush if-chains / if-trees.
3. **Recommended scalar: `struct Fixed { raw: i64 }` (Q32.32), floor rounding, arithmetic written
   with `core::internal::bounded_int`, and all glam kernels written "fused"** (accumulate raw
   Q64.64 products, rescale once). Versus a cubit-style `{mag: u64, sign: bool}`:
   `add` 4.8x cheaper, `lt` 4x, `mul` 1.45x, `dot` 3.4x, `Mat3*Mat3` 5.3x, **`Mat4*Mat4` 7.1x**
   (335 800 -> 47 230 gas), `Quat*Quat` 5.8x, `length` 4.5x. Only `div` is more expensive (1.6x).
   A `felt252`-backed scalar is another ~10-20 % cheaper on kernels and 8x cheaper on `add`, but
   gives up every static guarantee; not recommended as the public type (section 3.4).
4. **Transcendentals: range reduction by one divmod + Horner polynomial, no loop, no LUT needed.**
   `sin` costs 18 420 gas at 4.7e-10 max error, versus cubit's Taylor recursion 128 670 gas at
   2.3e-8 (7x cheaper *and* 48x more accurate) and cubit's `sin_fast` LUT 30 320 gas at 4.7e-6.
   `sin_cos` 28 060 (cubit: 263 610), `atan2` 22 420 @ 7.8e-10, `acos` 25 740 @ 7.6e-10
   (cubit: 113 810 @ 2.9e-6).
5. **Gas tracking in CI:** snforge 0.61 has no snapshot feature (`--gas-report` only covers contract
   calls). Use the provided `scripts/bench.py snapshot|check` (forge-snapshot-like, committed
   `gas-snapshot` file, exit 1 on any drift). Measurements are bit-for-bit deterministic.

---

## 1. Methodology (Step 0)

### 1.1 Tools compared

| tool | command | gives | verdict |
|---|---|---|---|
| snforge, sierra-gas mode | `snforge test --detailed-resources --tracked-resource sierra-gas` | `sierra gas` = `l2_gas` per test | **primary metric** (Sierra gas is what Starknet bills as `l2_gas` for recent Sierra contracts) |
| snforge, cairo-steps mode | `snforge test --detailed-resources --tracked-resource cairo-steps` | steps, memory holes, builtin counters | **secondary metric** (prover cost). In this mode the printed `l2_gas` is coarse (quantised to 40 000), do not use it |
| scarb execute | `scarb execute --executable-name op --arguments a,b --print-resource-usage` (requires `enable-gas = false`) | steps, holes, builtins | cross-check only: gave **exactly** the same delta as snforge (u64 div: +9 steps, +3 range checks). No gas figure |
| scarb cairo-test | `scarb cairo-test` | `gas usage est.` only | different accounting (u64 div: 1 510 vs 1 110 in snforge); no builtin breakdown. Not used |
| `snforge test --gas-report` | | per-contract/selector table | prints "No contract gas usage data to display, no contract calls made" for library tests. Useless for a pure library |
| `#[available_gas(n)]` | | a cap, not a measurement | not useful for measuring |

Raw outputs of the alternatives: `results/probe/scarb_cairo_test.txt`, `results/probe/scarb_execute_op.txt`.

### 1.2 Isolating the cost of a pure function

Every benchmark `X` is a **pair of tests with the same prelude**; the cost is the difference, for
every metric:

```cairo
#[inline(never)] pub fn bb<T>(x: T) -> T { x }            // black box: defeats constant folding
#[inline(never)] pub fn sink<T, +Drop<T>>(x: T) {}         // consumes the result

#[test] fn X__base() { let _a = bb::<u64>(..); let _b = bb::<u64>(..); let r = bb::<u64>(1); sink::<u64>(r); }
#[test] fn X__op()   { let a  = bb::<u64>(..); let b  = bb::<u64>(..); let _r = bb::<u64>(1); sink::<u64>(a / b); }
```

`scripts/bench.py` runs the suite in both modes, pairs `__base`/`__op`, subtracts, and writes the
tables. Facts established while building this:

- **Constant folding is aggressive.** An inlined `a + b` on literals costs *exactly* the same as an
  empty test (58 steps / 13 620 gas). Worse: a whole `atan2` (division, jump table, 5 Horner steps)
  called on literals through an inlinable helper was folded to the empty-test floor (13 620 gas).
  Inputs **must** go through an `#[inline(never)]` function. (Literal arguments passed to an
  `#[inline(never)]` callee are *not* specialised: measured identical to opaque arguments.)
- **Unused pure calls are not eliminated** (two unused `bb` calls still cost 10 steps), so the
  identical prelude really cancels out.
- **Empty-test floor:** 58 steps, 3 range checks, 13 620 gas. Never report absolute test costs.
- **Determinism:** two full runs produced bit-identical numbers for all 496 benchmarks.
- **Residual noise: about +-1 step (+-100 gas)**, from `store_temp`/local placement differences
  between the two tests. Cross-check in `tests/validation.cairo` (100-iteration loop of the op minus
  100-iteration loop of a no-op, divided by 100): u64 add 3.96 steps/465 gas (single-shot: 5/570),
  u64 div+add 13.0/1 584 (single-shot sum: 14/1 680), fixed mul 16.0/1 954 (17/2 050).
- **Sierra gas is a "worst sibling branch" measure**: `X__op` gas is the same whatever the input
  (e.g. our `sin` = 18 420 gas in every octant, while steps vary 124-140), because branch
  alignment charges the most expensive arm. Steps are for the path actually executed. For
  sign-magnitude code this matters: the input signs change the step count, not the gas.
- Steps-to-gas relation observed: `100 x steps + 70 x range_check + 583 x bitwise` exactly for
  straight-line code (e.g. u64 div: 9 steps + 3 RC = 1 110), higher when branches/panics exist.

### 1.3 Two cost facts that dominate everything else

| measured | l2_gas | steps | RC | holes |
|---|---:|---:|---:|---:|
| `a + b` (u64) inlined | 570 | 5 | 1 | 0 |
| same, in an `#[inline(never)]` fn (panicking => returns `PanicResult`) | **2 570** | 16 | 1 | 8 |
| `a * b + a` (felt252) inlined | 200 | 2 | 0 | 0 |
| same, in an `#[inline(never)]` fn (`nopanic`) | 600 | 6 | 0 | 0 |
| 47-step function, `inline(always)` vs not inlined | 5 420 vs 6 600 | 46 / 47 | 10 | 0 / 10 |

A call to a function **that can panic costs ~2 000 gas** (call/ret + building and matching the
`PanicResult` enum + branch alignment), 5x more than a call to a `nopanic` function (~400). A
fixed-point `mul` is ~2 000 gas, so a non-inlined operator doubles its price.

Compiler constraints discovered:

- `#[inline(always)]` is **rejected on functions with impl generic parameters** (error E2143). A
  library generic over the scalar (`fn dot<T, +Fused<T>>`) cannot force-inline its helpers; methods
  of a (generic) impl are fine. This is an argument for a **concrete scalar type**, or for keeping
  generic code flat.
- The consumer's `[cairo] inlining-strategy` changes the result for un-annotated code only:
  with `inlining-strategy = 200`, the un-annotated cubit-style type gets 25 % cheaper
  (`Mat4*Mat4` 335 800 -> 246 530, identical to its `inline(always)` variant), while code that
  already carries explicit `#[inline(always)]` does not move. `inlining-strategy = "avoid"` failed
  to compile this test crate (`Offset overflow` in the Sierra->CASM stage). A library must not rely
  on the consumer's setting: **annotate hot operators explicitly**.
  (`snforge optimize-inlining` exists to tune that threshold, but only for contracts.)

---

## 2. Primitive costs (Step 1)

Inline cost of one operation (`op - base`). `l2_gas / steps / range_checks`. Bitwise builtin usage
is given where non-zero. Full table: `results/results.md` (279 primitive rows).

### 2.1 Arithmetic and comparison by type

| op | u8 / u16 / u32 / u64 | u128 | u256 | i8..i64 | i128 | felt252 |
|---|---|---|---|---|---|---|
| `+` | 570 / 5 / 1 | 470 / 4 / 1 | 3 190 / 29 / 2 | 840 / 7 / 2 | 570 / 5 / 1 | **100 / 1 / 0** |
| `-` | 470 / 4 / 1 | 470 / 4 / 1 | 3 270 / 30 / 2 | 840 / 7 / 2 | 570 / 5 / 1 | **100 / 1 / 0** |
| `*` (checked) | 570 / 5 / 1 | **3 230 / 26 / 9** | **14 180 / 119 / 31** | 840 / 7 / 2 | **7 550 / 55 / 12** | **100 / 1 / 0** |
| `WideMul` (to next width) | **100 / 1 / 0** | 3 230 / 26 / 9 (-> u256) | 18 590 / 155 / 42 (-> u512) | **100 / 1 / 0** | n/a | n/a |
| `/` | 1 110 / 9 / 3 | 1 580 / 12 / 4 | 7 270 / 59 / 15 | **4 420 / 27 / 5** | 4 890 / 30 / 6 | 600 / 2 / 0 (field inverse, not integer division) |
| `%` | 1 010 / 8 / 3 | 1 480 / 11 / 4 | 7 270 / 59 / 15 | 4 420 / 27 / 5 | 4 890 / 30 / 6 | n/a |
| `DivRem::div_rem` | 1 210 / 10 / 3 | 1 680 / 13 / 4 | 7 470 / 61 / 15 | 4 520 / 28 / 5 | 4 990 / 31 / 6 | n/a |
| `/ const` | 1 110 / 9 / 3 | 1 580 / 12 / 4 | 7 270 / 60 / 15 | 1 880 / 16 / 4 (i64) | 2 350 / 19 / 5 | n/a |
| `<` | 770 / 7 / 1 | 770 / 7 / 1 | 1 070 / 10 / 1 | 870 / 8 / 1 | 870 / 8 / 1 | n/a (needs conversion) |
| `<=` | 870 / 8 / 1 | 870 / 8 / 1 | 1 200 / 11 / 1 | 770 / 7 / 1 | 770 / 7 / 1 | n/a |
| `==` | 500 / 5 / 0 | 500 / 5 / 0 | 710 / 7 / 0 | 500 / 5 / 0 | 500 / 5 / 0 | 400 / 4 / 0 |
| unary `-` | n/a | n/a | n/a | 300 / 3 / 0 | 300 / 3 / 0 | 100 / 1 / 0 |
| `Sqrt::sqrt` | 1 180 / 9 / 4 | 1 180 / 9 / 4 | 3 590 / 31 / 7 | n/a | n/a | n/a |

Observations:

- **Bit width does not matter up to 64 bits** (u8 = u16 = u32 = u64, i8 = ... = i64): the cost is
  the number of range checks, not the width. Hence **Q16.16 on i32 would cost exactly the same as
  Q32.32 on i64** (not separately implemented: every primitive involved has identical cost), while
  being far less precise. There is no reason to go below 64 bits.
- The **128-bit boundary is a cliff**: `u128 *` is 5.7x a `u64 *`, `i128 *` 9x an `i64 *`, u256 25x.
- Widening multiplications up to 64x64->128 are **1 step, no range check** (`u64_wide_mul`,
  `i64_wide_mul`). This is the cheapest multiplication available on integers.
- **Signed division is 4x unsigned division** (corelib sign-splits with two `constrain`, divides
  unsigned, re-negates). With a *constant* divisor the rhs branch folds: 1 880.
- A constant divisor does **not** make unsigned division cheaper (the `NonZero` check of a runtime
  divisor is folded into the same cost: `u128 / d` runtime = `u128 / 2^32` const = 1 580).
- **`Sqrt` is a bargain**: 1 180 gas for any width up to u128, the price of one division.
- `wrapping_add` (870), `saturating_add` (870), `checked_add` (970), `overflowing_add` (1 270) are
  all **more expensive than the panicking `+` (570)**. `u64 wrapping_mul` = 1 510.

### 2.2 Conversions

| conversion | cost | | conversion | cost |
|---|---|---|---|---|
| any upcast `into` (u8->u64, u64->u128, i64->i128, uN/iN->felt252, bool->felt252) | 100 / 1 / 0 | | felt252 -> u128 `try_into` | 370 / 3 / 1 |
| uN -> u256 `into` | 200 / 2 / 0 | | felt252 -> u8/u32/u64 `try_into` | 640 / 5 / 2 |
| u64 -> u32/u8, u128 -> u64, u64 -> i64 `try_into` | 470 / 4 / 1 | | felt252 -> i64 `try_into` | 740 / 6 / 2 |
| i64 -> u64, i128 -> u128 `try_into` | 370 / 3 / 1 | | felt252 -> i128 `try_into` | 470 / 4 / 1 |
| i128 -> i64 `try_into` | 740 / 6 / 2 | | felt252 -> u256 `into` | 1 910 / 16 / 3 |
| u256 -> u128 / u64 / felt252 | 200 / 570 / 1 070 | | u64 -> `NonZero<u64>` | 200 / 2 / 0 |
| \|i64\| through felt252 + branches | 2 530 / 22 / 3 | | \|i64\| with `bounded_int::constrain` + negate | **770 / 7 / 1** |

Going *into* a felt is free; coming *back* costs one range check for 128-bit targets and two for
everything narrower. `upcast`/`downcast` are reachable from user code through
`core::internal::bounded_int` (section 2.8).

### 2.3 Bitwise

| op | u8 .. u128 | u256 |
|---|---|---|
| `&`, `\|`, `^` | 1 083 / 6 / 0 + **1 bitwise builtin** | 2 066 / 10 / 0 + 2 bitwise |
| `~` | 200 / 2 / 0 (it is a subtraction) | 400 / 4 / 0 |
| low 32 bits: `x & 0xffffffff` | 1 183 (1 bitwise) | vs `x % 2^32`: **1 010** / 8 / 3 |
| parity: `x & 1 == 1` | 1 683 (1 bitwise) | vs `x % 2 == 1`: **1 510** / 13 / 3 |

The bitwise builtin is priced 583 gas per use (5.8 steps). A mask is never cheaper than the
equivalent `%`/`DivRem` by a constant power of two, and `DivRem` gives quotient *and* remainder.

### 2.4 Shifts (there is no shift instruction)

| variant (`u64 >> 13`) | cost |
|---|---|
| `x / 0x2000` (constant) | **1 110 / 9 / 3** |
| `x * 0x2000` (left shift by constant) | **570 / 5 / 1** |
| variable shift, `x / *POW2_TABLE.span()[n]` (const array) | 2 380 / 21 / 4 |
| variable shift, `x / pow2_match(n)` (`match` jump table) | 3 380 / 26 / 4 |
| `x / Pow::pow(2, n)` (what alexandria-style `BitShift` does) | **14 940 / 132 / 25** |
| loop halving `n` times | 30 110 / 264 / 53 |

### 2.5 Loops

| measurement | total | per iteration |
|---|---|---|
| `while i != n` empty, u32 counter, n=100 | 138 570 / 1 315 / 101 | ~1 390 gas, 13 steps, 1 RC |
| same with a felt252 counter | 118 870 / 1 118 / 101 | ~1 190 gas, 11 steps |
| `for i in 0..n` | 129 640 / 1 225 / 102 | ~1 300 gas |
| tail recursion | 138 770 / 1 317 / 101 | ~1 390 gas |
| `for x in span` with one `\|` in the body, 16 elements | 50 388 | ~3 150 gas |
| 8 additions in a loop vs unrolled | 17 090 vs **4 780** | **3.6x** |

Pure loop overhead (~1 200-1 400 gas per iteration, includes a `withdraw_gas`) is 2.4x a u64
addition and ~65 % of a full fixed-point multiplication. Unroll everything of fixed size <= 16.

### 2.6 Lookup tables

| variant | cost |
|---|---|
| `const T: [u64; N]` + `T.span()[i]` (N = 64 and N = 256: same cost) | **1 270 / 12 / 1** |
| same via `.at(i)` / `.get(i).unwrap().unbox()` | 1 270 / 12 / 1 |
| const array of tuples `[(u64, u64); 64]` | 1 470 / 14 / 1 |
| `match i { 0 => .., ..., 63 => .., _ => panic }` (u32; 64 and 256 arms: same cost) | 2 370 / 18 / 1 |
| `match` on a felt252 | 3 110 / 19 / 2 |
| 8-arm `match` | 1 890 / 17 / 1 |
| if-chain, 8 entries, worst case | 3 200 / 25 / 0 |
| building `array![..64 values..]` at runtime then indexing | 14 070 / 140 / 1 |

`const` fixed-size arrays with `.span()` work in 2.19 for integers and tuples, cost O(1) regardless
of size, and live in the bytecode data segment (no runtime construction). cubit's 256-slot if-tree
and its 99-way linear `if slot == k` chain (its `atan` LUT) are obsolete techniques.

### 2.7 Sign handling and structs

| measurement | cost |
|---|---|
| native `i64 + i64` | 840 / 7 / 2 |
| `(mag, sign)` addition, mixed signs (cubit algorithm) | **4 250 / 29 / 2** |
| native `i64 * i64` | 840 / 7 / 2 ; `(mag*mag, sign ^ sign)` 770 / 7 / 1 |
| `bool ^`, `!` | 200 / 2 / 0 ; `&&` 300 ; `!=` 400 ; `if c {a} else {b}` 300 / 3 / 0 |
| passing a 3-felt struct by value vs by snapshot to a non-inlined fn | 700 vs 700 (identical) |

Sign-magnitude is only competitive for pure multiplications; every addition, subtraction and
comparison pays 3-5x for the branches.

### 2.8 `core::internal::bounded_int` from user code

Usable on 2.19.4 with `#[feature("bounded-int-utils")]` on the `use`. User crates can declare their
own `AddHelper` / `SubHelper` / `MulHelper` / `DivRemHelper` impls (the result bounds must be
exact) and then call `bounded_int::{add, sub, mul, div_rem, constrain, trim_min}`, `upcast`,
`downcast`. Native ints (`i64`, `u64`, `i128`...) are accepted directly as operands.

| measurement | bounded-int | plain corelib |
|---|---|---|
| `i64 + i64` without overflow check (result type is wider) | **100 / 1 / 0** | 840 / 7 / 2 |
| `(i64 * i64) >> 32`, floor, back to i64 | **2 050 / 17 / 5** | 4 110 / 34 / 7 (`i128 /`) |
| `(u64 * u64) >> 32`, back to u64 | 1 580 / 13 / 4 | 2 050 / 16 / 5 |
| is-negative | 770 / 7 / 1 (`constrain`) | 970 / 9 / 1 (`< 0`) |
| \|i64\| | 770 / 7 / 1 | 2 530 / 22 / 3 |
| `u64 / 2^13` | 1 110 / 9 / 3 | 1 110 / 9 / 3 (no gain) |

Rescale variants for `(a * b) >> 32` on i64 (coordinator item 2), all force-inlined:

| variant | cost | note |
|---|---|---|
| v1 naive `(wide_mul(a,b) / 2^32).try_into()` (signed i128 division) | 4 110 / 34 / 7 | truncation |
| v2 sign-split by hand on stable API (abs, u128 divmod, re-sign) | 6 580 / 57 / 9 | truncation; slowest |
| **v3 bounded-int bias: `((p + 2^126) div 2^32) - 2^94`, `downcast` to i64** | **2 050 / 17 / 5** | floor, branch-free |
| v4 same bias trick on stable API (felt252 product, `u128` divmod) | 3 710 / 31 / 7 | floor, branch-free |

Limits found the hard way (all of them surface as **compiler panics at Sierra specialisation time,
not as diagnostics**, so they must be covered by tests in CI):

- `bounded_int::div_rem` requires a statically non-negative dividend (hence the bias trick).
  Dividends up to 2^129 with a constant divisor work.
- `downcast` rejects source ranges wider than 2^128 (go through `felt252` + `try_into`).
- `upcast` between `NonZero<BoundedInt<..>>` types is unsupported.
- `bounded_int::is_zero` is unusable: its result type `IsZeroResult` is `pub(crate)`.
- The module is `core::internal` behind a feature flag: **unstable API**. It has been stable in
  practice since 2.7-2.8 and corelib itself is built on it, but pin the compiler version and keep a
  stable-API fallback (v4 above costs 1.8x) behind the same function signature.

### 2.9 Verdict on the owner's heuristic

> "simple math (add, mul, div, mod) is cheaper than bitwise (and/or/xor/shifts), which is cheaper
> than loops."

| class | representative cost (u64) |
|---|---|
| field op (felt252 add/mul) | 100 |
| add / sub / mul | 470-570 |
| eq / lt | 500 / 770 |
| div, rem, divmod, shift-by-constant (= div) | 1 010-1 210 |
| and / or / xor | 1 083 (+ 1 bitwise builtin cell for the prover) |
| const-array lookup | 1 270 |
| `match` jump table | 2 370 |
| non-inlined panicking call | ~2 000 on top of the body |
| one loop iteration (overhead only) | ~1 200-1 400 |
| variable shift through `pow` | ~15 000 |

**Confirmed**, quantitatively: add/mul < div/mod ~= bitwise < loop iteration. Refinements:

1. Within "simple math", div/mod is 2x add/mul and **equal to a bitwise op in gas**; bitwise is
   worse for the prover (dedicated builtin) and never better than `DivRem` by a power of two. So
   the rule becomes: *never use bitwise ops for masks/shifts; use `DivRem` by a constant.*
2. What really costs is **range checks** (every checked integer op has 1-5) and **function-call
   boundaries of panicking functions**. `felt252`/`bounded_int` arithmetic has neither.
3. **Width is free up to 64 bits, then a cliff** at 128 (mul 5.7x) and 256 (25x).
4. LUTs: const array < `match` < if-chain; all are cheaper than two loop iterations.

---

## 3. Scalar representation shoot-out (Step 2)

### 3.1 Candidates (all Q32.32 unless noted, all pass `tests/correctness.cairo`)

| tag | type | arithmetic | rounding of `mul` |
|---|---|---|---|
| **A `mag`** | `{ mag: u64, sign: bool }` | cubit's algorithms verbatim, default inlining (as cubit ships) | truncation |
| **A' `magi`** | same | A + `#[inline(always)]` on operators, cheap sqrt scaling | truncation |
| **B `i64n`** | `{ raw: i64 }` | stable corelib only: `i64_wide_mul`, signed `i128 /`, checked `+` | truncation |
| **C/E `i64b`** | `{ raw: i64 }` | bounded-int bias rescale; **fused kernels** with static bounds | floor |
| **D `felt`** | `{ raw: felt252 }` | unchecked field add/sub; lazy reduction (range check only when rescaling/comparing) | floor |
| F `q64` | `{ mag: u128, sign: bool }` Q64.64 | add / mul / div only, optimised | truncation |

`Fused<T>` kernels (`dot2`, `mul_sub`, `dot3`, `dot4`, `norm3`) are implemented naively for A, A',
B (one rescale per product) and with **a single rescale** for C/E and D. `norm3` for C/E and D is
`u128_sqrt(x*x + y*y + z*z)` on the raw Q64.64 sum: the integer square root of a Q64.64 value *is*
the Q32.32 result, so `length` needs no rescale and no precision is lost.

### 3.2 Scalar operations

| op | A mag | A' magi | B i64n | **C/E i64b** | D felt |
|---|---|---|---|---|---|
| `add` (mixed signs) | 4 050 / 28 / 2 | 3 160 / 29 / 2 | 840 / 7 / 2 | **840 / 7 / 2** | 100 / 1 / 0 |
| `add` (same sign) | 4 050 / 23 / 1 | 2 390 / 22 / 1 | 840 / 7 / 2 | **840 / 7 / 2** | 100 / 1 / 0 |
| `sub` | 4 450 / 27-32 | 2 790-3 560 | 840 / 7 / 2 | **840 / 7 / 2** | 100 / 1 / 0 |
| `mul` | 2 970 / 24 / 5 | 2 970 / 24 / 5 | 4 110 / 34 / 7 | **2 050 / 17 / 5** | 1 680 / 14 / 4 |
| `div` | **2 970 / 24 / 5** | 2 970 / 24 / 5 | 5 530 / 35 / 8 | 4 850 / 43 / 6 | 7 020 / 54 / 10 |
| `neg` | 400 / 4 / 0 | 400 / 4 / 0 | 300 / 3 / 0 | 300 / 3 / 0 | 100 / 1 / 0 |
| `abs` (negative input) | 0 | 0 | 1 170 / 11 / 1 | 1 240 / 11 / 2 | 1 140 / 10 / 2 |
| `lt` (same sign) | 3 110 / 29 / 1 | 3 110 / 29 / 1 | 770 / 7 / 1 | **770 / 7 / 1** | 1 140 / 10 / 2 |
| `le` | 3 110 / 29 / 1 | 3 110 / 29 / 1 | 870 / 8 / 1 | **870 / 8 / 1** | 1 440 / 13 / 2 |
| `eq` | 610 / 6 / 0 | 610 / 6 / 0 | 500 / 5 / 0 | 500 / 5 / 0 | 400 / 4 / 0 |
| `from_int(i32)` | 3 710 / 25 / 3 | 3 710 / 25 / 3 | 840 / 7 / 2 | **100 / 1 / 0** | 100 / 1 / 0 |
| `to_int` (floor) | 5 960 / 46 / 8 | 5 960 / 46 / 8 | 9 400 / 75 / 15 | **1 210 / 10 / 3** | 3 240 / 27 / 6 |
| `floor` | 3 300 / 29 / 4 | 3 300 / 29 / 4 | 5 960 / 46 / 9 | **1 680 / 14 / 4** | 1 580 / 13 / 4 |
| `round` | 3 570 / 31 / 5 | 3 570 / 31 / 5 | 6 800 / 53 / 11 | 3 440 / 29 / 6 | 1 680 / 14 / 4 |
| `sqrt` | 5 430 / 44 / 13 | **1 380 / 11 / 4** | 2 020 / 16 / 6 | 2 020 / 16 / 6 | 1 820 / 14 / 6 |
| `a * b + c` | 7 020 / 51 / 7 | 5 220 / 45 / 7 | 4 850 / 40 / 9 | **3 710 / 31 / 7** | 1 780 / 15 / 4 |
| `lerp`: `a + (b - a) * t` | 11 470 / 78 / 8 | 7 220 / 64 / 8 | 5 590 / 46 / 11 | **4 450 / 37 / 9** | 1 880 / 16 / 4 |

Q64.64 (F): `add` 2 570, `mul` **4 940** / 40 / 13 (optimised: `hi * 2^64 + lo / 2^64` from
`u128_wide_mul`), `mul` through u256 division as cubit f128 does **9 910** / 81 / 24, `div`
**8 090** / 66 / 18. So Q64.64 costs **2.4x (mul) and 1.7-2.7x (div)** the Q32.32 `i64b`, and its
raw products (256 bits) do not fit a felt, which kills the fused kernels. Not worth it.

Reading the table:

- Predictions of doc 04 section 5.5 item 1 confirmed: i64 wins big on add/sub/compare (4-5x),
  modestly on mul (1.45x, only with the bias trick: the naive signed `i128 /` of B is *slower*
  than cubit). cubit's `sqrt` is slow only because it scales with a checked `u128 *` instead of
  `wide_mul` (5 430 -> 1 380 once fixed).
- **Division is the one operation where sign-magnitude wins** (magnitudes are already split).
  `i64b` pays two `constrain` + conditional negate around the same unsigned divmod. A bias trick
  for division was attempted and is blocked by bounded-int limits (section 2.8). Division is rare
  in glam kernels (normalize, inverse, perspective divide): acceptable.
- cubit's `add` is 4-5x a native add, and its cost shows up everywhere (`lerp` 2.6x, `a*b+c` 1.9x).

### 3.3 Composite glam workloads (what actually matters)

Each composite is an `#[inline(never)]` function (what a user of the library calls), written once,
generically, against the `Fused` kernels; identical inputs for all representations.

| workload | A mag (cubit-style) | A' magi | B i64n | **C/E i64b fused** | D felt lazy | A / E |
|---|---|---|---|---|---|---:|
| `Vec3 + Vec3` | 15 470 / 109 / 5 | 10 250 / 79 / 5 | 4 850 / 37 / 6 | **4 850 / 37 / 6** | 1 100 / 11 / 0 | 3.2x |
| `Vec3 * s` | 9 250 / 69 / 15 | 9 250 / 69 / 15 | 11 600 / 88 / 21 | **8 480 / 65 / 15** | 7 170 / 56 / 12 | 1.1x |
| `Vec3 dot` | 15 750 / 112 / 18 | 13 340 / 98 / 18 | 12 980 / 99 / 25 | **4 680 / 36 / 5** | 4 110 / 33 / 4 | 3.4x |
| `Vec3 cross` | 29 030 / 212 / 34 | 24 110 / 183 / 34 | 22 790 / 177 / 48 | **9 280 / 73 / 15** | 7 970 / 64 / 12 | 3.1x |
| `Vec3 length` | 20 280 / 145 / 30 | 13 510 / 104 / 21 | 14 770 / 109 / 31 | **4 520 / 32 / 6** | 3 910 / 29 / 5 | 4.5x |
| `Vec3 normalize` | 30 060 / 215 / 50 | 23 410 / 175 / 41 | 26 860 / 205 / 59 | **13 760 / 107 / 26** | 14 520 / 110 / 24 | 2.2x |
| `Mat3 * Vec3` | 46 350 / 330 / 54 | 36 000 / 280 / 54 | 35 500 / 280 / 75 | **11 400 / 93 / 15** | 10 090 / 84 / 12 | 4.1x |
| `Mat3 * Mat3` | 134 250 / 939 / 162 | 101 580 / 793 / 162 | 98 180 / 775 / 225 | **25 480 / 214 / 45** | 21 950 / 187 / 36 | 5.3x |
| `Mat4 * Mat4` | 335 800 / 2 282 / 381 | 246 530 / 1 889 / 381 | 233 110 / 1 831 / 544 | **47 230 / 407 / 80** | 41 110 / 359 / 64 | **7.1x** |
| `Quat * Quat` | 87 780 / 611 / 98 | 66 070 / 511 / 98 | 61 550 / 487 / 136 | **15 230 / 129 / 20** | 12 350 / 105 / 16 | 5.8x |
| `Quat * Vec3` (rotate) | 115 910 / 813 / 135 | 86 460 / 678 / 135 | 81 250 / 640 / 186 | **23 710 / 197 / 44** | 19 170 / 162 / 32 | 4.9x |
| `Mat3 * Mat3`, `Span` storage + triple loop (orion-Tensor-like proxy) | 316 550 / 2 652 | - | - | 234 170 / 2 110 | - | |

- The win comes from **fusion, not from the integer type**: B (`i64`, one rescale per product) is
  barely better than A' (-5 %). C/E does 16 rescales instead of 64 for `Mat4*Mat4`.
- A fused `dot3` costs 4 680 gas: 3 field-cost multiplications + 1 rescale, i.e. **2.3 plain muls**.
- **Array/loop style costs 9.2x the unrolled fused struct code** (234 170 vs 25 480) for the same
  3x3 product with the same scalar type, and still 2.4x the unrolled *non-fused* code of B
  (98 180): loops + bounds-checked indexing + per-product rescale. Doc 04's "one to two orders of magnitude" for orion's `Tensor` is plausible (a real
  Tensor adds shape/stride handling on top of this proxy). Structs + unrolled code, always.

### 3.4 The felt252 "lazy reduction" design, seriously evaluated

D stores the signed raw value in a felt (`-x` is `P - x`). add/sub/neg are single field ops with
no range check (100 gas vs 840); products are accumulated in the field and rescaled once with
`felt252 -> i128` (the only range check: `|acc| < 2^127`), bias, `div_rem 2^32`, un-bias.

Overflow envelope: a rescaled value satisfies `|raw| < 2^95`; a raw product of two such values is
`< 2^190`; the prime is `~2^251`, so `2^61` products can be accumulated before a wrap-around could
go undetected, and every value that *enters* a rescale, comparison, sqrt or conversion is
range-checked there. Unchecked add chains grow one bit per doubling. In practice it is sound.

Why it is **not** the recommended public type despite being the cheapest:

| | C/E `i64b` | D `felt` |
|---|---|---|
| kernels (`dot`, `Mat*Mat`, `Quat*Quat`) | 1.00 | 0.81-0.88 |
| `add`/`sub` | 840 | 100 |
| compare / abs / to_int / div | 770 / 1 240 / 1 210 / 4 850 | 1 140 / 1 140 / 3 240 / 7 020 |
| invariant | value is always a valid i64: **static, by construction** | none: any felt is a "valid" value; overflow detected late or (deserialised data) never unless validated |
| Serde / storage / ABI | i64: validated by the runtime, packs in 64 bits | felt252: needs explicit validation at every trust boundary |
| `PartialOrd`, `Hash`, equality | natural | `==` on felts is fine; ordering needs a conversion |

The decisive point: **C/E already captures most of D's gain** because its fused kernels *are* lazy
reduction, done in `BoundedInt` space where the accumulator bounds are tracked by the type system
(`i64*i64` in `[-(2^126-2^63), 2^126]`, sums of 2/3/4 products, difference of 2 products), so there
is no intermediate range check at all and the single runtime check is the final `downcast` to i64.
What D adds is only the unchecked `add` (-740 gas each). If profiling of the physics step later
shows `Vec3 + Vec3` dominating, the same trick can be offered *inside* i64b as wide accumulator
types (`Wide`), without changing the public scalar.

Constraints of the C/E fused kernels, for the record: up to 4 accumulated products stay below
2^128 + 2^126 and rescale with a constant-divisor `div_rem` (works up to a 2^129 dividend);
`norm3` needs the sum of 3 squares `< 2^128` (always true) and goes through `felt252 -> u128`
because `downcast` refuses the statically signed 2^129-wide range. Vec4 length (4 squares, up to
2^128) needs a checked conversion.

### 3.5 Recommendation

`#[derive(Copy, Drop, Serde, PartialEq)] pub struct Fixed { raw: i64 }`, Q32.32, **floor** rounding:

- operators `#[inline(always)]`; add/sub/neg/compare = native i64; `mul` = bounded-int bias rescale
  (2 050); `div` = sign-split bounded divmod (4 850); `sqrt` = `u128_sqrt(raw << 32)` (2 020);
  `from_int`/`to_int`/`floor` via bounded ints (100 / 1 210 / 1 680);
- an internal wide-accumulator API (`wide(a, b) -> Prod1`, typed sums, `narrow`, `sqrt`) and **all**
  Vec/Mat/Quat kernels written against it, flat and unrolled;
- a concrete type rather than a generic scalar parameter (E2143 forbids `inline(always)` on
  generic free functions; monomorphic code also keeps compile times and diagnostics sane);
- the bounded-int plumbing generated by a script (`scripts/gen_bounded.py`: every bound is computed,
  none is typed by hand) and guarded by the gas snapshot + correctness tests, because mistakes
  there are compiler panics.

---

## 4. Transcendentals (Step 3)

Implemented on `i64b` (`src/trig.cairo`), internals on felt accumulators at scale 2^60 with floor
shifts (`acc = shr(acc * x) + c`: 1 field mul + 1 field add + 1 range-checked shift per Horner
step, ~1 500 gas per coefficient). Coefficients are near-minimax fits (Chebyshev-node least
squares) generated by `scripts/gen_trig.py`, which also contains **bit-exact Python mirrors** of
every Cairo function (ours and cubit's): `tests/correctness_trig.cairo` asserts equality on 20+
inputs per function, and the error sweeps (40 001 points per function) run on the mirrors against
`math.*`. cubit's functions are vendored unchanged onto the same-layout `FMag` type.

Algorithms:

- **sin / cos / sin_cos**: `(x + BIAS) divmod (pi/4)` then `divmod 8` gives octant and remainder in
  two constant `div_rem` (no sign branch, BIAS is a multiple of 2 pi above 2^63); `match` on the
  octant selects `z * Ps(z^2)` (degree 9) or `Pc(z^2)` (degree 10) on `[0, pi/4]`.
- **sin (LUT)**: same reduction, two const tables (sin and cos on `[0, pi/4]`, step 2^-10 rad,
  2 x 806 entries), one `div_rem` gives index and fraction, linear interpolation.
- **atan2**: `z = min/max` (one u128 division), `divmod 2^29` gives one of 8 segments and the local
  offset, `match` jump table to a degree-5 Horner per segment (constants inlined), octant fix-up
  with 3 branches. `atan(x) = atan2(x, 1)`.
- **acos / asin**: `acos(x) = sqrt(1 - |x|) * P10(|x|)`, `pi - .` for negative x; one core `sqrt`,
  no division. `asin = pi/2 - acos`.

| function | variant | l2_gas | steps | RC | max abs error | vs cubit precise |
|---|---|---:|---:|---:|---:|---|
| sin | cubit `sin` (Taylor recursion, 8 levels: 16 mul + 8 div) | 128 670 | 1 035 | 197 | 2.3e-8 | 1x |
| sin | cubit `sin_fast` (256-slot if-tree LUT + lerp) | 30 320 | 221-226 | 30 | 4.7e-6 | 4.2x cheaper, 200x less accurate |
| sin | **ours, Horner** | **18 420** | 124-140 | 28-32 | **4.7e-10** | **7.0x cheaper, 48x more accurate** |
| sin | ours, const-array LUT + lerp (2^-10 rad) | 12 680 | 92-94 | 17 | 1.2e-7 | 10x cheaper |
| cos | cubit `cos` (= `sin(pi/2 - x)`) | 133 520 | 1 066-1 070 | 199 | 2.3e-8 | 1x |
| cos | **ours, Horner** | **18 420** | 130-145 | 28-32 | 4.1e-10 | 7.2x |
| sin+cos | cubit (two calls) | 263 610 | 2 114 | 396 | | 1x |
| sin+cos | **ours `sin_cos`** (shared reduction and z^2) | **28 060** | 217-221 | 54 | | **9.4x** |
| atan | cubit `atan` (up to 2 divisions + degree-10 Horner) | 83 740 | 436-541 | 68-82 | 1.6e-9 | 1x |
| atan | cubit `atan_fast` (99-way if-chain + lerp) | 57 290 | 209-335 | 18-32 | 4.0e-6 | 1.5x |
| atan / atan2 | **ours** (cubit has no atan2) | **22 420** | 168-180 | 37 | **7.8e-10** | 3.7x cheaper, 2x more accurate |
| acos | cubit `acos` (mul, sqrt, div, sqrt, atan) | 113 810 | 683-767 | 120-128 | 2.9e-6 | 1x |
| acos | cubit `acos_fast` | 87 360 | 478-494 | 70-79 | 4.0e-6 | 1.3x |
| acos | **ours** | **25 740** | 205 | 52 | **7.6e-10** | **4.4x cheaper, 3 800x more accurate** |
| asin | cubit / **ours** | 97 620 / **26 580** | 544-687 / 212 | | - / 7.6e-10 | 3.7x |
| sqrt | core `u128_sqrt(raw << 32)` | 2 020 | 16 | 6 | exact floor | |

Accuracy vs size trade-offs measured offline (`results/trig_errors.md`):

| variant | max abs error |
|---|---:|
| sin/cos Horner, degree 7/8 (one coefficient less each, ~-1 500 gas) | 2.7e-9 |
| sin/cos Horner, degree 9/10 (benchmarked) and 11/12 | 4.7e-10 (floor: quantisation of the pi/4 constant, 2 ulp) |
| sin Horner for \|x\| <= 1000 rad (phase error of the Q32.32 pi/4 constant grows with \|x\|; same in cubit) | 3.9e-8 |
| sin LUT step 2^-8 / 2^-9 / **2^-10** / 2^-11 / 2^-12 rad (2 x 203 / 404 / **806** / 1 610 / 3 218 entries) | 1.9e-6 / 4.8e-7 / **1.2e-7** / 3.0e-8 / 7.7e-9 |
| atan2, 8 segments, degree 4 / **5** / 6 | 1.2e-8 / **7.8e-10** / 5.7e-10 |
| acos, degree 7 / **10** / 12 | 2.5e-8 / **7.6e-10** / 7.0e-10 |

Recommendations:

- **Default to the Horner versions.** They are within 1.5x of the LUT in cost, 250x more accurate,
  add ~20 constants instead of 1 600 table entries to the bytecode, and their cost is
  input-independent. Offer the LUT only if a profile shows `sin` dominating and 1e-7 is acceptable.
- Expose **`sin_cos`** (rotations always need both: 28 060 vs 36 840 for two calls).
- `acos` via `sqrt(1 - x) * P(x)` exploits the unusually cheap core sqrt and is accurate at the
  end points, where cubit's `atan(a / sqrt(1 - a^2))` loses 4 digits.
- CORDIC was not implemented: 32 iterations x (2 shifts = 2 divmods at ~1 100 + loop overhead
  ~1 300 + compares) is > 120 000 gas by construction from the primitive table, i.e. worse than
  cubit's Taylor version.
- `exp` / `ln` were not measured (time); the same recipe applies (constant `div_rem` for the
  integer part / a 6-step comparison search for the msb, const-array powers of two, degree-8
  Horner at ~1 500 gas per coefficient => expected ~20 000 gas each).

---

## 5. Gas tracking in the repo and in CI

snforge 0.61 has **no snapshot feature** (checked `snforge --help`, `snforge test --help`:
`--gas-report` is contract-only, `optimize-inlining` is contract-only). Proposed mechanism, already
implemented in the bench project (`scripts/bench.py`, ~170 lines of dependency-free Python):

```bash
python3 scripts/bench.py run [FILTER]        # both modes -> results/results.{md,csv}, results/raw/*.txt
python3 scripts/bench.py snapshot            # -> ./gas-snapshot (committed)
python3 scripts/bench.py check [--tolerance PCT]   # exit 1 + list of ADDED/REMOVED/CHANGED benches
```

`gas-snapshot` is a sorted text file, one line per benchmark, reviewable in a PR diff like
foundry's `.gas-snapshot`:

```
# bench: l2_gas steps range_check bitwise other_builtins memory_holes
composite::i64b::mat4_mul_mat4: 47230 407 80 0 0 0
scalar::i64b::mul: 2050 17 5 0 0 0
```

It was exercised for real during this work: after force-inlining one helper, `check` reported
exactly `CHANGED prims::rescale_i64_v2_sign_split_u128: l2_gas 7630 -> 6580 (-13.76%)` and nothing
else. Because results are deterministic, **tolerance 0 is usable**; any diff is a real codegen
change (ours, or a compiler upgrade, which is exactly when one wants to look).

CI job:

```yaml
- uses: software-mansion/setup-scarb@v1      # versions from .tool-versions
- uses: foundry-rs/setup-snfoundry@v4      # (check the current major) versions from .tool-versions
- run: ./scripts/run_all.sh check             # regenerate sources, correctness tests, snapshot check
```

Conventions to keep when this becomes the repo harness: benchmarks are `X__base` / `X__op` test
pairs; inputs always through `#[inline(never)]` constructors; one `#[inline(never)]` wrapper per
public kernel so the number is what a caller pays; correctness tests live next to the benchmarks
(a benchmark of wrong code is worthless: three of the bounded-int mistakes made here compiled
fine at the semantic level and only failed at Sierra generation).

---

## 6. Coding rules derived from the measurements

1. Scalar = `i64` newtype, Q32.32, floor; no sign-magnitude, no u256, no Q64.64.
2. Multiply with `bounded_int::mul` / `wide_mul` (1 step) and rescale **once per output scalar**,
   not once per product. `length` = `u128_sqrt` of the raw sum of squares.
3. `#[inline(always)]` on every scalar operator and kernel helper; keep public kernels as the only
   call boundaries. Avoid generic free functions for hot code (E2143).
4. Prefer `nopanic`-able formulations (bounded ints, felts) inside kernels; a panicking call
   boundary costs ~2 000 gas.
5. No loops for fixed-size work (3.6x); no `Array`/`Span` storage for vectors and matrices (9x).
6. No bitwise ops. Masks and shifts are `DivRem` by a constant power of two (1 010-1 210, gives
   both halves). Never `pow(2, n)` at runtime (15 000): const-array of powers.
7. Tables are `const [T; N]` + `.span()[i]` (1 270, size-independent); dispatch is `match` on a
   small integer (2 370). Never if-chains / if-trees.
8. Stay <= 64-bit operands (products <= 128 bits); crossing into u128 multiplication or u256
   costs 5-25x.
9. `wrapping_*`/`checked_*`/`saturating_*`/`overflowing_*` are all more expensive than the plain
   panicking operators; use them only for semantics, never for speed.
10. Transcendentals: constant-divisor range reduction + Horner, coefficients generated by script
    with a bit-exact mirror for error sweeps.

## 7. Caveats

- Numbers are for cairo 2.19.4 / snforge 0.61.0; libfunc costs and the inliner change between
  compiler releases (that is what the snapshot is for).
- Costs are inline marginal costs (`op - base`) with +-1 step noise; composites and trig include
  one call boundary. Sierra gas is a worst-sibling-branch figure; steps are for the inputs used
  (sign-magnitude code is path-dependent: mixed-sign inputs were used, which is its typical case).
- `l2_gas` here is the Sierra gas of the test body delta; a contract call adds its own fixed
  overhead (entry point, calldata deserialisation, syscalls) which is outside the scope of a math
  library.
- Bytecode size (declare cost, class size limits) was not measured; `inline(always)` and 8
  inlined Horner segments trade bytecode for execution gas. The sin/cos LUT variant costs 1 612
  felts of data.
- Rounding differs between candidates (floor for C/E/D, truncation for A/B); correctness tests
  accept +-1 ulp on scalar ops.
- The `i64b` division and the `felt` division reuse the same kernel; a cheaper floor division is
  blocked by current bounded-int restrictions (section 2.8).
- The Q16.16 variant was not implemented; its cost equality with Q32.32 is inferred from the
  primitive table (identical costs for all <= 64-bit types).
- The orion `Tensor` comparison is a proxy (Span + loops), not orion's code, which does not build
  on scarb 2.19.
