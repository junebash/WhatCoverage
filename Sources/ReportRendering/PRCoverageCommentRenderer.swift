import CoreFoundation
import CoverageModel
import Foundation

public enum PRCoverageCommentError: Error, Equatable, Sendable {
    case invalidReport(String)
    case renderedCommentTooLarge
}

public struct PRCoverageCommentLimits: Equatable, Sendable {
    public static let standard = Self(
        files: 500,
        linesPerFile: 10_000,
        linesTotal: 50_000,
        lineNumber: 10_000_000,
        sourceFiles: 10,
        sourceAttempts: 20,
        sourceBytesPerFile: 64 * 1_024,
        sourceBytesTotal: 512 * 1_024,
        excerptTargets: 40,
        excerptLines: 200,
        lineCharacters: 400,
        commentCharacters: 50_000
    )

    public let files: Int
    public let linesPerFile: Int
    public let linesTotal: Int
    public let lineNumber: Int
    public let sourceFiles: Int
    public let sourceAttempts: Int
    public let sourceBytesPerFile: Int
    public let sourceBytesTotal: Int
    public let excerptTargets: Int
    public let excerptLines: Int
    public let lineCharacters: Int
    public let commentCharacters: Int
}

public struct ValidatedPRCoverageReport: Equatable, Sendable {
    public struct Counts: Equatable, Sendable {
        public let covered: Int
        public let uncovered: Int
        public let executable: Int
    }

    public struct File: Equatable, Sendable {
        public let path: String
        public let counts: Counts
        public let coveredLines: [Int]
        public let uncoveredLines: [Int]
    }

    public enum PolicyStatus: String, Equatable, Sendable {
        case passed, failed, notApplicable
    }

    public struct Policy: Equatable, Sendable {
        public let status: PolicyStatus
        public let threshold: Double?
        public let actual: Double?
    }

    public let totals: Counts
    public let wholeProjectCoverage: Counts?
    public let files: [File]
    public let policy: Policy

    public var sourceRequestPaths: [String] {
        Array(files.lazy.filter { !$0.uncoveredLines.isEmpty }.prefix(PRCoverageCommentLimits.standard.sourceAttempts).map(\.path))
    }
}

public struct LocalPRCoverageSourceLoader: Sendable {
    private let limits = PRCoverageCommentLimits.standard

    public init() {}

    public func load(for report: ValidatedPRCoverageReport, repositoryRoot: URL) -> [String: String] {
        let root = repositoryRoot.standardizedFileURL.resolvingSymlinksInPath()
        var sources: [String: String] = [:]
        var totalBytes = 0
        for path in report.sourceRequestPaths.prefix(limits.sourceAttempts) {
            guard sources.count < limits.sourceFiles else { break }
            let file = root.appending(path: path).standardizedFileURL.resolvingSymlinksInPath()
            let rootPrefix = root.path == "/" ? "/" : root.path + "/"
            guard file.path.hasPrefix(rootPrefix),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular,
                  let size = (attributes[.size] as? NSNumber)?.intValue,
                  size <= limits.sourceBytesPerFile,
                  totalBytes + size <= limits.sourceBytesTotal,
                  let data = try? Data(contentsOf: file),
                  data.count == size,
                  !data.contains(0),
                  let text = String(data: data, encoding: .utf8)
            else {
                continue
            }
            sources[path] = text
            totalBytes += size
        }
        return sources
    }
}

public struct PRCoverageReportValidator: Sendable {
    private let limits = PRCoverageCommentLimits.standard

    public init() {}

    public func validate(
        _ data: Data,
        expectedHead: String,
        requiredInputKind: CoverageInputKind? = .llvm
    ) throws -> ValidatedPRCoverageReport {
        let root: [String: Any]
        do {
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw invalid("contract")
            }
            root = value
        } catch let error as PRCoverageCommentError {
            throw error
        } catch {
            throw invalid("contract")
        }

