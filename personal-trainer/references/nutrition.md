# Nutrition Protocol

## Energy math
- **BMR (Mifflin-St Jeor, male):** 10·kg + 6.25·cm − 5·age + 5. Example: 80 kg, 175 cm, age 35 → ≈ 1,820 kcal.
- **Maintenance:** starts at BMR × 1.4 + ~250 ≈ **2,670 kcal** (uncertain; activity level is probably 1.5–1.7). With 5+ days of data, it uses the 14-day Apple Health average. From 14+ days with 10+ fully logged days and 8+ weigh-ins, it switches to an **adaptive TDEE**: mean logged intake − (median-based weight slope, lb/day × 3,500) over the last 21 days. It skips the first 10 days of the cut (water loss), and blends with the earlier estimate until 21 days are logged. This cancels out steady under-logging.
- **Target:** maintenance − 500, plus ½ × (today's hockey/golf kcal − your average daily sport kcal). The baseline already includes your average sport, so this only shifts calories between days, with no double-counting. Floor of 1,800.
- **Expected rate:** ~0.75–1.0 lb/week, so 182 → 170 takes ~12–16 weeks, matching the 16-week program. Water swings of ±2–3 lb from travel, sodium and games are normal, so judge the trend line.
- **Watch accuracy:** wrist energy estimates carry roughly 20–30% error, with no consistent direction. Resting energy is calculated, not measured. Trust the adaptive TDEE over the watch.
- **Trend weight:** an exponential average adjusted for gaps between weigh-ins (time constant 10 days). Rate and goal date come from a median-based slope on raw weigh-ins over 28 days.

## Macros
| | Daily | Why |
|---|---|---|
| Protein | 175 g (~2.1 g/kg; ~1 g/lb of goal weight) | Keeps lean mass while in a deficit |
| Fat | 70 g (~0.85 g/kg, ~30%) | The minimum is ~0.5–0.6 g/kg; 60–65 g is fine if you want more carbs for hockey |
| Carbs | the rest (~150–200 g; +50 g on hockey and golf days) | Fuels intensity |

Spread protein over 4 feedings of 35–50 g (leucine threshold).

## Activity estimates (net kcal = (MET − 1) × kg × h)
| Activity | MET | ~Net kcal at 82 kg |
|---|---|---|
| Rec hockey, 60 min (incl. bench time) | 7.0 | ~495 |
| Golf, 18 walking (4 h) | 4.8 | ~1,250 |
| Golf, 18 with cart (4 h) | 2.8 | ~595 |
| Strength session, 30 min | 4.5 | ~145 |
| Zone 2, 30 min | 6.0 | ~205 |

## Situational fueling
- **Hockey night:** 40–60 g carbs 2–3 h before. Within 2 h after, 40 g protein + 60–80 g carbs. Beer counts: 3 beers ≈ 450 kcal.
- **Golf, 18 walking:** 2 snacks of ~200 kcal (bar, banana + jerky) around the turn. Hydrate. Halfway-house hot dogs are ~300 kcal each, so log them.
- **Road trips:** hotel breakfast = 3–4 eggs + Greek yogurt + fruit. Team meals: fill half the plate with lean protein and take one starch. Photograph the plate for a Claude estimate.
- **Late nights at the rink:** have a protein-first fallback ready (shake + fruit, ~350 kcal) so you're not stuck with arena food.

## Estimating a meal from a photo or description
Itemize every food, with the portion in grams or household measures. Assume cooking fat for restaurant food (1–2 tbsp, +120–240 kcal). List sauces, oils and drinks as separate items. Give alcohol in grams (7 kcal/g). Size portions as actually served: restaurant and team-meal portions run 1.5–2× a USDA serving. State a confidence level and a kcal range. Photo estimates are typically within ±20–30%, so consistency matters more than precision: the weight trend will expose a systematic bias, and you adjust the target.
