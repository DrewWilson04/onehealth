import SwiftUI
import PulseCore
import PulseKit

/// Connected sources and per-metric preferred source.
struct SourcesView: View {
    @Environment(AppServices.self) private var services
    @Environment(SettingsStore.self) private var settings
    @State private var connected: [SourceRef] = []
    @State private var loading = true

    var body: some View {
        List {
            Section {
                if loading {
                    ProgressView()
                } else if connected.isEmpty {
                    ContentUnavailableView("No sources yet", systemImage: "antenna.radiowaves.left.and.right.slash",
                                           description: Text("Sources appear once Apple Health has data from a device or app."))
                } else {
                    ForEach(connected, id: \.key) { s in
                        let vendor = Vendor.infer(source: s, device: nil)
                        Label {
                            VStack(alignment: .leading) {
                                Text(s.name)
                                Text(vendor == .other ? s.bundleId : vendor.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: icon(vendor)) }
                    }
                }
            } header: {
                Text("Connected sources")
            } footer: {
                Text("Garmin, WHOOP, Oura, Fitbit and others appear here once their app syncs to Apple Health. Steps, energy and distance are deduplicated using Apple Health's source order (Health app → Browse → a metric → Data Sources & Access).")
            }

            ForEach(DashboardSection.allCases) { section in
                Section(section.title) {
                    ForEach(MetricRegistry.metrics(in: section).filter { $0.kind == .cumulative || $0.kind == .discrete || $0.id == .sleep || $0.id == .workout }) { m in
                        NavigationLink {
                            PreferredSourcePicker(metric: m)
                        } label: {
                            LabeledContent(m.displayName, value: settings.preferredSources[m.id].map(sourceName) ?? "Automatic")
                        }
                    }
                }
            }
        }
        .navigationTitle("Sources")
        .task { await load() }
    }

    private func sourceName(_ key: String) -> String { connected.first { $0.key == key }?.name ?? key }

    private func load() async {
        var all: [String: SourceRef] = [:]
        for id in [MetricID.steps, .heartRate, .sleep, .workout, .activeEnergy, .hrv, .bodyMass, .dietaryEnergy] {
            for s in (try? await services.provider.sources(for: id)) ?? [] { all[s.key] = s }
        }
        connected = all.values.sorted { $0.name < $1.name }
        loading = false
    }

    private func icon(_ v: Vendor) -> String {
        switch v {
        case .appleWatch: return "applewatch"
        case .iPhone: return "iphone"
        case .oura: return "circle.circle"
        case .whoop, .garmin, .fitbit, .polar, .coros, .suunto, .samsung: return "watch.analog"
        case .withings: return "scalemass"
        case .eightSleep: return "bed.double"
        default: return "app.badge"
        }
    }
}

struct PreferredSourcePicker: View {
    let metric: MetricType
    @Environment(AppServices.self) private var services
    @Environment(SettingsStore.self) private var settings
    @State private var sources: [SourceRef] = []

    var body: some View {
        List {
            Section {
                row(title: "Automatic", subtitle: metric.kind == .cumulative ? "Apple Health source priority" : "Best available source per day", key: nil)
                ForEach(sources, id: \.key) { s in
                    row(title: s.name, subtitle: Vendor.infer(source: s, device: nil).displayName, key: s.key)
                }
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle(metric.displayName)
        .task { sources = (try? await services.provider.sources(for: metric.id)) ?? [] }
    }

    private var footer: String {
        if metric.id == .hrv {
            return "Different devices measure HRV differently (Apple Watch uses SDNN; some wearables report RMSSD-style values). Picking one source keeps your readiness baseline consistent."
        }
        return "When the preferred source has no data for a day, \(PulseKitConfig.appName) falls back to Automatic."
    }

    private func row(title: String, subtitle: String, key: String?) -> some View {
        Button {
            services.setPreferredSource(key, for: metric.id)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if settings.preferredSources[metric.id] == key {
                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Selected")
                }
            }
        }
    }
}
