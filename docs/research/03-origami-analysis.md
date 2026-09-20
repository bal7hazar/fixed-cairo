# 03 - dojoengine/origami analysis

Reference study of [`dojoengine/origami`](https://github.com/dojoengine/origami) as an
architecture and code-efficiency reference for `glam.cairo`.

- Commit analysed: `1ddafcb` ("chore: bump dojo version"), tag `v1.7.0`, shallow clone.
- Toolchain pinned by the repo: `scarb 2.12.2` / Cairo 2.12.2 / Sierra 1.7.0, edition `2024_07`.
- All file paths below are relative to the origami repository root.
- All gas numbers are `cairo-test` "gas usage est." values produced locally with scarb 2.12.2
  (`scarb test -p <package>`). See section 4 for what that metric means and its limits.

Contents:

1. Workspace architecture
2. `crates/algebra` in depth
3. Catalog of efficiency idioms (with code and measurements)
4. How origami tests / tracks gas
5. Recommendations and rules for glam.cairo
6. Appendix: micro-benchmark used to validate the idioms

---

## 1. Workspace architecture

### 1.1 Layout

```
origami/
  Scarb.toml            # virtual workspace manifest
  Scarb.lock
  .tool-versions        # scarb 2.12.2 (asdf)
  .github/workflows/    # ci.yml, release.yaml
  scripts/build-all.sh  # stale (references removed packages)
  crates/
    algebra/   origami_algebra   vec2, vector, matrix          (dep: cubit)
    defi/      origami_defi      GDA / VRGDA auctions          (dep: cubit, starknet)
    map/       origami_map       bit-packed grid maps, generators, path finders, hex
    random/    origami_random    dice, deck                    (poseidon-seeded)
    rating/    origami_rating    Elo
    security/  origami_security  commit/reveal
    Scarb.toml                   # leftover umbrella package "origami" (not a workspace member)
```

Root `Scarb.toml`:

```toml
[workspace]
members = [
    "crates/contracts",   # directory does not exist anymore; scarb tolerates it
    "crates/algebra", "crates/defi", "crates/map",
    "crates/random", "crates/rating", "crates/security",
]

[workspace.package]
version = "1.1.2"
edition = "2024_07"

[workspace.dependencies]
cubit = { git = "https://github.com/bengineer42/cubit", branch = "bump-cairo-gt-2.8" }
starknet = "^2.12.2"
cairo_test = "^2.12.2"
```

Each crate manifest is minimal and inherits from the workspace:

```toml
[package]
name = "origami_map"
version.workspace = true
edition.workspace = true

[dev-dependencies]
cairo_test.workspace = true
```

Observations:

- One package per domain, `origami_<domain>` naming, zero inter-crate dependencies. `map`, `random`,
  `rating`, `security` are dependency-free pure Cairo (no `starknet`, no `dojo`). Only `algebra` and
  `defi` pull `cubit` (fixed point), and only `defi` pulls `starknet` (for `starknet::Store` derive).
  This is the good part to copy: a math library must be consumable without dragging Starknet/Dojo in.
- The fixed-point dependency is a **fork on a branch** (`bengineer42/cubit#bump-cairo-gt-2.8`), not a
  tag, not a registry package. This is a supply-chain and reproducibility smell (the lock file pins
  the commit for origami itself, but downstream users re-resolve the branch).
- Housekeeping debt is visible: a workspace member that no longer exists (`crates/contracts`), a
  stale `.gitmodules` (points to `examples/bridge/...`), a stale `scripts/build-all.sh`
  (`origami_token`, `origami_governance`), a leftover `crates/Scarb.toml` depending on `dojo`. The
  README still says "Physics (WIP)" with no physics crate in the tree.

### 1.2 Test layout

- Unit tests only, colocated at the bottom of each source file in `#[cfg(test)] mod tests { ... }`.
  No `tests/` directories, no integration tests, no snforge. The runner is `cairo-test`
  (`scarb test` -> `scarb cairo-test`).
- 75 tests in `origami_map`, 21 in `origami_algebra`.
- Tests of generators assert on a single golden `felt252` for a given seed, with the expected grid
  drawn as ASCII art in a comment (`crates/map/src/map.cairo`, `generators/*.cairo`). It is a cheap
  and very readable way of pinning deterministic output.
- Test-only helpers are gated: `#[cfg(target: "test")] pub mod printer;` in `crates/map/src/lib.cairo`.

### 1.3 CI

`.github/workflows/ci.yml`: `scarb fmt --check` -> `scarb build` -> one job per package running
`scarb test --package origami_<x>` (jobs fan out in parallel after `check` and `build`).
`release.yaml` only creates a GitHub release when a `v*` tag is pushed. There is no gas/step
reporting, no snapshot, no regression gate (see section 4).

### 1.4 Downstream consumption

Documented way (root README and each crate README) is a git dependency on the default branch:

```toml
[dependencies]
origami_map = { git = "https://github.com/dojoengine/origami" }
```

Tags exist (`v1.7.0`) but they follow the **Dojo** release train, not the crate version
(`[workspace.package] version = "1.1.2"`), so the tag and the package version disagree. Nothing in the
repo publishes to the scarbs.xyz registry (no publish workflow, READMEs only mention git).
For glam.cairo: tag releases with the crate's own semver and plan for registry publication, because a
git dependency on `main` gives downstream users no stability guarantee.

---

## 2. `crates/algebra` in depth

Three files: `vec2.cairo` (260 lines, 160 of them tests), `vector.cairo` (112), `matrix.cairo` (384).

### 2.0 Blocking defect: the crate cannot be used from outside

`crates/algebra/src/lib.cairo`:

```cairo
mod matrix;
mod vec2;
mod vector;
```

Modules, structs and traits are all declared without `pub`. Under edition `2024_07` visibility is
enforced, so a downstream package fails to compile (verified locally with a path dependency):

```
error: Item `origami_algebra::vec2` is not visible in this context.
error: Item `origami_algebra::vec2::Vec2` is not visible in this context.
```

In other words the algebra crate compiles and its own tests pass, but it is effectively dead code
for consumers. This tells us it has no real users and has not been exercised for performance; treat
it as a sketch, not as a battle-tested reference. (The `map` crate, by contrast, is `pub` throughout
and is used in production games.)

### 2.1 `Vec2<T>`

```cairo
struct Vec2<T> { x: T, y: T }

impl Vec2Copy<T, impl TCopy: Copy<T>> of Copy<Vec2<T>>;
impl Vec2Drop<T, impl TDrop: Drop<T>> of Drop<Vec2<T>>;

trait Vec2Trait<T> {
    fn new(x: T, y: T) -> Vec2<T>;
    fn splat(self: T) -> Vec2<T>;
    fn select(mask: Vec2<bool>, if_true: Vec2<T>, if_false: Vec2<T>) -> Vec2<T>;
    fn dot<impl TMul: Mul<T>, impl TAdd: Add<T>>(self: Vec2<T>, rhs: Vec2<T>) -> T;
    fn dot_into_vec<impl TMul: Mul<T>, impl TAdd: Add<T>>(self: Vec2<T>, rhs: Vec2<T>) -> Vec2<T>;
    fn xy(self: Vec2<T>) -> Vec2<T>;  // + xx, yx, yy
}

impl Vec2Impl<T, impl TCopy: Copy<T>, impl TDrop: Drop<T>> of Vec2Trait<T> { ... }
```

What is there:

- A generic struct of named fields, by-value (`Copy`) semantics, glam-like naming (`splat`, `select`,
  swizzles, `dot_into_vec`). The API surface is a direct, faithful transliteration of glam's `Vec2`.
- Generic bounds are split in two levels: the impl requires only `Copy<T> + Drop<T>`, and the math
  methods add their own per-method bounds (`dot<impl TMul: Mul<T>, impl TAdd: Add<T>>`). This keeps
  `Vec2<bool>` usable as a mask type (`BVec2` in glam) with the same struct, which is neat.
- `#[inline(always)]` on constructors, `select`, swizzles.

What is missing / awkward:

- **No operator overloading at all** on `Vec2` (`Add`, `Sub`, `Mul`, `Div`, `Neg`, `PartialEq` are
  not implemented). No `length`, `normalize`, `cross`/`perp_dot`, `min`/`max`, `abs`, `lerp`...
  The implementation stops at `dot`. `Vec3`, `Vec4`, `Mat*`, `Quat` do not exist.
- The source carries this comment on `dot`:
  `// #[inline(always)] is not allowed for functions with impl generic parameters.` That was a
  limitation of older compilers and the workaround (method-level impl generics, no inline) stayed.
  The consequence is that the one method that matters for performance is the one that is not inlined.
- Method-level generic bounds make call sites and trait signatures verbose, and every new math method
  has to restate its bounds. The modern spelling (`+Mul<T>, +Add<T>`, anonymous impls) is not used in
  this file, although `vector.cairo`/`matrix.cairo` use it.
- Tests only instantiate `T = cubit::f128::Fixed` (sign-magnitude Q64.64, `struct { mag: u128, sign: bool }`)
  and `T = bool`. With `Fixed`, a single `Vec2::dot` test costs **75,070 gas**, i.e. two fixed-point
  multiplications plus one sign-magnitude addition. For comparison a struct-based `u128` dot product
  measures ~10,900 gas in the same harness (appendix). The scalar type, not the vector wrapper,
  dominates the cost (see 2.4).

### 2.2 `Vector<T>` (dynamic length)

```cairo
#[derive(Copy, Drop)]
struct Vector<T> { data: Span<T> }

impl VectorImpl<T, +Mul<T>, +AddAssign<T, T>, +Zero<T>, +Copy<T>, +Drop<T>> of VectorTrait<T> {
    fn get(ref self: Vector<T>, index: u8) -> T {
        *self.data.get(index.into()).expect(errors::INVALID_INDEX).unbox()
    }
    fn dot(mut self: Vector<T>, mut vector: Vector<T>) -> T {
        assert(self.size() == vector.size(), errors::INVALID_SIZE);
        let mut value = Zero::zero();
        loop {
            match self.data.pop_front() {
                Option::Some(x_value) => {
                    let y_value = vector.data.pop_front().unwrap();
                    value += *x_value * *y_value;
                },
                Option::None => { break value; },
            };
        }
    }
}
```

- Span-backed, so `Copy` is cheap (a span is two pointers), and `dot` uses the idiomatic
  `pop_front` iteration (no index arithmetic, no bounds check per access). That part is fine.
- `Add`/`Sub` allocate a fresh `Array<T>` and go through the bounds-checked `get(index)` with a `u8`
  index converted to `u32` on every access. `get` takes `ref self` for no reason (forces `mut`
  bindings at call sites, visible in the tests: `let mut vector`).
- The bound list is the same superset on every impl (`VectorAdd` requires `+Mul<T>` and
  `+AddAssign<T, T>` although it only adds) because the impls call `VectorTrait` methods and therefore
  must satisfy `VectorImpl`'s bounds. This is the main ergonomic trap of generic Cairo: **bounds are
  transitive through the impl you call, not through the method you call**.

### 2.3 `Matrix<T>`

```cairo
#[derive(Copy, Drop)]
struct Matrix<T> { data: Span<T>, rows: u8, cols: u8 }

impl MatrixImpl<T, +Mul<T>, +Div<T>, +Add<T>, +AddAssign<T, T>, +Sub<T>, +SubAssign<T, T>,
                +Neg<T>, +Zero<T>, +Copy<T>, +Drop<T>> of MatrixTrait<T> { ... }
```

- Row-major `Span<T>` plus runtime dimensions; `Add`, `Sub`, `Mul` operators are implemented, plus
  `transpose`, `minor`, `det`, `inv`.
- Every operation is a runtime loop over a linear index with `index / cols` and `index % cols`
  (a `u8` divmod per element) and a bounds-checked `get`:

  ```cairo
  let row = index / lhs.cols;
  let col = index % lhs.cols;
  values.append(lhs.get(row, col) + rhs.get(row, col));
  ```

- `det` is the recursive Laplace expansion, allocating a new `Array` for each minor; `inv` computes
  `rows * cols` minors, each calling `det` recursively. It is O(n!) and allocation-heavy.
  Measured (T = `i128`): `det 2x2` 25,300 gas, `det 3x3` 312,070 gas, `inverse 2x2` 218,120 gas,
  `inverse 3x3` **1,230,370 gas**, `2x2 * 2x2` 159,600 gas. A hand-unrolled fixed-size `Mat3`
  inverse on the same scalar would be an order of magnitude or more below that.
- `inv` also has a correctness smell: it writes `cofactor / determinant` at the linear index computed
  with `col = index / rows; row = index % rows` to get the transposed (adjugate) layout implicitly;
  it works for square matrices but there is no squareness assert in `inv` itself (only inside `det`).
- `u8` dimensions: `rows * cols` is computed in `u8`, so anything beyond 255 elements panics with an
  overflow rather than a domain error.

### 2.4 Fixed point usage (cubit)

`algebra` uses cubit only in tests (as the `T` of `Vec2<T>`); `defi` uses it for real
(`exp`, `pow`, `ln` in GDA/VRGDA). Relevant facts about `cubit::f128::Fixed`:

```cairo
struct Fixed { mag: u128, sign: bool }        // sign-magnitude Q64.64

fn mul(a: Fixed, b: Fixed) -> Fixed {
    let res_u256 = a.mag.wide_mul(b.mag);
    let (scaled_u256, _) = u256_safe_div_rem(res_u256, u256_as_non_zero(ONE_u256));
    assert(scaled_u256.high == 0, 'result overflow');
    FixedTrait::new(scaled_u256.low, a.sign ^ b.sign)
}

fn add(a: Fixed, b: Fixed) -> Fixed {         // 3 branches
    if a.sign == b.sign { return FixedTrait::new(a.mag + b.mag, a.sign); }
    if a.mag == b.mag { return FixedTrait::ZERO(); }
    if (a.mag > b.mag) { FixedTrait::new(a.mag - b.mag, a.sign) } else { FixedTrait::new(b.mag - a.mag, b.sign) }
}
```

- Every multiplication goes through a **u256 division** by 2^64, the single most expensive primitive
  in the measurements below (~19.6k gas for the mul alone versus ~5.5k for a Q32.32 product that stays
  in `u128`).
- Every addition is a 3-way branch on sign and magnitude (~6.3k gas versus ~2.7k for a native `i128`
  or `u128` add).
- A `Vec2<Fixed>` is 4 felts wide (2 x (mag, sign)); a `Mat4<Fixed>` would be 32 felts copied around.

Conclusion for glam.cairo: **do not build on cubit f128 and do not make sign-magnitude the scalar
representation**. The scalar design (width, signedness encoding, where the range checks go) is the
first-order cost driver; it must be decided and benchmarked before any vector code is written.

### 2.5 Assessment: reuse vs do differently

Reuse:

- Struct-of-named-fields layout for fixed-size vectors (`Vec2 { x, y }`), by-value `Copy` semantics.
- glam-faithful naming and method set as the API contract (`new`, `splat`, `select`, swizzles,
  `dot_into_vec`), and `Vec2<bool>` as the mask type.
- Splitting bounds: keep `Copy + Drop` on the type, put arithmetic bounds only where needed.
- Error constants in a `mod errors` with `'Type: message'` short strings.

Do differently:

- Make everything `pub` and add a downstream "consumer" smoke test so visibility regressions are
  caught (origami's algebra crate has been unusable without anyone noticing).
- Implement `core::traits::{Add, Sub, Mul, Div, Neg, PartialEq}` plus `AddAssign` etc. for every type;
  glam users expect `a + b * s`.
- No `Span`-backed, runtime-dimension matrices in the hot path. `Mat2/3/4`, `Quat`, `Affine*` must be
  fixed-size structs with fully unrolled arithmetic and closed-form `determinant`/`inverse`.
  A generic `MatN`/`VecN`, if ever wanted, is a separate, explicitly slow module.
- Be careful with "generic over T" as the primary design. It costs little at runtime (Cairo
  monomorphizes), but it (a) prevents scalar-specific tricks such as accumulating a dot product in
  `felt252` and range-checking once, deferred rescaling of fixed-point products, or sharing one
  overflow check for a whole vector op, and (b) produces transitive bound lists like
  `MatrixImpl<T, +Mul, +Div, +Add, +AddAssign, +Sub, +SubAssign, +Neg, +Zero, +Copy, +Drop>`
  repeated on every impl. glam itself is not generic: it generates concrete `Vec2`, `DVec2`, `IVec2`,
  `UVec2`... from templates. Mirroring that (concrete types per scalar, shared trait names, code
  generated or macro-expanded from one template) fits Cairo better than `Vec2<T>`.
- `#[inline(always)]` on the small arithmetic kernels, which requires them not to be generic-impl
  methods in the origami style; with concrete types this limitation disappears entirely.

---

## 3. Efficiency idioms catalog

The `map` crate is where the care went. Its central design choice: **a whole grid (up to 252 cells)
is one `felt252` bitmap**, all generators and finders work on that single value, and a position is a
single `u8` (`index = y * width + x`).

Each idiom below has: what it is, a quote with its path, and a verdict for glam.cairo. "Measured"
refers to the micro-benchmark of the appendix (scarb 2.12.2, cairo-test gas estimate, black-boxed
inputs; net = after subtracting the harness overhead).

### 3.1 Pack state into one felt, pass scalars instead of collections

`crates/map/src/map.cairo`:

```cairo
#[derive(Copy, Drop)]
pub struct Map { pub width: u8, pub height: u8, pub grid: felt252, pub seed: felt252 }
```

`crates/map/src/types/direction.cairo` packs a permutation of 4 directions in a `u32`, 4 bits each,
and pops with `%` and `/`:

```cairo
pub const DIRECTION_SIZE: u32 = 0x10;

fn pop_front(ref directions: u32) -> Direction {
    let direciton: u8 = (directions % DIRECTION_SIZE).try_into().unwrap();
    directions /= DIRECTION_SIZE;
    direciton.into()
}
```

Verdict: excellent for storage and for passing sets of small values without arrays. For glam.cairo
this is relevant to `BVec*` masks (a `u8` bitmask instead of `Vec4<bool>` is an option to benchmark)
and to `StorePacking` of vectors, not to hot-path arithmetic: unpacking costs a divmod per field, so
keep vectors unpacked (struct of fields) in memory and pack only at the storage boundary.

### 3.2 Bit access via division and modulo by a power of two (no bitwise builtin)

`crates/map/src/helpers/bitmap.cairo`:

```cairo
fn get(x: felt252, index: u8) -> u8 {
    let x: u256 = x.into();
    let offset: u256 = TwoPower::pow(index);
    (x / offset % 2).try_into().unwrap()
}

fn set(x: felt252, index: u8) -> felt252 {
    let x: u256 = x.into();
    let offset: u256 = TwoPower::pow(index);
    let bit = x / offset % 2;
    let offset: u256 = offset * (1 - bit);     // branchless: add 2^i only if the bit is 0
    (x + offset).try_into().unwrap()
}

fn unset(x: felt252, index: u8) -> felt252 {
    ...
    let offset: u256 = offset * bit;           // branchless: subtract 2^i only if the bit is 1
    (x - offset).try_into().unwrap()
}
```

Two idioms in one: shifts are `/ 2^n` and `* 2^n`, masks are `% 2^n`; and set/unset are
**branchless arithmetic** (`offset * (1 - bit)`) instead of `if`. Same in the popcount kernel:

```cairo
fn _popcount(mut x: u32) -> u8 {
    x -= ((x / 2) & 0x55555555);
    x = (x & 0x33333333) + ((x / 4) & 0x33333333);
    x = (x + (x / 16)) & 0x0f0f0f0f;
    x += (x / 256);
    x += (x / 65536);
    return (x % 64).try_into().unwrap();
}
```

(shifts by division; `&` kept only where a true mask across all bits is needed; note it chunks the
u256 into u32 words with `% 0x100000000` and `/= 0x100000000` so the SWAR kernel runs on a cheap type.)

Verdict: adopt "shift = mul/div by a power-of-two constant" as a rule (the Cairo VM has no shift instruction, so any shift is ultimately a mul/div by a power of two; a
loop-based shift is the worst option).
But the origami implementation leaves a lot on the table by **doing it in `u256`**: measured,
`x / p % 2` costs ~13,300 gas net in `u256` versus ~3,260 in `u128` and ~2,320 in `u64`. Origami's
own `test_bitmap_get` costs 15,540 gas and `test_bitmap_set` 34,350 gas for a single bit. For a 252-bit
grid a split into two `u128` limbs would be roughly 3-4x cheaper per access.

On "division vs bitwise": in the same harness a single `x & p` on `u128` measured ~880 gas net, i.e.
**cheaper than the `/` + `%` pair (~3,260)** under cairo-test's cost table (bitwise builtin = 583 gas,
range check = 70, step = 100). Under the legacy Starknet VM-resource fee weights the bitwise builtin
was weighted 64 steps versus 16 for a range check, which is where the "avoid the bitwise builtin"
folklore (and origami's style) comes from; with those weights the two are roughly on par and division
wins when the quotient and remainder are both needed (one `DivRem` gives both). Practical rule: the
owner's ordering (arithmetic > bitwise > loops) is a sound default, but single-mask extraction is
exactly the kind of case where the benchmark, under the metric we decide to optimize, must arbitrate.

### 3.3 Precomputed powers of two in a const fixed-size array

`crates/map/src/helpers/power.cairo`:

```cairo
const TWO_POWER: [u256; 256] = [ 0x1, 0x2, 0x4, 0x8, ... ];

#[inline]
fn pow(exp: u8) -> u256 {
    *TWO_POWER.span().at(exp.into())
}
```

A const array compiles to a data segment; `.span().at(i)` is a bounds check plus a memory read, O(1)
whatever the exponent. Measured on an 8-entry table: const-array lookup 4,070 gas, equivalent `match`
2,170 gas, `while`-loop pow (exp = 7) 34,870 gas (all including call overhead). So:

- table or `match` instead of computing: yes, always, by an order of magnitude;
- for small dense tables a `match` on the integer (compiled to a jump table) beat the const array in
  this measurement; for large tables (256 entries) the const array is the more compact choice. Benchmark
  per table.
- origami's table is `u256` because the grid is; a `u128` table halves the element size and makes the
  downstream arithmetic 3-4x cheaper (3.2).

### 3.4 Lookup table via `match` instead of computing (permutations, enum conversions)

`crates/map/src/types/direction.cairo` replaces a Fisher-Yates shuffle (loop + 3 modulos + array
writes) by one modulo and a 24-arm `match` over all permutations of 4 directions, each packed in a
`u32`:

```cairo
fn compute_shuffled_directions(seed: felt252) -> u32 {
    let mut random: u32 = (seed.into() % 24_u256).try_into().unwrap();
    match random {
        0 => 0x2468,
        1 => 0x2486,
        ...
        22 => 0x8624,
        _ => 0x8642,
    }
}
```

Verdict: adopt. Applies to glam.cairo for trig (`sin`/`cos`/`atan` seeds and LUTs), `sqrt`/`rsqrt`
initial guesses, swizzle index tables, axis enums.

### 3.5 Manual unrolling of fixed-count loops

`crates/map/src/finders/astar.cairo` (same pattern in `mazer.cairo`, `walker.cairo`, `digger.cairo`)
writes the 4-direction loop out by hand:

```cairo
let direction: Direction = DirectionTrait::pop_front(ref directions);
if Finder::check(grid, width, height, current.position, direction, ref visited) {
    let neighbor_position = direction.next(current.position, width);
    Self::assess(width, neighbor_position, current, target, ref heap);
}
let direction: Direction = DirectionTrait::pop_front(ref directions);
if Finder::check(...) { ... }
// ... 4 times
```

and `caver.cairo` unrolls the 8-neighbour count into `count_direct_floor` + `count_indirect_floor`
with one `if` per neighbour. `bitmap.cairo::least_significant_bit` is a fully unrolled 8-step binary
search (128, 64, 32, ... 1) instead of a bit-by-bit scan loop.

Measured: summing 4 terms unrolled 6,150 gas versus 14,010 with a `while` loop (call overhead
included, so the real ratio on the loop body is larger). Every loop iteration in Cairo pays a
recursive function call, the counter update, the exit test and gas-withdrawal bookkeeping.

Verdict: hard rule for glam.cairo. Dimensions are 2, 3, 4: **no loops anywhere in Vec/Mat/Quat
arithmetic**. `Mat4 * Mat4` is 16 explicit dot products.

### 3.6 Tail recursion with early `return` instead of loop + flags

`crates/map/src/generators/walker.cairo`:

```cairo
fn iter(width: u8, height: u8, start: u8, mut steps: u16, ref grid: felt252, seed: felt252) {
    if steps == 0 { return; }
    steps -= 1;
    grid = Bitmap::set(grid, start);
    ...
    if Self::check(grid, width, height, start, direction) {
        let start = Mazer::next(width, start, direction);
        return Self::iter(width, height, start, steps, ref grid, seed);
    }
    ...
}
```

and `spreader.cairo::iter` takes `mut grid: felt252` by value and returns it. State travels as
function arguments (`ref grid: felt252`, a single felt), never as a collection.

Verdict: relevant mostly for iterative numeric routines (Newton iterations for `sqrt`/`rsqrt`,
CORDIC): prefer a fixed, unrolled number of iterations; if a loop is unavoidable, use `while i != n`
rather than `while i < n` (measured 35,410 vs 41,400 gas for 16 iterations: `!=` is a felt equality
test, `<` costs a range check per iteration).

### 3.7 Short-circuit ordering: cheap tests first

`crates/map/src/generators/mazer.cairo`:

```cairo
Direction::North => (y < height - 2)
    && (x != 0)
    && (x != width - 1)
    && (Bitmap::get(maze, position + 2 * width) == 0)   // expensive u256 divmods last
    && (Bitmap::get(maze, position + width + 1) == 0)
    && (Bitmap::get(maze, position + width - 1) == 0)
    && (order == 0 || Bitmap::get(maze, position + 2 * width + 1) == 0)
    && (order == 0 || Bitmap::get(maze, position + 2 * width - 1) == 0),
```

Bounds tests on `u8` come before the bitmap reads; `order == 0 ||` skips two reads in the common
case. Same in `astar.cairo::search`: the walkability of `from`/`to` is checked before any allocation
(`return array![].span();`).

Verdict: adopt where branching exists (intersection tests, `normalize_or_zero`, `clamp_length`...).
Note the flip side: data-independent straight-line code is often better than branching for tiny ops
(3.2's branchless set/unset), because both branches of an `if` must be aligned on the same
builtin/AP state and the merge has a cost. Benchmark both when the branch body is a few instructions.

### 3.8 Whole-word bitwise ops instead of per-cell loops

Where an operation touches every cell, origami does use the bitwise builtin, once, on the whole grid:

```cairo
// crates/map/src/generators/mazer.cairo
let merge: u256 = grid.into() | maze.into();
maze = merge.try_into().unwrap();

// crates/map/src/generators/spreader.cairo
let objects: u256 = grid.into() ^ merge.into();
```

This is precisely the owner's ordering: arithmetic where possible (3.2), a bitwise op when it
replaces a loop, loops last.

### 3.9 Use the narrowest adequate integer type; keep hot values out of u256

Used well: positions/dimensions are `u8`, costs `u16`, packed directions `u32`, popcount kernel `u32`.
Used badly: every bitmap access converts `felt252 -> u256` and divides in `u256`
(`let x: u256 = x.into();` at the top of `get`, `set`, `unset`, `popcount`, `least_significant_bit`),
then converts back with `try_into().unwrap()`. Measured unit costs (net, cairo-test gas):

| op | felt252 | u64 | u128 | i128 | u256 |
|---|---|---|---|---|---|
| add | ~0 | 1,470 | 1,470 | 1,570 | - |
| mul | ~0 | 1,470 | 4,030 | 8,590 | 15,280 |
| div | n/a | 1,410 | 1,880 | 5,190 | 7,150 |
| `<` | n/a | - | 780 | 780 | - |
| `/ p % 2` | n/a | 2,320 | 3,260 | - | 13,300 |
| `& p` | n/a | - | 880 | - | 2,270 |

Conversions: `u128 -> felt252` is free (no-op upcast); `felt252 -> u256` ~1,900;
`felt252 -> u128` (`try_into`) ~2,200. Sign-magnitude add (cubit style) ~5,050 versus 1,570 for `i128`.

Readings that matter for glam.cairo:

- `felt252` arithmetic is nearly free; all the cost of integer types is the range checks. Hence the
  trick (not used by origami, validated in the appendix): **accumulate in `felt252`, range-check
  once**. A 3-component `u64` dot product measured 7,350 gas with checked `u64` ops versus 6,410 when
  the three products are summed as felts and converted back once; the gap grows with the number of
  intermediate operations.
- `u64 * u64` is as cheap as an addition (the product fits a felt, one range check), `u128 * u128`
  is ~3x, `i128 * i128` ~6x, `u256` ~10x. A Q32.32-in-`u64`-style scalar whose products stay within
  `u128` is fundamentally cheaper than Q64.64-in-`u128` whose products need `u256`:
  fixed-point mul measured 5,550 gas (u64 operands, one `u128` division) versus 19,640 (cubit-style
  `u128.wide_mul` + `u256` div) and 19,140 (wide_mul + limb recombination without u256 division).
- Native `i128` add and compare are cheap, but `i128` mul and div are expensive in 2.12; the
  signedness encoding (native signed ints vs offset/biased unsigned vs sign-magnitude) must be
  benchmarked per operation mix. Sign-magnitude is the worst for add/sub.

### 3.10 Avoid array allocations; dictionaries only where random access is unavoidable

Good: generators never allocate, they thread a `felt252`. `Heap<T>` (`helpers/heap.cairo`) stores both
directions of the key/index mapping in **one** `Felt252Dict<u8>` by offsetting one keyspace:

```cairo
const KEY_OFFSET: felt252 = 252;
/// The keys of the items in the heap and also the indexes of the items in the data.
/// Both information is stored in the same map to save gas.
pub keys: Felt252Dict<u8>,
...
self.keys.insert(index.into(), key);
self.keys.insert(key.into() + KEY_OFFSET, index);
```

(each dict costs a squash at destruction; one dict instead of two is a real saving.)

Bad (counter-examples in the same repo): `crates/map/src/hex.cairo::neighbors` builds an `Array<Hex>`
of 6 on every call, `is_neighbor` allocates that array just to compare, and `tiles_within_range` does
a linear scan of `visited` for every neighbour plus `queue = next_queue.clone()`
(`test_tiles_within_range`: 9.5M gas). The algebra `Matrix` allocates a new array per operation and per
minor. Struct-vs-span measured: `dot` on a 2-field struct 10,930 gas versus 17,710 for the span
version (array construction included).

Verdict: glam types are structs of scalar fields, returned by value; no `Array`/`Span`/`Felt252Dict`
in the core library. Slices only appear in explicit `from_slice`/`to_array` conversions.

### 3.11 By-value `Copy` structs, snapshots only for non-Copy types

Everything small is `#[derive(Copy, Drop)]` and passed by value (`Map`, `Node`, `Hex`). Snapshots show
up only where the type is not `Copy` (`Heap`: `fn is_empty(self: @Heap<T>)`), or where a core trait
imposes them (`PartialEq::eq(lhs: @Node, rhs: @Node)`). `ref` is used for in-place mutation of a single
felt (`ref grid: felt252`) or of the heap.

Measured: `V3 + V3` by value and by snapshot cost the same when not inlined (6,910 gas both); by-value
with inlining 4,610. Snapshots of `Copy` structs buy nothing and add `*` noise.

Verdict: `self: Vec3` by value everywhere, as in glam. Open question to benchmark for the wide types
(`Mat4` = 16 scalars, 32 felts if the scalar is 2 felts wide): struct copies in Cairo are
compile-time variable moves when inlined, but crossing a non-inlined call boundary copies every felt.
This is another argument for a 1-felt scalar.

### 3.12 Inlining

83 `#[inline]` and 13 `#[inline(always)]` in the repo; practically every method of the map crate is
`#[inline]`, including large ones (`Astar::search`, recursive `iter` functions where it is meaningless).
`#[inline(always)]` is reserved for trivial constructors/getters (`Vec2::new`, `Dice::roll`, `Deck::draw`).

Measured: a 3-field vector add costs 4,610 gas inlined (`#[inline(always)]` and the default heuristic
gave the same result for this small body) versus 6,910 with `#[inline(never)]`: the call overhead is
about as large as the work for small kernels. Inlining also unlocks constant folding across the call.

Verdict: `#[inline(always)]` on every leaf arithmetic kernel (component-wise ops, `dot`, `cross`,
scalar mul/add), `#[inline]` (hint) or nothing on composite functions (`Mat4::inverse`,
`Quat::slerp`) where code-size growth of the Sierra program matters (contract class size limits).
Blanket `#[inline]` on everything, origami-style, is cargo cult; decide per function with numbers.

### 3.13 Integer-only scaled math instead of fixed point

`crates/rating/src/elo.cairo` computes `10^(d/400)` without fixed point by restructuring:
`(x / 400) == ((x / 25) / 16)`, a fast integer power, then a 16th root as four chained native square
roots, each on the next narrower type:

```cairo
let powered: u256 = PrivateTrait::pow(10, order);
let rooted: u16 = Sqrt::<u32>::sqrt(Sqrt::<u64>::sqrt(Sqrt::<u128>::sqrt(Sqrt::<u256>::sqrt(powered))));
```

with exponentiation by squaring (`pow(base * base, exp / 2)`, recursion, O(log n)) and a
`round_div` helper. `spreader.cairo` and `finder.cairo::euclidean` use an integer `MULTIPLIER`
(`10000`) rather than a fixed-point type.

Verdict: two takeaways. (1) `core::num::traits::Sqrt` is a native libfunc-backed integer sqrt
(u8..u256) and should be the basis of `length()`/`normalize()` rather than a Newton loop in Cairo
(cubit does the same: `a.mag.sqrt().into() * ONE_u128 / SQRT_ONE_u128`). (2) Algebraic restructuring to
stay in cheap integer types beats a general fixed-point pipeline.

### 3.14 Hash-derived randomness, one hash many uses

`crates/map/src/helpers/seeder.cairo` draws x from `seed % (width - 2)` and reuses the two u128 limbs
of the same seed for the next hash (`Self::shuffle(seed.low.into(), seed.high.into())`). Minor, but
the principle (extract several small values from one expensive value with `%`/`/`) is the same packing
idea as 3.1.

### 3.15 Things origami does that are *not* efficient (do not copy)

- `u256` as the working type for bit manipulation (3.2, 3.9). Largest single inefficiency of the crate:
  `test_map_cave` costs 128.7M gas, almost entirely `Bitmap::get` in `u256` (8 neighbours x size x order).
- `assert(order <= 1, ...)` inside `Mazer::check`, evaluated at every recursion step rather than once
  in `generate` (`crates/map/src/generators/mazer.cairo`).
- Recomputing `(position % width, position / width)` in every helper (`check`, `manhattan`,
  `assess`...) instead of carrying `(x, y)`; each is a `u8` divmod (~2k gas).
- `hex.cairo` array churn (3.10); `Matrix` Laplace expansion with allocation (2.3).
- Sign-magnitude fixed point through cubit (2.4).
- `Direction::East(())` explicit unit payload syntax and `_ => self` catch-alls: harmless but dated.

---

## 4. How origami tests and tracks gas or steps

It does not.

- No `#[available_gas(...)]` annotations, no gas assertions, no benchmark module, no snapshot files,
  no `snforge`, no `--detailed-resources`, nothing in CI beyond `fmt`, `build`, `test`.
- The only gas-related artefacts are comments (`heap.cairo`: "Both information is stored in the same
  map to save gas"; `map.cairo`: "the higher the order ... but also more expensive to generate").
- What exists implicitly: `cairo-test` prints `gas usage est.` per test, so numbers are visible in CI
  logs, but never compared or stored. That output is what this report used, e.g.:

  ```
  test origami_map::helpers::bitmap::tests::test_bitmap_get ... ok (gas usage est.: 15540)
  test origami_map::helpers::bitmap::tests::test_bitmap_set ... ok (gas usage est.: 34350)
  test origami_map::helpers::bitmap::tests::test_bitmap_popcount_large ... ok (gas usage est.: 210244)
  test origami_map::finders::astar::test::test_astar_search_large ... ok (gas usage est.: 17890050)
  test origami_map::map::tests::test_map_cave ... ok (gas usage est.: 128730628)
  test origami_algebra::vec2::tests::test_dot ... ok (gas usage est.: 75070)
  test origami_algebra::matrix::tests::test_matrix_inverse_3x3 ... ok (gas usage est.: 1230370)
  ```

Two pitfalls discovered while reading those numbers, both directly relevant to our benchmark design:

1. **Constant folding makes naive gas tests meaningless.** Several origami tests report 300 gas, the
   floor of an empty test, although they call real code:
   `test_finder_manhattan` (two `u8` divmods, two subtractions, comparisons) = 300,
   `test_hex_tile_neighbors` = 300, `vec2::test_splat` = 300. The callee is `#[inline]`, the inputs are
   literals, the compiler folds the whole computation at compile time. Any benchmark whose inputs are
   literals measures the optimizer, not the function. Inputs must be laundered through a
   `#[inline(never)]` identity function (a "black box"), or come from a non-foldable source.
2. **The harness overhead is of the same magnitude as the kernels.** A black-box call costs ~400 gas,
   a felt add is ~0, a `u64` add ~1,500. Benchmarks must report a baseline (same harness, no op) and
   the net figure, or compare alternatives only under an identical harness.

Also note that `gas usage est.` is a Sierra-gas estimate using cairo-test's cost table (100/step,
70/range check, 583/bitwise, ...). It is a good relative proxy but it is one weighting among several
(L2 fee weights, prover cost per builtin). snforge (`snforge test --detailed-resources`) reports
steps and per-builtin counters separately, which lets us re-weight later without re-measuring.

---

## 5. Recommendations for glam.cairo

### 5.1 Architecture

1. Scarb workspace, dependency-free core package (no `starknet`, no `dojo`, no cubit). If storage
   support (`Store`/`StorePacking`) is wanted, put it behind a separate package or feature so the math
   core stays pure.
2. Pin the toolchain with `.tool-versions` and mirror it in CI (`software-mansion/setup-scarb`), as
   origami does. CI = fmt check -> build -> test, plus the gas report step origami lacks.
3. Everything public is `pub` (modules, structs, fields, traits, impls); add a tiny consumer package in
   the workspace that imports the public API, so a visibility regression breaks CI. Origami's algebra
   crate shipped unusable for lack of this.
4. Release with the crate's own semver tags and target the scarbs.xyz registry; do not make users
   depend on a branch (origami depends on a cubit *branch* of a *fork*).
5. Keep origami's conventions that work: colocated `#[cfg(test)] mod tests`, `mod errors` with
   `'Type: message'` constants, `#[generate_trait] pub impl X of XTrait`, golden-value tests with the
   expected result explained in a comment.
6. Prefer concrete types per scalar (glam's own approach: `Vec2`, `IVec2`, `UVec2`...), generated from
   one template, over a single `Vec2<T>`. If a generic layer is kept, put `Copy + Drop` on the type and
   arithmetic bounds on the narrowest impl, and never call a wider-bounded impl from a narrower one.

### 5.2 Rules for sub-agents implementing features

Ordering principle (project owner's heuristic, confirmed by origami's practice and by measurement):
**constant/lookup < felt arithmetic < integer add/mul < div/mod < bitwise builtin < branch < loop <
allocation**, with the caveat of rule R6.

- **R1 - No loops in fixed-size math.** Vec2/3/4, Mat2/3/4, Quat, Affine: every operation fully
  unrolled. A loop needs a written justification and a benchmark against the unrolled version.
  If a loop is unavoidable: `while i != n`, never `while i < n`; iterate spans with `pop_front`.
- **R2 - No heap.** No `Array`, `Span`, `Felt252Dict`, `Box`, `Nullable` in the core. Types are
  `#[derive(Copy, Drop)]` structs of scalar fields, passed and returned by value. No snapshots (`@`)
  of `Copy` types except where a core trait signature imposes them (`PartialEq`).
- **R3 - Shifts and masks by arithmetic.** `x / 2^n`, `x * 2^n`, `x % 2^n` with literal or `const`
  powers of two; use `DivRem::div_rem` with a `const NonZero<T>` divisor when quotient and remainder
  are both needed. Never compute a power of two at runtime: const table or `match`.
- **R4 - Tables over computation.** Lookup via `match` on a small integer or a
  `const T: [u64; N]` + `.span().at(i)`; choose between the two by benchmark (for 8 entries `match`
  was ~2x cheaper; large tables favour the const array for code size).
- **R5 - Narrowest type, and never `u256` in a hot path.** Costs scale roughly
  u64 ~ 1x, u128 mul ~ 3x, i128 mul ~ 6x, u256 mul/div ~ 5-10x. Avoid `felt252 -> integer`
  conversions in hot paths (each is a range-check sequence, ~2k gas); `integer -> felt252` is free.
- **R6 - Bitwise only when it replaces a loop or is measured cheaper.** Default to arithmetic (R3).
  Use `&`, `|`, `^` for whole-word operations (mask merge, select). For single-mask extraction,
  benchmark `&` against `/`+`%` under the project's chosen metric: under cairo-test gas `&` on u128
  won (~0.9k vs ~3.3k), under builtin-heavy weightings it may not.
- **R7 - Accumulate in `felt252`, check once.** When operand ranges guarantee no field overflow,
  compute sums of products in `felt252` and convert back once, instead of checked integer ops at every
  step (dot products, matrix rows, polynomial evaluation). Document the range proof in a comment and
  test the boundary values. This is where a concrete (non-generic) scalar pays off.
- **R8 - Branchless for tiny bodies, short-circuit for expensive ones.** Prefer arithmetic selection
  (`offset * (1 - bit)`) over `if` when both sides are a few instructions; order `&&` chains
  cheapest-first and hoist invariant `assert`s out of recursive/iterated code.
- **R9 - Inline leaf kernels.** `#[inline(always)]` on component-wise ops, `dot`, `cross`, scalar
  ops, constructors, swizzles. Composite functions get `#[inline]` or nothing, decided by benchmark
  and with an eye on Sierra program size. Do not use method-level impl generics on hot functions.
- **R10 - Use native libfuncs.** `core::num::traits::Sqrt` (u8..u256), `WideMul`, `DivRem`,
  `OverflowingAdd`/`WrappingAdd` etc. instead of hand-written Cairo equivalents.
- **R11 - Do not recompute derived values.** Pass `(x, y)` rather than re-deriving them with divmod
  in each helper; compute `length_squared` once and share it between `length`, `normalize`, checks.
- **R12 - Scalar first.** Before implementing vectors, benchmark candidate scalar representations on
  the op mix of a physics step (add, sub, mul, div, compare, sqrt, neg, abs): at least
  Q32.32-in-u64-magnitude variants, native `i64`/`i128`-backed, offset-binary in a single felt, and
  cubit-style sign-magnitude as the baseline to beat. Sign-magnitude add (~5k) and u256-based mul
  (~19.6k) are the two costs to eliminate.

### 5.3 Rules for gas-tracking tests (the part origami lacks)

- **T1 - Every public function ships with at least one gas-tracked test**, separate from correctness
  tests, in a dedicated `bench` module per file (or a `benches` package) so the set can be run and
  diffed on its own.
- **T2 - Black-box all inputs and outputs.** Provide one shared helper and forbid literals flowing
  directly into the function under test:

  ```cairo
  #[inline(never)]
  pub fn black_box<T>(x: T) -> T { x }
  ```

  (origami's 300-gas tests show what happens otherwise).
- **T3 - Always include a baseline test** with the same harness shape (same number of `black_box`
  calls, no operation) and report net = measured - baseline. Wrap the function under test in an
  `#[inline(never)]` shim when comparing alternatives so the call boundary is identical.
- **T4 - Compare alternatives side by side.** When several implementations are plausible, keep them
  all in the bench module (`dot_checked`, `dot_felt_accum`, ...), same inputs, and let the numbers
  pick; keep the losers in the bench module (not in the public API) with their numbers in a comment,
  so the experiment is not redone.
- **T5 - Record steps and builtins, not only a single gas figure.** Prefer
  `snforge test --detailed-resources` (steps, range_check, bitwise, ... counters) so results can be
  re-weighted for L2 fees or for prover cost; cairo-test's `gas usage est.` is acceptable as a quick
  relative signal.
- **T6 - Snapshot and gate in CI.** Persist the per-test numbers (a checked-in snapshot file generated
  by a script from the test output), fail CI on regressions above a threshold, and print the diff in
  the PR. Pin the scarb/snforge versions: numbers are only comparable within one toolchain version.
- **T7 - Use representative magnitudes.** Costs of some paths depend on values (early returns,
  branches, u256 high limb zero or not); benchmark typical, zero and boundary inputs.

---

## 6. Appendix: micro-benchmark used for the measurements

Standalone package (scarb 2.12.2, `cairo_test`), inputs and outputs passed through
`#[inline(never)] fn bb<T>(x: T) -> T`. Raw `gas usage est.`; baseline with two `bb` calls = 800
(so ~400 per `bb`; tests below have three, net = raw - 1,200 for the simple-op rows).

```
t00_baseline                  800
t01_bit_u256_divmod         14500      x / p % 2 in u256   (origami Bitmap::get style)
t02_bit_u128_divmod          4460
t04_bit_u64_divmod           3520
t03_bit_u128_and             2083      x & p
t05_bit_u256_and             3466
t06_felt_to_u256             2710      (2 bb)
t07_felt_to_u128_try         3010      (2 bb)
t08_u128_to_felt              700      (2 bb) -> free
t10_pow2_table               4070      const [u128; 8] .span().at(e)
t11_pow2_match               2170      match e { 0 => 1, ... }
t12_pow2_loop               34870      while e != 0 { r *= 2 }   (e = 7)
t20_add_felt                 1200
t21_add_u128                 2670
t22_add_u64                  2670
t23_add_i128                 2770
t24_add_sign_mag             6250      cubit-style {mag, sign} add
t25_mul_felt                 1200
t26_mul_u128                 5230
t27_mul_u64                  2670
t28_mul_i128                 9790
t29_mul_u256                16480
t30_div_u128                 3080
t31_div_u256                 8350
t32_div_u64                  2610
t33_div_i128                 6390
t34_lt_u128                  1980
t35_lt_i128                  1980
t40_fp_mul_u256_div         19640      cubit-style Q64.64: wide_mul + u256 div_rem by 2^64
t41_fp_mul_limbs            19140      wide_mul + (high * 2^64 + low / 2^64)
t42_fp_mul_u64               5550      Q32.32: u64 wide_mul -> u128 / 2^32
t50_dot_struct              10930      V2 { x, y } of u128
t51_dot_span                17710      Span<u128>, pop_front loop (array build included)

u00_baseline_v3              1600
u01_v3_add_inline_always     4610
u03_v3_add_inline_default    4610
u02_v3_add_inline_never      6910
u04_v3_add_snapshot          6910      (@V3, @V3), inline(never)
u05_v3_dot_u64_checked       7350
u06_v3_dot_felt_accum        6410      products summed in felt252, one try_into at the end
u10_loop_lt_16              41400      while i < n
u11_loop_ne_16              35410      while i != n
u12_unrolled4                6150
u13_loop4                   14010
```

Caveats: single toolchain version (2.12.2), cairo-test cost table, tiny operand values, call overhead
included in the function-level rows. The figures are meant to rank idioms and size the gaps, not to be
quoted as absolute costs; glam.cairo's own benchmark suite (section 5.3) should reproduce them under
the project's toolchain and metric before they are turned into hard rules.
