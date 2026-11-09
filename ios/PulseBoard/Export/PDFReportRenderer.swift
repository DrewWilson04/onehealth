import SwiftUI
import Charts
import PulseCore
import PulseKit

/// Renders a multi-page US-Letter PDF report with SwiftUI + ImageRenderer.
@MainActor
enum PDFReportRenderer {
    static let pageSize = CGSize(width: 612, height: 792)

    struct MetricSummary: Identifiable {
        let metric: MetricType
        let points: [TrendPoint]
        let summary: TrendSummary
        var id: MetricID { metric.id }
    }

    static func render(services: AppServices, metrics: [MetricType], from: DayKey, to: DayKey, directory: URL) async throws -> URL {
        var summaries: [MetricSummary] = []
        for m in metrics {
            let rows = (try? await services.store.aggregates(m.id, period: .day, from: from, to: to)) ?? []
            guard !rows.isEmpty else { continue }
            summaries.append(MetricSummary(metric: m, points: Trends.points(rows, metric: m), summary: Trends.summary(rows, metric: m)))
        }
        var scores: [ScoreKind: [ScoreResult]] = [:]
        for k in [ScoreKind.readiness, .sleep] { scores[k] = await services.scoreService.history(k, from: from, to: to) }

        let url = directory.appendingPathComponent("\(PulseKitConfig.appName)-report-\(from)_to_\(to).pdf")
        var box = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle as String: "\(PulseKitConfig.appName) Health Report"] as CFDictionary) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var pages: [AnyView] = [AnyView(CoverPage(from: from, to: to, summaries: summaries, scores: scores))]
        let perPage = 4
        for chunk in stride(from: 0, to: summaries.count, by: perPage) {
            pages.append(AnyView(MetricsPage(summaries: Array(summaries[chunk..<min(chunk + perPage, summaries.count)]),
                                             page: pages.count + 1)))
        }
        for page in pages {
            let renderer = ImageRenderer(content: page.frame(width: pageSize.width, height: pageSize.height).environment(\.colorScheme, .light))
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return url
    }

    struct CoverPage: View {
        let from: DayKey, to: DayKey
        let summaries: [MetricSummary]
        let scores: [ScoreKind: [ScoreResult]]

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(PulseKitConfig.appName) Health Report").font(.system(size: 26, weight: .bold))
                Text("\(Fmt.day(from)) – \(Fmt.day(to))").font(.system(size: 14)).foregroundStyle(.secondary)
                Divider()
                HStack(spacing: 24) {
                    ForEach([ScoreKind.readiness, .sleep], id: \.self) { k in
                        let vals = (scores[k] ?? []).compactMap(\.value)
                        VStack(alignment: .leading) {
                            Text("Avg \(k.title)").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(vals.isEmpty ? "—" : "\(Int(vals.reduce(0, +) / Double(vals.count)))").font(.system(size: 28, weight: .bold))
                        }
                    }
                }
                Text("Daily averages").font(.system(size: 15, weight: .semibold)).padding(.top, 6)
                ForEach(summaries.prefix(18)) { s in
                    HStack {
                        Text(s.metric.displayName).font(.system(size: 11))
                        Spacer()
                        Text(Fmt.value(s.summary.average, metric: s.metric)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                        Text("\(s.summary.daysWithData) days").font(.system(size: 9)).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                    }
                    Divider()
                }
                Spacer()
                Text("Scores are \(PulseKitConfig.appName)'s own estimates, not equivalent to WHOOP, Garmin or Oura scores. Not medical advice. Generated on-device \(Date().formatted(date: .abbreviated, time: .shortened)).")
                    .font(.system(size: 8)).foregroundStyle(.secondary)
            }
            .padding(40)
            .foregroundStyle(.black)
            .background(.white)
        }
    }

    struct MetricsPage: View {
        let summaries: [MetricSummary]
        let page: Int

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(summaries) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(s.metric.displayName).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("avg \(Fmt.value(s.summary.average, metric: s.metric)) · min \(Fmt.value(s.summary.min, metric: s.metric)) · max \(Fmt.value(s.summary.max, metric: s.metric))")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        Chart(s.points) { p in
                            BarMark(x: .value("Day", p.day.date(), unit: .day), y: .value("v", p.value))
                                .foregroundStyle(Theme.accent(s.metric.section).opacity(p.isEstimated ? 0.4 : 0.9))
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 120)
                    }
                }
                Spacer()
                Text("Page \(page)").font(.system(size: 8)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(40)
            .foregroundStyle(.black)
            .background(.white)
        }
    }
}
