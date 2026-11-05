// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SomaFMMenuBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SomaFMMenuBar", targets: ["SomaFMMenuBar"])
    ],
    targets: [
        .executableTarget(name: "SomaFMMenuBar")
    ]
)
