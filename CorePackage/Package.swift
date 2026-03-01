// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FricuCore",
    products: [
        .library(
            name: "FricuCore",
            targets: ["FricuCore"]
        )
    ],
    targets: [
        .target(
            name: "FricuCore"
        ),
        .testTarget(
            name: "FricuCoreTests",
            dependencies: ["FricuCore"]
        )
    ]
)