        let inputKind = dictionary(root["coverageInput"])?["kind"] as? String
        guard integer(root["schemaVersion"]) == 1,
              inputKind == CoverageInputKind.llvm.rawValue || inputKind == CoverageInputKind.xcode.rawValue,
              requiredInputKind == nil || inputKind == requiredInputKind?.rawValue,
              dictionary(root["comparison"])?["resolvedHead"] as? String == expectedHead,
              let rawFiles = root["files"] as? [Any],
              rawFiles.count <= limits.files,
              let rawPolicy = dictionary(root["policy"]),
              let statusValue = rawPolicy["status"] as? String,
              let status = ValidatedPRCoverageReport.PolicyStatus(rawValue: statusValue)
        else {
            throw invalid("contract")
        }

        let totals = try counts(root["totals"], label: "totals")
        let wholeProjectCoverage: ValidatedPRCoverageReport.Counts?
        if root.keys.contains("wholeProjectCoverage") {
            let value = try counts(root["wholeProjectCoverage"], label: "whole-project coverage")
            try validatePercentage(
                root["wholeProjectCoverage"],
                counts: value,
                label: "whole-project coverage"
            )
            wholeProjectCoverage = value
        } else {
            wholeProjectCoverage = nil
        }
        var paths = Set<String>()
        var files: [ValidatedPRCoverageReport.File] = []
        var aggregateCovered = 0
        var aggregateUncovered = 0
        var aggregateExecutable = 0
        var lineTotal = 0

        for rawFile in rawFiles {
            guard let file = dictionary(rawFile), let path = file["path"] as? String,
                  validPath(path), paths.insert(path).inserted
            else {
                throw invalid("path")
            }
            let fileCounts = try counts(file["counts"], label: "file counts")
            let coveredLines = try lines(file["coveredLines"], label: "covered lines")
            let uncoveredLines = try lines(file["uncoveredLines"], label: "uncovered lines")
            guard coveredLines.count == fileCounts.covered, uncoveredLines.count == fileCounts.uncovered else {
                throw invalid("line counts")
            }
            guard Set(coveredLines).isDisjoint(with: uncoveredLines) else {
                throw invalid("overlapping lines")
            }
            aggregateCovered += fileCounts.covered
            aggregateUncovered += fileCounts.uncovered
            aggregateExecutable += fileCounts.executable
            lineTotal += fileCounts.executable
            guard lineTotal <= limits.linesTotal else { throw invalid("too many lines") }
            files.append(.init(
                path: path,
                counts: fileCounts,
                coveredLines: coveredLines,
                uncoveredLines: uncoveredLines
            ))
        }

        guard aggregateCovered == totals.covered,
              aggregateUncovered == totals.uncovered,
              aggregateExecutable == totals.executable
        else {
            throw invalid("aggregate counts")
        }

        let threshold = try optionalPercentage(rawPolicy, key: "threshold", label: "policy threshold")
        let actualValue = totals.executable == 0 ? nil : Double(totals.covered) * 100 / Double(totals.executable)
        let policyActual: Double?
        switch status {
        case .failed:
            guard let threshold,
                  rawPolicy.keys.contains("actual"),
                  let actual = percentage(rawPolicy["actual"]),
                  let actualValue,
                  abs(actual - actualValue) <= Double.ulpOfOne * max(1, actualValue),
                  actual < threshold
            else {
                throw invalid("failed policy")
            }
            policyActual = actual
        case .passed, .notApplicable:
            guard !rawPolicy.keys.contains("actual"),
                  (status == .notApplicable) == (actualValue == nil),
                  !(status == .passed && threshold.map { actualValue! < $0 } == true)
            else {
                throw invalid("policy outcome")
            }
            policyActual = nil
        }

