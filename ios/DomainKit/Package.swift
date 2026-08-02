// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DomainKit",
    platforms: [.iOS(.v17)],
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
