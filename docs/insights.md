# Insights stats engine

**Reference implementation:**
- iOS: `ios/Packages/PulseCore/Sources/PulseCore/Insights/`
- Web port: `web/src/core/insights.ts`

Both are tested against [`fixtures/insights_cases.json`](fixtures/insights_cases.json). That fixture contains planted effects that must be found, and pure-noise data that must produce no relationships.

## Inputs (daily features)
- **Measured daily values only.** Estimated values are never used:
  - steps
  - active energy
  - exercise minutes
  - resting HR
  - HRV
  - respiratory rate
  - wrist temperature
  - weight
  - VO₂ max
  - caffeine
- **Night features**, keyed by wake day: `sleepMinutes`, and `bedtimeAfter18` (minutes after 18:00).
- **Flags:** `workoutDay` and `lateWorkout` (a workout ending at or after 19:00).
  - Both are 0 on worn days without a workout. A day counts as worn when it has step data.
- `weekend`.
- `score.readiness`.

The lookback is 90 days.

## Analyses

### 1. Conditional differences (Welch t-test)
This is a curated list, which keeps the number of comparisons small.

| id | Condition (day D) | Outcome | Lag | Minimum effect |
|---|---|---|---|---|
| `lateWorkout-hrv` | workout ends ≥ 19:00 | HRV | D+1 | 2 ms |
| `steps8k-sleep` | steps ≥ 8,000 | sleep | night ending D+1 | 10 min |
| `workout-sleep` | any workout | sleep | D+1 | 10 min |
| `caffeine-sleep` | caffeine ≥ 200 mg | sleep | D+1 | 10 min |
| `weekend-sleep` | wake day is Sat/Sun | sleep | 0 | 15 min |
| `lateBed-readiness` | fell asleep after 00:00 | readiness | 0 | 3 pts |

Each group needs at least 7 days.

### 2. Correlations (Spearman ρ)
- `sleep-rhr` (lag 0)
- `sleep-hrv` (lag 0)
- `exercise-readiness` (lag 1)

Each needs ≥ 21 pairs and |ρ| ≥ 0.30. The p-value uses the t approximation `t = ρ √((n−2)/(1−ρ²))`.

### 3. Multiple testing
Benjamini–Hochberg FDR control at **q = 0.10** is applied across all conditional and correlation tests.

### 4. Anomalies
Today's value is compared against the mean and SD of the previous 30 days (≥ 14 days needed). A value is flagged when |z| ≥ 2.5, and only in the meaningful direction:
- resting HR: high
- HRV: low
- sleep: short
- respiratory rate: high
- wrist temperature and steps: either direction

### 5. Trend changes
The last 14 days are compared with the preceding 28 days using Welch's t-test.
- **Requirements:** p < 0.01, a change of at least 5 %, and ≥ 10 recent and ≥ 14 prior days.
- **Metrics:** steps, sleep, RHR, HRV, weight, VO₂ max, active energy and exercise minutes.

## Output
Each `Finding` has:
- a template with `[[token]]` placeholders
- `values`: locale-neutral formatted numbers that fill the tokens
- raw `numbers`
- `p`, `n`, and a `strength` used for ranking

## AI phrasing layer (Apple Intelligence)
- **Availability.** `SystemLanguageModel.default.availability` is checked at launch and whenever the app becomes active.
  - **Unavailable:** the Insights tab is hidden. Settings shows a single note: *"AI insights require an Apple Intelligence-capable device."*
- **What the model sees.** The finding's template with **tokens instead of numbers**, plus the list of tokens. It returns `headline`, `explanation` and `suggestion` through guided generation (`@Generable`).
- **Validation.** `InsightValidation.validateAndFill` rejects any output that contains a digit, an unknown token or a broken token. Only then are the tokens replaced with the engine's values. As a result, **every number shown comes from the stats engine.**
  - If the output is rejected (on an AI-capable device), the engine's deterministic sentence is shown instead.
- **Privacy and wording.** There are no network calls. A "not medical advice" disclaimer is always shown.
- **Gating.** AI insights are Pro. Anomaly and trend-change notes on metric trend views appear on **all** devices; they are pure statistics.