        return ValidatedPRCoverageReport(
            totals: totals,
            wholeProjectCoverage: wholeProjectCoverage,
            files: files,
            policy: .init(status: status, threshold: threshold, actual: policyActual)
        )
    }

    private func validPath(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 500, !value.hasPrefix("/") else { return false }
        let forbidden = value.unicodeScalars.contains { scalar in
            scalar.value <= 0x1F || scalar.value == 0x7F || scalar.value == 0x5C
        }
        return !forbidden && value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }

    private func lines(_ value: Any?, label: String) throws -> [Int] {
        guard let values = value as? [Any], values.count <= limits.linesPerFile else { throw invalid(label) }
        var result: [Int] = []
        var previous = 0
        for value in values {
            guard let line = integer(value), line > previous, line <= limits.lineNumber else { throw invalid(label) }
            result.append(line)
            previous = line
        }
        return result
    }

    private func counts(_ value: Any?, label: String) throws -> ValidatedPRCoverageReport.Counts {
        guard let value = dictionary(value),
              let covered = integer(value["covered"]), covered >= 0,
              let uncovered = integer(value["uncovered"]), uncovered >= 0,
              let executable = integer(value["executable"]), executable >= 0,
              covered + uncovered == executable
        else {
            throw invalid(label)
        }
        return .init(covered: covered, uncovered: uncovered, executable: executable)
    }

    private func validatePercentage(
        _ value: Any?,
        counts: ValidatedPRCoverageReport.Counts,
        label: String
    ) throws {
        guard let value = dictionary(value) else { throw invalid(label) }
        if counts.executable == 0 {
            guard !value.keys.contains("percentage") else { throw invalid(label) }
            return
        }
        let expected = Double(counts.covered) * 100 / Double(counts.executable)
        guard let actual = percentage(value["percentage"]),
              abs(actual - expected) <= Double.ulpOfOne * max(1, expected)
        else {
            throw invalid(label)
        }
    }

    private func optionalPercentage(
        _ object: [String: Any],
        key: String,
        label: String
    ) throws -> Double? {
        guard object.keys.contains(key) else { return nil }
        guard let value = percentage(object[key]) else { throw invalid(label) }
        return value
    }

    private func percentage(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        let value = number.doubleValue
        return value.isFinite && (0...100).contains(value) ? value : nil
    }

    private func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBoolean(number) else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded(.towardZero) == double,
              abs(double) <= 9_007_199_254_740_991,
              double >= Double(Int.min), double <= Double(Int.max)
        else {
            return nil
        }
        return Int(double)
    }

    private func dictionary(_ value: Any?) -> [String: Any]? { value as? [String: Any] }

    private func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func invalid(_ message: String) -> PRCoverageCommentError {
        .invalidReport(message)
    }
}

public struct PRCoverageCommentRenderer: Sendable {
    private let limits = PRCoverageCommentLimits.standard

    public init() {}

