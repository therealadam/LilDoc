// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LilDocKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LilDocKit", targets: ["LilDocKit"]),
        .executable(name: "lildoc-cli", targets: ["lildoc-cli"]),
        .executable(name: "lildoc-mcp", targets: ["lildoc-mcp"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.4.0"
        ),
        .package(
            url: "https://github.com/modelcontextprotocol/swift-sdk.git",
            exact: "0.11.0"
        ),
    ],
    targets: [
        .target(
            name: "LilDocKit",
            dependencies: []
        ),
        .executableTarget(
            name: "lildoc-cli",
            dependencies: [
                "LilDocKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "lildoc-mcp",
            dependencies: [
                "LilDocKit",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "LilDocKitTests",
            dependencies: ["LilDocKit"]
        ),
    ]
)
