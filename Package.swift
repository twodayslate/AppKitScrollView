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
            name: "AppKitScrollView",
            path: "AppKitCollectionViewDemo",
            exclude: [
                "AppDelegate.swift",
                "BuilderDemoView.swift",
                "CollectionViewController.swift",
                "DemoCells.swift",
                "Info.plist",
                "MainWindowController.swift",
                "main.swift"
            ],
            sources: [
                "AppKitScrollView.swift",
                "DemoCellMeasurer.swift",
                "HostedCollectionViewItem.swift",
                "VerticalListCollectionLayout.swift"
            ]
        )
    ]
)
