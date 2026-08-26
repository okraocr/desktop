// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "okraPDF",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Okra", targets: ["Okra"]),
        // The build product must differ from `Okra` beyond letter case because
        // the default macOS filesystem is case-insensitive. Packaging renames
        // this thin client to the user-facing `okra` command inside the app.
        .executable(name: "okra-desktop-cli", targets: ["OkraCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4")
    ],
    targets: [
        .executableTarget(
            name: "Okra",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "OkraPDF",
            resources: [
                .copy("AppIcon.png"),
                .copy("ProviderScripts")
            ]
        ),
        .executableTarget(
            name: "OkraCLI",
            path: "OkraCLI"
        ),
        .testTarget(
            name: "okraPDFTests",
            dependencies: ["Okra"],
            path: "Tests"
        )
    ]
)
