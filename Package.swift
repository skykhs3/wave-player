// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WavePlayer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WavePlayer", targets: ["WavePlayer"])
    ],
    targets: [
        .executableTarget(name: "WavePlayer")
    ]
)
