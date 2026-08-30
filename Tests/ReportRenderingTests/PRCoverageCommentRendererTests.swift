import Foundation
import ReportRendering
import Testing

@Suite struct PRCoverageCommentRendererTests {
    private let head = String(repeating: "a", count: 40)

    @Test func rendersCompactEscapedSourceExcerptsWithContext() throws {
        let body = try render(
            report(),
            sources: ["Sources/A.swift": "one\ntwo\nif a < b {\nfour\nfive\nsix\n~~~ secret\n"]
        )

        #expect(body.contains("<summary>Uncovered source (2 lines)</summary>"))
        #expect(body.contains("▶    3 │ if a < b {"))
        #expect(body.contains("~~~~text"))
        #expect(body.contains("Sources/A.swift"))
        #expect(body.contains("Failed: 33.33% is below the required 60.00%"))
    }

    @Test func escapesMarkdownTablePathsAndUsesLongerFence() throws {
        var value = report()
        value["files"] = [[
            "path": "Sources/A|<B>.swift",
            "counts": counts(covered: 1, uncovered: 2, executable: 3),
            "coveredLines": [1],
            "uncoveredLines": [3, 7],
        ]]

        let body = try render(value, sources: ["Sources/A|<B>.swift": "one\ntwo\n~~~~~\nfour\nfive\nsix\nseven"])

        #expect(body.contains("Sources/A&#124;&lt;B&gt;.swift"))
        #expect(body.contains("~~~~~~text"))
    }

    @Test func rejectsMalformedPathsAndInconsistentLineData() throws {
        var malformedPath = report()
        malformedPath["files"] = [[
            "path": "../bad",
            "counts": counts(covered: 1, uncovered: 2, executable: 3),
            "coveredLines": [1],
            "uncoveredLines": [1, 2],
        ]]
        #expect(throws: PRCoverageCommentError.self) { try validate(malformedPath) }

        var inconsistentTotals = report()
        inconsistentTotals["totals"] = counts(covered: 1, uncovered: 1, executable: 2)
        #expect(throws: PRCoverageCommentError.self) { try validate(inconsistentTotals) }

        var inconsistentPolicy = report()
        inconsistentPolicy["policy"] = ["status": "failed", "threshold": 20, "actual": 100.0 / 3]
        #expect(throws: PRCoverageCommentError.self) { try validate(inconsistentPolicy) }
    }

    @Test func rendersPassingAndNotApplicablePolicyOutcomesClearly() throws {
        var passing = report()
        passing["policy"] = ["status": "passed", "threshold": 100.0 / 3]
        #expect(try render(passing).contains("Passed: 33.33% meets the required 33.33%"))

        var notApplicable = report()
        notApplicable["policy"] = ["status": "notApplicable", "threshold": 60]
        notApplicable["totals"] = counts(covered: 0, uncovered: 0, executable: 0)
        notApplicable["files"] = []
        #expect(try render(notApplicable).contains("Not applicable: no changed executable lines"))
    }

    @Test func truncatesSourceAndOmitsUnavailableExcerpts() throws {
        let longSource = Array(repeating: String(repeating: "x", count: 500), count: 8).joined(separator: "\n") + "\n"
        #expect(try render(report(), sources: ["Sources/A.swift": longSource]).contains("…"))

        let unavailable = try render(report(), sources: ["Sources/A.swift": "\0binary"])
        #expect(!unavailable.contains("Uncovered source"))
    }

    private func report() -> [String: Any] {
        [
            "schemaVersion": 1,
            "coverageInput": ["kind": "llvm"],
            "comparison": ["resolvedHead": head],
            "policy": ["status": "failed", "threshold": 60, "actual": 100.0 / 3],
            "totals": counts(covered: 1, uncovered: 2, executable: 3),
            "files": [[
                "path": "Sources/A.swift",
                "counts": counts(covered: 1, uncovered: 2, executable: 3),
                "coveredLines": [1],
                "uncoveredLines": [3, 7],
            ]],
        ]
    }

    private func counts(covered: Int, uncovered: Int, executable: Int) -> [String: Int] {
        ["covered": covered, "uncovered": uncovered, "executable": executable]
    }

    private func validate(_ value: [String: Any]) throws -> ValidatedPRCoverageReport {
        try PRCoverageReportValidator().validate(
            JSONSerialization.data(withJSONObject: value),
            expectedHead: head
        )
    }

    private func render(_ value: [String: Any], sources: [String: String] = [:]) throws -> String {
        try PRCoverageCommentRenderer().render(validate(value), sources: sources)
    }
}
