// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "XcodeFixture",
    products: [.library(name: "XcodeFixture", targets: ["XcodeFixture"])],
    targets: [
        .target(name: "XcodeFixture"),
        .testTarget(name: "XcodeFixtureTests", dependencies: ["XcodeFixture"]),
    ]
)
