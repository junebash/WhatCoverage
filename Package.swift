// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WhatCoverage",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "what-coverage", targets: ["WhatCoverage"]),
        .executable(name: "what-coverage-pr-comment", targets: ["WhatCoveragePRComment"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "CoverageModel"),
        .target(name: "CoverageReaders", dependencies: ["CoverageModel", "ProcessSupport"]),
        .target(name: "CoverageDelta", dependencies: ["CoverageModel"]),
        .target(name: "DiffCoverage", dependencies: ["CoverageModel"]),
        .target(name: "GitDiff", dependencies: ["CoverageModel", "ProcessSupport"]),
        .target(name: "ProcessSupport"),
        .target(name: "ReportRendering", dependencies: ["CoverageModel"]),
        .executableTarget(
            name: "WhatCoverage",
            dependencies: [
                "CoverageReaders",
                "CoverageDelta",
                "DiffCoverage",
                "GitDiff",
                "ReportRendering",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "WhatCoveragePRComment",
            dependencies: ["ReportRendering"]
        ),
        .testTarget(name: "CoverageModelTests", dependencies: ["CoverageModel"]),
        .testTarget(name: "CoverageDeltaTests", dependencies: ["CoverageDelta"]),
        .testTarget(
            name: "CoverageReadersTests",
            dependencies: ["CoverageReaders", "CoverageDelta", "DiffCoverage", "GitDiff", "ProcessSupport"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "DiffCoverageTests", dependencies: ["DiffCoverage"]),
        .testTarget(name: "GitDiffTests", dependencies: ["CoverageModel", "GitDiff", "ProcessSupport"]),
        .testTarget(
            name: "ReportRenderingTests",
            dependencies: ["CoverageModel", "CoverageDelta", "DiffCoverage", "ReportRendering"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "WhatCoverageTests",
            dependencies: [
                "WhatCoverage",
                "ReportRendering",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
