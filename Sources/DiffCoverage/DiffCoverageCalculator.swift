import CoverageModel

public enum DiffCoverageCalculator {
    public static func calculate(
        coverage: NormalizedCoverage,
        changes: ChangedLines,
        minimum: Percentage? = nil
    ) -> DiffCoverageReport {
        let results = changes.files.values.compactMap { change -> FileCoverageResult? in
            guard let fileCoverage = coverage.files[change.path] else { return nil }
            var covered: [Int] = []
            var uncovered: [Int] = []
            for line in change.addedLines.sorted() {
                guard let count = fileCoverage.lines[line] else { continue }
                if count > 0 { covered.append(line) } else { uncovered.append(line) }
            }
            guard !covered.isEmpty || !uncovered.isEmpty else { return nil }
            return FileCoverageResult(path: change.path, coveredLines: covered, uncoveredLines: uncovered)
        }.sorted { $0.path < $1.path }

        let executable = results.reduce(0) { $0 + $1.counts.executable }
        let covered = results.reduce(0) { $0 + $1.counts.covered }
        let totals = CoverageCounts(executable: executable, covered: covered)
        let policy: PolicyOutcome
        if let actual = totals.percentage {
            if let minimum, actual < minimum {
                policy = .failed(threshold: minimum, actual: actual)
            } else {
                policy = .passed(threshold: minimum)
            }
        } else {
            policy = .notApplicable(threshold: minimum)
        }
        return DiffCoverageReport(files: results, totals: totals, policy: policy)
    }
}
