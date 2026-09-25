# consumer

Unpublished. A Starknet contract fixture that links `fixed` into a deployable class, so that the
compiled class size of a consumer is tracked against the network limits:

| contract | content |
|---|---|
| `Scalar` | one entry point per `fixed` family (`mul`, `div`, `sqrt`, `sin_cos`, `atan2`, `exp`, `ln`, `powf`) |

Every input comes from calldata (nothing is constant-folded). The heavier fixtures that link
`glam` / `glamx` (`Particles2d`, `Rigid3d`, `KitchenSink`) live in
[`glam-cairo`](https://github.com/bal7hazar/glam-cairo) and
[`glamx-cairo`](https://github.com/bal7hazar/glamx-cairo).

Run from the repository root:

```sh
scripts/bytecode_size.py            # size table (release build)
scripts/bytecode_size.py check      # compare with gas/bytecode.size (part of scripts/check.sh and CI)
scripts/bytecode_size.py snapshot   # rewrite gas/bytecode.size
scripts/bytecode_size.py attribution --strategy default --strategy avoid   # CASM felts per call site
```

Keep the compiler's default `inlining-strategy` in a contract that uses this package: `avoid` or
a small numeric threshold shrinks the class but costs much more gas on the library (measured in
`glam-cairo`, `docs/audits/R1-bytecode-size.md` section 4.2).
