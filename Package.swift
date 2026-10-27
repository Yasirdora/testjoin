// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "testjoin",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "TestJoinCore", targets: ["TestJoinCore"]),
        .executable(name: "testjoin", targets: ["testjoin"]),
    ],
    targets: [
        .target(name: "TestJoinCore"),
        .executableTarget(
            name: "testjoin",
            dependencies: ["TestJoinCore"]
        ),
        .testTarget(
            name: "TestJoinCoreTests",
            dependencies: ["TestJoinCore"],
            exclude: ["Fixtures"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
