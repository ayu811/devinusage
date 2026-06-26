// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DevinBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DevinBar", targets: ["DevinBar"])
    ],
    targets: [
        .executableTarget(
            name: "DevinBar",
            path: "Sources/DevinBar"
        )
    ]
)
