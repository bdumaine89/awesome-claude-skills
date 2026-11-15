// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BlueLineCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "BlueLineCore", targets: ["BlueLineCore"])],
    targets: [
        .target(name: "BlueLineCore"),
        .testTarget(name: "BlueLineCoreTests", dependencies: ["BlueLineCore"]),
    ]
)
