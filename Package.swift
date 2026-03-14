// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BatteryChargeCLI",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(
            name: "btcharge",
            targets: ["btcharge"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "btcharge",
            dependencies: ["CSMCHelpers"],
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit"),
            ]
        ),
        .target(
            name: "CSMCHelpers",
            path: "Sources/CSMCHelpers",
            publicHeadersPath: "include"
        ),
    ]
)
