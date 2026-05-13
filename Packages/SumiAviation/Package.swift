// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SumiAviation",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SumiAviation", targets: ["SumiAviation"]),
    ],
    targets: [
        .target(
            name: "SumiAviation",
            path: "Sources/SumiAviation"
        ),
        .testTarget(
            name: "SumiAviationTests",
            dependencies: ["SumiAviation"],
            path: "Tests/SumiAviationTests"
        ),
    ]
)
