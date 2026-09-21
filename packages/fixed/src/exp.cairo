//! Loop-free exponentials, logarithms and powers (exp, exp2, exp_m1, ln, log2, log10, ln_1p, log,
//! powf).
//!
//! Every function is straight-line code, with no loop and no bitwise operation:
//!
//! * `exp2(x)`: `x = k / 16 + g` with **one** `DivRem` by the constant `2^28` (`1 / 16` in raw
//!   units), then `2^x = 2^(k/16) * 2^g`: one lookup in a `const` table of the 1 024 values
//!   `2^(k/16)` (the power of two and the segment in one lookup; its cost does not depend on its
//!   size) times a degree-6 minimax polynomial of `2^g` on `[0, 1/16)`, rescaled once.
//! * `exp(x) = exp2(x * log2(e))`, where the product keeps **56** fractional bits (a wide
//!   `log2(e)` and a single rescale): the reduced exponent is exact to `2^-53`, so `exp` is as
//!   accurate as `exp2` (a Q32.32 product would cost `2^15` ULP at `e^11`).
//! * `log2(x)`: `x = 2^e * m` with `m` in `[1, 2)`; `e` comes from an unrolled binary search on
//!   constant thresholds (6 comparisons), `m` from one multiplication by `2^(62 - e)` (the search
//!   yields the constant), then 32 segments of `[1, 2)` (one `DivRem`, one `match`) with a
//!   degree-4 polynomial each, in the exact mantissa fraction (62 bits, not 32). `ln` and
//!   `log10` rescale the same accumulator by a wide `ln(2)` / `log10(2)`, so they cost the same
//!   as `log2`.
//! * `powf(x, n) = exp2(n * log2(x))` on the wide accumulators: the product `n * log2(x)` is
//!   never rounded to 32 bits.
//!
//! Polynomials run on the Q96.96 accumulators of `fixed::wide` (one rescale per Horner step)
//! with 24 to 28 extra fractional bits, so the error is dominated by the final rescale.
//!
//! Rounding: `log2`, `ln` and `log10` round their final rescale to nearest (`docs/DESIGN.md`
//! section 2, second exception). `exp2`, `exp` and `powf` keep the floor of the house rule, and
//! so does their table (`floor(2^(k/16) * 2^32)`): with a polynomial that never overshoots
//! `2^(1/16)` at the end of a segment, this makes them **non-decreasing by construction** across
//! every seam (rounding to nearest would let a seam step down by 1 ULP where the table entries
//! are small). The segments of `log2` are sealed the same way (each one ends at or below the
//! start of the next), so every function of this module is monotone.
//!
//! The coefficients, the table, the search tree, the thresholds and the measured errors come
//! from [`scripts/gen_exp.py`](../../../../scripts/gen_exp.py), which also mirrors every
//! function of this module in Python integer arithmetic, bit for bit, and sweeps the mirror
//! against 50-digit references (`scripts/gen_exp.py sweep`). The table of measured errors is at
//! the end of the generated block below.
#[feature("bounded-int-utils")]
use core::internal::bounded_int::upcast;
use crate::fixed::{Fixed, FixedTrait, ONE, ZERO};
use crate::internal::bounded;
use crate::wide::{W1, WideAdd, WideLift, WideMul, WideNarrow, wide_from, wide_mul};

// GENERATED-BEGIN exp
/// The smallest raw input of `exp2` whose result does not fit the scalar range (it rounds
/// to `2^31` or above).
const EXP2_MAX_RAW: i64 = 0x1f00000000;
/// `-33` in raw units: below it `2^x < 2^-33` rounds to zero.
const EXP2_MIN_RAW: i64 = -0x2100000000;
/// The smallest raw input of `exp` whose result does not fit the scalar range.
const EXP_MAX_RAW: i64 = 0x157cd0e703;
/// The smallest raw input of `exp` whose wide exponent `x * log2(e)` reaches `-33`: below
/// it `e^x < 2^-33` rounds to zero.
const EXP_MIN_RAW: i64 = -0x16dfb516f2;
/// `log2(e) * 2^56`, rounded to nearest: `x * LOG2_E_Q`, narrowed once, is the wide
/// exponent `x * log2(e)` with 56 fractional bits.
const LOG2_E_Q: Fixed = Fixed { raw: 0x171547652b82fe1 };
/// `33 * 2^32`: biases a raw exponent in `[-33, 31)` to a non-negative table offset.
const EXP2_BIAS: i64 = 0x2100000000;
/// `33 * 2^56`: the same bias at the scale of the wide exponent.
const EXP_BIAS_Q: i64 = 0x2100000000000000;
/// `1 / 16` in raw units: the segment width of the `exp2` reduction.
const EXP2_SEG_NZ: NonZero<u64> = 0x10000000;
/// `1 / 16` at the scale of the wide exponent (`2^52`).
const EXP_SEG_Q_NZ: NonZero<u64> = 0x10000000000000;
/// `2^8`: lifts the fraction of the wide exponent to the Q64.64 scale.
const EXP_FRAC_LIFT: Fixed = Fixed { raw: 256 };
/// `16`: `TABLE * P * 16 / 2^64 = TABLE * P / 2^60`, the rescale of `exp2_core`.
const SIXTEEN: Fixed = Fixed { raw: 16 };
/// `2^62`: the leading bit of a normalised mantissa.
const MANT_ONE: u64 = 0x4000000000000000;
/// `1 / 32` at the scale of the mantissa: the segment width of the `log2` polynomials.
const LOG_SEG_NZ: NonZero<u64> = 0x200000000000000;
/// `2^2`: lifts the mantissa fraction to the Q64.64 scale.
const LOG_FRAC_LIFT: Fixed = Fixed { raw: 4 };
/// `2^40`: `A * K / 2^64` turns the log accumulator (`2^56`) into Q32.32.
const K_LOG2: Fixed = Fixed { raw: 0x10000000000 };
/// `ln(2) * 2^40`, rounded to nearest.
const K_LN: Fixed = Fixed { raw: 0xb17217f7d2 };
/// `log10(2) * 2^40`, rounded to nearest.
const K_LOG10: Fixed = Fixed { raw: 0x4d104d427e };

/// `2^g` for `g` in `[0, 1/16)`, degree 6, in the Q64.64 fraction `u`, at the
/// scale `2^60`. Minimax with the constant term pinned to 1 so that `exp2(k) = 2^k`
/// exactly.
#[inline(always)]
fn exp2_poly(u: W1) -> Fixed {
    let acc = Fixed { raw: 0xa4887adf2592 };
    let acc = step(u, acc, Fixed { raw: 0x575e9d7b699f5 });
    let acc = step(u, acc, Fixed { raw: 0x2765589dae4e3c });
    let acc = step(u, acc, Fixed { raw: 0xe35846b1ad1990 });
    let acc = step(u, acc, Fixed { raw: 0x3d7f7bff06171e0 });
    let acc = step(u, acc, Fixed { raw: 0xb17217f7d1cf580 });
    step(u, acc, Fixed { raw: 0x1000000000000000 })
}

