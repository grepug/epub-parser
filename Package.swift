// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "epub-parser",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "EPUBParser",
            targets: ["EPUBParser"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMajor(from: "0.9.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "EPUBParser",
            dependencies: ["ZIPFoundation"]
        ),
        .testTarget(
            name: "epub-parserTests",
            dependencies: ["EPUBParser"]
        ),
    ]
)
