// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "Ponten",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Ponten",
            path: "Ponten",
            resources: [
                .process("Resources/Assets.xcassets"),
                .process("Resources/AppIcon.icns"),
                .process("Resources/MenuBarIconTemplate.png"),
                .process("Resources/OriginalLogo.png")
            ]
        ),
        .testTarget(
            name: "PontenTests",
            dependencies: ["Ponten"],
            path: "PontenTests"
        ),
        .testTarget(
            name: "PontenE2ETests",
            dependencies: ["Ponten"],
            path: "PontenE2ETests"
        )
    ]
)
