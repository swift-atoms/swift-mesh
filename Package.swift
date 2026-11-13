// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "swift-mesh",
    platforms: [.macOS(.v27), .iOS(.v27), .tvOS(.v27), .watchOS(.v27), .visionOS(.v27)],
    products: [.library(name: "Mesh", targets: ["Mesh"])],
    dependencies: [
        .package(url: "https://github.com/swift-atoms/swift-bezier.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-cardinal.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-index.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-point.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-polygon.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-random.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-trigonometry.git", branch: "main"),
        .package(url: "https://github.com/swift-atoms/swift-vector.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Mesh",
            dependencies: [
                .product(name: "Bezier", package: "swift-bezier"),
                .product(name: "Cardinal", package: "swift-cardinal"),
                .product(name: "Index", package: "swift-index"),
                .product(name: "Point", package: "swift-point"),
                .product(name: "Polygon", package: "swift-polygon"),
                .product(name: "Random", package: "swift-random"),
                .product(name: "Trigonometry", package: "swift-trigonometry"),
                .product(name: "Vector", package: "swift-vector"),
            ]
        ),
        .testTarget(
            name: "Mesh Tests",
            dependencies: [
                .target(name: "Mesh")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    target.swiftSettings =
        (target.swiftSettings ?? []) + [
            .strictMemorySafety(),
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault"),
            .enableUpcomingFeature("MemberImportVisibility"),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            .enableUpcomingFeature("InferIsolatedConformances"),
            .enableExperimentalFeature("Lifetimes"),
            .treatAllWarnings(as: .error),
        ]
}
