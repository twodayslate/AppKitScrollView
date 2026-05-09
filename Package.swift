// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppKitScrollView",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AppKitScrollView",
            targets: ["AppKitScrollView"]
        )
    ],
    targets: [
        .target(
            name: "AppKitScrollView"
        )
    ],
    swiftLanguageModes: [.v6]
)
