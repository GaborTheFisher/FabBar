// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FabBar",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "FabBar", targets: ["FabBar"]),
    ],
    targets: [
        .target(name: "FabBar"),
        .testTarget(name: "FabBarTests", dependencies: ["FabBar"]),
    ]
)
