// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NewsCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "NewsCore", targets: ["NewsCore"])],
    dependencies: [
        // Pin an audited commit: upstream currently does not publish the README's 1.0.0 tag.
        .package(url: "https://github.com/rodrigosambadesaa/ConnectivityAndInternetAccess-iOS-mobile.git",
                 revision: "1803edfc3becb2a5b011569ca73f974ad24736f3")
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
