// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "asset_shield_macos",
    platforms: [.macOS(.v10_13)],
    products: [
        .library(name: "asset_shield_macos", targets: ["AssetShieldCrypto"])
    ],
    targets: [
        .binaryTarget(
            name: "AssetShieldCrypto",
            path: "Frameworks/AssetShieldCrypto.xcframework"
        )
    ]
)
