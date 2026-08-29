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

    @Test func percentageValidationAndRatio() throws {
        #expect(throws: CoverageModelError.self) { try Percentage(-0.1) }
        #expect(throws: CoverageModelError.self) { try Percentage(100.1) }
        #expect(Percentage.ratio(covered: 0, executable: 0) == nil)
        let ratio = try #require(Percentage.ratio(covered: 2, executable: 3))
        #expect(abs(ratio.value - 200.0 / 3.0) < 0.000_001)
    }
}
