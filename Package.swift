// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FricuApp",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(
            name: "FricuApp",
            targets: ["FricuApp"]
        )
    ],
    dependencies: [
        .package(path: "CorePackage")
    ],
    targets: [
        .executableTarget(
            name: "FricuApp",
            dependencies: [
                .product(name: "FricuCore", package: "CorePackage")
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
            name: "FricuAppTests",
            dependencies: [
                "FricuApp"
            ]
        )
    ]
)
