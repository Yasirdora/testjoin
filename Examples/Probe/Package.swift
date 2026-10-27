// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Probe",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .testTarget(name: "ProbeTests"),
    ],
    swiftLanguageModes: [.v6]
)
