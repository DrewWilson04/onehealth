// swift-tools-version: 6.2
import PackageDescription

// PulseKit adapts Apple frameworks (HealthKit, SwiftData, CloudKit, StoreKit,
// WidgetKit, WatchConnectivity, FoundationModels) to the platform-neutral
// protocols in PulseCore. It is shared by the iOS app, widgets and watch app.
let package = Package(
    name: "PulseKit",
    platforms: [.iOS(.v26), .watchOS(.v26)],
    products: [
        .library(name: "PulseKit", targets: ["PulseKit"]),
    ],
    dependencies: [
        .package(path: "../PulseCore"),
    ],
    targets: [
        .target(
            name: "PulseKit",
            dependencies: ["PulseCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
