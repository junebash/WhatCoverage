import Foundation

public enum CoverageModelError: Error, Equatable, Sendable {
    case invalidRepositoryPath(String)
    case invalidLineNumber(Int)
    case negativeExecutionCount(Int)
    case duplicateLine(path: RepositoryPath, line: Int)
    case duplicateFile(RepositoryPath)
    case invalidPercentage(Double)
    case invalidPercentagePointChange(Double)
}

public struct RepositoryPath: Hashable, Comparable, Codable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.hasPrefix("\\"),
              !value.contains("\\"),
              value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ $0 != "" && $0 != "." && $0 != ".." })
        else {
            throw CoverageModelError.invalidRepositoryPath(value)
        }
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}

public struct LineCoverage: Equatable, Sendable {
    public let line: Int
    public let executionCount: Int

    public init(line: Int, executionCount: Int) throws {
        guard line > 0 else { throw CoverageModelError.invalidLineNumber(line) }
        guard executionCount >= 0 else { throw CoverageModelError.negativeExecutionCount(executionCount) }
        self.line = line
        self.executionCount = executionCount
    }
}

public struct FileCoverage: Equatable, Sendable {
    public let path: RepositoryPath
    public let lines: [Int: Int]

    public init(path: RepositoryPath, lines: [LineCoverage]) throws {
        var indexed: [Int: Int] = [:]
        for line in lines {
            guard indexed.updateValue(line.executionCount, forKey: line.line) == nil else {
                throw CoverageModelError.duplicateLine(path: path, line: line.line)
            }
        }
        self.path = path
        self.lines = indexed
    }
}

public struct NormalizedCoverage: Equatable, Sendable {
    public let files: [RepositoryPath: FileCoverage]

    public init(files: [FileCoverage]) throws {
        var indexed: [RepositoryPath: FileCoverage] = [:]
        for file in files {
            guard indexed.updateValue(file, forKey: file.path) == nil else {
                throw CoverageModelError.duplicateFile(file.path)
            }
        }
        self.files = indexed
    }

    public var wholeProjectCounts: CoverageCounts {
        CoverageCounts(
            executable: files.values.reduce(0) { $0 + $1.lines.count },
            covered: files.values.reduce(0) { total, file in
                total + file.lines.values.count(where: { $0 > 0 })
            }
        )
    }
}

public struct ChangedFile: Equatable, Sendable {
    public let path: RepositoryPath
    public let addedLines: Set<Int>

    public init(path: RepositoryPath, addedLines: Set<Int>) throws {
        if let invalid = addedLines.first(where: { $0 <= 0 }) {
            throw CoverageModelError.invalidLineNumber(invalid)
        }
        self.path = path
        self.addedLines = addedLines
    }
}

public struct ChangedLines: Equatable, Sendable {
    public let files: [RepositoryPath: ChangedFile]

    public init(files: [ChangedFile]) throws {
        var indexed: [RepositoryPath: ChangedFile] = [:]
        for file in files {
            guard indexed.updateValue(file, forKey: file.path) == nil else {
                throw CoverageModelError.duplicateFile(file.path)
            }
        }
        self.files = indexed
    }
}

public struct Percentage: Equatable, Comparable, Codable, Sendable {
    public let value: Double

