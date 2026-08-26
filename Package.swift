// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "okraPDF",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4")
    ],
    targets: [
        .target(
            name: "OkraClientCore",
            path: "OkraClientCore"
        ),
        .executableTarget(
            name: "Okra",
            dependencies: [
                "OkraClientCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "OkraPDF",
            resources: [
                .copy("AppIcon.png"),
                .copy("ProviderScripts")
            ]
        ),
        .executableTarget(
            name: "okra",
            dependencies: ["OkraClientCore"],
            path: "OkraCLI"
        ),
        .testTarget(
            name: "okraPDFTests",
            dependencies: ["Okra", "OkraClientCore"],
            path: "Tests",
            exclude: ["OkraDesktopTests"]
        )
    ]
)