/// `round(2^((i - 528) / 16) * 2^32)` for `i` in `0..1024`: `2^(k/16)` for every
/// exponent of the range, so that the power of two and the segment share one lookup.
const EXP2_TABLE: [i64; 1024] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 7, 7, 7,
    8, 8, 8, 9, 9, 9, 10, 10, 11, 11, 12, 12, 13, 14, 14, 15, 16, 16, 17, 18, 19, 19, 20, 21, 22,
    23, 24, 25, 26, 28, 29, 30, 32, 33, 34, 36, 38, 39, 41, 43, 45, 47, 49, 51, 53, 56, 58, 61, 64,
    66, 69, 72, 76, 79, 82, 86, 90, 94, 98, 103, 107, 112, 117, 122, 128, 133, 139, 145, 152, 158,
    165, 173, 181, 189, 197, 206, 215, 224, 234, 245, 256, 267, 279, 291, 304, 317, 331, 346, 362,
    378, 394, 412, 430, 449, 469, 490, 512, 534, 558, 583, 608, 635, 663, 693, 724, 756, 789, 824,
    861, 899, 939, 980, 1024, 1069, 1116, 1166, 1217, 1271, 1327, 1386, 1448, 1512, 1579, 1649,
    1722, 1798, 1878, 1961, 2048, 2138, 2233, 2332, 2435, 2543, 2655, 2773, 2896, 3024, 3158, 3298,
    3444, 3596, 3756, 3922, 4096, 4277, 4466, 4664, 4870, 5086, 5311, 5547, 5792, 6049, 6316, 6596,
    6888, 7193, 7512, 7844, 8192, 8554, 8933, 9328, 9741, 10173, 10623, 11094, 11585, 12098, 12633,
    13193, 13777, 14387, 15024, 15689, 16384, 17109, 17866, 18657, 19483, 20346, 21247, 22188,
    23170, 24196, 25267, 26386, 27554, 28774, 30048, 31378, 32768, 34218, 35733, 37315, 38967,
    40693, 42494, 44376, 46340, 48392, 50535, 52772, 55108, 57548, 60096, 62757, 65536, 68437,
    71467, 74631, 77935, 81386, 84989, 88752, 92681, 96785, 101070, 105545, 110217, 115097, 120193,
    125514, 131072, 136875, 142935, 149263, 155871, 162772, 169979, 177504, 185363, 193570, 202140,
    211090, 220435, 230195, 240387, 251029, 262144, 273750, 285870, 298526, 311743, 325545, 339958,
    355009, 370727, 387141, 404281, 422180, 440871, 460390, 480774, 502059, 524288, 547500, 571740,
    597053, 623487, 651091, 679917, 710019, 741455, 774282, 808562, 844360, 881743, 920781, 961548,
    1004119, 1048576, 1095000, 1143480, 1194106, 1246974, 1302182, 1359834, 1420039, 1482910,
    1548564, 1617125, 1688721, 1763487, 1841563, 1923096, 2008239, 2097152, 2190000, 2286960,
    2388212, 2493948, 2604364, 2719669, 2840079, 2965820, 3097128, 3234250, 3377443, 3526975,
    3683127, 3846193, 4016479, 4194304, 4380001, 4573920, 4776425, 4987896, 5208729, 5439339,
    5680159, 5931641, 6194257, 6468501, 6754886, 7053950, 7366255, 7692387, 8032958, 8388608,
    8760003, 9147841, 9552851, 9975792, 10417458, 10878678, 11360318, 11863283, 12388515, 12937002,
    13509772, 14107900, 14732510, 15384774, 16065917, 16777216, 17520006, 18295683, 19105702,
    19951584, 20834916, 21757357, 22720637, 23726566, 24777031, 25874004, 27019544, 28215801,
    29465021, 30769549, 32131834, 33554432, 35040013, 36591367, 38211405, 39903169, 41669833,
    43514714, 45441275, 47453132, 49554062, 51748008, 54039088, 56431603, 58930043, 61539099,
    64263668, 67108864, 70080027, 73182735, 76422811, 79806338, 83339667, 87029429, 90882551,
    94906265, 99108124, 103496016, 108078176, 112863206, 117860087, 123078199, 128527336, 134217728,
    140160054, 146365470, 152845623, 159612677, 166679334, 174058858, 181765102, 189812531,
    198216249, 206992033, 216156353, 225726412, 235720174, 246156398, 257054673, 268435456,
    280320108, 292730940, 305691246, 319225354, 333358668, 348117717, 363530205, 379625062,
    396432499, 413984066, 432312706, 451452825, 471440349, 492312796, 514109346, 536870912,
    560640217, 585461880, 611382492, 638450708, 666717336, 696235434, 727060410, 759250124,
    792864999, 827968132, 864625413, 902905650, 942880699, 984625593, 1028218693, 1073741824,
    1121280435, 1170923761, 1222764985, 1276901416, 1333434672, 1392470868, 1454120821, 1518500249,
    1585729999, 1655936264, 1729250826, 1805811301, 1885761398, 1969251187, 2056437386, 2147483648,
    2242560871, 2341847523, 2445529971, 2553802833, 2666869344, 2784941737, 2908241642, 3037000499,
    3171459999, 3311872529, 3458501653, 3611622602, 3771522796, 3938502375, 4112874773, 4294967296,
    4485121743, 4683695047, 4891059943, 5107605667, 5333738689, 5569883475, 5816483284, 6074000999,
    6342919998, 6623745058, 6917003306, 7223245205, 7543045592, 7877004751, 8225749546, 8589934592,
    8970243487, 9367390095, 9782119886, 10215211334, 10667477378, 11139766950, 11632966569,
    12148001999, 12685839997, 13247490117, 13834006612, 14446490411, 15086091184, 15754009503,
    16451499092, 17179869184, 17940486974, 18734780191, 19564239773, 20430422668, 21334954756,
    22279533901, 23265933138, 24296003999, 25371679994, 26494980234, 27668013224, 28892980822,
    30172182369, 31508019006, 32902998185, 34359738368, 35880973948, 37469560382, 39128479546,
    40860845336, 42669909513, 44559067803, 46531866276, 48592007999, 50743359989, 52989960469,
    55336026449, 57785961645, 60344364738, 63016038013, 65805996370, 68719476736, 71761947897,
    74939120765, 78256959093, 81721690673, 85339819026, 89118135606, 93063732552, 97184015999,
    101486719979, 105979920938, 110672052899, 115571923290, 120688729477, 126032076027,
    131611992740, 137438953472, 143523895795, 149878241530, 156513918186, 163443381347,
    170679638052, 178236271212, 186127465104, 194368031998, 202973439958, 211959841877,
    221344105799, 231143846581, 241377458954, 252064152055, 263223985481, 274877906944,
    287047791590, 299756483061, 313027836373, 326886762694, 341359276104, 356472542424,
    372254930209, 388736063996, 405946879916, 423919683754, 442688211599, 462287693163,
    482754917909, 504128304110, 526447970962, 549755813888, 574095583180, 599512966122,
    626055672747, 653773525389, 682718552209, 712945084849, 744509860418, 777472127993,
    811893759832, 847839367509, 885376423199, 924575386326, 965509835818, 1008256608221,
    1052895941924, 1099511627776, 1148191166360, 1199025932245, 1252111345494, 1307547050779,
    1365437104419, 1425890169698, 1489019720837, 1554944255987, 1623787519664, 1695678735018,
    1770752846399, 1849150772653, 1931019671637, 2016513216442, 2105791883849, 2199023255552,
    2296382332721, 2398051864490, 2504222690988, 2615094101558, 2730874208838, 2851780339397,
    2978039441674, 3109888511975, 3247575039328, 3391357470036, 3541505692798, 3698301545306,
    3862039343274, 4033026432884, 4211583767698, 4398046511104, 4592764665442, 4796103728980,
    5008445381976, 5230188203117, 5461748417677, 5703560678794, 5956078883349, 6219777023950,
    6495150078656, 6782714940072, 7083011385596, 7396603090612, 7724078686548, 8066052865769,
    8423167535396, 8796093022208, 9185529330884, 9592207457960, 10016890763953, 10460376406235,
    10923496835354, 11407121357589, 11912157766698, 12439554047901, 12990300157312, 13565429880144,
    14166022771192, 14793206181225, 15448157373097, 16132105731538, 16846335070792, 17592186044416,
    18371058661769, 19184414915921, 20033781527906, 20920752812471, 21846993670708, 22814242715178,
    23824315533396, 24879108095803, 25980600314625, 27130859760288, 28332045542384, 29586412362451,
    30896314746194, 32264211463076, 33692670141584, 35184372088832, 36742117323538, 38368829831842,
    40067563055812, 41841505624942, 43693987341416, 45628485430356, 47648631066792, 49758216191607,
    51961200629251, 54261719520577, 56664091084769, 59172824724903, 61792629492389, 64528422926153,
    67385340283169, 70368744177664, 73484234647076, 76737659663685, 80135126111624, 83683011249884,
    87387974682832, 91256970860712, 95297262133584, 99516432383215, 103922401258502,
    108523439041155, 113328182169538, 118345649449806, 123585258984778, 129056845852306,
    134770680566339, 140737488355328, 146968469294152, 153475319327371, 160270252223249,
    167366022499768, 174775949365665, 182513941721425, 190594524267169, 199032864766430,
    207844802517004, 217046878082310, 226656364339076, 236691298899613, 247170517969556,
    258113691704612, 269541361132678, 281474976710656, 293936938588304, 306950638654743,
    320540504446499, 334732044999537, 349551898731330, 365027883442850, 381189048534338,
    398065729532860, 415689605034008, 434093756164621, 453312728678153, 473382597799226,
    494341035939113, 516227383409224, 539082722265357, 562949953421312, 587873877176609,
    613901277309487, 641081008892999, 669464089999074, 699103797462660, 730055766885700,
    762378097068677, 796131459065721, 831379210068016, 868187512329243, 906625457356306,
    946765195598453, 988682071878227, 1032454766818448, 1078165444530715, 1125899906842624,
    1175747754353219, 1227802554618974, 1282162017785998, 1338928179998149, 1398207594925320,
    1460111533771401, 1524756194137354, 1592262918131443, 1662758420136033, 1736375024658486,
    1813250914712612, 1893530391196907, 1977364143756455, 2064909533636897, 2156330889061430,
    2251799813685248, 2351495508706439, 2455605109237949, 2564324035571996, 2677856359996298,
    2796415189850641, 2920223067542803, 3049512388274708, 3184525836262886, 3325516840272067,
    3472750049316973, 3626501829425224, 3787060782393814, 3954728287512910, 4129819067273795,
    4312661778122860, 4503599627370496, 4702991017412879, 4911210218475898, 5128648071143992,
    5355712719992597, 5592830379701282, 5840446135085607, 6099024776549417, 6369051672525772,
    6651033680544134, 6945500098633947, 7253003658850448, 7574121564787629, 7909456575025820,
    8259638134547591, 8625323556245721, 9007199254740992, 9405982034825758, 9822420436951797,
    10257296142287984, 10711425439985194, 11185660759402564, 11680892270171214, 12198049553098834,
    12738103345051545, 13302067361088269, 13891000197267894, 14506007317700896, 15148243129575258,
    15818913150051640, 16519276269095182, 17250647112491443, 18014398509481984, 18811964069651517,
    19644840873903595, 20514592284575969, 21422850879970388, 22371321518805128, 23361784540342428,
    24396099106197669, 25476206690103090, 26604134722176539, 27782000394535789, 29012014635401792,
    30296486259150517, 31637826300103280, 33038552538190364, 34501294224982886, 36028797018963968,
    37623928139303035, 39289681747807190, 41029184569151939, 42845701759940777, 44742643037610257,
    46723569080684856, 48792198212395338, 50952413380206180, 53208269444353078, 55564000789071578,
    58024029270803584, 60592972518301034, 63275652600206561, 66077105076380729, 69002588449965772,
    72057594037927936, 75247856278606070, 78579363495614381, 82058369138303878, 85691403519881554,
    89485286075220515, 93447138161369713, 97584396424790677, 101904826760412361, 106416538888706157,
    111128001578143157, 116048058541607169, 121185945036602069, 126551305200413122,
    132154210152761458, 138005176899931544, 144115188075855872, 150495712557212140,
    157158726991228763, 164116738276607756, 171382807039763109, 178970572150441030,
    186894276322739427, 195168792849581355, 203809653520824722, 212833077777412314,
    222256003156286315, 232096117083214339, 242371890073204139, 253102610400826244,
    264308420305522916, 276010353799863088, 288230376151711744, 300991425114424280,
    314317453982457527, 328233476553215513, 342765614079526219, 357941144300882061,
    373788552645478855, 390337585699162710, 407619307041649444, 425666155554824629,
    444512006312572630, 464192234166428679, 484743780146408279, 506205220801652488,
    528616840611045833, 552020707599726177, 576460752303423488, 601982850228848561,
    628634907964915054, 656466953106431027, 685531228159052438, 715882288601764122,
    747577105290957710, 780675171398325420, 815238614083298888, 851332311109649259,
    889024012625145261, 928384468332857358, 969487560292816559, 1012410441603304977,
    1057233681222091666, 1104041415199452354, 1152921504606846976, 1203965700457697122,
    1257269815929830108, 1312933906212862054, 1371062456318104877, 1431764577203528245,
    1495154210581915421, 1561350342796650840, 1630477228166597776, 1702664622219298519,
    1778048025250290523, 1856768936665714716, 1938975120585633118, 2024820883206609954,
    2114467362444183333, 2208082830398904709, 2305843009213693952, 2407931400915394245,
    2514539631859660217, 2625867812425724109, 2742124912636209755, 2863529154407056491,
    2990308421163830842, 3122700685593301681, 3260954456333195553, 3405329244438597039,
    3556096050500581047, 3713537873331429432, 3877950241171266237, 4049641766413219908,
    4228934724888366667, 4416165660797809419, 4611686018427387904, 4815862801830788490,
    5029079263719320435, 5251735624851448219, 5484249825272419511, 5727058308814112982,
    5980616842327661685, 6245401371186603363, 6521908912666391106, 6810658488877194079,
    7112192101001162094, 7427075746662858865, 7755900482342532474, 8099283532826439816,
    8457869449776733335, 8832331321595618838,
];