    public init(_ value: Double) throws {
        guard value.isFinite, (0...100).contains(value) else {
            throw CoverageModelError.invalidPercentage(value)
        }
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(Double.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    public static func ratio(covered: Int, executable: Int) -> Self? {
        guard executable > 0 else { return nil }
        return try? Self(Double(covered) * 100 / Double(executable))
    }
}

public struct CoverageCounts: Equatable, Sendable {
    public let executable: Int
    public let covered: Int
    public var uncovered: Int { executable - covered }
    public var percentage: Percentage? { .ratio(covered: covered, executable: executable) }

    package init(executable: Int, covered: Int) {
        precondition(executable >= 0 && covered >= 0 && covered <= executable)
        self.executable = executable
        self.covered = covered
    }
}

public struct PercentagePointChange: Equatable, Codable, Sendable {
    public let value: Double

    public init(_ value: Double) throws {
        guard value.isFinite, (-100...100).contains(value) else {
            throw CoverageModelError.invalidPercentagePointChange(value)
        }
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(Double.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct CoverageDeltaCounts: Equatable, Sendable {
    public let base: CoverageCounts
    public let head: CoverageCounts
    public let percentagePointChange: PercentagePointChange?

    package init(base: CoverageCounts, head: CoverageCounts) {
        self.base = base
        self.head = head
        if let basePercentage = base.percentage, let headPercentage = head.percentage {
            percentagePointChange = try? PercentagePointChange(headPercentage.value - basePercentage.value)
        } else {
            percentagePointChange = nil
        }
    }
}

public struct FileCoverageDelta: Equatable, Sendable {
    public let path: RepositoryPath
    public let target: String
    public let coverage: CoverageDeltaCounts

    package init(path: RepositoryPath, target: String, coverage: CoverageDeltaCounts) {
        self.path = path
        self.target = target
        self.coverage = coverage
    }
}

public struct TargetCoverageDelta: Equatable, Sendable {
    public let name: String
    public let coverage: CoverageDeltaCounts

    package init(name: String, coverage: CoverageDeltaCounts) {
        self.name = name
        self.coverage = coverage
    }
}

public struct WholeProjectCoverageDelta: Equatable, Sendable {
    public let project: CoverageDeltaCounts
    public let targets: [TargetCoverageDelta]
    public let files: [FileCoverageDelta]

    package init(
        project: CoverageDeltaCounts,
        targets: [TargetCoverageDelta],
        files: [FileCoverageDelta]
    ) {
        self.project = project
        self.targets = targets
        self.files = files
    }
}

public struct FileCoverageResult: Equatable, Sendable {
    public let path: RepositoryPath
    public let coveredLines: [Int]
    public let uncoveredLines: [Int]

    package init(path: RepositoryPath, coveredLines: [Int], uncoveredLines: [Int]) {
        self.path = path
        self.coveredLines = coveredLines
        self.uncoveredLines = uncoveredLines
    }

    public var counts: CoverageCounts {
        CoverageCounts(executable: coveredLines.count + uncoveredLines.count, covered: coveredLines.count)
    }
}

public enum PolicyOutcome: Equatable, Sendable {
    case notApplicable(threshold: Percentage?)
    case passed(threshold: Percentage?)
    case failed(threshold: Percentage, actual: Percentage)

    public var statusLabel: String {
        switch self {
        case .notApplicable:
            "Not applicable"
        case .passed:
            "Passed"
        case .failed:
            "Failed"
        }
    }

    public var statusSummary: String {
        switch self {
        case .notApplicable:
            "No changed executable lines"
        case .passed:
            "Coverage meets the configured minimum"
        case .failed:
            "Coverage is below the configured minimum"
        }
    }
}

public struct DiffCoverageReport: Equatable, Sendable {
    public let files: [FileCoverageResult]
    public let totals: CoverageCounts
    public let policy: PolicyOutcome

    package init(files: [FileCoverageResult], totals: CoverageCounts, policy: PolicyOutcome) {
        self.files = files
        self.totals = totals
        self.policy = policy
    }
}

public enum RevisionRangeMode: String, Codable, Sendable {
    case mergeBase
    case direct
}

public enum CoverageInputKind: String, Codable, Sendable {
    case xcode
    case llvm
}

public struct RevisionMetadata: Equatable, Sendable {
    public let requestedBase: String
    public let requestedHead: String
    public let resolvedBase: String
    public let resolvedHead: String
    public let mode: RevisionRangeMode

    public init(
        requestedBase: String,
        requestedHead: String,
        resolvedBase: String,
        resolvedHead: String,
        mode: RevisionRangeMode
    ) {
        self.requestedBase = requestedBase
        self.requestedHead = requestedHead
        self.resolvedBase = resolvedBase
        self.resolvedHead = resolvedHead
        self.mode = mode
    }
}

public struct CoverageInputMetadata: Equatable, Sendable {
    public let kind: CoverageInputKind
    public let source: String

    public init(kind: CoverageInputKind, source: String) {
        self.kind = kind
        self.source = source
    }
}

public struct PathMappingMetadata: Equatable, Sendable {
    public let repositoryRoot: String
    public let capturedSourceRoot: String?

    public init(repositoryRoot: String, capturedSourceRoot: String? = nil) {
        self.repositoryRoot = repositoryRoot
        self.capturedSourceRoot = capturedSourceRoot
    }
}

public struct ReportMetadata: Equatable, Sendable {
    public let revision: RevisionMetadata
    public let coverageInput: CoverageInputMetadata
    public let pathMapping: PathMappingMetadata

    public init(
        revision: RevisionMetadata,
        coverageInput: CoverageInputMetadata,
        pathMapping: PathMappingMetadata
    ) {
        self.revision = revision
        self.coverageInput = coverageInput
        self.pathMapping = pathMapping
    }
}

public struct CoverageReportDocument: Equatable, Sendable {
    public let metadata: ReportMetadata
    public let result: DiffCoverageReport
    public let wholeProjectCoverage: CoverageCounts?
    public let coverageDelta: CoverageDeltaDocument?

    public init(
        metadata: ReportMetadata,
        result: DiffCoverageReport,
        wholeProjectCoverage: CoverageCounts? = nil,
        coverageDelta: CoverageDeltaDocument? = nil
    ) {
        self.metadata = metadata
        self.result = result
        self.wholeProjectCoverage = wholeProjectCoverage
        self.coverageDelta = coverageDelta
    }
}

public struct CoverageDeltaDocument: Equatable, Sendable {
    public let baseInput: CoverageInputMetadata
    public let basePathMapping: PathMappingMetadata
    public let result: WholeProjectCoverageDelta

    public init(
        baseInput: CoverageInputMetadata,
        basePathMapping: PathMappingMetadata,
        result: WholeProjectCoverageDelta
    ) {
        self.baseInput = baseInput
        self.basePathMapping = basePathMapping
        self.result = result
    }
}
