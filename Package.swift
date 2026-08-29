// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WhatCoverage",
    products: [
        .library(name: "CoverageModel", targets: ["CoverageModel"]),
        .library(name: "CoverageReaders", targets: ["CoverageReaders"]),
        .library(name: "DiffCoverage", targets: ["DiffCoverage"]),
        .library(name: "GitDiff", targets: ["GitDiff"]),
        .executable(name: "what-coverage", targets: ["WhatCoverage"]),
    ],
    targets: [
        .target(name: "CoverageModel"),
        .target(name: "CoverageReaders", dependencies: ["CoverageModel"]),
        .target(name: "DiffCoverage", dependencies: ["CoverageModel"]),
        .target(name: "GitDiff", dependencies: ["CoverageModel"]),
        .executableTarget(
            name: "WhatCoverage",
            dependencies: ["CoverageReaders", "DiffCoverage", "GitDiff"]
        ),
        .testTarget(name: "CoverageModelTests", dependencies: ["CoverageModel"]),
        .testTarget(
            name: "CoverageReadersTests",
            dependencies: ["CoverageReaders", "DiffCoverage", "GitDiff"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "DiffCoverageTests", dependencies: ["DiffCoverage"]),
        .testTarget(name: "GitDiffTests", dependencies: ["CoverageModel", "GitDiff"]),
    ]
)