/// `log2(1 + 0 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`. The constant term is pinned to 0: `log2(2^k) = k`.
#[inline(always)]
fn log2_seg0(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x57e20e0a939100 };
    let acc = step(u, acc, Fixed { raw: 0x7b063313ad5db4 });
    let acc = step(u, acc, Fixed { raw: -0xb8aa184e25b408 });
    let acc = step(u, acc, Fixed { raw: 0x17154764a0fb7e0 });
    step(u, acc, Fixed { raw: 0x0 })
}

/// `log2(1 + 1 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg1(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x4ce4aa70b17aa4 };
    let acc = step(u, acc, Fixed { raw: 0x702040f23a47ec });
    let acc = step(u, acc, Fixed { raw: -0xada42ca347d488 });
    let acc = step(u, acc, Fixed { raw: 0x166235b1ab8e450 });
    step(u, acc, Fixed { raw: 0xb5d69bad62fa1 })
}

/// `log2(1 + 2 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg2(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x445b73a5063ad8 };
    let acc = step(u, acc, Fixed { raw: 0x6686f9da6dc3a8 });
    let acc = step(u, acc, Fixed { raw: -0xa393d29bb65260 });
    let acc = step(u, acc, Fixed { raw: 0x15b9ac9679edab0 });
    step(u, acc, Fixed { raw: 0x1663f6fad5c18a })
}

