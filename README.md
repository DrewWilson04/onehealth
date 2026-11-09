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

### iCloud / CloudKit (settings sync)
- **What syncs.** Only non-health configuration syncs: preferences, dashboard layout, preferred sources, challenge setup, goals, and saved meal templates. The last two can be turned off in Settings → iCloud Sync.
- **The guard.** `PulseCore/Model/CloudPolicy.swift` allow-lists the keys that may reach iCloud. Anything else is forced into the local store.
- **Data that never syncs.** The health cache (`HealthCache`, SwiftData `cloudKitDatabase: .none`) and custom metrics never sync.
- **Schema.** SwiftData creates the CloudKit schema automatically in the **Development** environment the first time a debug build syncs.
  - Before TestFlight, open the [CloudKit Console](https://icloud.developer.apple.com) → your container → **Deploy Schema Changes** to Production. TestFlight and App Store builds use Production.
- **Testing.** Sign into the same iCloud account on two devices. Change the dashboard layout or a goal on one, and it appears on the other within a minute or so, usually faster while both apps are in the foreground.
- **Conflicts.** One record per item; the newest write wins, and duplicates created while offline are removed on import.

### Running tests
- **Xcode:** select the `PulseBoardTests` scheme and press ⌘U. This runs the `PulseCoreTests` package tests.
- **Command line (macOS):** `cd ios/Packages/PulseCore && swift test`
- **Linux / CI:** `docker run --rm -v "$PWD":/repo -w /repo/ios/Packages/PulseCore swift:6.2 swift test`

### StoreKit testing (local)
`ios/PulseBoard.storekit` defines one subscription group, **PulseBoard Pro**:

| Product ID | Price | Intro offer |
|---|---|---|
| `pulseboard.pro.monthly` | $2.99 / month | 1 month free |
| `pulseboard.pro.yearly` | $29.99 / year | 1 month free |

- **Scheme.** The scheme already points at the file (`project.yml` → `storeKitConfiguration`). If needed, check Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration.
- **Test a purchase.** Run the app, open Settings → Upgrade to Pro → choose a plan, and purchase. No real money is charged.
- **Transaction Manager.** Use Debug → StoreKit → Manage Transactions to refund, expire, or clear purchase history (clearing resets intro-offer eligibility).
- **Fast renewals.** Editor → Subscription Renewal Rate → "Every 30 seconds" lets you watch renewals and expiry.
- **Debug toggle.** Debug builds have Settings → Subscription → **Simulate Pro** for quick UI work.

All gating goes through `EntitlementService` (PulseCore) and is implemented by `EntitlementManager` (PulseKit, StoreKit 2):
- It uses `Transaction.currentEntitlements` and `Transaction.updates`.
- Transactions are verified on-device; there is no receipt server.

### App Store Connect setup (before TestFlight)
1. **Create the app.** In App Store Connect → My Apps → **+**, use bundle ID `<prefix>.pulseboard`.
2. **Create the subscriptions.** Go to Monetization → Subscriptions and create the group **PulseBoard Pro** with both products.
   - The product IDs must match the table above, or change them in `AppConfig.xcconfig` and `PulseBoard.storekit`.
   - Set the prices, and add an **Introductory Offer → Free → 1 month** to each.
3. **Privacy.**
   - Enter a hosted privacy-policy URL. A placeholder lives in `docs/privacy-policy.md` and is served by the web app at `/privacy.html`.
   - Set `PRIVACY_POLICY_URL` in `AppConfig.xcconfig`.
   - App Privacy questionnaire: **Data Not Collected**, because nothing leaves the device in this phase.
4. **Paid Apps agreement.** Accept it in Business, otherwise products won't load in TestFlight.
5. **CloudKit.** Deploy the CloudKit schema to Production (see above).

### TestFlight upload
1. In `AppConfig.xcconfig`, bump `CURRENT_PROJECT_VERSION`. Bump `MARKETING_VERSION` for new versions.
2. In Xcode, select **Any iOS Device (arm64)** → Product → **Archive**.
3. In the Organizer, choose **Distribute App → App Store Connect → Upload**. Keep automatic signing.
4. In App Store Connect → TestFlight, wait for processing.
   - Answer export compliance. `ITSAppUsesNonExemptEncryption = NO` is already set.
   - Add an **Internal** testing group, or an **External** group (which needs Beta App Review) and invite friends by email or public link.
5. Testers install **TestFlight**, accept, and install.
   - Subscriptions in TestFlight use the sandbox and are free.
   - Renewals are accelerated: a 1-month period lasts about 5 minutes.

Before submitting to the **App Store**, set `CHALLENGES_PREVIEW = NO` in `Config/Release.xcconfig`. Mock challenge participants are for TestFlight only.

---

## Web
See [`web/README.md`](web/README.md) (Milestone 12).

---

## Milestones
1. ✅ HealthKit ingestion, schema, backfill, multi-source dedup
2. ✅ Core dashboard and charts
3. ✅ Manual entry with HealthKit write-back
4. ✅ Goals, streaks, widgets
5. ✅ CloudKit settings sync
6. ✅ Derived scores and gap handling
7. ✅ StoreKit 2 and paywall
8. ✅ CSV/PDF export
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
