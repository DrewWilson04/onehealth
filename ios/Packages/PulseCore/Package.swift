// swift-tools-version: 6.2
import PackageDescription

// PulseCore is pure Swift + Foundation. It holds every algorithm (normalization,
// dedup, aggregation, derived scores, gap handling, Activity Score, stats engine,
// CSV export) so it can be unit-tested on macOS *and* Linux, and stays portable
// for a future Android/Health Connect port (see /docs).
let package = Package(
    name: "PulseCore",
    platforms: [.iOS(.v26), .watchOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "PulseCore", targets: ["PulseCore"]),
    ],
    targets: [
        .target(name: "PulseCore"),
        .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore"]),
    ]
)
