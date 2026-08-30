import CoverageModel

public enum CoverageDeltaCalculator {
    public static func calculate(
        base: NormalizedCoverage,
        head: NormalizedCoverage
    ) -> WholeProjectCoverageDelta {
        let paths = Set(base.files.keys).union(head.files.keys).sorted()
        let files = paths.compactMap { path -> FileCoverageDelta? in
            let baseCounts = counts(base.files[path])
            let headCounts = counts(head.files[path])
            guard baseCounts.executable > 0 || headCounts.executable > 0 else { return nil }
            return FileCoverageDelta(
                path: path,
                target: targetName(for: path),
                coverage: CoverageDeltaCounts(
                    base: baseCounts,
                    head: headCounts
                )
            )
        }

        let grouped = Dictionary(grouping: files, by: \.target)
        let targets = grouped.keys.sorted().map { name in
            let values = grouped[name] ?? []
            return TargetCoverageDelta(
                name: name,
                coverage: CoverageDeltaCounts(
                    base: aggregate(values.map(\.coverage.base)),
                    head: aggregate(values.map(\.coverage.head))
                )
            )
        }

        return WholeProjectCoverageDelta(
            project: CoverageDeltaCounts(
                base: aggregate(files.map(\.coverage.base)),
                head: aggregate(files.map(\.coverage.head))
            ),
            targets: targets,
            files: files
        )
    }

    public static func targetName(for path: RepositoryPath) -> String {
        let components = path.value.split(separator: "/").map(String.init)
        if components.count >= 2, components[0] == "Sources" || components[0] == "Tests" {
            return components[1]
        }
        return components.count > 1 ? components[0] : "(root)"
    }

    private static func counts(_ file: FileCoverage?) -> CoverageCounts {
        guard let file else { return CoverageCounts(executable: 0, covered: 0) }
        return CoverageCounts(
            executable: file.lines.count,
            covered: file.lines.values.count(where: { $0 > 0 })
        )
    }

    private static func aggregate(_ values: [CoverageCounts]) -> CoverageCounts {
        CoverageCounts(
            executable: values.reduce(0) { $0 + $1.executable },
            covered: values.reduce(0) { $0 + $1.covered }
        )
    }
}
