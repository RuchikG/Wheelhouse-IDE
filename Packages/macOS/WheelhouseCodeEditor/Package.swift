// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WheelhouseCodeEditor",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "WheelhouseCodeEditor",
            targets: ["WheelhouseCodeEditor"]
        ),
    ],
    targets: [
        .target(
            name: "WheelhouseCodeEditor",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "WheelhouseCodeEditorTests",
            dependencies: ["WheelhouseCodeEditor"]
        ),
    ]
)
