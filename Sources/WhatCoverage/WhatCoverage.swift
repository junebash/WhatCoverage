import ArgumentParser
import CoverageModel
import CoverageReaders
import DiffCoverage
import Foundation
import GitDiff
import ReportRendering

#if os(Linux)
import Glibc
#else
import Darwin
#endif

public enum WhatCoverageExitStatus: Int32, Sendable {
    case success = 0
    case thresholdFailed = 2
    case invalidInvocation = 64
    case invalidCoverageInput = 65
    case gitFailure = 66
    case outputFailure = 74
}

public enum CoverageFormat: String, CaseIterable, ExpressibleByArgument, Sendable {
    case llvm
    case xcode
}

public enum ComparisonOption: String, CaseIterable, ExpressibleByArgument, Sendable {
    case mergeBase = "merge-base"
    case direct

    var gitMode: GitComparisonMode { self == .mergeBase ? .mergeBase : .direct }
}

public struct WhatCoverageConfiguration: Sendable {
    public let input: String
    public let format: CoverageFormat
    public let base: String
    public let head: String
    public let comparison: ComparisonOption
    public let capturedSourceRoot: String?
    public let markdownOutput: String?
    public let jsonOutput: String?
    public let minimum: Percentage?

    public init(
        input: String,
        format: CoverageFormat,
        base: String,
        head: String = "HEAD",
        comparison: ComparisonOption = .mergeBase,
        capturedSourceRoot: String? = nil,
        markdownOutput: String? = nil,
        jsonOutput: String? = nil,
        minimum: Percentage? = nil
    ) {
        self.input = input
        self.format = format
        self.base = base
        self.head = head
        self.comparison = comparison
        self.capturedSourceRoot = capturedSourceRoot
        self.markdownOutput = markdownOutput
        self.jsonOutput = jsonOutput
        self.minimum = minimum
    }
}

public enum WhatCoverageError: Error, CustomStringConvertible, Sendable {
    case invocation(String)
    case coverageInput(String)
    case git(String)
    case output(String)

    public var exitStatus: WhatCoverageExitStatus {
        switch self {
        case .invocation: .invalidInvocation
        case .coverageInput: .invalidCoverageInput
        case .git: .gitFailure
        case .output: .outputFailure
        }
    }

    public var description: String {
        switch self {
        case .invocation(let detail): "Invalid invocation: \(detail)"
        case .coverageInput(let detail): "Coverage input error: \(detail)"
        case .git(let detail): "Git comparison error: \(detail)"
        case .output(let detail): "Report output error: \(detail)"
        }
    }
}

public struct WhatCoverageWorkflow: Sendable {
    public init() {}

    public func run(_ configuration: WhatCoverageConfiguration, repository: URL) throws -> WhatCoverageExitStatus {
        let root = repository.standardizedFileURL
        let mapper: SourcePathMapper
        do {
            mapper = try SourcePathMapper(repositoryRoot: root.path, capturedSourceRoot: configuration.capturedSourceRoot)
        } catch {
            throw WhatCoverageError.invocation(String(describing: error))
        }

        let inputURL = resolvedURL(configuration.input, repository: root)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw WhatCoverageError.coverageInput(
                "No coverage artifact exists at \(inputURL.path). Check --input and its permissions."
            )
        }
        let coverage: NormalizedCoverage
        do {
            switch configuration.format {
            case .llvm:
                coverage = try LLVMCoverageReader().read(data: Data(contentsOf: inputURL), pathMapper: mapper)
            case .xcode:
                coverage = try XcodeCoverageReader().read(resultBundle: inputURL, pathMapper: mapper)
            }
        } catch {
            throw WhatCoverageError.coverageInput(String(describing: error))
        }

        let diff: GitDiffResult
        do {
            diff = try GitDiffProvider().changedLines(
                repository: root,
                base: configuration.base,
                head: configuration.head,
                mode: configuration.comparison.gitMode
            )
        } catch {
            throw WhatCoverageError.git(String(describing: error))
        }

