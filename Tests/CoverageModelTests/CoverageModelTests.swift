import CoverageModel
import Testing

@Suite struct CoverageModelTests {
    @Test func repositoryPathRejectsNonCanonicalAndAbsolutePaths() throws {
        for invalid in ["", "/tmp/a.swift", "Sources/../a.swift", "Sources//a.swift", "Sources\\a.swift"] {
            #expect(throws: CoverageModelError.self) { try RepositoryPath(invalid) }
        }
        #expect(try RepositoryPath("Sources/App.swift").value == "Sources/App.swift")
    }

    @Test func coverageRejectsDuplicateLinesAndFiles() throws {
        let path = try RepositoryPath("App.swift")
        let line = try LineCoverage(line: 1, executionCount: 0)
        #expect(throws: CoverageModelError.self) { try FileCoverage(path: path, lines: [line, line]) }
        let file = try FileCoverage(path: path, lines: [line])
        #expect(throws: CoverageModelError.self) { try NormalizedCoverage(files: [file, file]) }
    }

    @Test func wholeProjectCountsIncludeEveryNormalizedFile() throws {
        let coverage = try NormalizedCoverage(files: [
            FileCoverage(path: RepositoryPath("Sources/A.swift"), lines: [
                LineCoverage(line: 1, executionCount: 2),
                LineCoverage(line: 2, executionCount: 0),
            ]),
            FileCoverage(path: RepositoryPath("Generated/B.swift"), lines: [
                LineCoverage(line: 9, executionCount: 1),
            ]),
            FileCoverage(path: RepositoryPath("Empty.swift"), lines: []),
        ])

        #expect(coverage.wholeProjectCounts == CoverageCounts(executable: 3, covered: 2))
        #expect(try NormalizedCoverage(files: []).wholeProjectCounts == CoverageCounts(executable: 0, covered: 0))
    }

    @Test func percentageValidationAndRatio() throws {
        #expect(throws: CoverageModelError.self) { try Percentage(-0.1) }
        #expect(throws: CoverageModelError.self) { try Percentage(100.1) }
        #expect(Percentage.ratio(covered: 0, executable: 0) == nil)
        let ratio = try #require(Percentage.ratio(covered: 2, executable: 3))
        #expect(abs(ratio.value - 200.0 / 3.0) < 0.000_001)
        #expect(try PercentagePointChange(-100).value == -100)
        #expect(try PercentagePointChange(100).value == 100)
        #expect(throws: CoverageModelError.self) { try PercentagePointChange(-100.1) }
        #expect(throws: CoverageModelError.self) { try PercentagePointChange(100.1) }
    }

    @Test func policyOutcomeHasPassingStatusLabel() {
        #expect(PolicyOutcome.passed(threshold: nil).statusLabel == "Passed")
    }
}
