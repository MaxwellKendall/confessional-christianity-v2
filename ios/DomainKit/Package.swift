// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DomainKit",
    // macOS listed so `swift build`/`swift test` on the host Mac (used for
    // fast headless iteration) satisfy SwiftData's macOS 14 availability too
    // — the app itself only ships on iOS 17+.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DomainKit", targets: ["DomainKit"]),
    ],
    targets: [
        .target(
            name: "DomainKit",
            resources: [.copy("BundledContent")]
        ),
        .testTarget(
            name: "DomainKitTests",
            dependencies: ["DomainKit"]
        ),
    ]
)
