# Data schema (platform-neutral)

This is the contract shared by iOS (`ios/Packages/PulseCore`), web (`web/src/core`) and any
future Android / Health Connect port. Field names and raw values are persisted — **do not
rename them once shipped**.

## Sample

| Field | Type | Notes |
|---|---|---|
| `id` | string | HealthKit UUID when known. For export.xml records (no UUID): `"x" + FNV-1a-64(type\|startEpoch\|endEpoch\|value%.6f\|sourceKey)` in lowercase hex. |
| `type` | MetricID | See [metrics.md](metrics.md). Custom metrics: `custom.<uuid>`. |
| `value` | double | In the metric's canonical unit. Sleep: stage code. Workout: minutes. ECG: average HR. |
| `unit` | string | Canonical unit (`count`, `kcal`, `m`, `min`, `count/min`, `ms`, `%` (0–100), `kg`, `mL`, `degC`, …). |
| `start`, `end` | timestamp | UTC instants. `end >= start`. |
| `source` | `{bundleId, name}` | The app that wrote it. `key = bundleId || name`. |
| `device` | `{name, model, manufacturer, hardwareVersion}?` | When reported. |
| `isManual` | bool | `HKWasUserEntered == 1`, or written by this app. |
| `isEstimated` | bool | Produced by gap filling (never from a device). |
| `confidence` | `low\|medium\|high`? | Only for estimated values. |
| `metadata` | map<string,string>? | Workouts: `activityType`, `energyKcal`, `distanceM`, `avgHR`, `hasRoute`, `PulseBoardSets` (JSON), `mergedFrom`. |

### Normalization rules
1. Map the HealthKit identifier (also used as `type` in export.xml) to a MetricID. Unknown types are skipped (`unknownType`).
2. Convert the value to the canonical unit. Unknown or incompatible units are skipped (`unknownUnit`).
3. **Percentages:** HealthKit and export.xml store fractions (0.97) under `%`. Canonical storage is 0–100.
4. **Sleep stages:** codes match `HKCategoryValueSleepAnalysis`: 0 inBed, 1 asleep (unspecified/legacy), 2 awake, 3 core, 4 deep, 5 REM. Export strings such as `HKCategoryValueSleepAnalysisAsleepCore` map to these codes.
5. `end < start` → skipped (`invalidInterval`).
6. Fixtures: [`fixtures/normalizer_cases.json`](fixtures/normalizer_cases.json).

## Deduplication

Sources are ordered by `SourcePriority`:
1. The user's explicit order.
2. Then the vendor heuristic: Apple Watch (10) < wrist/ring wearables (Garmin, WHOOP, Oura, Fitbit, Polar, COROS, Suunto, Samsung: 20) < Withings / Eight Sleep (25) < iPhone (30) < this app (35) < Strava (40) < other (50).
3. Ties are broken by source key.

A per-metric **preferred source** moves that source to the front for that metric only.

| Kind | Rule |
|---|---|
| Cumulative (steps, energy, distance, nutrients) | Spread each sample uniformly over its duration. For every elementary time slice, only the highest-priority source covering it counts. On iOS, `HKStatisticsCollectionQuery` (`.cumulativeSum`) does the same using Apple Health's own source order. |
| Discrete (HR, HRV, SpO₂, weight…) | Use one source per day: the preferred source if it has data that day, else the source with the most samples, ties broken by priority. Sources are never averaged together, because HRV methods differ between devices. |
| Sleep | In-bed samples are handled separately from stages. Stage samples are swept slice by slice: the highest-priority covering source wins, and within a source a specific stage beats "asleep (unspecified)". Gaps in the best source are filled by the next source. Segments separated by ≤ 2 h form one session. A night is keyed by the local day it **ends**. |
| Workouts | Duplicates are workouts whose overlap is ≥ 50% of the shorter one. The highest-priority source is kept. Missing energy/distance/HR/route is filled from the duplicates, and `mergedFrom` lists the ids that were dropped. |
| Category events | Swept like sleep. Stand hours are deduplicated per hour slot. |

Fixtures: [`fixtures/dedup_cases.json`](fixtures/dedup_cases.json). They include Watch + iPhone, Garmin + Watch + WHOOP, Watch + Oura + iPhone sleep, and Watch + Garmin + Strava workouts.

## Aggregates

`DailyAggregate { metric, period(hour|day|week|month|year), day, hour?, sum, average, min, max, latest, count, primarySource, sourcePolicy, isEstimated, confidence }`

- There is one row per `(metric, period, day, hour)`, reflecting the **effective** source policy. Changing the preferred source rebuilds that metric.
- **Daily rows:** for quantity types, iOS takes them from HealthKit statistics; for sleep, workouts, events and custom metrics they come from `Aggregator.daily`. Web always uses `Aggregator.daily`.
- **Sleep rows:** `sum` = asleep minutes, `average` = efficiency %, `max` = in-bed minutes.
- **Workout rows:** `sum` = minutes, `average` = kcal, `count` = workouts.
- **Rollups:** week (ISO, Monday start), month and year rows are built from daily rows.
  - Sum metrics: `sum` = period total, `average` = mean per day with data.
  - Average metrics: mean of daily averages.
  - Latest metrics: last value in the period.
- **Hourly rows** are kept for 120 days for `steps`, `activeEnergy`, `heartRate`, `distanceWalkingRunning` and `exerciseTime` (intraday charts).

### Storage volume (10+ years)
- **High-volume types** (HR, steps, energy, distance, audio exposure, running/cycling metrics) are **not stored raw**. Only aggregates are stored, and HealthKit remains the source of truth.
  - Scores that need minute-level HR (Strain, Energy) query HealthKit for that day and cache the result.
- **Low-volume types** (sleep, workouts, HRV, resting HR, body, vitals, nutrition) are stored raw. Scores, gap handling and per-source baselines need them.

## Score cache
`ScoreDay { kind, day, value?, inputsUsed[], confidence, reason? }`. See [scores.md](scores.md). Rows are invalidated by dirty days only.

## Settings (synced via CloudKit private DB — non-health only)
Key-value records:
- `preferences`
- `preferredSources`
- `sourcePriority`
- `dashboardLayout`
- `goal.<id>`
- `meal.<id>`
- `challenge.<id>`

The newest `updatedAt` wins, and duplicate keys are removed on import. Health samples, aggregates, scores and custom metrics are **never** in this store (App Review 5.1.3(ii)).

## Web (IndexedDB)
The object stores use the same shapes:
- `samples` (key `id`, index `[type,start]`)
- `aggregates` (key `metric|period|day|hour`)
- `scores`
- `meta` (import info, source priority)
