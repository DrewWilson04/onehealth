import SwiftUI
import PulseKit

struct AboutScoresView: View {
    var body: some View {
        List {
            Section {
                Text("\(PulseKitConfig.appName) computes its own estimates from raw data every device shares through Apple Health (heart rate, HRV, resting heart rate, sleep, steps, workouts). They are not the same as — and not comparable to — WHOOP Recovery/Strain, Garmin Body Battery or Oura Readiness.")
            }
            Section("Readiness (0–100)") {
                Text("Today's HRV and resting heart rate compared with your own 30-day baseline, plus last night's sleep (duration, consistency and stages when available).")
            }
            Section("Sleep Score (0–100)") {
                Text("Duration vs your goal, efficiency (asleep ÷ in bed), bed/wake-time consistency over 7 nights, and stage balance when your device records stages.")
            }
            Section("Strain & Training Load") {
                Text("Heart-rate-zone training impulse (TRIMP) from workouts and daytime heart rate, and the ratio of your 7-day to 28-day load to flag over- or under-training.")
            }
            Section("Energy (0–100)") {
                Text("Starts from overnight recovery, drains with activity and elevated heart rate while resting (stress), and recharges with rest and sleep.")
            }
            Section("Missing data") {
                Text("Short gaps (e.g. watch not worn one night) may be filled from your baseline. Filled values are marked Estimated with a confidence level, and are never used in challenges. When key inputs are missing we show \"Not enough data\" instead of guessing.")
            }
            Section {
                Text("Not medical advice.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("How Scores Work")
    }
}
