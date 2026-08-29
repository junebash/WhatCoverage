import CoverageModel
import Foundation
import ProcessSupport

public typealias GitComparisonMode = RevisionRangeMode

public struct GitComparison: Equatable, Sendable {
    public let requestedBase: String
    public let requestedHead: String
    public let resolvedBase: String
    public let resolvedHead: String
    public let mode: GitComparisonMode
}

public struct GitDiffResult: Equatable, Sendable {
    public let changes: ChangedLines
    public let comparison: GitComparison
}

public enum GitDiffError: Error, Equatable, Sendable, CustomStringConvertible {
    case commandFailed(arguments: [String], detail: String)
    case invalidOutput(operation: String, detail: String)
    case malformedDiff(String)

    public var description: String {
        switch self {
        case .commandFailed(let arguments, let detail):
            return "Git command failed (`git \(arguments.joined(separator: " "))`): \(detail). Check the revisions and fetch the required history."
        case .invalidOutput(let operation, let detail):
            return "Git returned invalid output while \(operation): \(detail)."
        case .malformedDiff(let detail):
            return "Git produced a patch WhatCoverage could not parse: \(detail)."
        }
    }
}

public struct GitDiffProvider<Runner: ProcessRunning>: Sendable {
    private let runner: Runner

    public init(runner: Runner) { self.runner = runner }

    public func changedLines(
        repository: URL,
        base: String,
        head: String = "HEAD",
        mode: GitComparisonMode = .mergeBase
    ) throws -> GitDiffResult {
        let resolvedHead = try resolve(head, repository: repository)
        let requestedBaseSHA = try resolve(base, repository: repository)
        let resolvedBase: String
        switch mode {
        case .mergeBase:
            resolvedBase = try textOutput(
                ["merge-base", requestedBaseSHA, resolvedHead],
                repository: repository,
                operation: "finding the merge base"
            )
        case .direct:
            resolvedBase = requestedBaseSHA
        }

        let raw = try successfulResult(
            ["diff", "--raw", "-z", "--find-renames", resolvedBase, resolvedHead],
            repository: repository
        ).standardOutput
        let entries: [GitRawChange]
        do { entries = try GitRawDiffParser.parse(raw) }
        catch { throw GitDiffError.malformedDiff(String(describing: error)) }

        var changedFiles: [ChangedFile] = []
        for entry in entries {
            guard entry.status != "D",
                  entry.newMode != "160000",
                  let pathText = entry.newPath
            else { continue }
            let path: RepositoryPath
            do { path = try RepositoryPath(pathText) }
            catch { throw GitDiffError.malformedDiff("invalid repository path \(String(reflecting: pathText))") }
            let pathArguments = entry.oldPath.map { [$0, pathText] } ?? [pathText]
            let patchData = try successfulResult(
                ["diff", "--unified=0", "--no-color", "--no-ext-diff", "--find-renames", resolvedBase, resolvedHead, "--"] + pathArguments,
                repository: repository
            ).standardOutput
            let added: Set<Int>
            do { added = try UnifiedDiffParser.addedLines(String(decoding: patchData, as: UTF8.self)) }
            catch { throw GitDiffError.malformedDiff(String(describing: error)) }
            if !added.isEmpty {
                do { changedFiles.append(try ChangedFile(path: path, addedLines: added)) }
                catch { throw GitDiffError.malformedDiff(String(describing: error)) }
            }
        }

        let changes: ChangedLines
        do { changes = try ChangedLines(files: changedFiles) }
        catch { throw GitDiffError.malformedDiff(String(describing: error)) }
        return GitDiffResult(
            changes: changes,
            comparison: GitComparison(
                requestedBase: base,
                requestedHead: head,
                resolvedBase: resolvedBase,
                resolvedHead: resolvedHead,
                mode: mode
            )
        )
    }

    private func resolve(_ revision: String, repository: URL) throws -> String {
        try textOutput(
            ["rev-parse", "--verify", "\(revision)^{commit}"],
            repository: repository,
            operation: "resolving revision \(revision)"
        )
    }

    private func textOutput(_ arguments: [String], repository: URL, operation: String) throws -> String {
        let result = try successfulResult(arguments, repository: repository)
        let output = String(decoding: result.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty, !output.contains("\n") else {
            throw GitDiffError.invalidOutput(operation: operation, detail: String(reflecting: output))
        }
        return output
    }

    private func successfulResult(_ arguments: [String], repository: URL) throws -> ProcessResult {
        let result: ProcessResult
        do { result = try runner.run(command: "git", arguments: arguments, currentDirectory: repository) }
        catch { throw GitDiffError.commandFailed(arguments: arguments, detail: String(describing: error)) }
        guard result.exitCode == 0 else {
            let detail = result.standardError.isEmpty ? "exit status \(result.exitCode)" : result.standardError
            throw GitDiffError.commandFailed(arguments: arguments, detail: detail)
        }
        return result
    }
}

public extension GitDiffProvider where Runner == FoundationProcessRunner {
    init() { self.init(runner: FoundationProcessRunner()) }
}
