# Challenges

**Status:** the client and its abstractions are built. Every challenge is a **local preview with generated sample participants**, gated by the `CHALLENGES_PREVIEW` build setting. There is no server yet.

**Reference implementation:**
- iOS: `ios/Packages/PulseCore/Sources/PulseCore/Challenges/`
- Web port: `web/src/core/activityScore.ts`

The Activity Score fixtures are in [`fixtures/activity_score_cases.json`](fixtures/activity_score_cases.json).

## Device-agnostic Activity Score (0–100 per day)

| Part | Points | Formula |
|---|---|---|
| Steps | 30 | `30 · min(steps, 15 000) / 15 000` |
| Active minutes | 30 | `30 · min(A, 90) / 90`, where `A = max(Apple exercise minutes, minutes in HR zones 2–5)` |
| Intensity | 25 | `25 · min(W, 120) / 120`, where `W = Σ zone minutes × weight` (Z1 0.5, Z2 1, Z3 1.5, Z4 2, Z5 2.5). Devices with **no HR data** use `W = workout minutes × 1.0`. |
| Sleep | 15 | 15 for 7–9 h asleep; 7 for 6–7 h or 9–10 h; otherwise 0 |

HR zones are percentages of heart-rate reserve, as defined in [scores.md](scores.md#strain--training-load-021--pro).

**Why it's fair across devices**
- **Max of two measures.** Apple Watch users have both exercise minutes and HR zones; Garmin, WHOOP, Oura and Fitbit users usually have only HR zones. Taking the max means nobody gets double credit and nobody is penalized for lacking Apple Exercise minutes.
- **Caps.** Every part is capped, so no single metric that a particular device inflates can dominate.
- **Dedup.** Steps come from deduplicated totals, so several devices worn together are never summed.
- **Phones without HR.** Users with only a phone still earn steps and workout points.

## Eligibility (always enforced on-device)
These are **never counted**:
- **Manual entries.** Samples with `HKWasUserEntered`, or written by this app, are excluded.
  - On iOS, cumulative totals are queried with `NOT (metadata.HKWasUserEntered == YES)`.
- **Estimated and gap-filled values.**
- **Implausible days.** These are flagged by the client-side `AntiCheat.check`: more than 80 000 steps, or more than 16 h of exercise. *Placeholder: the server will be authoritative.*

## Challenge model
- **Types:** `friends`, `local`, `global`, and `custom` (created by the user, Pro).
- **Metric:** Activity Score, steps, active minutes, workout minutes, or nights of 7–9 h sleep.
- **Rules:** aggregation (total / daily average / best day) plus an optional daily cap.
- **Ranking:** ties share a rank.

## Privacy
- **Shared data.** Only `DailyChallengeScore {challengeID, day, value}` would ever leave the device. Raw samples, sources and devices are never shared.
- **Opt-in.** Sharing is **opt-in per challenge** and off by default. Turning it off deletes previously queued scores.
- **Local challenges.** These use **city/region only**. Location is requested with reduced accuracy, reverse-geocoded to "City, Region", and the coordinates are discarded.
- **What syncs via CloudKit.** Membership and custom challenge configuration are synced as settings. Scores are not.

## Architecture
- **Protocols.**
  - `ChallengeService`: discover, joined, join/leave, sharing, create, submit.
  - `LeaderboardService`.
  - `DataProvider`: Apple Health now.
  - The UI depends only on these protocols.
- **Mock.** `MockChallengeService` is an actor with a deterministic seeded catalog and participants, all labeled "(sample)".
- **Server stubs (TODO):**
  - `ServerChallengeService` (server sync)
  - `AuthService` (Sign in with Apple)
  - `ChallengeNotificationService` (push)
  - `AntiCheat` (server validation plus App Attest)
  - Direct provider connectors for Fitbit, WHOOP, Garmin and Oura (OAuth via the server)
- **Before a real server ships:**
  - Declare `NSPrivacyCollectedDataTypeFitness` in `PrivacyInfo.xcprivacy`.
  - Update the App Privacy answers and the privacy policy.
  - Set `CHALLENGES_PREVIEW = NO` for the App Store if the server isn't ready (App Review 2.1 / 2.3).