/// `log2(1 + 3 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg3(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x3cf93b0ad80788 };
    let acc = step(u, acc, Fixed { raw: 0x5dfe5276162cb0 });
    let acc = step(u, acc, Fixed { raw: -0x9a5d20826056a0 });
    let acc = step(u, acc, Fixed { raw: 0x151ac4ea7832f20 });
    step(u, acc, Fixed { raw: 0x2118b119bff1fc })
}

/// `log2(1 + 4 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg4(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x368f7a8f961f0c };
    let acc = step(u, acc, Fixed { raw: 0x566183854d214c });
    let acc = step(u, acc, Fixed { raw: -0x91e83e37261d90 });
    let acc = step(u, acc, Fixed { raw: 0x1484b139bae3260 });
    step(u, acc, Fixed { raw: 0x2b803474013e44 })
}

/// `log2(1 + 5 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg5(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x30f8031c7eaa78 };
    let acc = step(u, acc, Fixed { raw: 0x4f919195ad446c });
    let acc = step(u, acc, Fixed { raw: -0x8a2081260f6490 });
    let acc = step(u, acc, Fixed { raw: 0x13f6ba466194160 });
    step(u, acc, Fixed { raw: 0x359ebc5b7234bc })
}

/// `log2(1 + 6 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg6(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x2c13521a76122c };
    let acc = step(u, acc, Fixed { raw: 0x4974433b568b1c });
    let acc = step(u, acc, Fixed { raw: -0x82f3ed8d0d3bc8 });
    let acc = step(u, acc, Fixed { raw: 0x13703c1c6d273f0 });
    step(u, acc, Fixed { raw: 0x3f782d720c23d2 })
}

/// `log2(1 + 7 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg7(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x27c744c58f9a32 };
    let acc = step(u, acc, Fixed { raw: 0x43f34c58397eac });
    let acc = step(u, acc, Fixed { raw: -0x7c52ce34186b10 });
    let acc = step(u, acc, Fixed { raw: 0x12f0a398b01e7b0 });
    step(u, acc, Fixed { raw: 0x49101eac3e8eec })
}

/// `log2(1 + 8 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg8(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x23fe120a73bffc };
    let acc = step(u, acc, Fixed { raw: 0x3efba2c52be382 });
    let acc = step(u, acc, Fixed { raw: -0x762f5e28fe93bc });
    let acc = step(u, acc, Fixed { raw: 0x12776c4eb476160 });
    step(u, acc, Fixed { raw: 0x5269e12f3a1e44 })
}

/// `log2(1 + 9 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg9(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x20a57bece332a4 };
    let acc = step(u, acc, Fixed { raw: 0x3a7cf397c5c7da });
    let acc = step(u, acc, Fixed { raw: -0x707d8106aec5fc });
    let acc = step(u, acc, Fixed { raw: 0x12041ebd60a3960 });
    step(u, acc, Fixed { raw: 0x5b888736793c60 })
}

/// `log2(1 + 10 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg10(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x1dae2a8e99afa5 };
    let acc = step(u, acc, Fixed { raw: 0x366932226c5728 });
    let acc = step(u, acc, Fixed { raw: -0x6b32870b2a3460 });
    let acc = step(u, acc, Fixed { raw: 0x11964ec53bd9090 });
    step(u, acc, Fixed { raw: 0x646eea2480d45c })
}

/// `log2(1 + 11 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg11(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x1b0b28b7734392 };
    let acc = step(u, acc, Fixed { raw: 0x32b43b7f6e39f6 });
    let acc = step(u, acc, Fixed { raw: -0x6644fad0cc6f30 });
    let acc = step(u, acc, Fixed { raw: 0x112d9a55a2d0800 });
    step(u, acc, Fixed { raw: 0x6d1fafdce6051c })
}

/// `log2(1 + 12 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg12(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x18b1792ec23bbf };
    let acc = step(u, acc, Fixed { raw: 0x2f538a73e4f19c });
    let acc = step(u, acc, Fixed { raw: -0x61ac76eefae824 });
    let acc = step(u, acc, Fixed { raw: 0x10c9a8482f84fc0 });
    step(u, acc, Fixed { raw: 0x759d4f80cf3568 })
}

/// `log2(1 + 13 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg13(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x1697c1a534800b };
    let acc = step(u, acc, Fixed { raw: 0x2c3df8a2120e6c });
    let acc = step(u, acc, Fixed { raw: -0x5d61821fa58de8 });
    let acc = step(u, acc, Fixed { raw: 0x106a2763243cce0 });
    step(u, acc, Fixed { raw: 0x7dea15a32f48cc })
}

/// `log2(1 + 14 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg14(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x14b60479b436de };
    let acc = step(u, acc, Fixed { raw: 0x296b8a509c7664 });
    let acc = step(u, acc, Fixed { raw: -0x595d70c95e6184 });
    let acc = step(u, acc, Fixed { raw: 0x100ecd7ce9eb7c0 });
    step(u, acc, Fixed { raw: 0x86082806b4aef0 })
}

/// `log2(1 + 15 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg15(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x13056841b09c96 };
    let acc = step(u, acc, Fixed { raw: 0x26d542f16e4b44 });
    let acc = step(u, acc, Fixed { raw: -0x559a4b06849924 });
    let acc = step(u, acc, Fixed { raw: 0xfb756bbb4f0960 });
    step(u, acc, Fixed { raw: 0x8df988f4b11090 })
}

/// `log2(1 + 16 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg16(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x118008b454343e };
    let acc = step(u, acc, Fixed { raw: 0x247500b84cafec });
    let acc = step(u, acc, Fixed { raw: -0x5212b66bc8ab70 });
    let acc = step(u, acc, Fixed { raw: 0xf6384ed3546460 });
    step(u, acc, Fixed { raw: 0x95c01a39fe25c0 })
}

