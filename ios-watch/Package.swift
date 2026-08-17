// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodingQuotaShared",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "QuotaShared",
            targets: ["QuotaShared"]
        )
    ],
    targets: [
        .target(
            name: "QuotaShared",
            path: "Sources/Shared"
        ),
        .testTarget(
            name: "QuotaSharedTests",
            dependencies: ["QuotaShared"],
            path: "Tests/QuotaSharedTests"
        )
    ]
)
