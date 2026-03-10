// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "asset_shield",
    platforms: [.iOS(.v12)],
    products: [
        .library(name: "asset_shield", targets: ["AssetShieldCrypto"])
    ],
    targets: [
        .binaryTarget(
            name: "AssetShieldCrypto",
            path: "Frameworks/AssetShieldCrypto.xcframework"
        )
    ]
)
