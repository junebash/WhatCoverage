import CoverageModel
import Foundation

public struct HTMLReportRenderer: Sendable {
    public init() {}

    public func render(_ document: CoverageReportDocument) -> String {
        let result = document.result
        var body = """
        <!doctype html>
        <html lang="en">
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>WhatCoverage report</title><style>
        body { font-family: system-ui, sans-serif; margin: 2rem; color: #1f2937; } table { border-collapse: collapse; width: 100%; } th, td { border: 1px solid #d1d5db; padding: .5rem; text-align: left; } th { background: #f3f4f6; } .covered { color: #166534; } .uncovered { color: #b91c1c; } code { font-family: ui-monospace, monospace; } .meta { color: #4b5563; }
        </style></head><body><h1>WhatCoverage</h1>
        <p><strong>Diff coverage:</strong> \(coverage(result.totals))</p>
        <p><strong>Policy:</strong> \(escape(policy(result.policy)))</p>
        <p class="meta">Comparison: <code>\(escape(comparison(document.metadata.revision)))</code></p>
        <p class="meta">Coverage input: <code>\(escape(document.metadata.coverageInput.source))</code></p>
        """
        if result.files.isEmpty {
            body += "<p><em>No changed executable lines.</em></p>"
        } else {
            body += "<table><thead><tr><th>File</th><th>Coverage</th><th>Covered lines</th><th>Uncovered lines</th></tr></thead><tbody>"
            for file in result.files.sorted(by: { $0.path < $1.path }) {
                body += "<tr><td><code>\(escape(file.path.value))</code></td><td>\(coverage(file.counts))</td><td class=\"covered\">\(lines(file.coveredLines))</td><td class=\"uncovered\">\(lines(file.uncoveredLines))</td></tr>"
            }
            body += "</tbody></table>"
        }
        return body + "</body></html>\n"
    }

    private func coverage(_ counts: CoverageCounts) -> String {
        guard let percentage = counts.percentage else { return "N/A" }
        return "\(format(percentage)) (\(counts.covered)/\(counts.executable))"
    }

    private func lines(_ values: [Int]) -> String {
        values.map(String.init).joined(separator: ", ")
    }

    private func policy(_ outcome: PolicyOutcome) -> String {
        switch outcome {
        case .passed(let threshold): return threshold.map { "Passed (minimum \(format($0)))" } ?? "Passed"
        case .failed(let threshold, _): return "Failed (minimum \(format(threshold)))"
        case .notApplicable(let threshold): return threshold.map { "Not applicable (minimum \(format($0)))" } ?? "Not applicable"
        }
    }

    private func comparison(_ revision: RevisionMetadata) -> String {
        let separator = revision.mode == .mergeBase ? "..." : ".."
        return "\(revision.requestedBase)\(separator)\(revision.requestedHead) (\(revision.resolvedBase) → \(revision.resolvedHead))"
    }

    private func format(_ percentage: Percentage) -> String {
        String(format: "%.2f%%", locale: Locale(identifier: "en_US_POSIX"), percentage.value)
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
