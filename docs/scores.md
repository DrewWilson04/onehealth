# Derived scores

These are PulseBoard's **own estimates**, computed on-device from raw data that every wearable shares through Apple Health:
- heart rate
- HRV
- resting HR
- sleep stages
- steps
- workouts

They are **not** equivalent to, and not calibrated against, WHOOP Recovery/Strain, Garmin Body Battery or Oura Readiness. The app labels them as estimates, and they are **not medical advice**.

**Reference implementation:**
- iOS: `ios/Packages/PulseCore/Sources/PulseCore/Scores/` and `Gaps/`
- Web port: `web/src/core/scores.ts`

Both are tested against [`fixtures/scores_cases.json`](fixtures/scores_cases.json) with a tolerance of ±0.05.
- To regenerate the fixture inputs, run `tools/generate_scores.py`.
- To re-record the expected values:
  ```sh
  RECORD_FIXTURES=1 swift test --filter ScoreFixtureTests | python3 tools/merge_expected.py
  ```

## Shared rules

- **Adaptive inputs.** A score uses whatever inputs exist.
  - Missing components are dropped and the remaining weights are **renormalized** so they sum to 1.
  - Every result lists `inputsUsed`, `missingInputs`, its components with effective weights, and a `confidence`.
- **Not enough data.** When a *key* input is missing, `value = null` and a `reason` is shown. We never guess.
- **Baselines** cover the trailing 30 days, **excluding the day being scored and any estimated values**. A baseline needs at least 10 days.
- **Per-source HRV.** HRV is scored against a baseline from the **same source**. The source is the preferred one if set, otherwise the one with the most days in the last 30. Apple Watch writes SDNN, while some wearables write RMSSD-style values into the same type, so mixing sources would be meaningless.
- `logistic(x) = 1 / (1 + e^(−x))`, and `clamp` limits values to 0–100.

## Sleep Score (0–100) — free

| Component | Weight | Sub-score |
|---|---|---|
| Duration | 0.40 | `r = asleep / goal`; `100 · min(1, r)^1.5`. If `r > 1.3`: `max(70, 100 − (r − 1.3)·100)` |
| Efficiency | 0.20 | `e = asleep / in-bed`; `clamp((e − 0.70) / 0.25 · 100)` (70 % → 0, 95 %+ → 100) |
| Consistency | 0.20 | Needs ≥ 3 of the last 7 nights. `sd = (circSD(onset) + circSD(wake)) / 2` in minutes; `clamp(100 − (sd − 15) · 100/75)` (≤ 15 min → 100, ≥ 90 min → 0) |
| Stages | 0.20 | Only when the primary source recorded stages. Mean of `band(deep %, 13, 23)` and `band(REM %, 20, 25)`. `band` = 100 inside the band, falling linearly to 0 at 10 points below or 15 points above. |

- **Circular SD:** `sqrt(−2 ln R) / 2π · 1440`. Here `R` is the mean resultant length of clock times mapped to angles, so 23:50 and 00:10 count as 20 minutes apart.
- **Not enough data:** no night ended on the day, or less than 60 minutes asleep.
- **Confidence:** high with 4 components, medium with 3, low otherwise. If the night was estimated, confidence is at most medium.

## Readiness (0–100) — free

| Component | Weight | Sub-score |
|---|---|---|
| HRV | 0.40 | `z = (ln HRV_today − mean(ln HRV)) / max(sd, 0.10)`; `100 · logistic(0.6 + 1.2 z)` |
| Resting HR | 0.25 | `z = (RHR_today − mean) / max(sd, 2 bpm)`; `100 · logistic(0.6 − 1.2 z)` |
| Sleep | 0.35 | The Sleep Score above |

- At the baseline (z = 0) each sub-score is about 65; +1 SD gives about 86, and −1 SD about 35.
- **Not enough data:** neither HRV nor RHR has both a baseline and a today value (measured or gap-filled).
- **Confidence:** high with 3 components, medium with 2, low with 1. If any input was estimated, confidence is at most medium.

## Strain / Training Load (0–21) — Pro

