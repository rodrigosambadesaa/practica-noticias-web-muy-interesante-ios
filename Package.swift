// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NewsCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "NewsCore", targets: ["NewsCore"])],
    dependencies: [
        // Pin the reviewed, CI-tested upstream commit; no stable version tag exists yet.
        .package(url: "https://github.com/rodrigosambadesaa/ConnectivityAndInternetAccess-iOS-mobile.git",
                 revision: "b31a010cc2bcafde10e23cbf774c837ef4a34774")
    ],
    targets: [
        .target(
            name: "NewsCore",
            dependencies: [.product(name: "ConnectivityAndInternetAccess",
                                    package: "ConnectivityAndInternetAccess-iOS-mobile")]
        ),
        .testTarget(
            name: "NewsCoreTests",
            dependencies: [
                "NewsCore",
                .product(name: "ConnectivityAndInternetAccess",
                         package: "ConnectivityAndInternetAccess-iOS-mobile")
            ]
        )
    ]
)
