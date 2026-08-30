import CoverageModel
import Foundation

public struct MarkdownReportRenderer: Sendable {
    public init() {}

    public func render(_ document: CoverageReportDocument) -> String {
        let result = document.result
        let metadata = document.metadata
        var lines = ["# WhatCoverage", ""]

        if let percentage = result.totals.percentage {
            lines.append("**Diff coverage:** \(format(percentage)) (\(result.totals.covered)/\(result.totals.executable) executable lines)")
        } else {
            lines.append("**Diff coverage:** Not applicable (no changed executable lines)")
        }
        lines.append("**Policy:** \(policy(result.policy))")
        let separator = metadata.revision.mode == .mergeBase ? "..." : ".."
        lines.append("**Comparison:** \(code(metadata.revision.requestedBase + separator + metadata.revision.requestedHead)) (\(code(metadata.revision.resolvedBase)) → \(code(metadata.revision.resolvedHead)))")
        lines.append("**Coverage input:** \(inputName(metadata.coverageInput.kind)) — \(code(metadata.coverageInput.source))")
        lines.append("")

        if let delta = document.coverageDelta {
            appendCoverageDelta(delta, to: &lines)
        }

        if result.files.isEmpty {
            lines.append("_No changed executable lines._")
        } else {
            lines.append("| File | Coverage | Covered | Uncovered |")
            lines.append("| --- | ---: | ---: | ---: |")
            for file in result.files.sorted(by: { $0.path < $1.path }) {
                let counts = file.counts
                lines.append("| \(tableCode(file.path.value)) | \(counts.percentage.map(format) ?? "N/A") | \(counts.covered) | \(counts.uncovered) |")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func appendCoverageDelta(_ document: CoverageDeltaDocument, to lines: inout [String]) {
        let delta = document.result
        lines.append("## Whole-project coverage delta")
        lines.append("")
        lines.append("**Base coverage input:** \(inputName(document.baseInput.kind)) — \(code(document.baseInput.source))")
        lines.append("**Project:** \(deltaDescription(delta.project))")
        lines.append("")
        lines.append("### Targets")
        lines.append("")
        lines.append("| Target | Base | Head | Change |")
        lines.append("| --- | ---: | ---: | ---: |")
        for target in delta.targets.sorted(by: { $0.name < $1.name }) {
            lines.append("| \(tableCode(target.name)) | \(coverage(target.coverage.base)) | \(coverage(target.coverage.head)) | \(change(target.coverage)) |")
        }
        lines.append("")
        lines.append("### Files")
        lines.append("")
        lines.append("| File | Target | Base | Head | Change |")
        lines.append("| --- | --- | ---: | ---: | ---: |")
        for file in delta.files.sorted(by: { $0.path < $1.path }) {
            lines.append("| \(tableCode(file.path.value)) | \(tableCode(file.target)) | \(coverage(file.coverage.base)) | \(coverage(file.coverage.head)) | \(change(file.coverage)) |")
        }
        lines.append("")
    }

    private func deltaDescription(_ delta: CoverageDeltaCounts) -> String {
        "\(coverage(delta.base)) → \(coverage(delta.head)) (\(change(delta)))"
    }

    private func coverage(_ counts: CoverageCounts) -> String {
        guard let percentage = counts.percentage else { return "N/A (0/0)" }
        return "\(format(percentage)) (\(counts.covered)/\(counts.executable))"
    }

    private func change(_ delta: CoverageDeltaCounts) -> String {
        guard let value = delta.percentagePointChange?.value else { return "N/A" }
        return String(format: "%+.2f pp", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func policy(_ outcome: PolicyOutcome) -> String {
        switch outcome {
        case .passed(let threshold):
            return threshold.map { "Passed (minimum \(format($0)))" } ?? "Passed"
        case .failed(let threshold, _):
            return "Failed (minimum \(format(threshold)))"
        case .notApplicable(let threshold):
            return threshold.map { "Not applicable (minimum \(format($0)))" } ?? "Not applicable"
        }
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

    private func tableCode(_ value: String) -> String {
        code(value).replacingOccurrences(of: "|", with: "\\|")
    }

    private func code(_ value: String) -> String {
        var longestRun = 0
        var currentRun = 0
        for character in value {
            if character == "`" {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        let delimiter = String(repeating: "`", count: longestRun + 1)
        let padding = value.hasPrefix("`") || value.hasSuffix("`") ? " " : ""
        return delimiter + padding + value + padding + delimiter
    }
}
