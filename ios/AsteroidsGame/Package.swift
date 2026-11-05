// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AsteroidsGame",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AsteroidsGame", targets: ["AsteroidsGame"])
    ],
    targets: [
        .executableTarget(name: "AsteroidsGame")
    ]
)
