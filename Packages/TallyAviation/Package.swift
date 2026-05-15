// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "TallyAviation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TallyAviation", targets: ["TallyAviation"]),
    ],
    targets: [
        .target(
            name: "TallyAviation",
            path: "Sources/TallyAviation",
            resources: [
                // ~4 MB of OurAirports runway data, bundled so the
                // RunwayDatabase lookups never need a network call.
                .copy("Resources/runways.csv"),
                // ~3.5 MB of OurAirports airport metadata (ident, type,
                // lat/lon, name, IATA) — drives the map pane's pin
                // rendering and the tier-by-zoom filtering.
                .copy("Resources/airports.csv"),
            ]
        ),
        .testTarget(
            name: "TallyAviationTests",
            dependencies: ["TallyAviation"],
            path: "Tests/TallyAviationTests"
        ),
    ]
)