        let result = DiffCoverageCalculator.calculate(
            coverage: coverage,
            changes: diff.changes,
            minimum: configuration.minimum
        )
        let document = CoverageReportDocument(
            metadata: ReportMetadata(
                revision: RevisionMetadata(
                    requestedBase: diff.comparison.requestedBase,
                    requestedHead: diff.comparison.requestedHead,
                    resolvedBase: diff.comparison.resolvedBase,
                    resolvedHead: diff.comparison.resolvedHead,
                    mode: diff.comparison.mode
                ),
                coverageInput: CoverageInputMetadata(kind: configuration.format == .llvm ? .llvm : .xcode, source: configuration.input),
                pathMapping: PathMappingMetadata(repositoryRoot: root.path, capturedSourceRoot: configuration.capturedSourceRoot)
            ),
            result: result
        )
        do {
            if let markdownOutput = configuration.markdownOutput {
                try Data(MarkdownReportRenderer().render(document).utf8).write(to: outputURL(markdownOutput, repository: root))
            }
            if let jsonOutput = configuration.jsonOutput {
                try JSONReportRenderer().render(document).write(to: outputURL(jsonOutput, repository: root))
            }
        } catch {
            throw WhatCoverageError.output(String(describing: error))
        }

        if case .failed = result.policy { return .thresholdFailed }
        return .success
    }

    private func outputURL(_ path: String, repository: URL) -> URL {
        resolvedURL(path, repository: repository)
    }

    private func resolvedURL(_ path: String, repository: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return repository.appending(path: path).standardizedFileURL
    }
}

@main
public struct WhatCoverageCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "what-coverage",
        abstract: "Report coverage for lines changed between Git revisions."
    )

    @Option(help: "LLVM JSON or Xcode result-bundle coverage input.") var input: String
    @Option(help: "Git base revision.") var base: String
    @Option(help: "Explicit coverage format; inferred from the input extension when omitted.") var format: CoverageFormat?
    @Option(help: "Git head revision.") var head = "HEAD"
    @Option(help: "Comparison mode: merge-base (base...head) or direct (base..head).") var comparison: ComparisonOption = .mergeBase
    @Option(help: "Original absolute source root recorded in the coverage artifact.") var capturedSourceRoot: String?
    @Option(help: "Write a Markdown report to this path.") var markdownOutput: String?
    @Option(help: "Write a JSON report to this path.") var jsonOutput: String?
    @Option(help: "Minimum changed-line coverage percentage (0 through 100).") var minimum: Double?

    public init() {}

    public static func main() {
        do {
            var command = try parseAsRoot()
            try command.run()
        } catch let error as WhatCoverageError {
            FileHandle.standardError.write(Data("Error: \(error.description)\n".utf8))
            terminate(with: error.exitStatus.rawValue)
        } catch {
            exit(withError: error)
        }
    }

    public mutating func validate() throws {
        guard markdownOutput != nil || jsonOutput != nil else {
            throw ValidationError("Specify --markdown-output, --json-output, or both.")
        }
        guard markdownOutput != jsonOutput || markdownOutput == nil else {
            throw ValidationError("Markdown and JSON output paths must be different.")
        }
        if let capturedSourceRoot, !capturedSourceRoot.hasPrefix("/") {
            throw ValidationError("--captured-source-root must be an absolute path.")
        }
        if let minimum, (!(0...100).contains(minimum) || !minimum.isFinite) {
            throw ValidationError("--minimum must be a finite percentage from 0 through 100.")
        }
        if format == nil { format = try Self.inferFormat(for: input) }
    }

    public mutating func run() throws {
        let minimum = try minimum.map(Percentage.init)
        let configuration = WhatCoverageConfiguration(
            input: input,
            format: format!,
            base: base,
            head: head,
            comparison: comparison,
            capturedSourceRoot: capturedSourceRoot,
            markdownOutput: markdownOutput,
            jsonOutput: jsonOutput,
            minimum: minimum
        )
        let status = try WhatCoverageWorkflow().run(configuration, repository: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        if status != .success { throw ExitCode(rawValue: status.rawValue) }
    }

    public static func inferFormat(for input: String) throws -> CoverageFormat {
        if input.lowercased().hasSuffix(".xcresult") { return .xcode }
        if input.lowercased().hasSuffix(".json") { return .llvm }
        throw ValidationError("Cannot infer the coverage format from \(input). Specify --format llvm or --format xcode.")
    }

    private static func terminate(with status: Int32) -> Never {
        #if os(Linux)
        Glibc.exit(status)
        #else
        Darwin.exit(status)
        #endif
    }
}