/// `log2(1 + 17 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg17(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x1020d045d9b170 };
    let acc = step(u, acc, Fixed { raw: 0x22455e01b728c2 });
    let acc = step(u, acc, Fixed { raw: -0x4ec1e2f2c6542c });
    let acc = step(u, acc, Fixed { raw: 0xf131ef2e2aff60 });
    step(u, acc, Fixed { raw: 0x9d5d9fd5032110 })
}

/// `log2(1 + 18 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg18(u: W1) -> Fixed {
    let acc = Fixed { raw: -0xee358ff67dab3 };
    let acc = step(u, acc, Fixed { raw: 0x20419791b3770e });
    let acc = step(u, acc, Fixed { raw: -0x4ba37a89f1a100 });
    let acc = step(u, acc, Fixed { raw: 0xec5f04002605c8 });
    step(u, acc, Fixed { raw: 0xa4d3c25e6abf60 })
}

/// `log2(1 + 19 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg19(u: W1) -> Fixed {
    let acc = Fixed { raw: -0xdc3d0ed5c1470 };
    let acc = step(u, acc, Fixed { raw: 0x1e6576adc447a0 });
    let acc = step(u, acc, Fixed { raw: -0x48b392dfdbd768 });
    let acc = step(u, acc, Fixed { raw: 0xe7bc866f736590 });
    step(u, acc, Fixed { raw: 0xac241134c69f88 })
}

/// `log2(1 + 20 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg20(u: W1) -> Fixed {
    let acc = Fixed { raw: -0xcbee5298d417d };
    let acc = step(u, acc, Fixed { raw: 0x1cad3ea0417354 });
    let acc = step(u, acc, Fixed { raw: -0x45eea113ab6f30 });
    let acc = step(u, acc, Fixed { raw: 0xe347ab3cdab568 });
    step(u, acc, Fixed { raw: 0xb35004723dd420 })
}

/// `log2(1 + 21 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg21(u: W1) -> Fixed {
    let acc = Fixed { raw: -0xbd1aef74032a4 };
    let acc = step(u, acc, Fixed { raw: 0x1b159ce7cfc9fb });
    let acc = step(u, acc, Fixed { raw: -0x43516f01a4e634 });
    let acc = step(u, acc, Fixed { raw: 0xdefddd243fc428 });
    step(u, acc, Fixed { raw: 0xba58feb271a488 })
}

/// `log2(1 + 22 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg22(u: W1) -> Fixed {
    let acc = Fixed { raw: -0xaf9a466026a86 };
    let acc = step(u, acc, Fixed { raw: 0x199b9bb4c36650 });
    let acc = step(u, acc, Fixed { raw: -0x40d911ef59bb28 });
    let acc = step(u, acc, Fixed { raw: 0xdadcb7dd164698 });
    step(u, acc, Fixed { raw: 0xc1404eadf4cd90 })
}

/// `log2(1 + 23 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg23(u: W1) -> Fixed {
    let acc = Fixed { raw: -0xa348b3cc33aa7 };
    let acc = step(u, acc, Fixed { raw: 0x183c9656cf9de8 });
    let acc = step(u, acc, Fixed { raw: -0x3e82e2651dcb36 });
    let acc = step(u, acc, Fixed { raw: 0xd6e203a66c48c8 });
    step(u, acc, Fixed { raw: 0xc80730b00143b0 })
}

/// `log2(1 + 24 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg24(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x9806e009df3a1 };
    let acc = step(u, acc, Fixed { raw: 0x16f62f48ea7fb5 });
    let acc = step(u, acc, Fixed { raw: -0x3c4c7509d83940 });
    let acc = step(u, acc, Fixed { raw: 0xd30bb14d17c628 });
    step(u, acc, Fixed { raw: 0xceaecfea819928 })
}

/// `log2(1 + 25 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg25(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x8db92cb2281f2 };
    let acc = step(u, acc, Fixed { raw: 0x15c6479e8a020d });
    let acc = step(u, acc, Fixed { raw: -0x3a33945d62d196 });
    let acc = step(u, acc, Fixed { raw: 0xcf57d69d07f7e8 });
    step(u, acc, Fixed { raw: 0xd53847ac01a300 })
}

/// `log2(1 + 26 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg26(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x844731cded6df };
    let acc = step(u, acc, Fixed { raw: 0x14aaf79420426e });
    let acc = step(u, acc, Fixed { raw: -0x38363b32e58d84 });
    let acc = step(u, acc, Fixed { raw: 0xcbc4ab30cbf5d8 });
    step(u, acc, Fixed { raw: 0xdba4a47aaa7e60 })
}

/// `log2(1 + 27 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg27(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x7b9b56c5314de };
    let acc = step(u, acc, Fixed { raw: 0x13a28827057d92 });
    let acc = step(u, acc, Fixed { raw: -0x36528fd1ad2b02 });
    let acc = step(u, acc, Fixed { raw: 0xc8508594219300 });
    step(u, acc, Fixed { raw: 0xe1f4e5170dd760 })
}

/// `log2(1 + 28 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg28(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x73a2706fc78f7 };
    let acc = step(u, acc, Fixed { raw: 0x12ab6d77a43f06 });
    let acc = step(u, acc, Fixed { raw: -0x3486dfa5fa27f4 });
    let acc = step(u, acc, Fixed { raw: 0xc4f9d8afdbddb8 });
    step(u, acc, Fixed { raw: 0xe829fb69310868 })
}

/// `log2(1 + 29 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg29(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x6c4b7585969ce };
    let acc = step(u, acc, Fixed { raw: 0x11c441f0672ba3 });
    let acc = step(u, acc, Fixed { raw: -0x32d19b6fa2ff86 });
    let acc = step(u, acc, Fixed { raw: 0xc1bf3176b7a1c0 });
    step(u, acc, Fixed { raw: 0xee44cd5a005fb0 })
}

/// `log2(1 + 30 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg30(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x6587391571643 };
    let acc = step(u, acc, Fixed { raw: 0x10ebc202fe2ee7 });
    let acc = step(u, acc, Fixed { raw: -0x313153ddf8da5e });
    let acc = step(u, acc, Fixed { raw: 0xbe9f34cbc87600 });
    step(u, acc, Fixed { raw: 0xf446359b13f9f0 })
}

/// `log2(1 + 31 / 32 + t)` for `t` in `[0, 1/32)`, degree 4, at the scale
/// `2^56`.
#[inline(always)]
fn log2_seg31(u: W1) -> Fixed {
    let acc = Fixed { raw: -0x5f483266a60ef };
    let acc = step(u, acc, Fixed { raw: 0x1020c87414b344 });
    let acc = step(u, acc, Fixed { raw: -0x2fa4b68b845bd0 });
    let acc = step(u, acc, Fixed { raw: 0xbb989d9c18ac20 });
    step(u, acc, Fixed { raw: 0xfa2f045e78cc50 })
}

