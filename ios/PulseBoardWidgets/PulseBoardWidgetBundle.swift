import WidgetKit
import SwiftUI

@main
struct PulseBoardWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        MetricWidget()
        ScoresWidget()
        LockScreenWidget()
    }
}
