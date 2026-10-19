// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "InvisibleWatermark",
    platforms: [
        .iOS(.v16),
        .macOS(.v12)
    ],
    products: [
        .library(name: "WatermarkCore", targets: ["WatermarkCore"]),
        .executable(name: "CoreTests", targets: ["CoreTests"])
    ],
    targets: [
        .target(
            name: "WatermarkCore",
            path: "Core"
        ),
        .executableTarget(
            name: "CoreTests",
            dependencies: ["WatermarkCore"],
            path: "Tests",
            exclude: ["README.md"]
        )
    ]
)
