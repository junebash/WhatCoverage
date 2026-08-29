import CoverageModel
import Foundation

public enum ReportRenderingError: Error, Equatable, Sendable {
    case encodingFailed(String)
}

public struct JSONReportRenderer: Sendable {
    public static let schemaVersion = 1

    public init() {}

    public func render(_ document: CoverageReportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            var data = try encoder.encode(JSONReport(document))
            data.append(0x0A)
            return data
        } catch {
            throw ReportRenderingError.encodingFailed(error.localizedDescription)
        }
    }
}

private struct JSONReport: Encodable {
    let schemaVersion: Int
    let comparison: Comparison
    let coverageInput: CoverageInput
    let pathMapping: PathMapping
    let totals: Counts
    let files: [FileResult]
    let policy: Policy

    init(_ document: CoverageReportDocument) {
        schemaVersion = JSONReportRenderer.schemaVersion
        comparison = Comparison(document.metadata.revision)
        coverageInput = CoverageInput(document.metadata.coverageInput)
        pathMapping = PathMapping(document.metadata.pathMapping)
        totals = Counts(document.result.totals)
        files = document.result.files.sorted { $0.path < $1.path }.map(FileResult.init)
        policy = Policy(document.result.policy)
    }
}

private struct Comparison: Encodable {
    let requestedBase: String
    let requestedHead: String
    let resolvedBase: String
    let resolvedHead: String
    let mode: RevisionRangeMode

    init(_ metadata: RevisionMetadata) {
        requestedBase = metadata.requestedBase
        requestedHead = metadata.requestedHead
        resolvedBase = metadata.resolvedBase
        resolvedHead = metadata.resolvedHead
        mode = metadata.mode
    }
}

private struct CoverageInput: Encodable {
    let kind: CoverageInputKind
    let source: String

    init(_ metadata: CoverageInputMetadata) {
        kind = metadata.kind
        source = metadata.source
    }
}

private struct PathMapping: Encodable {
    let repositoryRoot: String
    let capturedSourceRoot: String?

    init(_ metadata: PathMappingMetadata) {
        repositoryRoot = metadata.repositoryRoot
        capturedSourceRoot = metadata.capturedSourceRoot
    }
}

private struct Counts: Encodable {
    let executable: Int
    let covered: Int
    let uncovered: Int
    let percentage: Percentage?

    init(_ counts: CoverageCounts) {
        executable = counts.executable
        covered = counts.covered
        uncovered = counts.uncovered
        percentage = counts.percentage
    }
}

private struct FileResult: Encodable {
    let path: RepositoryPath
    let counts: Counts
    let coveredLines: [Int]
    let uncoveredLines: [Int]

    init(_ result: FileCoverageResult) {
        path = result.path
        counts = Counts(result.counts)
        coveredLines = result.coveredLines
        uncoveredLines = result.uncoveredLines
    }
}

private struct Policy: Encodable {
    enum Status: String, Encodable {
        case passed, failed, notApplicable
    }

    let status: Status
    let threshold: Percentage?
    let actual: Percentage?

    init(_ outcome: PolicyOutcome) {
        switch outcome {
        case .passed(let threshold):
            status = .passed
            self.threshold = threshold
            actual = nil
        case .failed(let threshold, let actual):
            status = .failed
            self.threshold = threshold
            self.actual = actual
        case .notApplicable(let threshold):
            status = .notApplicable
            self.threshold = threshold
            actual = nil
        }
    }
}
