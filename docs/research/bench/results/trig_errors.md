| function / variant | max abs error | in Q32.32 ulp (2^-32) | worst input (raw) |
|---|---:|---:|---|
| sin: cubit `sin` (Taylor recursion, 8 terms) | 2.278e-08 | 97.9 | `-26980125560` |
| sin: cubit `sin_fast` (if-tree LUT, 256 slots + lerp) | 4.705e-06 | 20206.4 | `-20173461389` |
| sin: ours, Horner polynomial, sin deg 7 / cos deg 8, |x| <= 7 | 2.683e-09 | 11.5 | `-10119801943` |
| cos: ours, Horner polynomial, sin deg 7 / cos deg 8, |x| <= 7 | 2.655e-09 | 11.4 | `-3373267314` |
| sin: ours, Horner polynomial, sin deg 9 / cos deg 10 **(benchmarked)**, |x| <= 7 | 4.741e-10 | 2.0 | `-26923002495` |
| cos: ours, Horner polynomial, sin deg 9 / cos deg 10 **(benchmarked)**, |x| <= 7 | 4.147e-10 | 1.8 | `-20168951674` |
| sin: ours, Horner polynomial, sin deg 11 / cos deg 12, |x| <= 7 | 4.741e-10 | 2.0 | `-26923002495` |
| cos: ours, Horner polynomial, sin deg 11 / cos deg 12, |x| <= 7 | 4.147e-10 | 1.8 | `-20168951674` |
| sin: ours, Horner polynomial (benchmarked), |x| <= 1000 (phase error of the Q32.32 pi/4 constant grows with |x|) | 3.880e-08 | 166.6 | `-4290672328704` |
| sin: ours, const-array LUT + lerp, step 2^24 raw = 2^-8 rad, 2 x 203 entries | 1.907e-06 | 8191.4 | `-20298230189` |
| sin: ours, const-array LUT + lerp, step 2^23 raw = 2^-9 rad, 2 x 404 entries | 4.770e-07 | 2048.7 | `-20218558546` |
| sin: ours, const-array LUT + lerp, step 2^22 raw = 2^-10 rad, 2 x 806 entries **(benchmarked)** | 1.194e-07 | 512.9 | `-20388424502` |
| sin: ours, const-array LUT + lerp, step 2^21 raw = 2^-11 rad, 2 x 1610 entries | 3.003e-08 | 129.0 | `-20353850016` |
| sin: ours, const-array LUT + lerp, step 2^20 raw = 2^-12 rad, 2 x 3218 entries | 7.723e-09 | 33.2 | `-20331301437` |
| atan: cubit `atan` (2 range reductions + degree-10 Horner) | 1.568e-09 | 6.7 | `-3006477107` |
| atan: cubit `atan_fast` (99-way if-chain LUT + lerp) | 3.977e-06 | 17082.2 | `-7348689043` |
| atan2: ours, 1 division + 8 segments x degree-4 Horner | 1.171e-08 | 50.3 | `(1619121910177, -128838845503127)` |
| atan2: ours, 1 division + 8 segments x degree-5 Horner **(benchmarked)** | 7.848e-10 | 3.4 | `(7188685691, -53203632955)` |
| atan2: ours, 1 division + 8 segments x degree-6 Horner | 5.718e-10 | 2.5 | `(113480975, -1585080860)` |
| acos: cubit `acos` (sqrt + asin -> div + atan) | 2.858e-06 | 12274.7 | `-214748` |
| acos: cubit `acos_fast` | 3.978e-06 | 17087.1 | `2147913145` |
| acos: ours, sqrt(1-|x|) * P(|x|), degree 7 | 2.532e-08 | 108.7 | `-214748` |
| acos: ours, sqrt(1-|x|) * P(|x|), degree 10 **(benchmarked)** | 7.573e-10 | 3.3 | `-315894845` |
| acos: ours, sqrt(1-|x|) * P(|x|), degree 12 | 6.967e-10 | 3.0 | `-1034013377` |