/// Dispatches `log2(1 + j / 32 + t)` on the segment index (a jump table, never an if-chain).
#[inline(always)]
fn log2_poly(j: u64, u: W1) -> Fixed {
    match j {
        0 => log2_seg0(u),
        1 => log2_seg1(u),
        2 => log2_seg2(u),
        3 => log2_seg3(u),
        4 => log2_seg4(u),
        5 => log2_seg5(u),
        6 => log2_seg6(u),
        7 => log2_seg7(u),
        8 => log2_seg8(u),
        9 => log2_seg9(u),
        10 => log2_seg10(u),
        11 => log2_seg11(u),
        12 => log2_seg12(u),
        13 => log2_seg13(u),
        14 => log2_seg14(u),
        15 => log2_seg15(u),
        16 => log2_seg16(u),
        17 => log2_seg17(u),
        18 => log2_seg18(u),
        19 => log2_seg19(u),
        20 => log2_seg20(u),
        21 => log2_seg21(u),
        22 => log2_seg22(u),
        23 => log2_seg23(u),
        24 => log2_seg24(u),
        25 => log2_seg25(u),
        26 => log2_seg26(u),
        27 => log2_seg27(u),
        28 => log2_seg28(u),
        29 => log2_seg29(u),
        30 => log2_seg30(u),
        _ => log2_seg31(u),
    }
}

/// `(2^(62 - e), (e - 32) * 2^56)` for `e = floor(log2(x))`, `x` in `[1, 2^63)`: an unrolled
/// binary search on constant thresholds (6 comparisons, no loop, no bitwise operation).
#[inline(always)]
#[allow(collapsible_if_else)]
fn normalize(x: u64) -> (u64, i64) {
    if x < 0x80000000 {
        if x < 0x8000 {
            if x < 0x80 {
                if x < 0x8 {
                    if x < 0x2 {
                        (0x4000000000000000, -0x2000000000000000)
                    } else {
                        if x < 0x4 {
                            (0x2000000000000000, -0x1f00000000000000)
                        } else {
                            (0x1000000000000000, -0x1e00000000000000)
                        }
                    }
                } else {
                    if x < 0x20 {
                        if x < 0x10 {
                            (0x800000000000000, -0x1d00000000000000)
                        } else {
                            (0x400000000000000, -0x1c00000000000000)
                        }
                    } else {
                        if x < 0x40 {
                            (0x200000000000000, -0x1b00000000000000)
                        } else {
                            (0x100000000000000, -0x1a00000000000000)
                        }
                    }
                }
            } else {
                if x < 0x800 {
                    if x < 0x200 {
                        if x < 0x100 {
                            (0x80000000000000, -0x1900000000000000)
                        } else {
                            (0x40000000000000, -0x1800000000000000)
                        }
                    } else {
                        if x < 0x400 {
                            (0x20000000000000, -0x1700000000000000)
                        } else {
                            (0x10000000000000, -0x1600000000000000)
                        }
                    }
                } else {
                    if x < 0x2000 {
                        if x < 0x1000 {
                            (0x8000000000000, -0x1500000000000000)
                        } else {
                            (0x4000000000000, -0x1400000000000000)
                        }
                    } else {
                        if x < 0x4000 {
                            (0x2000000000000, -0x1300000000000000)
                        } else {
                            (0x1000000000000, -0x1200000000000000)
                        }
                    }
                }
            }
        } else {
            if x < 0x800000 {
                if x < 0x80000 {
                    if x < 0x20000 {
                        if x < 0x10000 {
                            (0x800000000000, -0x1100000000000000)
                        } else {
                            (0x400000000000, -0x1000000000000000)
                        }
                    } else {
                        if x < 0x40000 {
                            (0x200000000000, -0xf00000000000000)
                        } else {
                            (0x100000000000, -0xe00000000000000)
                        }
                    }
                } else {
                    if x < 0x200000 {
                        if x < 0x100000 {
                            (0x80000000000, -0xd00000000000000)
                        } else {
                            (0x40000000000, -0xc00000000000000)
                        }
                    } else {
                        if x < 0x400000 {
                            (0x20000000000, -0xb00000000000000)
                        } else {
                            (0x10000000000, -0xa00000000000000)
                        }
                    }
                }
            } else {
                if x < 0x8000000 {
                    if x < 0x2000000 {
                        if x < 0x1000000 {
                            (0x8000000000, -0x900000000000000)
                        } else {
                            (0x4000000000, -0x800000000000000)
                        }
                    } else {
                        if x < 0x4000000 {
                            (0x2000000000, -0x700000000000000)
                        } else {
                            (0x1000000000, -0x600000000000000)
                        }
                    }
                } else {
                    if x < 0x20000000 {
                        if x < 0x10000000 {
                            (0x800000000, -0x500000000000000)
                        } else {
                            (0x400000000, -0x400000000000000)
                        }
                    } else {
                        if x < 0x40000000 {
                            (0x200000000, -0x300000000000000)
                        } else {
                            (0x100000000, -0x200000000000000)
                        }
                    }
                }
            }
        }
    } else {
        if x < 0x800000000000 {
            if x < 0x8000000000 {
                if x < 0x800000000 {
                    if x < 0x200000000 {
                        if x < 0x100000000 {
                            (0x80000000, -0x100000000000000)
                        } else {
                            (0x40000000, 0x0)
                        }
                    } else {
                        if x < 0x400000000 {
                            (0x20000000, 0x100000000000000)
                        } else {
                            (0x10000000, 0x200000000000000)
                        }
                    }
                } else {
                    if x < 0x2000000000 {
                        if x < 0x1000000000 {
                            (0x8000000, 0x300000000000000)
                        } else {
                            (0x4000000, 0x400000000000000)
                        }
                    } else {
                        if x < 0x4000000000 {
                            (0x2000000, 0x500000000000000)
                        } else {
                            (0x1000000, 0x600000000000000)
                        }
                    }
                }
            } else {
                if x < 0x80000000000 {
                    if x < 0x20000000000 {
                        if x < 0x10000000000 {
                            (0x800000, 0x700000000000000)
                        } else {
                            (0x400000, 0x800000000000000)
                        }
                    } else {
                        if x < 0x40000000000 {
                            (0x200000, 0x900000000000000)
                        } else {
                            (0x100000, 0xa00000000000000)
                        }
                    }
                } else {
                    if x < 0x200000000000 {
                        if x < 0x100000000000 {
                            (0x80000, 0xb00000000000000)
                        } else {
                            (0x40000, 0xc00000000000000)
                        }
                    } else {
                        if x < 0x400000000000 {
                            (0x20000, 0xd00000000000000)
                        } else {
                            (0x10000, 0xe00000000000000)
                        }
                    }
                }
            }
        } else {
            if x < 0x80000000000000 {
                if x < 0x8000000000000 {
                    if x < 0x2000000000000 {
                        if x < 0x1000000000000 {
                            (0x8000, 0xf00000000000000)
                        } else {
                            (0x4000, 0x1000000000000000)
                        }
                    } else {
                        if x < 0x4000000000000 {
                            (0x2000, 0x1100000000000000)
                        } else {
                            (0x1000, 0x1200000000000000)
                        }
                    }
                } else {
                    if x < 0x20000000000000 {
                        if x < 0x10000000000000 {
                            (0x800, 0x1300000000000000)
                        } else {
                            (0x400, 0x1400000000000000)
                        }
                    } else {
                        if x < 0x40000000000000 {
                            (0x200, 0x1500000000000000)
                        } else {
                            (0x100, 0x1600000000000000)
                        }
                    }
                }
            } else {
                if x < 0x800000000000000 {
                    if x < 0x200000000000000 {
                        if x < 0x100000000000000 {
                            (0x80, 0x1700000000000000)
                        } else {
                            (0x40, 0x1800000000000000)
                        }
                    } else {
                        if x < 0x400000000000000 {
                            (0x20, 0x1900000000000000)
                        } else {
                            (0x10, 0x1a00000000000000)
                        }
                    }
                } else {
                    if x < 0x2000000000000000 {
                        if x < 0x1000000000000000 {
                            (0x8, 0x1b00000000000000)
                        } else {
                            (0x4, 0x1c00000000000000)
                        }
                    } else {
                        if x < 0x4000000000000000 {
                            (0x2, 0x1d00000000000000)
                        } else {
                            (0x1, 0x1e00000000000000)
                        }
                    }
                }
            }
        }
    }
}