**HR profile**
- **Rest:** the 30-day resting-HR baseline (minimum 3 days), otherwise today's RHR.
- **HRmax** (Tanaka): `208 − 0.7 · age`.
  - If the observed maximum is higher, it is used instead, capped at Tanaka + 15 to ignore optical spikes.
  - Without an age: the observed maximum, clamped to 160–220 (default 190).
- `HRR(h) = clamp((h − rest) / (max − rest), 0, 1)`.
- **Zones by %HRR:** Z1 50–60, Z2 60–70, Z3 70–80, Z4 80–90, Z5 90+.

**TRIMP (Banister):**
- `Σ Δt · x · k₁ · e^(k₂ x)`.
  - `Δt` is minutes between consecutive HR readings, capped at 5.
  - `x` is the HRR of the interval's mean HR.
  - Intervals with `x < 0.25` are ignored (resting).
- `(k₁, k₂)` = (0.64, 1.92), or (0.86, 1.67) when biological sex is female.
- The input is the day's HR series: workouts plus daytime HR.

**Display strain:** `21 · ln(1 + TRIMP/20) / ln 21`, clamped to 0–21 (TRIMP 400 ≈ 21).

**Acute:chronic workload ratio (ACWR)**
- `mean(daily TRIMP, last 7 days) / mean(last 28 days)`.
- Days without HR data are excluded, not counted as rest.
- Needs ≥ 4 acute and ≥ 14 chronic days.

| ACWR | Status |
|---|---|
| < 0.8 | Below your usual load (undertraining) |
| 0.8 – 1.3 | Optimal |
| 1.3 – 1.5 | Load is climbing (caution) |
| > 1.5 | Much higher than usual (overtraining risk) |

**Not enough data:** no resting-HR baseline, or fewer than 10 HR readings today.

**Confidence:** high with ≥ 100 readings, medium with ≥ 40, low otherwise.

## Energy (0–100, Body-Battery-style) — Pro

The model simulates 15-minute slots from wake time to now.

**Start value:** `clamp(20 + 0.8 · R)`, where `R = 0.6 · SleepScore + 0.4 · HRV sub-score`. Without HRV, `R = SleepScore`.

**Per slot:**
- **Asleep (nap):** `+1.5 · (1 − E/100)`.
- **Awake:**
  - Baseline drain: `−0.15`, about 0.6 per hour.
  - If `HRR(HR) ≥ 0.25`, activity drain: `−0.25 · 15 · x · k₁ e^(k₂x)`, i.e. 0.25 per TRIMP unit.
  - Otherwise, if still (< 50 steps in the slot and not in a workout):
    - Stress: if `HR > RHR + 15`, `−min(2, 0.08 · (HR − RHR − 15))`.
    - Rest: if `HR ≤ RHR + 5`, `+0.3`.
- `E` is clamped to 0–100 after every slot.

**Gaps:** HR gaps of up to 3 hours are linearly interpolated, which marks the score estimated.

**Not enough data:** no sleep last night, no RHR baseline, or HR in under 25 % of slots.

**Confidence:** high above 70 % HR coverage, medium above 35 %, low otherwise. Estimated inputs cap it at medium.

## Gap handling

- **Daily:** a missing day is filled only if a measured value exists within the previous **2 days**.
  - `value = w · last + (1 − w) · baseline30`, with `w = 0.5` (1 day back) or `0.25` (2 days back).
  - Confidence: high if 1 day back and baseline CV < 0.10; medium if CV < 0.25; low otherwise. A 2-day gap is at most medium.
- **Intraday:** gaps of up to **3 hours** are interpolated linearly at 15-minute steps.
- **Labels:** filled values carry `isEstimated = true` and the confidence level, and the UI shows an "Estimated" pill.
- **Exclusions:** filled values are **never** used in baselines, personal bests, streaks or **challenge scoring**.

## Recompute policy (battery)
- Scores are cached per day (`ScoreRecord`).
- Ingestion reports *dirty days*. Only those days, and today, are recomputed, and the work is batched after each sync.
- Daily TRIMP is cached so the ACWR never rescans 28 days of heart rate.
