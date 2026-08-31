import ArgumentParser
import CoverageDelta
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
    public let baseInput: String?
    public let baseFormat: CoverageFormat?
    public let baseCapturedSourceRoot: String?
    public let markdownOutput: String?
    public let jsonOutput: String?
    public let minimum: Percentage?
    public let pathSelection: PathSelection

    public init(
        input: String,
        format: CoverageFormat,
        base: String,
        head: String = "HEAD",
        comparison: ComparisonOption = .mergeBase,
        capturedSourceRoot: String? = nil,
        baseInput: String? = nil,
        baseFormat: CoverageFormat? = nil,
        baseCapturedSourceRoot: String? = nil,
        markdownOutput: String? = nil,
        jsonOutput: String? = nil,
        minimum: Percentage? = nil,
        pathSelection: PathSelection = PathSelection()
    ) {
        self.input = input
        self.format = format
        self.base = base
        self.head = head
        self.comparison = comparison
        self.capturedSourceRoot = capturedSourceRoot
        self.baseInput = baseInput
        self.baseFormat = baseFormat
        self.baseCapturedSourceRoot = baseCapturedSourceRoot
        self.markdownOutput = markdownOutput
        self.jsonOutput = jsonOutput
        self.minimum = minimum
        self.pathSelection = pathSelection
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
        guard (configuration.baseInput == nil) == (configuration.baseFormat == nil),
              configuration.baseInput != nil || configuration.baseCapturedSourceRoot == nil
        else {
            throw WhatCoverageError.invocation(
                "A base coverage input and format must be provided together; base path mapping requires both."
            )
        }
        let root = repository.standardizedFileURL
        let mapper: SourcePathMapper
        do {
            mapper = try SourcePathMapper(repositoryRoot: root.path, capturedSourceRoot: configuration.capturedSourceRoot)
        } catch {
            throw WhatCoverageError.invocation(String(describing: error))
        }

        let coverage = try readCoverage(
            input: configuration.input,
            format: configuration.format,
            mapper: mapper,
            repository: root
        )

        let coverageDelta: CoverageDeltaDocument?
        if let baseInput = configuration.baseInput, let baseFormat = configuration.baseFormat {
            let baseMapper: SourcePathMapper
            do {
                baseMapper = try SourcePathMapper(
                    repositoryRoot: root.path,
                    capturedSourceRoot: configuration.baseCapturedSourceRoot
                )
            } catch {
                throw WhatCoverageError.invocation(String(describing: error))
            }
            let baseCoverage = try readCoverage(
                input: baseInput,
                format: baseFormat,
                mapper: baseMapper,
                repository: root
            )
            coverageDelta = CoverageDeltaDocument(
                baseInput: CoverageInputMetadata(
                    kind: baseFormat == .llvm ? .llvm : .xcode,
                    source: baseInput
                ),
                basePathMapping: PathMappingMetadata(
                    repositoryRoot: root.path,
                    capturedSourceRoot: configuration.baseCapturedSourceRoot
                ),
                result: CoverageDeltaCalculator.calculate(base: baseCoverage, head: coverage)
            )
        } else {
            coverageDelta = nil
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
            changes: try configuration.pathSelection.filter(diff.changes),
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
            result: result,
            wholeProjectCoverage: coverage.wholeProjectCounts,
            coverageDelta: coverageDelta
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

    private func readCoverage(
        input: String,
        format: CoverageFormat,
        mapper: SourcePathMapper,
        repository: URL
    ) throws -> NormalizedCoverage {
        let inputURL = resolvedURL(input, repository: repository)
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw WhatCoverageError.coverageInput(
                "No coverage artifact exists at \(inputURL.path). Check the input path and its permissions."
            )
        }
        do {
            switch format {
            case .llvm:
                return try LLVMCoverageReader().read(data: Data(contentsOf: inputURL), pathMapper: mapper)
            case .xcode:
                return try XcodeCoverageReader().read(resultBundle: inputURL, pathMapper: mapper)
            }
        } catch {
            throw WhatCoverageError.coverageInput(String(describing: error))
        }
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
    @Option(help: "Base-revision artifact used for whole-project coverage delta.") var baseInput: String?
    @Option(help: "Explicit base artifact format; inferred from --base-input when omitted.") var baseFormat: CoverageFormat?
    @Option(help: "Original absolute source root recorded in the base coverage artifact.") var baseCapturedSourceRoot: String?
    @Option(help: "Write a Markdown report to this path.") var markdownOutput: String?
    @Option(help: "Write a JSON report to this path.") var jsonOutput: String?
    @Option(help: "Minimum changed-line coverage percentage (0 through 100).") var minimum: Double?
    @Option(help: "Read coverage policy and path selection from this TOML file (relative paths are rooted at the compared repository).") var config: String?
    @Flag(name: .long, help: "Do not load the repository's .whatcoverage.toml file.") var noConfig = false

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
        if let baseCapturedSourceRoot, !baseCapturedSourceRoot.hasPrefix("/") {
            throw ValidationError("--base-captured-source-root must be an absolute path.")
        }
        if baseInput == nil, baseFormat != nil || baseCapturedSourceRoot != nil {
            throw ValidationError("--base-format and --base-captured-source-root require --base-input.")
        }
        if let minimum, (!(0...100).contains(minimum) || !minimum.isFinite) {
            throw ValidationError("--minimum must be a finite percentage from 0 through 100.")
        }
        if config != nil && noConfig { throw ValidationError("--config and --no-config cannot be used together.") }
        if format == nil { format = try Self.inferFormat(for: input) }
        if let baseInput, baseFormat == nil { baseFormat = try Self.inferFormat(for: baseInput) }
    }

    public mutating func run() throws {
        let repository = try Self.repositoryRoot(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let fileConfiguration = try Self.fileConfiguration(config: config, noConfig: noConfig, repository: repository)
        let minimum = try minimum.map(Percentage.init) ?? fileConfiguration.minimum
        let configuration = WhatCoverageConfiguration(
            input: input,
            format: format!,
            base: base,
            head: head,
            comparison: comparison,
            capturedSourceRoot: capturedSourceRoot,
            baseInput: baseInput,
            baseFormat: baseFormat,
            baseCapturedSourceRoot: baseCapturedSourceRoot,
            markdownOutput: markdownOutput,
            jsonOutput: jsonOutput,
            minimum: minimum,
            pathSelection: fileConfiguration.pathSelection
        )
        let status = try WhatCoverageWorkflow().run(configuration, repository: repository)
        if status != .success { throw ExitCode(rawValue: status.rawValue) }
    }

    public static func inferFormat(for input: String) throws -> CoverageFormat {
        if input.lowercased().hasSuffix(".xcresult") { return .xcode }
        if input.lowercased().hasSuffix(".json") { return .llvm }
        throw ValidationError("Cannot infer the coverage format from \(input). Specify --format llvm or --format xcode.")
    }

    static func fileConfiguration(config: String?, noConfig: Bool, repository: URL) throws -> RepositoryConfiguration {
        if noConfig { return RepositoryConfiguration() }
        let url: URL
        if let config {
            url = config.hasPrefix("/") ? URL(fileURLWithPath: config) : repository.appending(path: config)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw WhatCoverageError.invocation("Configuration file \(url.path) requested by --config does not exist.")
            }
        } else {
            url = repository.appending(path: ".whatcoverage.toml")
            guard FileManager.default.fileExists(atPath: url.path) else { return RepositoryConfiguration() }
        }
        return try PathConfigurationLoader.load(from: url)
    }

    static func repositoryRoot(from directory: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--show-toplevel"]
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { throw WhatCoverageError.git("Could not start Git while locating the repository root: \(error.localizedDescription)") }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw WhatCoverageError.git("Could not locate a Git repository from \(directory.path).") }
        let path = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw WhatCoverageError.git("Git did not return a repository root.") }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private static func terminate(with status: Int32) -> Never {
        #if os(Linux)
        Glibc.exit(status)
        #else
        Darwin.exit(status)
        #endif
    }
}
