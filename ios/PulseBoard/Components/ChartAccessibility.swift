import SwiftUI
import Charts
import Accessibility
import PulseCore

/// VoiceOver audio-graph + summary for metric charts.
struct MetricChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let unit: String
    let points: [(label: String, value: Double)]

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = points.map(\.value)
        let minV = values.min() ?? 0, maxV = values.max() ?? 1
        let x = AXCategoricalDataAxisDescriptor(title: "Date", categoryOrder: points.map(\.label))
        let y = AXNumericDataAxisDescriptor(title: unit.isEmpty ? title : unit, range: minV...max(maxV, minV + 1), gridlinePositions: []) { v in
            "\(v.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
        }
        let series = AXDataSeriesDescriptor(name: title, isContinuous: false,
                                            dataPoints: points.map { AXDataPoint(x: $0.label, y: $0.value) })
        let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        return AXChartDescriptor(title: title,
                                 summary: "\(points.count) values. Average \(avg.formatted(.number.precision(.fractionLength(0...1)))) \(unit), range \(minV.formatted(.number.precision(.fractionLength(0...1)))) to \(maxV.formatted(.number.precision(.fractionLength(0...1)))).",
                                 xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}
