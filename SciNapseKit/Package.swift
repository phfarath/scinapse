// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SciNapseKit",
    platforms: [.iOS("17.4"), .macOS(.v14)],
    products: [
        .library(name: "SciNapseKit", targets: ["SciNapseKit"])
    ],
    targets: [
        .target(name: "SciNapseKit"),
        .testTarget(name: "SciNapseKitTests", dependencies: ["SciNapseKit"])
    ]
)
