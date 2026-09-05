// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "UIKitConsumer",
    platforms: [.iOS("18.4")],
    products: [
        .library(name: "UIKitConsumer", targets: ["UIKitConsumer"]),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "UIKitConsumer",
            dependencies: [
                .product(name: "NavigationStackController", package: "NavigationStackController"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "UIKitConsumerTests",
            dependencies: [
                "UIKitConsumer",
                .product(name: "NavigationStackController", package: "NavigationStackController"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6), .defaultIsolation(MainActor.self)]
        ),
    ]
)
