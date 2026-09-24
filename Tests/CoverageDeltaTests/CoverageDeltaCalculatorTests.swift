import CoverageDelta
import CoverageModel
import Testing

@Suite struct CoverageDeltaCalculatorTests {
    @Test func comparesUnionOfFilesAndAggregatesProjectTargetsAndFiles() throws {
        let base = try NormalizedCoverage(files: [
            file("Sources/App/A.swift", [1: 1, 2: 0]),
            file("Sources/Removed/Old.swift", [1: 1]),
            file("README.swift", [1: 0]),
        ])
        let head = try NormalizedCoverage(files: [
            file("Sources/App/A.swift", [1: 1, 2: 1, 3: 0]),
            file("Tests/AppTests/A.swift", [1: 1]),
            file("README.swift", [1: 1]),
        ])

        let result = CoverageDeltaCalculator.calculate(base: base, head: head)

        #expect(result.project.base == CoverageCounts(executable: 4, covered: 2))
        #expect(result.project.head == CoverageCounts(executable: 5, covered: 4))
        #expect(result.project.percentagePointChange?.value == 30)
        #expect(result.targets.map(\.name) == ["(root)", "App", "AppTests", "Removed"])
        #expect(result.files.map(\.path.value) == [
            "README.swift", "Sources/App/A.swift", "Sources/Removed/Old.swift", "Tests/AppTests/A.swift",
        ])
        #expect(result.files.first(where: { $0.path.value == "Sources/Removed/Old.swift" })?.coverage.head == CoverageCounts(executable: 0, covered: 0))
        #expect(result.files.first(where: { $0.path.value == "Tests/AppTests/A.swift" })?.coverage.base == CoverageCounts(executable: 0, covered: 0))
    }

    @Test func omitsChangeWhenEitherArtifactHasNoExecutableLines() throws {
        let result = CoverageDeltaCalculator.calculate(
            base: try NormalizedCoverage(files: []),
            head: try NormalizedCoverage(files: [file("Sources/App/A.swift", [1: 1])])
        )

        #expect(result.project.base.percentage == nil)
        #expect(result.project.percentagePointChange == nil)
        #expect(result.files[0].coverage.percentagePointChange == nil)
    }

    @Test func targetGroupingIsPortableAndPathBased() throws {
        #expect(try CoverageDeltaCalculator.targetName(for: RepositoryPath("Sources/Library/A.swift")) == "Library")
        #expect(try CoverageDeltaCalculator.targetName(for: RepositoryPath("Tests/LibraryTests/A.swift")) == "LibraryTests")
        #expect(try CoverageDeltaCalculator.targetName(for: RepositoryPath("App/Feature/A.swift")) == "App")
        #expect(try CoverageDeltaCalculator.targetName(for: RepositoryPath("Package.swift")) == "(root)")
    }

    private func file(_ path: String, _ lines: [Int: Int]) throws -> FileCoverage {
        try FileCoverage(
            path: RepositoryPath(path),
            lines: lines.keys.sorted().map { try LineCoverage(line: $0, executionCount: lines[$0]!) }
        )
    }
}
