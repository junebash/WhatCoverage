import CoverageModel
import DiffCoverage
import Foundation
import ReportRendering
import Testing

@Suite struct ReportRenderingTests {
    @Test func failedReportMatchesJSONAndMarkdownGoldens() throws {
        let document = try measurableDocument(minimum: 50)

        try expectGolden(JSONReportRenderer().render(document), named: "failed-report", extension: "json")
        try expectGolden(Data(MarkdownReportRenderer().render(document).utf8), named: "failed-report", extension: "md")
    }

    @Test func passedPolicyIsRenderedWithoutChangingTheCalculatedResult() throws {
        let document = try measurableDocument(minimum: 30)

        let json = try #require(String(data: JSONReportRenderer().render(document), encoding: .utf8))
        let markdown = MarkdownReportRenderer().render(document)

        #expect(json.contains(#""status" : "passed""#))
        #expect(json.contains(#""threshold" : 30"#))
        #expect(markdown.contains("**Policy:** Passed (minimum 30.00%)"))
        #expect(markdown.contains("**Diff coverage:** 33.33%"))
    }

    @Test func notApplicableReportMatchesJSONAndMarkdownGoldens() throws {
        let document = try notApplicableDocument()

        try expectGolden(JSONReportRenderer().render(document), named: "not-applicable-report", extension: "json")
        try expectGolden(Data(MarkdownReportRenderer().render(document).utf8), named: "not-applicable-report", extension: "md")
    }

    @Test func markdownEscapesTableSeparatorsAndBackticks() throws {
        let path = try RepositoryPath("Sources/A|`B.swift")
        let coverage = try NormalizedCoverage(files: [
            FileCoverage(path: path, lines: [try LineCoverage(line: 1, executionCount: 1)]),
        ])
        let changes = try ChangedLines(files: [ChangedFile(path: path, addedLines: [1])])
        let result = DiffCoverageCalculator.calculate(coverage: coverage, changes: changes)

        let markdown = MarkdownReportRenderer().render(CoverageReportDocument(
            metadata: metadata(),
            result: result
        ))

        #expect(markdown.contains(#"``Sources/A\|`B.swift``"#))
    }

    @Test func htmlEscapesPathsAndShowsExistingLineMetadata() throws {
        let path = try RepositoryPath("Sources/A<&\"'.swift")
        let coverage = try NormalizedCoverage(files: [
            FileCoverage(path: path, lines: [try LineCoverage(line: 2, executionCount: 1), try LineCoverage(line: 4, executionCount: 0)]),
        ])
        let document = CoverageReportDocument(metadata: metadata(), result: DiffCoverageCalculator.calculate(
            coverage: coverage,
            changes: try ChangedLines(files: [ChangedFile(path: path, addedLines: [2, 4])])
        ))

        let html = HTMLReportRenderer().render(document)

        #expect(html.contains("Sources/A&lt;&amp;&quot;&#39;.swift"))
        #expect(html.contains("<td class=\"covered\">2</td>"))
        #expect(html.contains("<td class=\"uncovered\">4</td>"))
    }

    private func measurableDocument(minimum: Double) throws -> CoverageReportDocument {
        let a = try RepositoryPath("Sources/A.swift")
        let b = try RepositoryPath("Sources/B.swift")
        let coverage = try NormalizedCoverage(files: [
            FileCoverage(path: b, lines: [try LineCoverage(line: 2, executionCount: 0)]),
            FileCoverage(path: a, lines: [
                try LineCoverage(line: 1, executionCount: 2),
                try LineCoverage(line: 3, executionCount: 0),
            ]),
        ])
        let changes = try ChangedLines(files: [
            ChangedFile(path: b, addedLines: [2]),
            ChangedFile(path: a, addedLines: [1, 3]),
        ])
        return CoverageReportDocument(
            metadata: metadata(),
            result: DiffCoverageCalculator.calculate(
                coverage: coverage,
                changes: changes,
                minimum: try Percentage(minimum)
            )
        )
    }

    private func notApplicableDocument() throws -> CoverageReportDocument {
        CoverageReportDocument(
            metadata: ReportMetadata(
                revision: RevisionMetadata(
                    requestedBase: "v1",
                    requestedHead: "HEAD",
                    resolvedBase: "1111111",
                    resolvedHead: "2222222",
                    mode: .direct
                ),
                coverageInput: CoverageInputMetadata(kind: .llvm, source: "coverage.json"),
                pathMapping: PathMappingMetadata(repositoryRoot: "/workspace/repo")
            ),
            result: DiffCoverageCalculator.calculate(
                coverage: try NormalizedCoverage(files: []),
                changes: try ChangedLines(files: []),
                minimum: try Percentage(75)
            )
        )
    }

    private func metadata() -> ReportMetadata {
        ReportMetadata(
            revision: RevisionMetadata(
                requestedBase: "origin/main",
                requestedHead: "HEAD",
                resolvedBase: "aaaaaaa",
                resolvedHead: "bbbbbbb",
                mode: .mergeBase
            ),
            coverageInput: CoverageInputMetadata(kind: .xcode, source: "Artifacts/Tests.xcresult"),
            pathMapping: PathMappingMetadata(
                repositoryRoot: "/workspace/repo",
                capturedSourceRoot: "/build/repo"
            )
        )
    }

    private func expectGolden(_ actual: Data, named name: String, extension fileExtension: String) throws {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Fixtures"
        ))
        let expected = try Data(contentsOf: url)
        #expect(actual == expected)
    }
}