    public func render(_ report: ValidatedPRCoverageReport, sources: [String: String] = [:]) throws -> String {
        let percent = report.totals.executable == 0
            ? "Not applicable"
            : format(Double(report.totals.covered) * 100 / Double(report.totals.executable))
        let threshold = report.policy.threshold.map(format)
        let status: String
        switch report.policy.status {
        case .failed:
            status = "❌ Failed: \(percent) is below the required \(threshold!)"
        case .notApplicable:
            status = "➖ Not applicable: no changed executable lines"
        case .passed where threshold != nil:
            status = "✅ Passed: \(percent) meets the required \(threshold!)"
        case .passed:
            status = "✅ Coverage check passed (no minimum configured)"
        }

        var excerpts: [String] = []
        var targets = 0
        var renderedLines = 0
        var unavailable = 0
        for file in report.files where !file.uncoveredLines.isEmpty {
            guard let sourceValue = sources[file.path],
                  let source = safeSource(sourceValue),
                  excerpts.count < limits.sourceFiles
            else {
                unavailable += file.uncoveredLines.count
                continue
            }
            let remainingTargets = max(0, limits.excerptTargets - targets)
            let selected = Array(file.uncoveredLines.prefix(remainingTargets))
            guard !selected.isEmpty else {
                unavailable += file.uncoveredLines.count
                continue
            }
            let wanted = Set(selected)
            var shown = Set<Int>()
            for line in selected {
                let lowerBound = max(1, line - 2)
                let upperBound = min(source.count, line + 2)
                guard lowerBound <= upperBound else { continue }
                for index in lowerBound...upperBound {
                    shown.insert(index)
                }
            }
            let lines = Array(shown.sorted().prefix(max(0, limits.excerptLines - renderedLines)))
            guard !lines.isEmpty else {
                unavailable += file.uncoveredLines.count
                continue
            }
            let body = lines.map { line in
                "\(wanted.contains(line) ? "▶" : " ") \(String(format: "%4d", line)) │ \(source[line - 1])"
            }.joined(separator: "\n")
            let longestTildes = body.split(whereSeparator: { $0 != "~" }).map(\.count).max() ?? 0
            let fence = String(repeating: "~", count: max(3, longestTildes + 1))
            excerpts.append("**\(escapeText(file.path))**\n\(fence)text\n\(body)\n\(fence)")
            targets += selected.count
            renderedLines += lines.count
            unavailable += file.uncoveredLines.count - selected.count
        }

        let displayedFiles = report.files.prefix(80)
        var rows = displayedFiles.map { file in
            let coverage = file.counts.executable == 0
                ? "Not applicable"
                : format(Double(file.counts.covered) * 100 / Double(file.counts.executable))
            return "| \(escapeText(file.path)) | \(coverage) | \(file.counts.covered) | \(file.counts.uncovered) |"
        }
        let omittedFiles = report.files.count - displayedFiles.count
        if omittedFiles > 0 { rows.append("\n_\(omittedFiles) additional files omitted._") }

        let sourceSection: [String]
        if excerpts.isEmpty {
            sourceSection = []
        } else {
            sourceSection = [
                "<details>",
                "<summary>Uncovered source (\(min(targets, limits.excerptTargets)) lines)</summary>",
                "",
            ] + excerpts + (unavailable > 0 ? ["\n_\(unavailable) uncovered lines omitted or source unavailable._"] : [""]) + ["</details>"]
        }
        let table = report.files.isEmpty
            ? ["No changed executable lines were found."]
            : ["| File | Coverage | Covered | Uncovered |", "| --- | ---: | ---: | ---: |"] + rows
        var bodyParts = [
            "<!-- whatcoverage:pr-report:v1 -->",
            "## WhatCoverage",
            "",
            status,
            "",
            "**Diff coverage:** \(percent) (\(report.totals.covered)/\(report.totals.executable) executable lines)",
        ]
        if let wholeProject = report.wholeProjectCoverage {
            let current = wholeProject.executable == 0
                ? "Not applicable"
                : format(Double(wholeProject.covered) * 100 / Double(wholeProject.executable))
            bodyParts.append("**Whole-project coverage:** \(current) (\(wholeProject.covered)/\(wholeProject.executable) executable lines)")
        }
        bodyParts.append("")
        bodyParts.append(contentsOf: sourceSection)
        if !sourceSection.isEmpty { bodyParts.append("") }
        bodyParts.append(contentsOf: [
            "<details>",
            "<summary>Verbose coverage report</summary>",
            "",
        ])
        bodyParts.append(contentsOf: table)
        bodyParts.append(contentsOf: [
            "",
            "[View the workflow run](RUN_URL)",
            "</details>",
        ])
        let body = bodyParts.joined(separator: "\n")
        guard body.utf16.count <= limits.commentCharacters else {
            throw PRCoverageCommentError.renderedCommentTooLarge
        }
        return body
    }

    public func safeSource(_ value: String) -> [String]? {
        guard value.utf8.count <= limits.sourceBytesPerFile, !value.contains("\0") else { return nil }
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return normalized.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let safe = line.unicodeScalars.map { scalar -> String in
                (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value)
                    ? "�" : String(scalar)
            }.joined()
            guard safe.utf16.count > limits.lineCharacters else { return safe }
            return String(decoding: safe.utf16.prefix(limits.lineCharacters - 1), as: UTF16.self) + "…"
        }
    }

    private func escapeText(_ value: String) -> String {
        value.reduce(into: "") { result, character in
            result += ["&": "&amp;", "<": "&lt;", ">": "&gt;", "|": "&#124;"][character] ?? String(character)
        }
    }

    private func format(_ value: Double) -> String { String(format: "%.2f%%", value) }
}
