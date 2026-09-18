// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Anythings",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Anythings", targets: ["Anythings"])
    ],
    targets: [
        .executableTarget(
            name: "Anythings",
            path: "Sources"
        )
    ]
)
