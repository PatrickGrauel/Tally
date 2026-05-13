// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SumiEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SumiEngine", targets: ["SumiEngine"]),
    ],
    dependencies: [
        .package(path: "../SumiAviation"),
    ],
    targets: [
        .target(
            name: "SumiEngine",
            dependencies: [
                .product(name: "SumiAviation", package: "SumiAviation"),
            ],
            path: "Sources/SumiEngine",
            resources: [
                .copy("Resources/mathjs.bundle.js"),
            ]
        ),
        .testTarget(
            name: "SumiEngineTests",
            dependencies: ["SumiEngine"],
            path: "Tests/SumiEngineTests"
        ),
    ]
)