/// Measured maximum error of the mirrored implementation (`scripts/gen_exp.py sweep`):
/// absolute in ULP (`2^-32`), or relative in units of `2^-30` where marked.
///
/// | function | range | max error |
/// |---|---|---:|
/// | `exp2` | result < 2^16 | 2.02 |
/// | `exp2` | result >= 2^16 | 7.14e-06 x 2^-30 |
/// | `exp` | result < 2^16 | 2.02 |
/// | `exp` | result >= 2^16 | 7.12e-06 x 2^-30 |
/// | `exp_m1` | [-1, 1] | 2.01 |
/// | `log2` | [2^-32, 2^31) | 0.75 |
/// | `ln` | [2^-32, 2^31) | 0.66 |
/// | `log10` | [2^-32, 2^31) | 0.57 |
/// | `ln_1p` | [-1/2, 1] | 0.64 |
/// | `log` | bases 2, 10, 1.5, 1/3, 1000 | 1.88 |
/// | `powf` | x in [2^-8, 2^8], n in [-4, 4], result < 1 | 2.05 |
/// | `powf` | x in [2^-8, 2^8], n in [-4, 4], result >= 1 | 4.32e-01 x 2^-30 |
// GENERATED-END exp

/// `31 * 2^24`: `n * log2(x)` at the scale of `powf`'s coarse check; from there on `x^n` does
/// not fit.
const POW_T_MAX: i64 = 0x1f000000;
/// `-33 * 2^24`: below it `x^n < 2^-33` rounds to zero.
const POW_T_MIN: i64 = -0x21000000;

pub trait ExpTrait {
    /// Computes `e^self`.
    ///
    /// Mirrors `f32::exp`.
    /// #### Panics
    /// * `'Fixed: exp overflow'` if the result does not fit the scalar range, i.e. for
    ///   `self >= 21.487` (`31 ln 2`), where `f32::exp` returns a large value or infinity.
    /// #### Deviations
    /// * Returns `ZERO` below `-22.873` (`-33 ln 2`), where the result is below half an ULP.
    /// * Rounds toward negative infinity: within 2.02 ULP below the exact value for results
    ///   below `2^16`, within `7.2e-6 * 2^-30` relative above (see the table above).
    ///   `exp(0) = 1` exactly, and the function is non-decreasing over the whole range.
    fn exp(self: Fixed) -> Fixed;
    /// Computes `2^self`.
    ///
    /// Mirrors `f32::exp2`.
    /// #### Panics
    /// * `'Fixed: exp overflow'` if `self >= 31`.
    /// #### Deviations
    /// * Returns `ZERO` below `-33`, where the result is below half an ULP.
    /// * Rounds toward negative infinity: within 2.02 ULP below the exact value for results
    ///   below `2^16`, within `7.2e-6 * 2^-30` relative above. `exp2(k) = 2^k` exactly for
    ///   every integer `k` in `[-32, 30]`, and the function is non-decreasing.
    fn exp2(self: Fixed) -> Fixed;
    /// Computes `e^self - 1`.
    ///
    /// Mirrors `f32::exp_m1`.
    /// #### Panics
    /// * `'Fixed: exp overflow'` as [`ExpTrait::exp`].
    /// #### Deviations
    /// * Computed as `exp(self) - 1`: a fixed-point result has an absolute precision, so the
    ///   cancellation that `f32::exp_m1` avoids near zero does not exist here (2.01 ULP on
    ///   `[-1, 1]`). Returns `-1` below `-22.873`.
    fn exp_m1(self: Fixed) -> Fixed;
    /// Computes the natural logarithm of `self`.
    ///
    /// Mirrors `f32::ln`.
    /// #### Panics
    /// * `'Fixed: ln domain'` if `self <= 0` (`f32::ln` returns NaN or negative infinity).
    /// #### Deviations
    /// * Maximum absolute error 0.66 ULP over the whole positive range; `ln(1) = 0` exactly and
    ///   the function is non-decreasing.
    fn ln(self: Fixed) -> Fixed;
    /// Computes the base-2 logarithm of `self`.
    ///
    /// Mirrors `f32::log2`.
    /// #### Panics
    /// * `'Fixed: ln domain'` if `self <= 0`.
    /// #### Deviations
    /// * Maximum absolute error 0.75 ULP over the whole positive range; `log2(2^k) = k` exactly
    ///   for every `k` in `[-32, 30]` and the function is non-decreasing.
    fn log2(self: Fixed) -> Fixed;
    /// Computes the base-10 logarithm of `self`.
    ///
    /// Mirrors `f32::log10`.
    /// #### Panics
    /// * `'Fixed: ln domain'` if `self <= 0`.
    /// #### Deviations
    /// * Maximum absolute error 0.57 ULP over the whole positive range; `log10(1) = 0` exactly.
    fn log10(self: Fixed) -> Fixed;
    /// Computes `ln(1 + self)`.
    ///
    /// Mirrors `f32::ln_1p`.
    /// #### Panics
    /// * `'Fixed: ln domain'` if `self <= -1`.
    /// * `'i64_add Overflow'` if `self + 1` does not fit the scalar range.
    /// #### Deviations
    /// * Computed as `ln(self + 1)`, which is exact in fixed point (the addition does not round):
    ///   0.64 ULP on `[-1/2, 1]`.
    fn ln_1p(self: Fixed) -> Fixed;
    /// Computes the logarithm of `self` in base `base`, as `log2(self) / log2(base)` on the
    /// unrounded 56-bit accumulators.
    ///
    /// Mirrors `f32::log`.
    /// #### Panics
    /// * `'Fixed: ln domain'` if `self <= 0` or `base <= 0`.
    /// * `'Fixed: division by zero'` if `base == 1`.
    /// * `'Fixed: overflow'` if the quotient does not fit the scalar range (`base` within
    ///   `2^-31`-ish of 1).
    /// #### Deviations
    /// * The division truncates, like every `/` of the crate: 1.88 ULP for the bases 2, 10,
    ///   1.5, 1/3 and 1000. A base close to 1 amplifies the error of the numerator by
    ///   `1 / |log2(base)|`.
    fn log(self: Fixed, base: Fixed) -> Fixed;
    /// Raises `self` to the power `n`: `exp2(n * log2(self))`, the product being kept at 88
    /// fractional bits (never rounded to 32).
    ///
    /// Mirrors `f32::powf`.
    /// #### Panics
    /// * `'Fixed: overflow'` if the result does not fit the scalar range.
    /// * `'Fixed: division by zero'` if `self == 0` and `n < 0` (Rust returns infinity).
    /// * `'Fixed: powf domain'` if `self < 0` and `n` is not an integer (Rust returns NaN).
    /// * `'i64_neg Underflow'` if `self` is `MIN` (its magnitude does not fit).
    /// #### Deviations
    /// * `0^n = 0` for `n > 0` and `x^0 = 1` for every `x`, as in Rust.
    /// * A negative base is accepted for an integer `n` only, and computed as
    ///   `(-1)^n * |self|^n` (the same values as a positive base, with the sign of `powi`).
    /// * Error: the relative error of the `log2` stage (~`2^-36`) is multiplied by
    ///   `|n log(self)|`, then `exp2` adds its own; measured for `self` in `[2^-8, 2^8]` and `n`
    ///   in `[-4, 4]`: within `0.44 * 2^-30` relative for results above 1, within 2.05 ULP below.
    ///   `powf(x, 1)` is therefore not bit-identical to `x`; use `powi` for integer exponents.
    /// * Returns `ZERO` when the exact result is below `2^-33`.
    fn powf(self: Fixed, n: Fixed) -> Fixed;
}

