// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "okraPDF",
    platforms: [.macOS(.v13)],
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
        .testTarget(
            name: "okraPDFTests",
            dependencies: ["Okra"],
            path: "Tests",
            exclude: ["OkraDesktopTests"]
        )
    ]
)
