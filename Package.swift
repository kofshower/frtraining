// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Fricu",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "FricuCore",
            targets: ["FricuCore"]
        ),
        .executable(
            name: "FricuApp",
            targets: ["FricuApp"]
        )
    ],
    targets: [
        .target(
            name: "FricuCore"
        ),
        .executableTarget(
            name: "FricuApp",
            dependencies: [
                "FricuCore"
            ],
            exclude: [
                "Info.plist"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/FricuApp/Info.plist"
                ], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "FricuCoreTests",
            dependencies: [
                "FricuCore"
            ]
        ),
        .testTarget(
            name: "FricuAppTests",
            dependencies: [
                "FricuApp"
            ]
        )
    ]
)
