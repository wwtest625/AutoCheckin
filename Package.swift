// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutoCheckin",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "AutoCheckin",
            targets: ["AutoCheckin"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AutoCheckin",
            path: "Sources/AutoCheckin"
        )
    ]
)
