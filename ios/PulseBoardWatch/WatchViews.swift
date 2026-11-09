import SwiftUI
import PulseCore

/// Glanceable pages: rings & steps, scores, heart rate, challenge, quick log.
struct WatchRootView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        TabView {
            RingsPage()
            ScoresPage()
            HeartPage()
            if model.snapshot?.challenge != nil { ChallengePage() }
            WaterPage()
        }
        .tabViewStyle(.verticalPage)
    }
}

struct RingsPage: View {
    @Environment(WatchModel.self) private var model
    var body: some View {
        VStack(spacing: 6) {
            if let r = model.rings {
                RingsView(activity: r, lineWidth: 10).frame(width: 96, height: 96)
            }
            Text(model.steps.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                .font(.title2.bold().monospacedDigit())
            Text("steps").font(.caption2).foregroundStyle(.secondary)
            if let kcal = model.activeEnergy { Text("\(Int(kcal)) kcal").font(.footnote) }
        }
        .accessibilityElement(children: .combine)
        .containerBackground(Theme.orange.gradient.opacity(0.25), for: .tabView)
    }
}

struct ScoresPage: View {
    @Environment(WatchModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([ScoreKind.readiness, .sleep, .strain, .energy], id: \.self) { k in
                if let s = model.snapshot?.score(k) {
                    HStack {
                        Image(systemName: k.symbol).foregroundStyle(Theme.bluishGreen).frame(width: 20)
                        Text(k.title).font(.footnote)
                        Spacer()
                        Text(s.value.map { k == .strain ? $0.formatted(.number.precision(.fractionLength(1))) : "\(Int($0))" } ?? "—")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(s.value.map { k == .strain ? Theme.orange : Theme.scoreColor($0) } ?? .secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if model.snapshot == nil {
                Text("Open the iPhone app to sync scores.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Our own estimates").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .containerBackground(Theme.bluishGreen.gradient.opacity(0.25), for: .tabView)
    }
}

struct HeartPage: View {
    @Environment(WatchModel.self) private var model
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "heart.fill").font(.title).foregroundStyle(Theme.vermillion)
            Text(model.heartRate.map { "\(Int($0))" } ?? "—").font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
            Text("bpm · last hour").font(.caption2).foregroundStyle(.secondary)
            if let rhr = model.snapshot?.metric(.restingHeartRate)?.formatted {
                Text("Resting \(rhr)").font(.footnote)
            }
        }
        .accessibilityElement(children: .combine)
        .containerBackground(Theme.vermillion.gradient.opacity(0.25), for: .tabView)
    }
}

struct ChallengePage: View {
    @Environment(WatchModel.self) private var model
    var body: some View {
        if let c = model.snapshot?.challenge {
            VStack(spacing: 4) {
                Image(systemName: "trophy.fill").font(.title2).foregroundStyle(Theme.orange)
                Text(c.title).font(.headline).multilineTextAlignment(.center)
                Text("#\(c.rank) of \(c.participants)").font(.title3.bold().monospacedDigit())
                Text("\(Int(c.score)) pts · preview").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .containerBackground(Theme.orange.gradient.opacity(0.25), for: .tabView)
        }
    }
}

struct WaterPage: View {
    @Environment(WatchModel.self) private var model
    var body: some View {
        VStack(spacing: 8) {
            Label("Water", systemImage: "drop.fill").foregroundStyle(Theme.skyBlue)
            HStack {
                Button("250") { Task { await model.logWater(250) } }
                Button("500") { Task { await model.logWater(500) } }
            }
            .accessibilityHint("Logs millilitres of water to Apple Health")
            if let m = model.lastLogged { Text(m).font(.caption2).foregroundStyle(.secondary) }
        }
        .containerBackground(Theme.skyBlue.gradient.opacity(0.25), for: .tabView)
    }
}