pub impl ExpImpl of ExpTrait {
    fn exp(self: Fixed) -> Fixed {
        assert(self.raw < EXP_MAX_RAW, 'Fixed: exp overflow');
        if self.raw < EXP_MIN_RAW {
            return ZERO;
        }
        exp_from_q(wide_mul(self, LOG2_E_Q).narrow())
    }

    fn exp2(self: Fixed) -> Fixed {
        assert(self.raw < EXP2_MAX_RAW, 'Fixed: exp overflow');
        if self.raw < EXP2_MIN_RAW {
            return ZERO;
        }
        // EXP2_MIN_RAW <= self < EXP2_MAX_RAW: the biased value is in [0, 2^38).
        let biased: u64 = (self.raw + EXP2_BIAS).try_into().unwrap();
        let (idx, g) = DivRem::div_rem(biased, EXP2_SEG_NZ);
        // g < 2^28: the conversion cannot fail.
        exp2_core(idx, wide_from(Fixed { raw: g.try_into().unwrap() }))
    }

    #[inline(always)]
    fn exp_m1(self: Fixed) -> Fixed {
        Self::exp(self) - ONE
    }

    fn ln(self: Fixed) -> Fixed {
        rescale(log2_core(self), K_LN)
    }

    fn log2(self: Fixed) -> Fixed {
        rescale(log2_core(self), K_LOG2)
    }

    fn log10(self: Fixed) -> Fixed {
        rescale(log2_core(self), K_LOG10)
    }

    #[inline(always)]
    fn ln_1p(self: Fixed) -> Fixed {
        Self::ln(self + ONE)
    }

    fn log(self: Fixed, base: Fixed) -> Fixed {
        // Both accumulators are at the scale 2^56: the quotient of the raw values is the result.
        Fixed { raw: log2_core(self) } / Fixed { raw: log2_core(base) }
    }

    fn powf(self: Fixed, n: Fixed) -> Fixed {
        if self.raw > 0 {
            return pow_pos(self, n);
        }
        if self.raw == 0 {
            if n.raw > 0 {
                return ZERO;
            }
            assert(n.raw == 0, 'Fixed: division by zero');
            return ONE;
        }
        assert(FixedTrait::fract_gl(n).raw == 0, 'Fixed: powf domain');
        let r = pow_pos(-self, n);
        if FixedTrait::to_int(n) % 2 == 0 {
            r
        } else {
            -r
        }
    }
}

/// One Horner step at the Q96.96 scale: `floor(acc * u + c)` where `u` is an exact Q64.64
/// fraction. One rescale per step.
#[inline(always)]
fn step(u: W1, acc: Fixed, c: Fixed) -> Fixed {
    u.mul(acc).add(wide_from(c).lift()).narrow()
}

/// `2^(idx / 16 - 33) * 2^g` with `u = g * 2^64`: one table lookup, one Horner chain, one floor
/// rescale (`TABLE * P * 16 / 2^64`, i.e. `TABLE * P / 2^60`, as a single Q96.96 product).
#[inline(always)]
fn exp2_core(idx: u64, u: W1) -> Fixed {
    // idx < 1024: the conversion cannot fail.
    let t = *EXP2_TABLE.span()[idx.try_into().unwrap()];
    wide_mul(Fixed { raw: t }, exp2_poly(u)).mul(SIXTEEN).narrow()
}

/// `2^t` from the wide exponent `q = floor(t * 2^56)`, `t` in `[-33, 31)`.
#[inline(always)]
fn exp_from_q(q: Fixed) -> Fixed {
    // -33 <= t < 31: the biased value is in [0, 2^62).
    let biased: u64 = (q.raw + EXP_BIAS_Q).try_into().unwrap();
    let (idx, g) = DivRem::div_rem(biased, EXP_SEG_Q_NZ);
    // g < 2^52: the conversion cannot fail.
    exp2_core(idx, wide_mul(Fixed { raw: g.try_into().unwrap() }, EXP_FRAC_LIFT))
}

/// `log2(x) * 2^56`, unrounded (each Horner step floors): the shared core of the logarithms and
/// of `powf`.
fn log2_core(x: Fixed) -> i64 {
    assert(x.raw > 0, 'Fixed: ln domain');
    // x > 0: the conversion cannot fail.
    let xu: u64 = x.raw.try_into().unwrap();
    let (c, ek) = normalize(xu);
    // xu * 2^(62 - e) is the mantissa in [2^62, 2^63): exact, no overflow.
    let (j, t) = DivRem::div_rem(xu * c - MANT_ONE, LOG_SEG_NZ);
    // t < 2^57: the conversion cannot fail.
    let acc = log2_poly(j, wide_mul(Fixed { raw: t.try_into().unwrap() }, LOG_FRAC_LIFT));
    ek + acc.raw
}

/// `round(a * k / 2^64)`: the single rounded rescale of the logarithms.
#[inline(always)]
fn rescale(a: i64, k: Fixed) -> Fixed {
    Fixed { raw: bounded::narrow64_round(upcast(wide_mul(Fixed { raw: a }, k).v)) }
}

/// `x^n` for `x > 0`.
fn pow_pos(x: Fixed, n: Fixed) -> Fixed {
    // w = n * log2(x) * 2^88, exact.
    let w = wide_mul(Fixed { raw: log2_core(x) }, n);
    // |n * log2(x)| < 2^36: its value at 24 fractional bits always fits, and tells whether the
    // result over- or underflows before the precise exponent is narrowed.
    let t24 = bounded::narrow64(upcast(w.v));
    assert(t24 < POW_T_MAX, 'Fixed: overflow');
    if t24 < POW_T_MIN {
        return ZERO;
    }
    exp_from_q(w.narrow())
}
