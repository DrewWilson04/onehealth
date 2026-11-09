# PulseBoard

PulseBoard is a local-first health dashboard for iPhone, iPad, Apple Watch and the web.

The name is a placeholder. To rename the app, change `APP_NAME` in `ios/Config/AppConfig.xcconfig` and `BRAND` in `web/src/brand.ts`.

- **No backend and no server costs.** All health data stays on your own devices.
- **iOS / iPadOS / watchOS:** Swift, SwiftUI, HealthKit, SwiftData, Swift Charts, WidgetKit, StoreKit 2, CloudKit (settings only), Foundation Models (on supported devices).
- **Web:** TypeScript, React and Vite, built as a PWA. It imports an Apple Health `export.zip` entirely in the browser.

```
/ios     Xcode project spec (XcodeGen) + app, widgets, watch app, watch complications
  Packages/PulseCore   pure-Swift algorithms (normalize, dedup, aggregate, scores, stats) + tests
  Packages/PulseKit    Apple-framework adapters (HealthKit, SwiftData, CloudKit, StoreKit, …)
/web     PWA companion (imports export.zip, IndexedDB, same scores)
/docs    shared specs: schema, metrics, score formulas, challenge scoring, fixtures
```

The algorithms in `PulseCore` and `web/src/core` are tested against the same JSON fixtures in `docs/fixtures`, which keeps iOS and web consistent.

---

## iOS: Xcode setup

Requirements:
- Xcode 26 or later
- iOS / iPadOS 26+ and watchOS 26+ (the latest two major versions)
- A paid Apple Developer account

1. Install XcodeGen once. The `.xcodeproj` is generated from `ios/project.yml` and is not committed.
   ```sh
   brew install xcodegen
   ```
2. Edit `ios/Config/AppConfig.xcconfig`:
   - `TEAM_ID`: your Team ID, from Xcode → Settings → Accounts, or developer.apple.com → Membership.
   - `BUNDLE_ID_PREFIX`: for example `com.yourname`.
   - `APP_NAME` (optional): renames the app everywhere.
3. Generate and open the project:
   ```sh
   cd ios && xcodegen && open PulseBoard.xcodeproj
   ```
4. Select the **PulseBoard** scheme and a real iPhone (HealthKit background delivery doesn't run in the Simulator), then press Run.

Re-run `xcodegen` whenever you add or remove files or change `project.yml`.

### Signing & capabilities
`project.yml` declares the entitlements below. With automatic signing, Xcode registers the App IDs, App Group and iCloud container the first time you build for a device.

| Capability | Targets | Notes |
|---|---|---|
| HealthKit (+ Background Delivery) | app, watch app | No clinical records (see docs/metrics.md) |
| iCloud → CloudKit | app | Container `iCloud.<prefix>.pulseboard`. **Settings only.** |
| App Groups | app, widgets, watch, watch widgets | `group.<prefix>.pulseboard`, widget snapshot |
| Background Modes | app | Background fetch, background processing, remote notifications (CloudKit pushes) |
| In-App Purchase | app | Enabled automatically for StoreKit products |
| Push Notifications | app | Added by Xcode for CloudKit subscriptions (`aps-environment`) |

If automatic signing complains about the App Group or iCloud container, open **Signing & Capabilities** for each target. Click the refresh button next to the container, or create it at developer.apple.com → Identifiers.

### Running tests
- **Xcode:** select the `PulseBoardTests` scheme and press ⌘U. This runs the `PulseCoreTests` package tests.
- **Command line (macOS):** `cd ios/Packages/PulseCore && swift test`
- **Linux / CI:** `docker run --rm -v "$PWD":/repo -w /repo/ios/Packages/PulseCore swift:6.2 swift test`

### StoreKit testing
Covered in Milestone 7.

### TestFlight
Covered in Milestone 7 / release readiness.

---

## Web
See [`web/README.md`](web/README.md) (Milestone 12).

---

## Milestones
1. ✅ HealthKit ingestion, schema, backfill, multi-source dedup
2. ✅ Core dashboard and charts
3. ✅ Manual entry with HealthKit write-back
4. Goals, streaks, widgets
5. CloudKit settings sync
6. Derived scores and gap handling
7. StoreKit 2 and paywall
8. CSV/PDF export
9. Insights stats engine + Apple Intelligence layer
10. Challenge abstractions + mock UI
11. Apple Watch app + complications
12. Web importer, dashboard, static deploy

## Deviations from the original spec (Apple rules or technical limits)

1. **HealthKit read access.** We request every type the app uses, not literally every HealthKit type. Clinical records are excluded (App Review 5.1.1; they also need a separate entitlement).
2. **Strength sets, reps and weight.** HealthKit has no sample types for these. They are stored as JSON in the `HKWorkout` metadata key `PulseBoardSets`, so they still sync with the workout.
3. **Backfill.** It runs mostly in the foreground and checkpoints after every chunk. iOS can't read HealthKit while the device is locked, and background processing time isn't guaranteed. Background delivery frequency is decided by the system.
4. **High-volume types (HR, steps, energy, distance)** are stored as aggregates, not raw rows. HealthKit stays the source of truth.
5. **Discrete metrics use one source per day.** HRV baselines are kept per source, because WHOOP and Oura write RMSSD-like values into the SDNN type.
6. **CloudKit stores non-health configuration only.** Goals and saved meal templates are a gray area under 5.1.3. They sync by default; set `SettingsSync.syncGoals` / `.syncMealTemplates` to `false` to keep them local-only.
7. **Watch complications** use WidgetKit, because ClockKit is deprecated. There are no AI insights on the watch, since Foundation Models isn't available on watchOS.
8. **Widgets** read a snapshot that the app writes to the App Group container. Widgets can't reliably query HealthKit, especially when the device is locked.
9. **Mock challenge participants** are labeled as a preview and gated by `CHALLENGES_PREVIEW`. Set it to `NO` in `Release.xcconfig` for the App Store build (App Review 2.1 / 2.3).
10. **Intro offers are one per subscription group.** A user who uses the Monthly trial won't get a second trial on Yearly.
11. **Web dedup** uses its own source order. `export.xml` has no Apple Health priority applied, so totals can differ slightly from the Health app.
12. **Web unzip** uses a custom ZIP64 reader plus native `DecompressionStream`, streaming in a Web Worker.
