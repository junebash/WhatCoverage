import CoverageModel
import DiffCoverage
import Testing

@Suite struct DiffCoverageCalculatorTests {
    @Test func intersectsExecutableAddedLinesAndSortsFiles() throws {
        let coverage = try NormalizedCoverage(files: [
            file("Sources/Z.swift", [(2, 0), (3, 9)]),
            file("Sources/A.swift", [(10, 1), (11, 0)]),
        ])
        let changes = try ChangedLines(files: [
            changed("Sources/Z.swift", [1, 2, 3, 4]),
            changed("Sources/A.swift", [10, 11]),
            changed("Sources/Missing.swift", [1]),
        ])

        let report = DiffCoverageCalculator.calculate(coverage: coverage, changes: changes)

        #expect(report.files.map(\.path.value) == ["Sources/A.swift", "Sources/Z.swift"])
        #expect(report.files[0].coveredLines == [10])
        #expect(report.files[0].uncoveredLines == [11])
        #expect(report.totals == CoverageCounts(executable: 4, covered: 2))
        #expect(report.totals.percentage?.value == 50)
        #expect(report.policy == .passed(threshold: nil))
    }

    @Test func thresholdPassAndFailureAreExplicit() throws {
        let coverage = try NormalizedCoverage(files: [file("A.swift", [(1, 1), (2, 0), (3, 1)])])
        let changes = try ChangedLines(files: [changed("A.swift", [1, 2, 3])])
        let exact = try Percentage(200.0 / 3.0)
        let high = try Percentage(67)
        let actual = try #require(Percentage.ratio(covered: 2, executable: 3))

        #expect(DiffCoverageCalculator.calculate(coverage: coverage, changes: changes, minimum: exact).policy == .passed(threshold: exact))
        #expect(DiffCoverageCalculator.calculate(coverage: coverage, changes: changes, minimum: high).policy == .failed(threshold: high, actual: actual))
    }

    @Test func noExecutableChangedLinesIsNotApplicableEvenWithThreshold() throws {
        let coverage = try NormalizedCoverage(files: [file("A.swift", [(2, 1)])])
        let changes = try ChangedLines(files: [changed("A.swift", [1, 3])])
        let threshold = try Percentage(100)

        let report = DiffCoverageCalculator.calculate(coverage: coverage, changes: changes, minimum: threshold)

        #expect(report.totals == CoverageCounts(executable: 0, covered: 0))
        #expect(report.totals.percentage == nil)
        #expect(report.policy == .notApplicable(threshold: threshold))
        #expect(report.files.isEmpty)
    }

    @Test func reportIdentifiesPartialCoverage() throws {
        let coverage = try NormalizedCoverage(files: [file("A.swift", [(1, 1), (2, 0)])])
        let changes = try ChangedLines(files: [changed("A.swift", [1, 2])])

        let report = DiffCoverageCalculator.calculate(coverage: coverage, changes: changes)

        #expect(report.totals.status == .partial)
    }

    private func file(_ path: String, _ lines: [(Int, Int)]) throws -> FileCoverage {
        try FileCoverage(path: RepositoryPath(path), lines: lines.map { try LineCoverage(line: $0.0, executionCount: $0.1) })
    }

    private func changed(_ path: String, _ lines: Set<Int>) throws -> ChangedFile {
        try ChangedFile(path: RepositoryPath(path), addedLines: lines)
    }
}
