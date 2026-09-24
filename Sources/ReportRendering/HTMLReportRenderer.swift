import CoverageModel
import Foundation

public struct HTMLReportRenderer: Sendable {
    public init() {}

    public func render(_ document: CoverageReportDocument) -> String {
        let result = document.result
        let metadata = document.metadata
        var body = """
        <!doctype html>
        <html lang="en">
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>WhatCoverage report</title><style>
        body { font-family: system-ui, sans-serif; margin: 2rem; color: #1f2937; } table { border-collapse: collapse; width: 100%; } th, td { border: 1px solid #d1d5db; padding: .5rem; text-align: left; } th { background: #f3f4f6; } .covered { color: #166534; } .uncovered { color: #b91c1c; } code { font-family: ui-monospace, monospace; } .meta { color: #4b5563; }
        </style></head><body><h1>WhatCoverage</h1>
        <p><strong>Diff coverage:</strong> \(diffCoverage(result.totals))</p>

        """
        if let counts = document.wholeProjectCoverage {
            body += "<p><strong>Whole-project coverage:</strong> \(coverage(counts))</p>\n"
        }
        body += """
        <p><strong>Policy:</strong> \(escape(policy(result.policy)))</p>
        <p class="meta">Comparison: <code>\(escape(requestedComparison(metadata.revision)))</code> (<code>\(escape(metadata.revision.resolvedBase))</code> → <code>\(escape(metadata.revision.resolvedHead))</code>)</p>
        <p class="meta">Coverage input: \(escape(inputName(metadata.coverageInput.kind))) — <code>\(escape(metadata.coverageInput.source))</code></p>
        <p class="meta">\(pathMapping(metadata.pathMapping))</p>

        """
        if let delta = document.coverageDelta {
            body += coverageDelta(delta)
        }
        if result.files.isEmpty {
            body += "<p><em>No changed executable lines.</em></p>"
        } else {
            body += "<table><thead><tr><th>File</th><th>Coverage</th><th>Covered lines</th><th>Uncovered lines</th></tr></thead><tbody>"
            for file in result.files.sorted(by: { $0.path < $1.path }) {
                body += "<tr><td><code>\(escape(file.path.value))</code></td><td>\(file.counts.percentage.map(format) ?? "N/A")</td><td class=\"covered\">\(lines(file.coveredLines))</td><td class=\"uncovered\">\(lines(file.uncoveredLines))</td></tr>"
            }
            body += "</tbody></table>"
        }
        return body + "</body></html>\n"
    }

    private func coverageDelta(_ document: CoverageDeltaDocument) -> String {
        let delta = document.result
        var html = """
        <h2>Whole-project coverage delta</h2>
        <p><strong>Base coverage input:</strong> \(escape(inputName(document.baseInput.kind))) — <code>\(escape(document.baseInput.source))</code></p>
        <p class="meta">\(pathMapping(document.basePathMapping, prefix: "Base path mapping"))</p>
        <p><strong>Project:</strong> \(escape(deltaDescription(delta.project)))</p>
        <h3>Targets</h3>
        <table><thead><tr><th>Target</th><th>Base</th><th>Head</th><th>Change</th></tr></thead><tbody>
        """
        for target in delta.targets.sorted(by: { $0.name < $1.name }) {
            html += "<tr><td><code>\(escape(target.name))</code></td><td>\(coverage(target.coverage.base))</td><td>\(coverage(target.coverage.head))</td><td>\(change(target.coverage))</td></tr>"
        }
        html += """
        </tbody></table>
        <h3>Files</h3>
        <table><thead><tr><th>File</th><th>Target</th><th>Base</th><th>Head</th><th>Change</th></tr></thead><tbody>
        """
        for file in delta.files.sorted(by: { $0.path < $1.path }) {
            html += "<tr><td><code>\(escape(file.path.value))</code></td><td><code>\(escape(file.target))</code></td><td>\(coverage(file.coverage.base))</td><td>\(coverage(file.coverage.head))</td><td>\(change(file.coverage))</td></tr>"
        }
        html += "</tbody></table>\n"
        return html
    }

    private func diffCoverage(_ counts: CoverageCounts) -> String {
        guard let percentage = counts.percentage else { return "Not applicable (no changed executable lines)" }
        return "\(format(percentage)) (\(counts.covered)/\(counts.executable) executable lines)"
    }

    private func coverage(_ counts: CoverageCounts) -> String {
        guard let percentage = counts.percentage else { return "N/A (0/0)" }
        return "\(format(percentage)) (\(counts.covered)/\(counts.executable))"
    }

    private func deltaDescription(_ delta: CoverageDeltaCounts) -> String {
        "\(coverage(delta.base)) → \(coverage(delta.head)) (\(change(delta)))"
    }

    private func change(_ delta: CoverageDeltaCounts) -> String {
        guard let value = delta.percentagePointChange?.value else { return "N/A" }
        return String(format: "%+.2f pp", locale: Locale(identifier: "en_US_POSIX"), value)
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

    private func requestedComparison(_ revision: RevisionMetadata) -> String {
        let separator = revision.mode == .mergeBase ? "..." : ".."
        return "\(revision.requestedBase)\(separator)\(revision.requestedHead)"
    }

    private func pathMapping(_ mapping: PathMappingMetadata, prefix: String = "Path mapping") -> String {
        var text = "\(prefix): <code>\(escape(mapping.repositoryRoot))</code>"
        if let captured = mapping.capturedSourceRoot {
            text += " (captured <code>\(escape(captured))</code>)"
        }
        return text
    }

    private func inputName(_ kind: CoverageInputKind) -> String {
        switch kind {
        case .xcode: "Xcode"
        case .llvm: "LLVM"
        }
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
