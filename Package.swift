// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MetaFetch",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "MetaFetch",
            targets: ["MetaFetch"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "MetaFetch"
        ),
        .testTarget(
            name: "MetaFetchTests",
            dependencies: ["MetaFetch"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
